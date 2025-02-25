#!/bin/zsh --no-rcs

# MARK: Initialization

export PATH="/bin:/usr/bin:/usr/local/bin:$PATH"

winsList=()
mainDir="${0:h:h}"
iconsDir="${mainDir}/resources/icons"

# Get open windows
(osascript <<-EOF
	tell application "Finder"
		set winsList to ""
		repeat with i from 1 to (count windows)
			set winType to class of window i
			-- If regular Finder window
			if winType is Finder window then
				try
					set winInfo to POSIX path of (target of window i as alias)
				on error
					try
						set winInfo to selection of window i
						if kind of winInfo is not "folder" then
							set winInfo to POSIX path of (container of winInfo as alias)
						end if
					end try
				end try
			-- If "Get Info" window
			else if winType is information window then
				set winInfo to (POSIX path of (item of window i as alias)) & ";;info"
			-- If "Settings" window
			else if winType is preferences window then
				set winInfo to "settings"
			end if
			set winsList to winsList & i & ":" & winInfo & "\n"
		end repeat
		return winsList
	end tell
EOF
) | while read -r line; do
	[[ -z "${line}" ]] || winsList+="${line}"
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
declare -g customIconsDir="${HOME}/.alfred-finwin-icons-cache" winsDir="${tmpDir}/windows"
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
		[[ -z $(find "${trashDir}" -mindepth 1 | grep -v -e "^\.DS_Store$" -e "/\._") ]] || return 0
	done
	return 1
}

function get_icon() {
	local dirPath="${1}"
	local dirPath_noSlashes=$(echo "${dirPath}" | sed 's/\//-/g')
	local customIcon="${customIconsDir}/${dirPath_noSlashes}.icns"

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
		*)
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

			# Execute when icon extraction fails or resource fork not found
			local contentsDir="${dirPath}/Contents"

			# Return failure if no "Contents" directory exists
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

function escape_special_chars() {
	echo -E "${1}" | sed -e 's/[\\`"]/\\&/g' -e 's/\\$/\\\\$/g'
}

function build_match_string() {
	local winTarg="${1}"
	local -A seen_exts=() # Associative array for O(1) lookup
	local matchTerms=()
	
	while read -r line; do
		[[ "${line}" == "Icon"$'\r' ]] && continue
		matchTerms+=("${line}")
		local ext="${line##*.}"
		[[ -n "${ext}" && -z "${seen_exts[${ext}]}" ]] && {
			seen_exts[${ext}]=1
			matchTerms+=(".${ext}")
		}
	done < <(ls -1 "${winTarg}")

	echo -e "${winTarg} ${matchTerms[@]}" | sed -e 's/[\\`"]/\\&/g' -e 's/\\$/\\\\$/g'
}

function cache_window() {
	local i=${1}
	local title=""
	local cmdMod=""
	local winEntry="${winsList[i]}"
	local jsonFile="${winsDir}/${i}"

	local winInfo_original=$(echo -nE "${winEntry}" | sed "s/^[^:]*://")
	local winInfo="${winInfo_original%";;info"}"

	if [[ "${winInfo}" =~ '^/(;;info)?$' ]]; then
		local title=$(diskutil info / | grep "Volume Name" | sed -e "s/^[^:]*://" -e 's/^[[:blank:]]*//;s/[[:blank:]]*$//')
	else
		local winInfo="${winInfo%"/"}"
		[[ ! -z "${title}" ]] || local title=$(escape_special_chars "$(basename "${winInfo}")")
	fi; [[ "${title}" != "com~apple~CloudDocs" ]] || local title="iCloud Drive"

	if [[ "${winInfo_original}" == *";;info" ]]; then
		local subtitle="Information for '${title}'"
		local title="${title} (Info)"
		local winInfo="${winInfo%";;info"}"
		local icon="${iconsDir}/info.png"
		local icon=$(get_icon "${winInfo}" || echo "${iconsDir}/info.png")
		local matchString="info ${subtitle} getinfo get info"
		if [[ -d "${winInfo}" ]]; then
			local itemType="folder"
		else
			local itemType="file"
		fi
		local cmdMod='
			"cmd": {
				"subtitle": "Copy '${itemType}' path",
				"icon": { "path": "'${copyPathIcon}'" },
				"arg": "'${winInfo}'"
			},'
		local winInfo="${winInfo_original}"
		local extras=',
		"match": "'${matchString}'"'
	elif [[ "${winInfo}" == "settings" ]]; then
		local title="Finder Settings"
		local subtitle="${title}"
		local icon="/System/Library/CoreServices/ManagedClient.app/Contents/PlugIns/ConfigurationProfilesUI.bundle/Contents/Resources/SystemPrefApp.icns"
	elif [[ -d "${winInfo}" ]]; then
		[[ ! -z "${title}" ]] || local title=$(escape_special_chars "$(basename "${winInfo}")")
		local subtitle=$(escape_special_chars "${winInfo}")
		local icon=$(get_icon "${winInfo}" || get_generic_icon "${winInfo}")
		matchString="${i} $(build_match_string "${winInfo}")"
		local cmdMod='
			"cmd": {
				"subtitle": "'${cmdSubtitle}'",
				"icon": { "path": "'${copyPathIcon}'" },
				"arg": "'${winInfo}'"
			},'
		local extras=',
		"match": "'${matchString}'"'
	fi
	echo '		{
		"title": "'${title}'",
		"subtitle": "'${subtitle}'",
		"icon": { "path": "'${icon}'" },
		"arg": "reveal '${i}' '${winInfo}'",
		"mods": {'"${cmdMod}"'
			"alt": {
				"subtitle": "'${altSubtitle}'",
				"icon": { "path": "'${iconsDir}'/close.png" },
				"arg": "close '${i}'"
			}
		}'"${extras}"'
	}' > "${jsonFile}"
}

# MARK: Execution

# Iterate through windows
for ((i=1; i<=${#winsList[@]}; i++)); do
	cache_window ${i} &
done
wait

jsonOutput='{
	"items": ['
for ((i=1; i<=${#winsList[@]}; i++)); do
	winFile="${winsDir}/${i}"
	jsonOutput="${jsonOutput}\n$(<"${winFile}"),"
done
jsonOutput="${jsonOutput%,}\n\t]\n}"

# Output results
echo "${jsonOutput}"
