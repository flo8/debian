#!/usr/bin/env bash

# Pick the most-recently-active attached client. Needed when this runs from a
# detached background loop, where tmux has no "current" client to draw on.
client=$(tmux list-clients -F '#{client_activity} #{client_name}' 2>/dev/null \
  | sort -rn | head -1 | cut -d' ' -f2-)

# Nobody attached → nothing to pop up.
[ -z "$client" ] && exit 0

tmux display-popup \
  -c "$client" \
  -x 'R' \
  -y 1 \
  -w 50 \
  -h 14 \
  -E '
bash -c "

clear

printf \"\033[48;5;17m\"
printf \"\033[38;5;213m\"

cat <<EOF

   ███████████████████████████████████

        COMMODORE WELLNESS OS v1.0

   ███████████████████████████████████

EOF

printf \"\033[38;5;51m\"

cat <<EOF
        ░▒▓█  N E O N   B R E A K  █▓▒░

EOF

printf \"\033[38;5;220m\"

cat <<EOF
    SYS64738: GO HYDRATE

    > blink your eyes
    > unclench shoulders
    > breathe slowly

EOF

printf \"\033[38;5;201m\"
printf \"    READY.\n\"

printf \"\033[0m\"

sleep 8
"
'
