#!/bin/bash
echo "Running installation script"

# Run like this:
# wget -qO- https://raw.githubusercontent.com/flo8/debian/main/install.sh | bash

# Add your script's commands here
apt-get update
apt-get upgrade

apt-get install micro tmux rsync cron htop


# Download .tmux.conf
wget -P ~/ https://raw.githubusercontent.com/flo8/debian/main/.tmux.conf
