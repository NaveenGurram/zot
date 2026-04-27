#!/bin/bash

# Path to zot
ZOT="$HOME/.local/bin/zot"
[ ! -f "$ZOT" ] && ZOT=$(which zot)

# Capture reminders and strip ANSI color codes
RAW_OUTPUT=$($ZOT remind 2>/dev/null)
CLEAN_OUTPUT=$(echo "$RAW_OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')

# Check if there are actual reminder items (lines starting with "  1.", "  2.", etc.)
if echo "$CLEAN_OUTPUT" | grep -E '^\s+[0-9]+\.' > /dev/null; then
    # Show native macOS popup
    osascript -e "display dialog \"$CLEAN_OUTPUT\" with title \"📝 Zot Reminders\" buttons {\"Open Terminal\", \"Done\"} default button \"Done\"" > /dev/null
fi
