#!/bin/bash

# Paths
ZOT_BIN=$(which zot 2>/dev/null || echo "$HOME/.local/bin/zot")
# We look for the Swift UI binary specifically
REMIND_UI="$(dirname "$0")/zot-remind-ui"

# Capture reminders and strip ANSI
RAW_OUTPUT=$($ZOT_BIN remind 2>/dev/null)
CLEAN_OUTPUT=$(echo "$RAW_OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')

# Check if there are actual reminder items
if echo "$CLEAN_OUTPUT" | grep -E '^\s+[0-9]+\.' > /dev/null; then
    # 1. Try the native Swift UI if it exists
    if [ -f "$REMIND_UI" ]; then
        exec "$REMIND_UI"
    fi

    # 2. Fallback to AppleScript
    osascript -e "display dialog \"$CLEAN_OUTPUT\" with title \"📝 Zot Reminders\" buttons {\"Open Terminal\", \"Done\"} default button \"Done\"" > /dev/null
fi
