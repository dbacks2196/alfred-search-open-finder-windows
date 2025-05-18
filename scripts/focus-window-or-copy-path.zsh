#!/bin/zsh --no-rcs

arg="${1}"

case "${arg}" in
	"reveal"*)
		# User selected to reveal window
		words=(${(z)arg}) # Split argument
		i="${words[2]}" # Parse path
		if [[ "${arg}" =~ '.*;;info|settings|;;view-options$' ]]; then
			/usr/bin/osascript <<-EOF
				set i to $i

				tell application "System Events"
					-- Ensure Finder is still focused
					if name of (first process whose frontmost is true) is not "Finder" then
						-- AppleScript's native app activation would bring all windows to front → embedded shell script used instead
						do shell script "/usr/bin/open -a \"/System/Library/CoreServices/Finder.app\""
					end if
				end tell

				tell application "Finder"
					-- Focus chosen window
					set index of window i to 1
				end tell

				-- Special handling for non-browser windows (they often lose focus)
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
			# Focus chosen window in background; activate Finder
			/usr/bin/osascript -e "tell application \"Finder\" to set index of window ${i} to 1"
			/usr/bin/open -a "/System/Library/CoreServices/Finder.app"
		fi
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
		if [[ -e "${arg}" || -e "$(print -n -- "${arg}")" ]]; then
			# Copy to clipboard without trailing newline
			/usr/bin/pbcopy < <(print -rn -- "${arg}")
		else
			print -r -- "ERROR: Invalid argument: ${arg}" >&2
			exit 1
		fi
		;;
esac
