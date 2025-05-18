#!/bin/zsh --no-rcs

# Get argument
arg="${1}"

# Define path to semi-persistent JSON cache; create if needed
jsonCacheDir="/tmp/alfred-search-open-finder-windows/json-cache"
[[ -d "${jsonCacheDir}" ]] || /bin/mkdir -p "${jsonCacheDir}"
jsonCacheFile=$(print "${jsonCacheDir}/"*(.))

case "${arg}" in
	"open-new-window")
		/usr/bin/open -a "/System/Library/CoreServices/Finder.app"
		/bin/rm -f "${jsonCacheFile}"
		exit 0
		;;
esac

words=(${(z)arg})
winIndex="${words[2]}"

# Close Finder window
winsExist="$(
	/usr/bin/osascript <<-EOF
		set winIndex to $winIndex as integer
		set winsExist to 1

		tell application "Finder"
			set winToClose to (id of window winIndex)

			if winIndex is equal to 1 then
				try
					set winToFocus to (id of window 2)
				on error
					set winsExist to 0
				end try
			else
				set winToFocus to (id of window 1)
			end if

			try -- Focus runner-up window (extra step to ensure JSON output remains ordered after closing window)
				set index of window id winToFocus to 1
			end try

			close window id winToClose

			return winsExist
		end tell
	EOF
)"

# If last window was closed
if ! (( winsExist )); then
	# Output JSON; exit
	iconPath="${0:h:h}/resources/icons/finder-crying.png"
	/usr/bin/tee "${jsonCacheFile}" < <(print -- '{\n\t"items": [
		\n\t\t{
			"title": "No open Finder windows",
			"subtitle": "Press enter to create one",
			"icon": { "path": "'${iconPath}'" },
			"arg": "open-new-window",
			"mods": {
				"alt": {
					"subtitle": "Press enter to create one"
				}
			}
		}\n\t]\n}'
	)
	exit 0
fi

# Create temporary file for modified JSON output
tmpFile="$(/usr/bin/mktemp)"

# Use Homebrew installation of jq
jq_exec="$(brew --prefix)/bin/jq"

# Remove closed window from JSON output; reorder indecies for "arg" fields
winIndex=$(( ${winIndex} - 1 ))
/usr/bin/tee "${tmpFile}" < <("${jq_exec}" --arg idx "${winIndex}" '
	# Convert passed index to integer
	($idx | tonumber) as $index_to_remove |

	# Remove closed window
	.items = (.items | del(.[$index_to_remove])) |

	# Create counter for new indices
	(.items | length) as $total |

	# Reorder indecies
	.items = [
		range(0; $total) as $i |
		.items[$i] |
		.arg |= gsub("reveal [0-9]+ "; "reveal \($i+1) ") |
		.mods.alt.arg |= gsub("close [0-9]+"; "close \($i+1)")
	] |

	# Return modified string
	.
' "${jsonCacheFile}")

# Update semi-persistent JSON output cache with new results
/bin/rm -f "${jsonCacheFile}" 2>/dev/null
/bin/mv "${tmpFile}" "${jsonCacheDir}/$(/bin/date +%s)"
