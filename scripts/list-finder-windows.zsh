#!/bin/zsh --no-rcs

# Dependencies: jq

# MARK: Housekeeping

# Set up trapping (allows for commands to be appended to 'trap' later)
trapScript="/tmp/$RANDOM"
trap "{ /bin/zsh --no-rcs ${trapScript} &> /dev/null &! }" SIGINT SIGTERM EXIT
print -r -- 'trap "rm -f \"${0}\"" SIGINT SIGTERM EXIT' > "${trapScript}" # Pre-populate with self-destruct

function trap_that() {
	print -r -- "$@" >> "${trapScript}"
}

# Create temporary directory; trap on exit
export tmpDir="$(/usr/bin/mktemp -d)"
trap_that "/bin/rm -rf \"${tmpDir}\""

# MARK: IPC Setup

# Define directory to test hidden item visibility
export testDir="${tmpDir}/test-hidden"

# Function to get open Finder windows
function get_wins() {
	# AppleScript: set up hidden file check
	hiddenFile="${testDir}/hidden-file"
	/bin/mkdir -p "${testDir}"
	/usr/bin/touch "${hiddenFile}"
	/usr/bin/chflags hidden "${hiddenFile}"

	/usr/bin/osascript <<-EOF
		-- Initialization
		set testDir to POSIX file "${testDir}" as alias
		set fifoEOF to "__EOF__"
		set winInfo to ""

		tell application "Finder"
			try -- Get hidden items state
				set showsHidden to (count files of folder testDir) as text
			on error errMsg
				log errMsg
				set showsHidden to 0 -- Set default value
			end try

			-- Log hidden items flag
			log ""
			log showsHidden

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
						try -- Fall back to selection
							set winInfo to selection of window i
							if kind of winInfo is not "folder" then
								-- Get folder if selection is file
								set winInfo to POSIX path of (container of winInfo as alias)
							end if
						end try
					end try
				-- If "Get Info" window
				else if winType is information window then
					try
						set winInfo to (POSIX path of (item of window i as alias)) & ";;info"
					on error
						set winName to name of window i
						try
							set winName to text 1 thru ((length of winName) - (length of " Info")) of winName
						on error
							set winName to "Unknown"
						end try
						set winInfo to winName & ";;info"
					end try
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
					log i & ":" & winInfo as text
				end if
			end repeat

			-- Signal to close output stream
			log fifoEOF
		end tell
	EOF
}

# Set up FIFO
fifo="${tmpDir}/fifo"
/usr/bin/mkfifo "${fifo}" 2>/dev/null
getWinsScript="${0:h}/get-windows.applescript"
fifoEOF="__EOF__"

# Function to stream AppleScript to FIFO
function write_to_fifo() {
	# Run 'get_wins' function asynchronously; stream live AppleScript output
	/usr/bin/script -qF "${fifo}" /bin/zsh --no-rcs -c $'\n'"$(declare -f get_wins)"$'\n'"get_wins"
}

exec 3<> "${fifo}" # Open FIFO for read, write (prevents blocking)
write_to_fifo &> /dev/null & # Begin AppleScript stream
pid_write_to_fifo=$! # Capture PID
trap_that "{ kill -15 ${pid_write_to_fifo} || kill -9 ${pid_write_to_fifo} } 2>/dev/null" # Trap 'kill' in case of early exit

# MARK: Initialization

# Restate Alfred environment variables
extendedMatch=${extended_match:-1}

# zsh global settings
setopt extended_glob
setopt null_glob

# Define commands (avoids PATH lookup faster async loops)
cmds=(awk date find grep head perl rm sed stat tail tee)
for ((i=1; i<=${#cmds[@]}; i++)); do
	cmdName="${cmds[i]}"
	declare -g "${cmdName}_exec"="$(builtin command -v "${cmdName}" 2>/dev/null || command -v "${cmdName}")"
done

# Use Homebrew installation of jq
jq_exec="$(brew --prefix)/bin/jq"

# Define directories
function define_dirs() {
	# Directories to create
	declare -g winsDir="${tmpDir}/windows"
	declare -g cacheDir="/tmp/alfred-search-open-finder-windows"
	declare -g jsonCacheDir="${cacheDir}/json-cache"
	declare -g customIconsDir="${cacheDir}/icons-cache"

	print # Dummy command (delimiter to trim for mkdir)

	# Existing directories
	declare -g mainDir=${0:h:h}
	declare -g iconsDir=${mainDir}/resources/icons
	declare -g dockIconsDir=/System/Library/CoreServices/Dock.app/Contents/Resources
}; define_dirs &> /dev/null # Run function

# Create each directory (if needed)
dirsToCreate=()
while read -r line; do
	# Skip empty lines
	case "${line}" in
		(([[:blank:]])#) continue ;;
	esac
	dirPath=$(eval print "${"${line}"#*"="}") # Expand variable names
	[[ -d "${dirPath}" ]] || dirsToCreate+="${dirPath}"
done < <(print -l "${"${$(declare -f define_dirs)#*"{"$'\n'}"%%"print"*}") # Stop at 'print' marker
/bin/mkdir -p "${dirsToCreate[@]}" # Create all directories

# Handle semi-persistent JSON cache
jsonCacheFile=$(print "${jsonCacheDir}/"*(.)) # Look for existing
if [[ -f "${jsonCacheFile}" ]]; then # If exists
	timestamp="${jsonCacheFile:t}"
	# If just created
	if [[ ${timestamp} -ge $(( $("${date_exec}" +%s) - 2 )) ]]; then
		# Output existing results; exit early (avoids regeneration)
		< "${jsonCacheFile}"
		/bin/mv "${jsonCacheFile}" "${jsonCacheDir}/$("${date_exec}" +%s)" # Update time
		exit 0
	else # If expired
		"${rm_exec}" -f "${jsonCacheFile}"
	fi
fi
jsonCacheFile="${jsonCacheDir}/$("${date_exec}" +%s)" # Define new JSON cache file

# Define misc.
copyPathIcon="${iconsDir}/clipboard.png"
cmdSubtitle="Copy folder path"
altSubtitle="Close window"
computerName="$(/usr/sbin/scutil --get ComputerName)"
hwModel=$(/usr/sbin/sysctl -n hw.model)
coreTypesRoot="/System/Library/Templates/Data/System/Library/CoreServices/CoreTypes.bundle/Contents"
coreTypesLib="${coreTypesRoot}/Library"

# MARK: UX Setup

# Get system appearance for icon definitions
case "$(/usr/bin/defaults read -g AppleInterfaceStyle 2>/dev/null)" in
	"Dark")
		folderIconsDir="${iconsDir}/folder-icons/dark"
		trashIconEmpty="${dockIconsDir}/trashempty2@2x.png"
		trashIconFull="${dockIconsDir}/trashfull2@2x.png"
		;;
	*)
		folderIconsDir="${iconsDir}/folder-icons/light"
		trashIconEmpty="${dockIconsDir}/trashempty@2x.png"
		trashIconFull="${dockIconsDir}/trashfull@2x.png"
		;;
esac

# List contents, excluding dotfiles
function list_items_nonhidden() {
	"${find_exec}" "${1}" -mindepth 1 -maxdepth 1 \
	\( -name '.*' \
		-o -name "*"$'\r'"*" \
		-o -name "._*" \
		-o -name ".DS_Store" \
		-o -name ".localized" \
		-o -name ".Spotlight-V100*" \
		-o -name ".fseventsd*" \
		-o -name ".Trashes*" \
		-o -name "Backups.backupdb" \) \
		-prune \
	-o -print
}

# List contents, including dotfiles
function list_items_all() {
	"${find_exec}" "${1}" -mindepth 1 -maxdepth 1 \
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
}

bundleIconGenericNames=(
	"app"
	"appicon"
	"electron"
	"icon"
)

# MARK: Main Functions

function get_generic_icon() {
	local dirPath="${1}"
	case "${dirPath:t}" in
		"."*)
			print -- "${folderIconsDir}/Generic-hidden.png"
			return 0
	esac

	if "${grep_exec}" -q "hidden" < <("${stat_exec}" -f "%Sf" "${dirPath}"); then
		print -- "${folderIconsDir}/Generic-hidden.png"
	else
		print -- "${folderIconsDir}/Generic.png"
	fi
}

function trash_is_full() {
	local trashDirs=(
		"${HOME}/.Trash"(N)
		"${HOME}/Library/Mobile Documents/.Trash"(N)
		/Volumes/*/.Trashes/501(N)
	)

	for ((i=1; i<=${#trashDirs[@]}; i++)); do
		trashDir="${trashDirs[i]}"
		trashContents=("${trashDir}/"*(N))
		[[ -n "${trashContents}" ]] && return 0
	done

	return 1
}

function read_plist() {
	local bundle="${1}"
	local plist="${2}"
	local hwIconCacheFile="${3}"
	local index=${4}
	local iconName=$(/usr/libexec/PlistBuddy -c "Print :UTExportedTypeDeclarations:${index}:UTTypeIcons:UTTypeIconFile" "${plist}" 2>/dev/null)
	case "${iconName}" in
		^)
			local iconPath="${bundle}/Contents/Resources/${iconName}"
			[[ -f "${iconPath}" ]] && {
				print -r -- "${iconPath}"
				return 0
			}
	esac
	return 1
}

function get_icon() {
	local dirPath="${1}"
	local dirPath_noSlashes="${dirPath//\//-}"
	local cacheFile="${customIconsDir}/${dirPath_noSlashes}.path"

	# Check cache
	if [[ -f "${cacheFile}" ]]; then
		local cachedIcon=$(< "${cacheFile}")
		if [[ -f "${cachedIcon}" ]]; then
			print -r -- "${cachedIcon}"
			return 0
		fi
	fi

	local customIcon="${customIconsDir}/${dirPath_noSlashes}.icns"

	# Try to extract custom icon
	local iconResourceFork="${dirPath}/Icon"$'\r'
	if [[ -f "${iconResourceFork}" ]]; then
		# Get hex dump; extract offset; count
		read byteOffset byteCount < <("${awk_exec}" -F "69636e73" '{ printf "%s %d", (length($1) + 2) / 2, "0x" substr($2, 0, 8) }' < <(/usr/bin/tr -d '\n' < <(/usr/bin/xxd -p "${iconResourceFork}/..namedfork/rsrc")))

		if (( byteOffset && byteCount )); then
			# Icon resource fork found; extract icon data
			if "${head_exec}" -c "${byteCount}" > "${customIcon}" < <("${tail_exec}" -c "+${byteOffset}" "${iconResourceFork}/..namedfork/rsrc"); then
				print -r -- "${customIcon}" > "${cacheFile}" # Cache result
				print -r -- "${customIcon}"
				return 0
			fi
		fi
	fi

	case "${dirPath}" in
		"/"|"")
			# Boot volume
			local icon="/System/Library/Extensions/IOStorageFamily.kext/Contents/Resources/Internal.icns"
			print -- "${icon}" > "${cacheFile}"
			print -- "${icon}"
			return 0
			;;
		"/Applications"|"/Library"|"/System"|"/Users"|"${HOME}/Applications"|"${HOME}/Desktop"|"${HOME}/Downloads"|"${HOME}/Library"|"${HOME}/Movies"|"${HOME}/Music"|"${HOME}/Pictures")
			# Folder with macOS-assigned icon
			local icon="${folderIconsDir}/${1:t}.png"
			print -- "${icon}" > "${cacheFile}"
			print -- "${icon}"
			return 0
			;;
		"${HOME}")
			# Home folder
			local icon="${folderIconsDir}/Home.png"
			print -- "${icon}" > "${cacheFile}"
			print -- "${icon}"
			return 0
			;;
		"${HOME}/Library/Mobile Documents/com~apple~CloudDocs")
			# iCloud Drive
			local icon="${folderIconsDir}/iCloud.png"
			print -- "${icon}" > "${cacheFile}"
			print -- "${icon}"
			return 0
			;;
		"/Volumes/"*)
			# Get volume name
			local volPath="/Volumes/${"$(/bin/df "${dirPath}")"#*"/Volumes/"}"
			case "${dirPath%"/"}" in
				"${volPath}")
					icon="${volPath}/.VolumeIcon.icns"
					# If volume has custom icon
					if [[ -f "${icon}" ]]; then
						print -- "${icon}" > "${cacheFile}"
						print -- "${icon}"
						return 0
					else # If removable drive
						if [[ $("${awk_exec}" '{print $3}' < \
							<("${grep_exec}" 'Removable Media' < \
							<(diskutil info "${volPath}"))\
							) == "Removable" ]]; then
							# Removable drive icon
							local icon="/System/Library/Extensions/IOStorageFamily.kext/Contents/Resources/Removable.icns"
							print -- "${icon}" > "${cacheFile}"
							print -- "${icon}"
							return 0
						else # External drive icon
							local icon="/System/Library/Extensions/IOStorageFamily.kext/Contents/Resources/External.icns"
							print -- "${icon}" > "${cacheFile}"
							print -- "${icon}"
							return 0
						fi
					fi
					;;
			esac
			;;
		"${HOME}/.Trash"|"${HOME}/Library/Mobile Documents/.Trash"|/Volumes/*/.Trashes/501)
			if trash_is_full "${dirPath}"; then
				print -- "${trashIconFull}"
			else
				print -- "${trashIconEmpty}"
			fi
			return 0
			;;
		"AirDrop")
			print -- "${iconsDir}/airdrop.png"
			return 0
			;;
		"Network")
			print -- "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericNetworkIcon.icns"
			return 0
			;;
		"Recents")
			print -- "${iconsDir}/clock.png"
			return 0
			;;
		"${computerName}")
			local iconPath=""

			# Try to get Mac model icon in newest location
			for bundle in "${coreTypesLib}/CoreTypes-"*".bundle"; do
				plist="${bundle}/Contents/Info.plist"
				index=0
				while :; do
					models=$(/usr/libexec/PlistBuddy -c "Print :UTExportedTypeDeclarations:${index}:UTTypeTagSpecification:com.apple.device-model-code" "${plist}" 2>/dev/null) || break
					case "${models}" in
						*"${hwModel}"*)
							iconPath=$(read_plist "${bundle}" "${plist}" "${cacheFile}" ${index} 2>/dev/null) && {
								print -r -- "${iconPath}"
								print -r -- "${iconPath}" > "${cacheFile}"
								return 0
							}
							;;
					esac
					((index++))
				done
			done

			# Fallback: get Mac model icon from legacy location
			if [[ -z "${iconPath}" ]]; then
				local plist="${coreTypesRoot}/Info.plist"
				local index=0
				while :; do
					models=$(/usr/libexec/PlistBuddy -c "Print :UTExportedTypeDeclarations:${index}:UTTypeTagSpecification:com.apple.device-model-code" "${plist}" 2>/dev/null) || break
					case "${models}" in
						*"${hwModel}"*)
							read_plist "${bundle}" "${plist}" "${cacheFile}" ${index} 2>/dev/null && break
							;;
					esac
					((index++))
				done
			fi
			;;
		*)
			# Check if path is bundle; fail if no "Contents" directory exists
			local contentsDir="${dirPath}/Contents"
			[[ -d "${contentsDir}" ]] || return 1

			local itemName="${dirPath:t}"
			local resourcesDir="${contentsDir}/Resources"

			# Check default icon names
			for iconName in "${bundleIconGenericNames[@]}"; do
				local iconPath="${resourcesDir}/${iconName}.icns"
				[[ -f "${iconPath}" ]] && {
					print -r -- "${iconPath}"
					return 0
				}
			done

			# Try to get icon from bundle name
			local itemNameNoExt="${itemName:r}"
			local iconPath="${resourcesDir}/${itemNameNoExt}.icns"
			if [[ -f ${(L)iconPath} ]]; then
				print -- "${iconPath}"
				return 0
			else # Try to get icon from executable name
				local -a execFiles=("${dirPath}/Contents/MacOS"/*(X))
				local execName="${execFiles[1]:t}"
				local iconPath="${resourcesDir}/${execName}.icns"
				if [[ -f ${(L)iconPath} ]]; then
					print -- "${iconPath}"
					return 0
				else # Try to get icon name from "Info.plist" file
					local infoPlist="${contentsDir}/Info.plist"
					local iconsList=($(
					"${awk_exec}" '
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
						case "${stringVal}" in
							(^(*".icns")) stringVal="${stringVal}.icns" ;;
						esac
						if [[ -f "${stringVal}" ]]; then
							print -- "${stringVal}"
							return 0
						else
							local iconFile="${resourcesDir}/${stringVal}"
							if [[ -f "${iconFile}" ]]; then
								print -- "${iconFile}"
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
	local cleaned="${1}"

	# Remove any ASCII directional formatting characters
	case "${cleaned}" in
		*[$'\u2066\u2067\u2068\u2069\u202A\u202B\u202C\u202D\u202E\u200B']*)
			cleaned="${cleaned//[$'\u2066\u2067\u2068\u2069\u202A\u202B\u202C\u202D\u202E\u200B']/}"
		;;
	esac

	# Replace any reduced-width space characters with normal space
	case "${cleaned}" in
		*$'\u202F'*) cleaned=${cleaned//$'\u202F'/ } ;;
	esac

	# Extra failsafe for lingering control characters
	case "${cleaned}" in
		*[$'\x00'-$'\x09']*|*[$'\x0B'-$'\x1F']*)
			cleaned=$("${perl_exec}" -pe 's/([\x00-\x09\x0B-\x1F])/sprintf("\\u%04X", ord($1))/ge' <<< ${cleaned})
			;;
	esac

	# Collapse $HOME path
	case "${cleaned}" in
		"${HOME}"|"${HOME}/") cleaned="${cleaned%"/"}" ;;
		"${HOME}/"*) cleaned="~${cleaned#"${HOME}"}" ;;
	esac

	print -r -- "${cleaned}"
}

function build_match_string() {
	# Skip if user deselected "Extended Matching"
	(( extendedMatch )) || return 1

	local winTarg="${1}"
	local showsHidden="${2}"
	local matchTerms=()
	local -a seenExts=()

	# Determine whether to match dotfiles
	if (( showsHidden )) then
		# Hidden items are visible → include
		function list_items() {
			list_items_all "${@}"
		}
	else # Hidden items are invisible → exclude (default)
		function list_items() {
			list_items_nonhidden "${@}"
		}
	fi

	# Add '~' to match string if path is in home directory
	case "${winTarg}" in
		"${HOME}/"*) matchTerms+="~" ;;
	esac

	while read -r line; do
		local name="${line#${winTarg}/}"
		matchTerms+="${name}"

		# Handle filename extensions
		case "${name}" in
			([^.]*.[[:alnum:]]##|.[^.]*.[[:alnum:]]##) ;; # Item has extension → proceed
			*) continue ;; # Item has no extension → skip
		esac

		# Add each extension only once
		local ext="${name:e}"
		(( ${seenExts[(Ie)${ext}]} )) || {
			# Extension seen for first time → add to array
			seenExts+="${ext}"
			matchTerms+=".${ext}"
		}
	done < <(list_items "${winTarg}")

	sanitize "${winTarg} ${(j. .)matchTerms[@]}"
}

function create_json_entry() {
	local title="$(sanitize "${1}")"
	local subtitle="$(sanitize "${2}")"
	local icon="$(sanitize "${3}")"
	local arg="$(sanitize "${4}")"

	# Initialize optional parameters
	local altSubtitle="${altSubtitle//\\/\\\\}"
	local altIcon="${iconsDir//\\/\\\\}/close.png"

	# Parse named arguments
	shift 4
	while (( $# )); do
		case "${1}" in
			--cmd-subtitle) cmdSubtitle="${2}"; shift 2 ;;
			--cmd-icon) cmdIcon="${2}"; shift 2 ;;
			--cmd-arg) cmdArg="${2}"; shift 2 ;;
			--alt-subtitle) altSubtitle="${2}"; shift 2 ;;
			--alt-icon) altIcon="${2}"; shift 2 ;;
			--alt-arg) altArg="${2}"; shift 2 ;;
			--match) match="${2}"; shift 2 ;;
			*) print -r -- "Unknown parameter: ${1}" >&2; shift ;;
		esac
	done

	# Build jq arguments with all possible variables defined
	"${jq_exec}" -n \
		--arg title "${title}" \
		--arg subtitle "${subtitle}" \
		--arg icon "${icon}" \
		--arg arg "${arg}" \
		--arg cmdSubtitle "${cmdSubtitle}" \
		--arg cmdIcon "${cmdIcon}" \
		--arg cmdArg "${cmdArg}" \
		--arg altSubtitle "${altSubtitle}" \
		--arg altIcon "${altIcon}" \
		--arg altArg "${altArg}" \
		--arg match "${match}" \
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
	"${sed_exec}" -e "s/^[^:]*://" -e 's/^[[:blank:]]*//;s/[[:blank:]]*$//' < <("${grep_exec}" "Volume Name" < <(/usr/sbin/diskutil info /))
}

function cache_window() {
	local winEntry="${1}"
	local showsHidden=${2}
	local i="${winEntry%%":"*}" # Window index
	local jsonFile="${winsDir}/${i}"
	/usr/bin/touch "${jsonFile}"

	local winInfo_original="${winEntry#*":"}"
	local winInfo="${winInfo_original}"

	# If regular Finder window
	if [[ -d "${winInfo}" ]]; then
		local winInfo="${winInfo%"/"}"
		case "${winInfo}" in
			"") # Boot drive (empty)
				local winInfo="/"
				local title="$(get_boot_drive_name)"
				local subtitle="/"
				;;
			"${HOME}/.Trash"|"${HOME}/Library/Mobile Documents/.Trash"|/Volumes/*/.Trashes/501)
				# Trash
				local title="Trash"
				local subtitle="${winInfo}"
				;;
			"${HOME}/Library/Mobile Documents/com~apple~CloudDocs")
				# iCloud Drive
				local title="iCloud Drive"
				local subtitle="${winInfo}"
				;;
			*)
				# All other directory paths
				local title="${winInfo:t}"
				local subtitle="${winInfo}"
				;;
		esac

		local icon=$(get_icon "${winInfo}" || get_generic_icon "${winInfo}")
		local matchString="$(build_match_string "${winInfo}" "${showsHidden}" || print -r -- "${title}")${bootDriveName}"

		jsonEntry=$(create_json_entry \
			"${title//":"/"/"}" \
			"${subtitle//":"/"/"}" \
			"${icon}" \
			"reveal ${i} ${winInfo//":"/"/"}" \
			--cmd-subtitle "${cmdSubtitle//":"/"/"}" \
			--cmd-icon "${copyPathIcon}" \
			--cmd-arg "${winInfo}" \
			--alt-arg "close ${i}" \
			--match "${matchString//":"/"/"}"
		)
	else
		case "${winInfo_original}" in
			*";;info") # "Get Info" window (inspector)
				local winInfo="${winInfo%";;info"}"

				if [[ -d "${winInfo}" ]]; then
					local winInfo="${winInfo%"/"}"
					local cmdIcon="${copyPathIcon}"
					local cmdArg="${winInfo//\\/\\\\}"
				elif [[ -e "${winInfo}" ]]; then
					local cmdSubtitle="Copy file path"
					local cmdIcon="${copyPathIcon}"
					local cmdArg="${winInfo//\\/\\\\}"
				else
					# Use default action variables
					cmdSubtitle="${subtitle}"
					cmdIcon="${icon}"
					cmdArg="${arg}"
				fi

				case "${winInfo}" in
					""|"/")
						# Boot drive
						local name="$(get_boot_drive_name)"
						;;
					"${HOME}/.Trash"|"${HOME}/Library/Mobile Documents/.Trash"|/Volumes/*/.Trashes/501)
						# Trash
						local name="Trash"
						;;
					*)
						# All other directory paths → get basename
						local name="${winInfo:t}"
						;;
				esac

				local subtitle="Information for '${name}'"
				local title="${name} (Info)"
				local icon=$(get_icon "${winInfo}" || print "${iconsDir}/info.png")
				local matchString="${subtitle} getinfo get info"
				local arg="reveal ${i} ${winInfo_original}"

				jsonEntry=$(create_json_entry \
					"${title//":"/"/"}" \
					"${subtitle//":"/"/"}" \
					"${icon}" \
					"reveal ${i} ${winInfo_original}" \
					--cmd-subtitle "${cmdSubtitle}" \
					--cmd-icon "${copyPathIcon}" \
					--cmd-arg "${winInfo//\\/\\\\}" \
					--alt-arg "close ${i}" \
					--match "${matchString//":"/"/"}"
				)
				;;
			*";;view-options")
				# "View Options" window
				local title="${winInfo%";;view-options"}"
				local subtitle="View options for '${title}'"
				local title="${title} (View options)"
				local icon="${iconsDir}/view-options.png"
				local matchString="${subtitle} viewoptions showviewoptions show view options"

				jsonEntry=$(create_json_entry \
					"${title//":"/"/"}" \
					"${subtitle//":"/"/"}" \
					"${icon}" \
					"reveal ${i} ${title}" \
					--alt-arg "close ${i}"
				)
				;;
			"settings")
				# Settings/Preferences window
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
				;;
			*)
				# Any other window type
				local title="${winInfo}"
				local subtitle="${winInfo}"
				case "${winInfo}" in
					"Searching “"*"”")
						local icon="${iconsDir}/search.png"
						;;
					*)
						local icon=$(get_icon "${winInfo}" || print -r -- "${iconsDir}/generic-window.png")
						;;
				esac

				jsonEntry=$(create_json_entry \
					"${title//":"/"/"}" \
					"${subtitle//":"/"/"}" \
					"${icon}" \
					"reveal ${i} ${winInfo}" \
					--alt-arg "close ${i}"
				)
				;;
		esac
	fi

	# Write to JSON file
	print -rn -- "${jsonEntry}" >> "${jsonFile}"
}

function no_windows_open_json() {
	"${tee_exec}" "${jsonCacheFile}" < <(print -- '{\n\t"items": [
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
}

function main() {
	hiddenFlagFile="${testDir}/shows-hidden"
	pids=()
	while read -r line; do
		# Remove any junk characters from unbuffered AppleScript stream
		case "${line}" in
			*[$'\x00\x04\x08\x0D\x7F']*)
				line="${line//[$'\x00\x04\x08\x0D\x7F']/}"
					# \x00 Null
					# \x04 # ASCII 'EOT' (end-of-transmission) marker (^D)
					# \x08 # Backspace (^H)
					# \x0D # Same as \r (^M)
					# \x7F # Delete
			;;
		esac

		# Handle lines
		case "${line}" in
			(([[:blank:]]|$'\n')#)
				continue # Skip if empty or whitespace/newline-only
				;;
			(0|1)
				# Line is hidden items visibility flag
				print -r ${line} > "${hiddenFlagFile}" # Write to file
				continue
				;;
			"${fifoEOF}")
				# EOF marker found → end write process manually
				{ kill -15 ${pid_write_to_fifo} || kill -9 ${pid_write_to_fifo}
				} 2>/dev/null
				rm -f "${fifo}"
				break
				;;
			"^D")
				# Skip leading '^D' (sometimes prepends first line as literal)
				[[ -f "${hiddenFlagFile}" ]] || {
					# If trimmed line contains hidden status
					case "${line#"^D"}" in
						((1|0)([[:blank:]])#)
							# Create flag file
							print -r -- "${${line##[[:blank:]]##}%%[[:blank:]]##}" > "${hiddenFlagFile}"
							;;
					esac
				}
				continue
				;;
			*)
				# Real entry found
				for ((i=1; i<=20; i++)); do
					# Wait for hidden flag to be written
					[[ -f "${hiddenFlagFile}" ]] && {
						showsHidden=$(<"${hiddenFlagFile}")
						break
					}
					# Set to default (exclude) on timeout
					[[ ${i} -ge 20 ]] && showsHidden=0
				done

				# Cache each window (async)
				cache_window "${line}" "${showsHidden}" &
				pids+=$!
				;;
		esac
	done

	# Wait for background processes
	wait "${pids[@]}" 2>/dev/null
}

function combine_json_entries() {
	# Open JSON string
	print '{\n\t"items": ['

	# Loop sequentially through JSON objects
	for ((i=1; i<=${#cachedWins[@]}; i++)); do
		winFile="${cachedWins[i]}"
		[[ -f "${winFile}" ]] || continue
		[[ ${i} -eq 1 ]] || print ','
		< "${winFile}"
	done

	# Close JSON string
	print '\t]\n}'
}

# MARK: Execution

# Run main using FD 3 for reading
main <&3

# Get list of cached windows
cachedWins=("${winsDir}"/*(.))
cachedWins=(${(n)cachedWins}) # Sort numerically (ensures proper indexing)
cacheCount=${#cachedWins[@]}

# Build full JSON; output results
if (( cacheCount )); then
	# List open windows; write to main cache
	"${tee_exec}" "${jsonCacheFile}" < <("${jq_exec}" '.' <<< "$(combine_json_entries)")
else # No windows are open
	no_windows_open_json
fi
