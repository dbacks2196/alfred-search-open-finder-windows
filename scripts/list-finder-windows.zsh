#!/bin/zsh --no-rcs

# Dependencies: jq

# MARK: Initialization
winsList=()
mainDir="${0:h:h}"
iconsDir="${mainDir}/resources/icons"

# Use Homebrew installation of jq
export jq="$(brew --prefix)/bin/jq"

function get_open_windows() {
	osascript <<-EOF
		tell application "Finder"
			set winsList to ""
			set winInfo to ""
			repeat with i from 1 to (count windows)
				set winType to class of window i
				-- If regular Finder window
				if winType is Finder window then
					try
						set winTarg to (target of window i)
						try -- Try to get window target
							set winInfo to POSIX path of (winTarg as alias)
						on error -- Handle nonstandard Finder windows (i.e. "Recents" window)
							set winName to (name of window i)
							set winInfo to winName
						end try
					on error
						try
							-- Fall back to selection
							set winInfo to selection of window i
							if kind of winInfo is not "folder" then
								-- Get folder if selection is file
								set winInfo to POSIX path of (container of winInfo as alias)
							end if
						on error
							set winName to name of window i
							-- If "Searching" window
							if winName starts with "Searching “" and winName ends with "”" then
								set winInfo to winName -- Fall back to window name
							end if
						end try
					end try
				-- If "Get Info" window
				else if winType is information window then
					set winInfo to (POSIX path of (item of window i as alias)) & ";;info"
				-- If "Settings" window
				else if winType is preferences window then
					set winInfo to "settings"
				-- Handle nonstandard/floating windows (i.e. "Show View Options" window)
				else if winType is window and (floating of window i) is true and (modal of window i) is false then
					set winInfo to (name of window i) & ";;view-options"
				else -- Handle any other window class
					set winInfo to "misc-win"
				end if
				if winInfo is not "" then
					set winsList to winsList & i & ":" & winInfo & "\n"
				end if
			end repeat
			return winsList
		end tell
	EOF
}

# Get open windows
get_open_windows | while read -r line; do
	[[ -z "${line//\\/\\\\}" ]] || winsList+="${line}"
done

# If no windows open
if [[ ${#winsList[@]} -eq 0 ]]; then
	echo -e '{\n\t"items": [
		\n\t\t{
			"title": "No open Finder windows",
			"subtitle": "Press enter to create one",
			"icon": { "path": "'${iconsDir}'/finder-crying.png" },
			"arg": "open-new-window"
		}\n\t]\n}'
	exit
fi

# More initialization
tmpDir=$(mktemp -d)
trap "rm -rf \"${tmpDir}\"" SIGINT SIGTERM EXIT
declare -g customIconsDir="/tmp/alfred-finwin-icons-cache" winsDir="${tmpDir}/windows"
mkdir -p "${winsDir}" "${customIconsDir}"
copyPathIcon="${iconsDir}/clipboard.png"
dockIconsDir="/System/Library/CoreServices/Dock.app/Contents/Resources"

# Get system appearance
if [[ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" == "Dark" ]]; then
	folderIconsDir="${iconsDir}/folder-icons/dark"
	trashIconEmpty="${dockIconsDir}/trashempty2@2x.png"
	trashIconFull="${dockIconsDir}/trashfull2@2x.png"
else
	folderIconsDir="${iconsDir}/folder-icons/light"
	trashIconEmpty="${dockIconsDir}/trashempty@2x.png"
	trashIconFull="${dockIconsDir}/trashfull@2x.png"
fi

# Define text
cmdSubtitle="Copy folder path"
altSubtitle="Close window"

export bundleIconGenericNames=(
	"app"
	"appicon"
	"electron"
	"icon"
)

# MARK: Functions

function get_generic_icon() {
	local dirPath="${1}"
	if [[ $(basename "${dirPath}") == "."* ]]; then
		echo "${folderIconsDir}/Generic-hidden.png"
	elif stat -f "%Sf" "${dirPath}" | grep -q "hidden"; then
		echo "${folderIconsDir}/Generic-hidden.png"
	else
		echo "${folderIconsDir}/Generic.png"
	fi
}

function trash_is_full() {
	local trashDirs=(
		"${HOME}/.Trash"(N)
		"${HOME}/Library/Mobile Documents/.Trash"(N)
		/Volumes/*/.Trashes/501(N)
	)
	for trashDir in "${trashDirs[@]}"; do
		[[ -d "${trashDir}" ]] || continue
		[[ -z $(find "${trashDir}" -mindepth 1 | grep -v -e "\.DS_Store$" -e "/\._") ]] || return 0
	done
	return 1
}

function get_icon() {
	local dirPath="${1}"
	local dirPath_noSlashes=$(echo "${dirPath}" | sed 's/\//-/g')
	local customIcon="${customIconsDir}/${dirPath_noSlashes}.icns"

	# Try to extract custom icon
	local iconResourceFork="${dirPath}/Icon"$'\r'
	if [[ -f "${iconResourceFork}" ]]; then
		# Get hex dump; extract offset; count
		read -r byteOffset byteCount < <(xxd -p "${iconResourceFork}/..namedfork/rsrc" | tr -d '\n' | \
			awk -F "69636e73" '{ printf "%s %d", (length($1) + 2) / 2, "0x" substr($2, 0, 8) }')

		if [[ ${byteOffset} -gt 0 && ${byteCount} -gt 0 ]]; then
			# Icon resource fork found; extract icon data
			if tail -c "+${byteOffset}" "${iconResourceFork}/..namedfork/rsrc" | head -c "${byteCount}" > "${customIcon}"; then
				echo "${customIcon}"
				return 0
			fi
		fi
	fi

	case "${dirPath}" in
		"/")
			# Boot volume
			echo "/System/Library/Extensions/IOStorageFamily.kext/Contents/Resources/Internal.icns"
			return 0
			;;
		"/Applications"|"/Library"|"/System"|"/Users"|"${HOME}/Applications"|"${HOME}/Desktop"|"${HOME}/Downloads"|"${HOME}/Library"|"${HOME}/Movies"|"${HOME}/Music"|"${HOME}/Pictures")
			# Folder with macOS-assigned icon
			echo "${folderIconsDir}/$(basename "${1}").png"
			return 0
			;;
		"${HOME}")
			# Home folder
			echo "${folderIconsDir}/Home.png"
			return 0
			;;
		"${HOME}/Library/Mobile Documents/com~apple~CloudDocs")
			# iCloud Drive
			echo "${folderIconsDir}/iCloud.png"
			return 0
			;;
		"/Volumes/"*)
			# External or removable volume (i.e. flash drive, mounted disk image)
			local volPath="$(df "${dirPath}" | tail -1 | awk '{for (i=9; i<=NF; i++) printf $i" "; print ""}' | sed 's/ *$//' 2>/dev/null)"
			# If directory is volume base directory
			if [[ "${dirPath}" == "${volPath}" ]]; then
				icon="${volPath}/.VolumeIcon.icns"
				# If volume has custom icon
				if [[ -f "${icon}" ]]; then
					echo "${icon}"
					return 0
				else
					# If volume is classified as removable
					if [[ $(diskutil info "${volPath}" \
					| grep 'Removable Media' \
					| awk '{print $3}'\
					) == "Removable" ]]; then
						# Removable drive icon
						echo "/System/Library/Extensions/IOStorageFamily.kext/Contents/Resources/Removable.icns"
						return 0
					else
						# External drive icon
						echo "/System/Library/Extensions/IOStorageFamily.kext/Contents/Resources/External.icns"
						return 0
					fi
				fi
			fi
			;;
		"${HOME}/.Trash"|"${HOME}/Library/Mobile Documents/.Trash"|/Volumes/*/.Trashes/501)
			if trash_is_full; then
				echo "${trashIconFull}"
			else
				echo "${trashIconEmpty}"
			fi
			return 0
			;;
		"Recents")
			echo "${iconsDir}/clock.png"
			return 0
			;;
		*)
			# Check if path is bundle; return failure if no "Contents" directory exists
			local contentsDir="${dirPath}/Contents"
			[[ -d "${contentsDir}" ]] || return 1

			local itemName=$(basename "${dirPath}")
			local resourcesDir="${contentsDir}/Resources"

			# Check default icon names
			for iconName in "${bundleIconGenericNames[@]}"; do
				local iconPath="${resourcesDir}/${iconName}.icns"
				[[ -f "${iconPath}" ]] && {
					echo "${iconPath}"
					return 0
				}
			done

			# Try to get icon from bundle name
			local itemNameNoExt="${itemName%.*}"
			local iconPath="${resourcesDir}/${itemNameNoExt}.icns"
			if [[ -f ${(L)iconPath} ]]; then
				echo "${iconPath}"
				return 0
			else
				# Try to get icon from executable name
				local -a execFiles=("${dirPath}/Contents/MacOS"/*(X))
				local execName="${execFiles[1]:t}"
				local iconPath="${resourcesDir}/${execName}.icns"
				if [[ -f ${(L)iconPath} ]]; then
					echo "${iconPath}"
					return 0
				else
					# Try to get icon name from "Info.plist" file
					local infoPlist="${contentsDir}/Info.plist"
					local iconsList=($(
					awk '
						$0 ~ /<key>CFBundleIcon(File|Name)<\/key>/ {
							getline;
							if ($0 ~ /<string>/) {
								sub(/.*<string>/, ""); sub(/<\/string>.*/, "");
								if (!seen[$0]++) { # Filter duplicates
									icons[++count] = $0
								}
							}
						}
						END {
							for (i = 1; i <= count; i++)
								print icons[i]
						}
					' "${infoPlist}"
					))

					for stringVal in "${iconsList[@]}"; do
						[[ "${stringVal}" == *".icns" ]] || stringVal="${stringVal}.icns"
						if [[ -f "${stringVal}" ]]; then
							echo "${stringVal}"
							return 0
						else
							local iconFile="${resourcesDir}/${stringVal}"
							if [[ -f "${iconFile}" ]]; then
								echo "${iconFile}"
								return 0
							fi
						fi
					done

				fi
			fi
			;;
	esac
	return 1
}

function sanitize() {
	# Remove empty ASCII characters (directional formatting)
	local cleaned="${1//[$'\u2068\u2069']/}"

	# Check for control characters
	if [[ "${cleaned}" == *[$'\x00'-$'\x1F']* ]]; then
		# Sanitize with perl
		result="$(echo -E "${cleaned}" | perl -pe 's/([\x00-\x1F])/sprintf("\\u%04X", ord($1))/ge')"
	else
		result="$(echo -E "${cleaned}")"
	fi

	if [[ "${result}" == "${HOME}"* ]]; then
		result="${result/"${HOME}"/"~"}"
	fi

	echo "${result}"
}

function build_match_string() {
	local winTarg="${1}"
	local -A seen_exts=()
	local matchTerms=()
	
	while read -r line; do
		case "${line}" in # Skip macOS resource forks, Time Machine databases
			*$'\r'*|"._"*|".DS_Store"|".localized"|".Spotlight-V100"*|".fseventsd"*|".Trashes"*|"Backups.backupdb")
				continue
			;;
		esac

		matchTerms+=("${line}")
		local ext="${line##*.}"
		[[ -n "${ext}" && -z "${seen_exts[${ext}]}" ]] && {
			seen_exts[${ext}]=1
			matchTerms+=(".${ext}")
		}
	done < <(ls -1 "${winTarg}")

	echo -E "${winTarg} ${matchTerms[@]}"
}

function create_json_entry() {
	local title="$(sanitize "${1}")"
	local subtitle="$(sanitize "${2}")"
	local icon="$(sanitize "${3}")"
	local arg="$(sanitize "${4}")"

	# Initialize optional parameters
	local cmd_subtitle=""
	local cmd_icon=""
	local cmd_arg=""
	local alt_subtitle="${altSubtitle//\\/\\\\}"
	local alt_icon="${iconsDir//\\/\\\\}/close.png"
	local alt_arg=""
	local match=""

	# Parse named arguments
	shift 4
	while [[ $# -gt 0 ]]; do
		case "${1}" in
			--cmd-subtitle) cmd_subtitle="${2}"; shift 2 ;;
			--cmd-icon) cmd_icon="${2}"; shift 2 ;;
			--cmd-arg) cmd_arg="${2}"; shift 2 ;;
			--alt-subtitle) alt_subtitle="${2}"; shift 2 ;;
			--alt-icon) alt_icon="${2}"; shift 2 ;;
			--alt-arg) alt_arg="${2}"; shift 2 ;;
			--match) match="${2}"; shift 2 ;;
			*) echo "Unknown parameter: ${1}" >&2; shift ;;
		esac
	done

	# Build jq arguments with all possible variables defined
	jq -n \
		--arg title "${title//\\/\\\\}" \
		--arg subtitle "${subtitle//\\/\\\\}" \
		--arg icon "${icon}" \
		--arg arg "${arg//\\/\\\\}" \
		--arg cmd_subtitle "${cmd_subtitle//\\/\\\\}" \
		--arg cmd_icon "${cmd_icon}" \
		--arg cmd_arg "${cmd_arg//\\/\\\\}" \
		--arg alt_subtitle "${alt_subtitle//\\/\\\\}" \
		--arg alt_icon "${alt_icon}" \
		--arg alt_arg "${alt_arg//\\/\\\\}" \
		--arg match "${match//\\/\\\\}" \
	'{
		title: $title,
		subtitle: $subtitle,
		icon: {path: $icon},
		arg: $arg,
		mods: {}
	}
	| if $cmd_subtitle != "" and $cmd_icon != "" and $cmd_arg != "" then 
		.mods.cmd = {
			subtitle: $cmd_subtitle,
			icon: {path: $cmd_icon},
			arg: $cmd_arg
		} 
	  else . end
	| if $alt_arg != "" then 
		.mods.alt = {
			subtitle: $alt_subtitle,
			icon: {path: $alt_icon},
			arg: $alt_arg
		}
	  else . end
	| if $match != "" then .match = $match else . end'
}

function get_boot_drive_name() {
	diskutil info / | grep "Volume Name" | sed -e "s/^[^:]*://" -e 's/^[[:blank:]]*//;s/[[:blank:]]*$//'
}

function cache_window() {
	local i=${1}
	local title=""
	local bootDriveName=""
	local winEntry="${winsList[i]}"
	local jsonFile="${winsDir}/${i}"
	local jsonEntry=""

	local winInfo_original=$(echo -nE "${winEntry}" | sed "s/^[^:]*://")
	local winInfo="${winInfo_original}"

	if [[ "${winInfo_original}" =~ '^/(;;info|;;view-options)?$' ]]; then
		local title="$(diskutil info / | grep "Volume Name" | sed -e "s/^[^:]*://" -e 's/^[[:blank:]]*//;s/[[:blank:]]*$//')"
		local bootDriveName=" ${title}"
	else
		local winInfo="${winInfo%"/"}"
		[[ ! -z "${title}" ]] || local title=$(basename "${winInfo}")
	fi
	
	[[ "${title}" == "com~apple~CloudDocs" ]] && local title="iCloud Drive"

	# Create JSON entry based on window type
	if [[ -d "${winInfo}" ]]; then # If regular Finder window
		[[ ! -z "${title}" ]] || local title=$(basename "${winInfo}")
		local subtitle="${winInfo}"
		local icon=$(get_icon "${winInfo}" || get_generic_icon "${winInfo}")
		local matchString="${i} $(build_match_string "${winInfo}")${bootDriveName}"
		
		jsonEntry=$(create_json_entry \
			"${title//":"/"/"}" \
			"${subtitle//":"/"/"}" \
			"${icon}" \
			"reveal ${i} ${winInfo//":"/"/"}" \
			--cmd-subtitle "${cmdSubtitle//":"/"/"}" \
			--cmd-icon "${copyPathIcon}" \
			--cmd-arg "${winInfo//\\/\\\\}" \
			--alt-arg "close ${i}" \
			--match "${matchString//":"/"/"}"
		)
	# If "Get Info" window
	elif [[ "${winInfo_original}" == *";;info" ]]; then
		local winInfo="${winInfo%";;info"}"
		local title="${winInfo%"/"}"
		if [[ -z "${title}" ]]; then
			local title="$(get_boot_drive_name)"
		else
			local title="$(basename "${winInfo}")"
		fi
		local subtitle="Information for '${title}'"
		local title="${title} (Info)"
		local icon=$(get_icon "${winInfo}" || echo "${iconsDir}/info.png")
		local matchString="${subtitle} getinfo get info"
		
		if [[ -d "${winInfo}" ]]; then
			local itemType="folder"
		else
			local itemType="file"
		fi
		
		jsonEntry=$(create_json_entry \
			"${title//":"/"/"}" \
			"${subtitle//":"/"/"}" \
			"${icon}" \
			"reveal ${i} ${winInfo_original}" \
			--cmd-subtitle "Copy ${itemType} path" \
			--cmd-icon "${copyPathIcon}" \
			--cmd-arg "${winInfo//\\/\\\\}" \
			--alt-arg "close ${i}" \
			--match "${matchString//":"/"/"}"
		)
	# If "View Options" window
	elif [[ "${winInfo_original}" == *";;view-options" ]]; then
		local winInfo="${winInfo%";;view-options"}"
		local title="${winInfo%"/"}"
		if [[ -z "${title}" ]]; then
			local title="$(get_boot_drive_name)"
		else
			local title="$(basename "${winInfo}")"
		fi
		local subtitle="View options for '${title}'"
		local title="${title} (View options)"
		local icon="${iconsDir}/view-options.png"
		local matchString="${subtitle} viewoptions showviewoptions show view options"

		jsonEntry=$(create_json_entry \
			"${title//":"/"/"}" \
			"${subtitle//":"/"/"}" \
			"${icon}" \
			"reveal ${i} ${winInfo%"/"}" \
			--alt-arg "close ${i}"
		)
	# If "Settings" or "Preferences" window
	elif [[ "${winInfo}" == "settings" ]]; then
		local title="Finder Settings"
		local subtitle="${title}"
		local icon="/System/Library/CoreServices/ManagedClient.app/Contents/PlugIns/ConfigurationProfilesUI.bundle/Contents/Resources/SystemPrefApp.icns"
		
		jsonEntry=$(create_json_entry \
			"${title//":"/"/"}" \
			"${subtitle//":"/"/"}" \
			"${icon}" \
			"reveal ${i} ${winInfo}" \
			--alt-arg "close ${i}"
		)
	else # If any other window type
		local title="${winInfo}"
		local subtitle="${winInfo}"
		local icon=$(get_icon "${winInfo}" || echo "${iconsDir}/generic-window.png")
		
		jsonEntry=$(create_json_entry \
			"${title//":"/"/"}" \
			"${subtitle//":"/"/"}" \
			"${icon}" \
			"reveal ${i} ${winInfo}" \
			--alt-arg "close ${i}"
		)
	fi
	
	# Write to JSON file (if created)
	[[ -n "${jsonEntry}" ]] && echo "${jsonEntry}" > "${jsonFile}"
}

function combine_json_entries() {
	# Open string
	echo '{'
	echo '	"items": ['
	
	# Add entries
	for ((i=1; i<=${#winsList[@]}; i++)); do
		[[ ${i} -eq 1 ]] || echo ','
		[[ -f "${winsDir}/${i}" ]] || continue
		cat "${winsDir}/${i}"
	done
	
	# Close string
	echo '	]'
	echo '}'
}

# MARK: Execution

# Cache each window (async)
for ((i=1; i<=${#winsList[@]}; i++)); do
	cache_window ${i} &
done
wait

# Build full JSON
jq '.' <<< "$(combine_json_entries)" > "${tmpDir}/final.json"

# Output results
cat "${tmpDir}/final.json"
