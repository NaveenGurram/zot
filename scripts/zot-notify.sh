#!/bin/bash
ZOT=$(which zot 2>/dev/null || whereis zot | awk '{print $2}')

$ZOT remind | while IFS= read -r line; do
    osascript -e "display notification \"$line\" with title \"📝 Zot Reminder\""
done
