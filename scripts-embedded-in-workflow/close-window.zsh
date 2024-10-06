#!/bin/zsh

if [ ${1} = "open-new-window" ]; then
	/usr/bin/open -a "/System/Library/CoreServices/Finder.app"
	exit
fi

winIndex=$(echo ${1} | /usr/bin/cut -d',' -f1)
if [ -z "${winIndex}" ]; then
	winIndex=1
else
	winIndex=$((winIndex + 1))
fi

modifierSubtext=$(echo ${1} | /usr/bin/cut -d',' -f3)

osascript <<EOF
set winIndex to ${winIndex}
tell application "Finder"
	close window winIndex
end tell
return winIndex
EOF