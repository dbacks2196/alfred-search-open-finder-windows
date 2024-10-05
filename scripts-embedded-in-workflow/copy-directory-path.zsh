#!/bin/zsh

if [ "{query}" = "open-new-window" ]; then
	/usr/bin/open -a "/System/Library/CoreServices/Finder.app"
	exit
fi

jsIndex=$(echo "{query}" | /usr/bin/cut -d',' -f1)
winTarget=$(echo "{query}" | /usr/bin/cut -d',' -f2)
modifierSubtext=$(echo "{query}" | /usr/bin/cut -d',' -f3)

# Remove index from array in case it passes through
if [[ "${winTarget}" == [0-9]##,* ]]; then
	winTarget="${winTarget/#([0-9]##,)/}"
fi

if [ "${modifierSubtext}" = "Copy folder path" ]; then
	echo -n "${winTarget}" | /usr/bin/pbcopy
else

	# Trim trailing whitespaces from target
	winTarget=$(echo "${winTarget}" | /usr/bin/sed 's/^[ \t]*//;s/[ \t]*$//')

	osascriptIndex=(${jsIndex} + 1)
	osascriptIndex=$(printf "%d" "${osascriptIndex}")

	osascript <<EOF
tell application "Finder"
	set winToFocus to window ${osascriptIndex}
	set index of winToFocus to 1
	do shell script "/usr/bin/open -a \"/System/Library/CoreServices/Finder.app\""
	set index of winToFocus to 1
end tell
EOF
fi