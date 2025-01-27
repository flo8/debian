#!/bin/bash
echo "Running installation script"

# Run the script like this:
# wget -qO- https://raw.githubusercontent.com/flo8/debian/main/install.sh | bash

# Set non-interactive mode to suppress prompts
export DEBIAN_FRONTEND=noninteractive

# Ensure apt-get does not prompt about config file changes
sudo mkdir -p /etc/apt/apt.conf.d
echo 'Dpkg::Options {
    "--force-confdef";
    "--force-confold";
};' | sudo tee /etc/apt/apt.conf.d/90forceconf

# Update package lists
sudo apt-get -y update

# Upgrade all packages automatically while keeping existing config files
sudo apt-get -y dist-upgrade

# Install necessary applications without prompting
sudo apt-get install -y micro tmux rsync cron htop rsyslog fail2ban git lsof openssh-server

# Download custom .tmux.conf
wget -q -P ~/ https://raw.githubusercontent.com/flo8/debian/main/.tmux.conf

# Install TPM for tmux
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# Reload tmux configuration
tmux source ~/.tmux.conf

# Enable and start cron service
sudo systemctl enable cron
sudo systemctl start cron

# Cosmetic changes: Add alias to bashrc
echo "alias ls='ls --color=auto'" >> ~/.bashrc
source ~/.bashrc

# Ensure system time is synced
sudo timedatectl set-ntp true
timedatectl status

# Indicate successful installation
echo "Installation complete! Press Prefix + [I] to install tpm plugins in tmux."
