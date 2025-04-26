#!/bin/zsh --no-rcs

# Dependencies: jq

# Set up semi-persistent cache for icons, final JSON object
cacheDir="/tmp/alfred-search-open-finder-windows"
jsonCacheDir="${cacheDir}/json-cache"
declare -g customIconsDir="/${cacheDir}/icons-cache"
mkdir -p "${jsonCacheDir}" "${customIconsDir}"
jsonCacheFile=$(echo "${jsonCacheDir}/"*(.))

# If JSON cache exists
if [[ -f "${jsonCacheFile}" ]]; then
	# If JSON cache was just created
	timestamp="${jsonCacheFile:t}"
	if [[ ${timestamp} -ge $(( $(date +%s) - 2 )) ]]; then
		cat "${jsonCacheFile}"
		mv "${jsonCacheFile}" "${jsonCacheDir}/$(date +%s)" # Update time
		exit 0
	else
		rm -f "${jsonCacheFile}"
	fi
fi

# Create cache for JSON output
mkdir -p "${jsonCacheDir}"
jsonCacheFile="${jsonCacheDir}/$(date +%s)"
touch "${jsonCacheFile}"

# MARK: Initialization
winsList=()
mainDir="${0:h:h}"
iconsDir="${mainDir}/resources/icons"

# Restate Alfred environment variables; define defaults
extendedMatch=${extended_match:-1}

# Use Homebrew installation of jq
export jq="$(brew --prefix)/bin/jq"

# Get open windows
IFS=$'\n'
winsList=(
	$(osascript <<-EOF
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
	)
)
unset IFS

# If no windows are open
if [[ ${#winsList[@]} -eq 0 ]]; then
	# Output JSON; exit
	tee "${jsonCacheFile}" < <(echo -e '{\n\t"items": [
		\n\t\t{
			"title": "No open Finder windows",
			"subtitle": "Press enter to create one",
			"icon": { "path": "'${iconsDir}'/finder-crying.png" },
			"arg": "open-new-window",
			"mods": {
				"alt": {
					"subtitle": "Press enter to create one"
				}
			}
		}\n\t]\n}'
	)
	exit 0
fi

# More initialization
tmpDir=$(mktemp -d)
trap "rm -rf \"${tmpDir}\"" SIGINT SIGTERM EXIT
declare -g winsDir="${tmpDir}/windows"
mkdir -p "${winsDir}"
copyPathIcon="${iconsDir}/clipboard.png"
dockIconsDir="/System/Library/CoreServices/Dock.app/Contents/Resources"
cmdSubtitle="Copy folder path"
altSubtitle="Close window"

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
	elif grep -q "hidden" < <(stat -f "%Sf" "${dirPath}"); then
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
		local trashContents="$(find "${trashDir}" -mindepth 1 -name "" -o -name "._*" -o -name ".DS_Store" -prune -o -print)"
		[[ -n "${trashContents}" ]] && return 0
	done

	return 1
}

function get_icon() {
	local dirPath="${1}"
	local dirPath_noSlashes="${dirPath//\//-}"
	local cacheFile="${customIconsDir}/${dirPath_noSlashes}.path"

	# Check cache
	if [[ -f "${cacheFile}" ]]; then
		local cachedIcon=$(cat "${cacheFile}")
		if [[ -f "${cachedIcon}" ]]; then
			echo "${cachedIcon}"
			return 0
		fi
	fi

	local customIcon="${customIconsDir}/${dirPath_noSlashes}.icns"

	# Try to extract custom icon
	local iconResourceFork="${dirPath}/Icon"$'\r'
	if [[ -f "${iconResourceFork}" ]]; then
		# Get hex dump; extract offset; count
		read -r byteOffset byteCount < <(awk -F "69636e73" '{ printf "%s %d", (length($1) + 2) / 2, "0x" substr($2, 0, 8) }' < <(tr -d '\n' < <(xxd -p "${iconResourceFork}/..namedfork/rsrc")))
		if [[ ${byteOffset} -gt 0 && ${byteCount} -gt 0 ]]; then
			# Icon resource fork found; extract icon data
			if head -c "${byteCount}" > "${customIcon}" < <(tail -c "+${byteOffset}" "${iconResourceFork}/..namedfork/rsrc"); then
				echo "${customIcon}" > "${cacheFile}" # Cache result
				echo "${customIcon}"
				return 0
			fi
		fi
	fi

	case "${dirPath}" in
		"/")
			# Boot volume
			local icon="/System/Library/Extensions/IOStorageFamily.kext/Contents/Resources/Internal.icns"
			echo "${icon}" > "${cacheFile}"
			echo "${icon}"
			return 0
			;;
		"/Applications"|"/Library"|"/System"|"/Users"|"${HOME}/Applications"|"${HOME}/Desktop"|"${HOME}/Downloads"|"${HOME}/Library"|"${HOME}/Movies"|"${HOME}/Music"|"${HOME}/Pictures")
			# Folder with macOS-assigned icon
			local icon="${folderIconsDir}/$(basename "${1}").png"
			echo "${icon}" > "${cacheFile}"
			echo "${icon}"
			return 0
			;;
		"${HOME}")
			# Home folder
			local icon="${folderIconsDir}/Home.png"
			echo "${icon}" > "${cacheFile}"
			echo "${icon}"
			return 0
			;;
		"${HOME}/Library/Mobile Documents/com~apple~CloudDocs")
			# iCloud Drive
			local icon="${folderIconsDir}/iCloud.png"
			echo "${icon}" > "${cacheFile}"
			echo "${icon}"
			return 0
			;;
		"/Volumes/"*)
			# Get volume name
			local volPath="/Volumes/${"$(df "${dirPath}")"#*"/Volumes/"}"
			if [[ "${dirPath%"/"}" == "${volPath}" ]]; then
				icon="${volPath}/.VolumeIcon.icns"
				# If volume has custom icon
				if [[ -f "${icon}" ]]; then
					echo "${icon}" > "${cacheFile}"
					echo "${icon}"
					return 0
				else
					# If removable drive
					if [[ $(awk '{print $3}' < \
						<(grep 'Removable Media' < \
						<(diskutil info "${volPath}"))\
						) == "Removable" ]]; then
						# Removable drive icon
						local icon="/System/Library/Extensions/IOStorageFamily.kext/Contents/Resources/Removable.icns"
						echo "${icon}" > "${cacheFile}"
						echo "${icon}"
						return 0
					else
						# External drive icon
						local icon="/System/Library/Extensions/IOStorageFamily.kext/Contents/Resources/External.icns"
						echo "${icon}" > "${cacheFile}"
						echo "${icon}"
						return 0
					fi
				fi
			fi
			;;
		"${HOME}/.Trash"|"${HOME}/Library/Mobile Documents/.Trash"|/Volumes/*/.Trashes/501)
			if trash_is_full "${dirPath}"; then
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
		result="$(perl -pe 's/([\x00-\x1F])/sprintf("\\u%04X", ord($1))/ge' < <(echo -E "${cleaned}"))"
	else
		result="$(echo -E "${cleaned}")"
	fi

	# Collapse home path to "~"
	if [[ "${result}" == "${HOME}/" ]]; then
		result="${result%"/"}"
	elif [[ "${result}" =~ "^${HOME}[^$]" ]]; then
		result="${result/"${HOME}"/"~"}"
	fi

	echo "${result}"
}

function build_match_string() {
	# Exit early if user deselected "Extended Matching"
	[[ ${extendedMatch} -eq 0 ]] && return 1

	local winTarg="${1}"
	local matchTerms=()
	local -A seenExts=()

	# Add "~" to match string if path is in home directory
	[[ "${winTarg}" == "${HOME}/"* ]] && matchTerms+="~"

	while read -r file; do
		# Get item name; append to match terms
		local name="${file#${winTarg}/}"
		matchTerms+=("${name}")

		# Handle filename extensions
		if [[ "${name}" =~ '[^\.]\.[^\.]' ]]; then
			local ext="${name##*.}"
			[[ -n "${ext}" && -z "${seenExts[${ext}]}" ]] && {
				seenExts[${ext}]=1
				matchTerms+=(".${ext}")
			}
		fi
	done < <(find "${winTarg}" -mindepth 1 -maxdepth 1 \
		\( -name "*"$'\r'"*" \
			-o -name "._*" \
			-o -name ".DS_Store" \
			-o -name ".localized" \
			-o -name ".Spotlight-V100*" \
			-o -name ".fseventsd*" \
			-o -name ".Trashes*" \
			-o -name "Backups.backupdb" \) \
			-prune \
		-o -print
	)

	echo -E "${winTarg} ${matchTerms[@]}"
}

function create_json_entry() {
	local title="$(sanitize "${1}")"
	local subtitle="$(sanitize "${2}")"
	local icon="$(sanitize "${3}")"
	local arg="$(sanitize "${4}")"

	# Initialize optional parameters
	local cmdSubtitle=""
	local cmdIcon=""
	local cmdArg=""
	local altSubtitle="${altSubtitle//\\/\\\\}"
	local altIcon="${iconsDir//\\/\\\\}/close.png"
	local altArg=""
	local match=""

	# Parse named arguments
	shift 4
	while [[ $# -gt 0 ]]; do
		case "${1}" in
			--cmd-subtitle) cmdSubtitle="${2}"; shift 2 ;;
			--cmd-icon) cmdIcon="${2}"; shift 2 ;;
			--cmd-arg) cmdArg="${2}"; shift 2 ;;
			--alt-subtitle) altSubtitle="${2}"; shift 2 ;;
			--alt-icon) altIcon="${2}"; shift 2 ;;
			--alt-arg) altArg="${2}"; shift 2 ;;
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
		--arg cmdSubtitle "${cmdSubtitle//\\/\\\\}" \
		--arg cmdIcon "${cmdIcon}" \
		--arg cmdArg "${cmdArg//\\/\\\\}" \
		--arg altSubtitle "${altSubtitle//\\/\\\\}" \
		--arg altIcon "${altIcon}" \
		--arg altArg "${altArg//\\/\\\\}" \
		--arg match "${match//\\/\\\\}" \
	'{
		title: $title,
		subtitle: $subtitle,
		icon: {path: $icon},
		arg: $arg,
		mods: {}
	}
	| if $cmdSubtitle != "" and $cmdIcon != "" and $cmdArg != "" then
		.mods.cmd = {
			subtitle: $cmdSubtitle,
			icon: {path: $cmdIcon},
			arg: $cmdArg
		}
	  else . end
	| if $altArg != "" then
		.mods.alt = {
			subtitle: $altSubtitle,
			icon: {path: $altIcon},
			arg: $altArg
		}
	  else . end
	| if $match != "" then .match = $match else . end'
}

function get_boot_drive_name() {
	sed -e "s/^[^:]*://" -e 's/^[[:blank:]]*//;s/[[:blank:]]*$//' < <(grep "Volume Name" < <(diskutil info /))
}

function cache_window() {
	local i=${1}
	local title=""
	local bootDriveName=""
	local winEntry="${winsList[i]}"
	local jsonFile="${winsDir}/${i}"
	local jsonEntry=""

	local winInfo_original="${winEntry#*":"}"
	local winInfo="${winInfo_original}"

	[[ "${title}" == "com~apple~CloudDocs" ]] && local title="iCloud Drive"

	# If regular Finder window
	if [[ -d "${winInfo}" ]]; then
		case "${winInfo}" in
			"/")
				# Boot drive
				local title="$(get_boot_drive_name)"
				local subtitle="/"
				;;
			"${HOME}/.Trash/"|"${HOME}/Library/Mobile Documents/.Trash/"|/Volumes/*/.Trashes/501/)
				# Trash
				local title="Trash"
				local subtitle="${winInfo%"/"}"
				;;
			*)
				# All other directory paths
				local title="$(basename "${winInfo%"/"}")"
				local subtitle="${winInfo%"/"}"
				;;
		esac
		
		local icon=$(get_icon "${winInfo%"/"}" || get_generic_icon "${winInfo}")
		local matchString="$(build_match_string "${winInfo}" || echo -nE "${title}")${bootDriveName}"

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
		if [[ "${winInfo}" == "/" ]]; then
			local title="$(get_boot_drive_name)"
		else
			local title="$(basename "${winInfo%"/"}")"
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
		if [[ "${title}" =~ '^Searching “.*”$' ]]; then
			local icon="${iconsDir}/search.png"
		else
			local icon=$(get_icon "${winInfo}" || echo "${iconsDir}/generic-window.png")
		fi

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
	echo -e '{\n\t"items": ['

	# Add entries
	for ((i=1; i<=${#winsList[@]}; i++)); do
		[[ ${i} -eq 1 ]] || echo ','
		[[ -f "${winsDir}/${i}" ]] || continue
		cat "${winsDir}/${i}"
	done

	# Close string
	echo -e '\t]\n}'
}

# MARK: Execution

# Cache each window (async)
for ((i=1; i<=${#winsList[@]}; i++)); do
	cache_window ${i} &
done
wait

# Build full JSON; output results
tee "${jsonCacheFile}" < <(jq '.' <<< "$(combine_json_entries)")
