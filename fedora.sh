#!/bin/bash
echo "Running Fedora installation script"

# Run this script like:
# wget -qO- https://raw.githubusercontent.com/flo8/debian/main/fedora.sh | bash

# Update all packages and repositories
sudo dnf -y update

# Upgrade all installed packages without manual prompts
sudo dnf -y upgrade

# Install required packages
sudo dnf install -y micro tmux rsync cronie htop rsyslog fail2ban git lsof openssh-server wget

# Enable and start essential services
sudo systemctl enable --now crond    # Cron service
sudo systemctl enable --now rsyslog # Syslog for logging
sudo systemctl enable --now fail2ban # Fail2Ban for SSH protection
sudo systemctl enable --now sshd    # OpenSSH server

# Download custom .tmux.conf
wget -q -P ~/ https://raw.githubusercontent.com/flo8/fedora/main/.tmux.conf

# Install TPM (Tmux Plugin Manager)
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# Reload tmux configuration to apply settings
tmux source ~/.tmux.conf

# Add a simple alias for colored output in `ls`
echo "alias ls='ls --color=auto'" >> ~/.bashrc
source ~/.bashrc

# Ensure system time synchronization is enabled
sudo timedatectl set-ntp true
timedatectl status

# Installation complete message
echo "Installation complete! Press Prefix + [I] inside tmux to install plugins via TPM."
