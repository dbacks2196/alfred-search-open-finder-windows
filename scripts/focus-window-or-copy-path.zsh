#!/bin/zsh --no-rcs

arg="${1}"

case "${arg}" in
	"reveal"*)
		if [[ "${arg}" =~ '.*;;info|settings|;;view-options$' ]]; then
			i=$(echo "${arg}" | awk '{print $2}')
			osascript <<-EOF
				set i to $i

				tell application "System Events"
					if name of (first process whose frontmost is true) is not "Finder" then
						do shell script "open -a \"/System/Library/CoreServices/Finder.app\""
					end if
				end tell
								
				tell application "Finder"
					set index of window i to 1
				end tell
				
				tell application "System Events"
					repeat 10 times
						if (first process whose frontmost is true) is "Finder" then
							exit repeat
						end if
						delay 0.1
					end repeat
					click group 1 of window 1 of application process "Finder"
				end tell
			EOF
		else
			osascript -e "tell application \"Finder\" to set index of window $(echo "${arg}" | awk '{print $2}') to 1"
			open -a "/System/Library/CoreServices/Finder.app"
		fi
		;;
	"open-new-window")
		open -a "/System/Library/CoreServices/Finder.app"
		;;
	*)
		echo -n "${arg}"
		exit 1
		;;
esac

# Clear custom icons cache
rm -rf "${HOME}/.alfred-finwin-icons-cache"
