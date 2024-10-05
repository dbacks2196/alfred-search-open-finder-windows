#!/bin/zsh

dir="${1}"

# Exit if input is not a directory
if [ -d "${dir}" ]; then
	exit
fi

cd "${dir}" # Change PWD to input directory

# List folder contents in parallel
contents=$(/bin/ls | /usr/bin/xargs -I {} -P 0 sh -c '
	item="{}"
	[[ "${item}" =~ ^\. ]] && exit 0
	statResult=$(stat -f "%f" "${item}")
	[[ $(( statResult & 0x8000 )) -eq 0 ]] && echo "${item}"
') &> /dev/null

# Set delimiter according to xargs output (new line)
IFS=$'\n'
# Output folder contents as string, delimited by tab (-s)
printf "%s" "${contents}" | /usr/bin/paste -s -
