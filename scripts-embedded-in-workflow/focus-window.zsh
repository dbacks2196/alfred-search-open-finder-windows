#!/bin/zsh

if [[ "{query}" = "open-new-window" ]]; then
	/usr/bin/open -a "/System/Library/CoreServices/Finder.app"
	exit
fi

jsIndex=$(echo "{query}" | /usr/bin/cut -d',' -f1)
osascriptIndex=(${jsIndex} + 1)
osascriptIndex=$(printf "%d" "${osascriptIndex}")
winTarget=$(echo {query} | /usr/bin/cut -d',' -f2)

if [ -z "${winTarget}" ]; then
	osascript <<EOF
tell application "Finder"
	set winToFocus to window ${osascriptIndex}
	do shell script "/usr/bin/open -a \"/System/Library/CoreServices/Finder.app\""
	set index of winToFocus to 1
end tell
EOF
else
	osascript <<EOF
tell application "Finder"
	set index of window ${osascriptIndex} to 1
	do shell script "/usr/bin/open -a \"/System/Library/CoreServices/Finder.app\""
end tell
EOF
fi