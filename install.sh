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
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Install Clickhouse
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
GNUPGHOME=$(mktemp -d)
sudo GNUPGHOME="$GNUPGHOME" gpg --no-default-keyring --keyring /usr/share/keyrings/clickhouse-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 8919F6BD2B48D754
sudo rm -rf "$GNUPGHOME"
sudo chmod +r /usr/share/keyrings/clickhouse-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/clickhouse-keyring.gpg] https://packages.clickhouse.com/deb stable main" | sudo tee \/etc/apt/sources.list.d/clickhouse.list
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y clickhouse-server clickhouse-client clickhouse-common-static

# Update clickhouse server conf file
sudo sed -i 's|<user_files_path>/var/lib/clickhouse/user_files/</user_files_path>|<user_files_path>/home/debian/apps</user_files_path>|g' /etc/clickhouse-server/config.xml

# Restart Clickhouse server
sudo service clickhouse-server restart

# A bit of cosmetic changes
echo "alias ls='ls --color=auto'" >> ~/.bashrc
source ~/.bashrc

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

# Check clickhouse is running
sudo systemctl status clickhouse-server
ps -ef | grep clickhouse
sudo lsof -i:9000

# Everything installed
echo "Press Prefix + [I] to install tpm in tmux"
