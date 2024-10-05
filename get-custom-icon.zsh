#!/bin/zsh

# Function to get macOS resource fork as byte string (hex dump); trim line breaks
get_byte_string() {
	xxd -p "${1}"/..namedfork/rsrc | tr -d '\n'
}

# Function to extract, save icon
get_custom_icon() {

	# Usage: get_custom_icon <inputItem> <outputIcon.icns>

	local inputItem="${1}" outputIcon="${2}" byteStr byteOffset byteCount

	# Check if input item is directory
	[[ -d "${inputItem}" ]] || { exit; }

	# Check for custom icon
	if [[ -d "${inputItem}" ]]; then
		iconResourceFork="${inputItem}/Icon"$'\r'
		[[ -f "${iconResourceFork}" ]] || { exit; }
	else
		iconResourceFork="${inputItem}"
	fi

	# Get byte offset and size of icon resource fork
	read -r byteOffset byteCount < <(get_byte_string "${iconResourceFork}" | awk -F "69636e73" '{ printf "%s %d", (length($1) + 2) / 2, "0x" substr($2, 0, 8) }')
	(( byteOffset > 0 && byteCount > 0 )) || { exit; }

	# Extract, save custom icon
	tail -c "+${byteOffset}" "${iconResourceFork}/..namedfork/rsrc" | head -c "${byteCount}" > "${outputIcon}"

	# Output icon path
	echo "${outputIcon}"
}

# If directory has special icon (either macOS-assigned or user-assigned)
case "${2}" in
	"/")
		# Boot volume
		echo "/System/Library/Extensions/IOStorageFamily.kext/Contents/Resources/Internal.icns"
		;;
	"/Applications/"|"/Library/"|"/System/"|"/Users/"|"${HOME}/Applications/"|"${HOME}/Desktop/"|"${HOME}/Downloads/"|"${HOME}/Library/"|"${HOME}/Movies/"|"${HOME}/Music/"|"${HOME}/Pictures/")
		# Folder with macOS-assigned icon
		echo "${3}$(/usr/bin/basename "${2}").png"
		;;
	"${HOME}/")
		# Home folder
		echo "${3}Home.png"
		;;
	"/Volumes/"*)
		# External or removable volume (i.e. flash drive, mounted disk image)
		volPath="$(df "${2}" | tail -1 | awk '{for (i=9; i<=NF; i++) printf $i" "; print ""}' | sed 's/ *$//')/" &> /dev/null
		# If directory is volume base directory
		if [[ "${2}" == "${volPath}" ]]; then
			# If volume has custom icon
			if [ -f "${2}.VolumeIcon.icns" ]; then
				echo "${2}.VolumeIcon.icns"
			else
				isRemovable="$(diskutil info "${2}" | grep 'Removable Media' | awk '{print $3}')"
				# If volume is classified as removable
				if [[ "${isRemovable}" == "Removable" ]]; then
					# Removable drive icon
					echo "/System/Library/Extensions/IOStorageFamily.kext/Contents/Resources/Removable.icns"
				else
					# External drive icon
					echo "/System/Library/Extensions/IOStorageFamily.kext/Contents/Resources/External.icns"
				fi
			fi
		fi
		;;
	*)
		# If workflow already extracted custom directory icon in previous execution
		if [ -f "${2}.folder-icon-${4}.icns" ]; then
			echo "${2}.folder-icon-${4}.icns"
		else
			# Run get_custom_icon function (will output icon path if custom icon exists)
			get_custom_icon "${2}" "${2}.folder-icon-${4}.icns"
		fi
		;;
esac