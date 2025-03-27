#!/bin/zsh --no-rcs

arg="${1}"
osascript -e "tell application \"Finder\" to close window $(echo "${arg}" | awk '{print $2}')"

rm -rf "/tmp/alfred-finwin-icons-cache"