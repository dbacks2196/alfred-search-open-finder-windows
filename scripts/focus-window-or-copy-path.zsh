#!/bin/zsh --no-rcs

arg="${1}"

case "${arg}" in
	"reveal"*)
		# User selected to reveal window
		words=(${(z)arg}) # Split argument
		i="${words[2]}" # Parse path

		case "${arg}" in # Handle based on window type
			*";;info"|*"settings"|*";;view-options")
				/usr/bin/osascript <<-EOF
					set i to $i

					tell application "Finder"
						-- Get id of chosen window (required due to Finder quirks)
						set winID to id of window i
						-- Focus chosen window
						set index of window i to 1
					end tell

					-- Special handling for non-browser windows (they often lose focus)
					tell application "System Events"
						-- If called from app other than Finder
						if name of (first process whose frontmost is true) is not "Finder" then
							-- AppleScript's native app activation would bring all windows to front → embedded shell script used instead
							do shell script "/usr/bin/open -a \"/System/Library/CoreServices/Finder.app\""

							-- Forcefully focus window by static ID
							tell application "Finder" to set index of window id winID to 1

							repeat 10 times -- Wait for Finder to become front app
								if (first process whose frontmost is true) is "Finder" then
									exit repeat
								end if
								delay 0.1
							end repeat
						end if

						-- Failsafe: simulate mouse click if needed
						if (id of window 1) is not winID then
							click group 1 of window 1 of application process "Finder"
						end if
					end tell
				EOF
				;;
			*)
				# Focus chosen window in background; activate Finder
				/usr/bin/osascript -e "tell application \"Finder\" to set index of window ${i} to 1"
				/usr/bin/open -a "/System/Library/CoreServices/Finder.app"
				;;
		esac
		;;
	"open-new-window")
		# User selected to open new window
		/usr/bin/open -a "/System/Library/CoreServices/Finder.app" # Launch Finder

		# Reset semi-persistent JSON cache
		jsonCacheFile=$(print -r -- "/tmp/alfred-search-open-finder-windows/json-cache/"*(.))
		/bin/rm -f "${jsonCacheFile}" 2>/dev/null
		;;
	*)
		# User selected to copy item path
		if [[ -e "${arg}" ]]; then
			# Item exists → copy to clipboard
			/usr/bin/pbcopy < <(print -rn -- "${arg}")
		else
			print -r -- "ERROR: Invalid argument: ${arg}" >&2
			exit 1
		fi
		;;
esac
