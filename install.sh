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
sudo apt-get install -y micro tmux rsync cron htop rsyslog fail2ban

# Download .tmux.conf
wget -P ~/ https://raw.githubusercontent.com/flo8/debian/main/.tmux.conf

# Reload tmux config
tmux source ~/.tmux.conf

# Start services
sudo systemctl enable cron
sudo systemctl start cron
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Install Clickhouse
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
curl -fsSL 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' | sudo gpg --dearmor -o /usr/share/keyrings/clickhouse-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg] https://packages.clickhouse.com/deb stable main" | sudo tee \
    /etc/apt/sources.list.d/clickhouse.list
sudo apt-get update
sudo apt-get install -y clickhouse-server 
sudo service clickhouse-server start

# Set the time
sudo timedatectl set-ntp true
timedatectl status

# Set correct permission and default security values
# Note that LogLevel is MANDATORY for fail2ban
sudo cat <<EOF >> /etc/ssh/sshd_config
LogLevel INFO
LoginGraceTime 1m
PermitRootLogin prohibit-password
StrictModes yes
MaxAuthTries 3
MaxSessions 5
EOF

# Everything installed
echo "Press Prefix + [I] to install tpm in tmux"
