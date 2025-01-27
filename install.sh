#!/bin/bash
echo "Running installation script"

# Run like this:
# wget -qO- https://raw.githubusercontent.com/flo8/debian/main/install.sh | bash

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

# Set correct permission and default security values
# Note that LogLevel is MANDATORY for fail2ban
cat <<EOF | sudo tee -a /etc/ssh/sshd_config
LogLevel INFO
LoginGraceTime 1m
PermitRootLogin prohibit-password
StrictModes yes
MaxAuthTries 3
MaxSessions 5
PubkeyAuthentication yes
PermitEmptyPasswords no
EOF

# Check SSH is correct
sudo sshd -t

# Adds fail2ban configuration
sudo wget -O /etc/fail2ban/jail.local https://raw.githubusercontent.com/flo8/debian/main/jail.local
sudo systemctl start fail2ban
sudo systemctl enable fail2ban

# Display status of fail2ban
sudo fail2ban-client status
sudo fail2ban-client status sshd

# Adds UFW and configure it
wget -qO- https://raw.githubusercontent.com/flo8/debian/main/ufw.sh | bash

# Check clickhouse is running
sudo systemctl status clickhouse-server
ps -ef | grep clickhouse
sudo lsof -i:9000

# Everything installed
echo "Press Prefix + [I] to install tpm in tmux"


