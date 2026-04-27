#!/bin/bash

# Paths
ZOT_BIN=$(which zot 2>/dev/null || echo "$HOME/.local/bin/zot")
REMIND_UI="$(dirname "$0")/zot-remind-ui"

# Capture reminders and strip ANSI
RAW_OUTPUT=$($ZOT_BIN remind 2>/dev/null)
CLEAN_OUTPUT=$(echo "$RAW_OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')

# Check if there are actual reminder items
if echo "$CLEAN_OUTPUT" | grep -E '^\s+[0-9]+\.' > /dev/null; then
    
    # Optional: Send a passive system notification first (can be commented out)
    # osascript -e 'display notification "You have reminders due" with title "📝 Zot"'

    # 1. Try the native Swift UI if it exists
    if [ -f "$REMIND_UI" ]; then
        exec "$REMIND_UI"
    fi

    # 2. Fallback to AppleScript Dialog with Snooze/Done/Open
    # The "Done" button here will open a prompt to enter IDs to mark as finished
    CHOICE=$(osascript -e "display dialog \"$CLEAN_OUTPUT\" with title \"📝 Zot Reminders\" buttons {\"Snooze\", \"Open Terminal\", \"Mark ID Done\"} default button \"Snooze\"" 2>/dev/null)

    if [[ "$CHOICE" == *"Mark ID Done"* ]]; then
        # Ask which ID to mark done
        ID=$(osascript -e 'text returned of (display dialog "Enter Note ID to mark as done:" default answer "" with title "Zot: Mark Done")' 2>/dev/null)
        if [ ! -z "$ID" ]; then
            $ZOT_BIN done "$ID"
            # Refresh to see if more are left
            exec "$0" 
        fi
    elif [[ "$CHOICE" == *"Open Terminal"* ]]; then
        open -a Terminal
    fi
    # If "Snooze" or window closed, script ends, it will reappear at next launchd interval
fi
