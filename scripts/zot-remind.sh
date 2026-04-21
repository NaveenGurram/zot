#!/bin/bash
ZOT=$(which zot 2>/dev/null || echo "zot")
REMIND_UI=$(which zot-remind 2>/dev/null || echo "zot-remind")

# Only show UI if there are due reminders
OUTPUT=$($ZOT remind 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^\s+[0-9]+\.')
[ -z "$OUTPUT" ] && exit 0

exec "$REMIND_UI"
