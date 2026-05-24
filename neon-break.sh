#!/usr/bin/env bash

# Pick the most-recently-active attached client. Needed when this runs from a
# detached background loop, where tmux has no "current" client to draw on.
client=$(tmux list-clients -F '#{client_activity} #{client_name}' 2>/dev/null \
  | sort -rn | head -1 | cut -d' ' -f2-)

# Nobody attached → nothing to pop up.
[ -z "$client" ] && exit 0

tmux display-popup \
    -c "$client" \
    -E \
    -x R \
    -y 0 \
    -w 36 \
    -h 12 \
    -b rounded \
    -s "bg=#24116b,fg=#b084ff,border-fg=#8d63ff" \
    -T "■ COMMODORE HEALTH OS" \
    "bash -c '
printf \"\033[48;2;36;17;107m\033[38;2;176;132;255m\"
clear
echo
echo \"  **** TAKE A BREAK ****\"
echo
echo \"  ░ DRINK WATER\"
echo \"  ░ LOOK AWAY\"
echo \"  ░ BREATHE\"
echo
for i in 10 9 8 7 6 5 4 3 2 1; do
    printf \"\r  CLOSING IN %d...  \" \"\$i\"
    sleep 1
done
'"
