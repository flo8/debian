#!/bin/bash
echo "Running installation script"

# Run like this:
# wget -qO- https://raw.githubusercontent.com/flo8/debian/main/install.sh | bash

# Useful for remote ssh based install
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Update package lists
sudo apt-get -y update

# Upgrade packages, automatically answering yes to all prompts
sudo apt-get -y upgrade

# Install apps
# Note that rsyslog is REQUIRED for fail2ban to work properly (since Debian 12)
sudo apt-get install -y micro tmux rsync cron htop rsyslog fail2ban git lsof

# Download .tmux.conf
wget -P ~/ https://raw.githubusercontent.com/flo8/debian/main/.tmux.conf

# Install TPM
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# Reload tmux config
tmux source ~/.tmux.conf

# Start services
sudo systemctl enable cron
sudo systemctl start cron

# Install Clickhouse
# wget -qO- https://raw.githubusercontent.com/flo8/debian/main/clickhouse.sh | bash

# A bit of cosmetic changes
echo "alias ls='ls --color=auto'" >> ~/.bashrc
source ~/.bashrc

# Set the time
sudo timedatectl set-ntp true
timedatectl status

# Everything installed
echo "Press Prefix + [I] to install tpm in tmux"

