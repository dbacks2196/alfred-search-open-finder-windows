#!/bin/zsh

if [ {query} = "open-new-window" ]; then
	/usr/bin/open -a "/System/Library/CoreServices/Finder.app"
	exit
fi

winIndex=$(echo {query} | /usr/bin/cut -d',' -f1)
if [ -z "${winIndex}" ]; then
	winIndex=1
else
	winIndex=$((winIndex + 1))
fi

modifierSubtext=$(echo {query} | /usr/bin/cut -d',' -f3)

osascript <<EOF
set winIndex to ${winIndex}
tell application "Finder"
	close window winIndex
end tell
return winIndex
EOF