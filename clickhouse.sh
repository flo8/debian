#!/bin/bash

echo "Installing ClickHouse on Fedora 40..."

# Install prerequisites
echo "Installing prerequisites..."
sudo dnf install -y epel-release
sudo dnf install -y gnupg2 wget curl ca-certificates lsof

# Create ClickHouse user and group if missing
if ! id -u clickhouse >/dev/null 2>&1; then
    echo "Creating ClickHouse user and group..."
    sudo groupadd clickhouse
    sudo useradd -r -g clickhouse clickhouse
fi

# Import the ClickHouse GPG key
echo "Importing ClickHouse GPG key..."
sudo rpm --import https://packages.clickhouse.com/rpm/clickhouse.asc

# Add the ClickHouse repository
echo "Adding ClickHouse repository..."
cat <<EOF | sudo tee /etc/yum.repos.d/clickhouse.repo
[clickhouse]
name=ClickHouse Repository
baseurl=https://packages.clickhouse.com/rpm/stable
gpgcheck=1
gpgkey=https://packages.clickhouse.com/rpm/clickhouse.asc
enabled=1
EOF

# Update package lists
echo "Updating package lists..."
sudo dnf makecache

# Install ClickHouse components
echo "Installing ClickHouse server and client..."
sudo dnf install -y clickhouse-server clickhouse-client clickhouse-common-static

# Configure ClickHouse directories
echo "Configuring ClickHouse directories..."
sudo mkdir -p /home/fedora/apps
sudo mkdir -p /home/fedora/agent
sudo chown -R clickhouse:clickhouse /var/lib/clickhouse /var/log/clickhouse-server /etc/clickhouse-server /etc/clickhouse-client /home/fedora/apps
sudo chmod -R o+x /home/fedora/apps

# Update ClickHouse server configuration file
echo "Updating ClickHouse server configuration..."
sudo sed -i 's|<user_files_path>/var/lib/clickhouse/user_files/</user_files_path>|<user_files_path>/home/fedora/apps</user_files_path>|g' /etc/clickhouse-server/config.xml

# Disable ClickHouse server autostart
echo "Disabling ClickHouse server autostart..."
sudo systemctl disable clickhouse-server.service

# Start ClickHouse server
echo "Starting ClickHouse server..."
sudo systemctl start clickhouse-server.service

# Verify ClickHouse server status
echo "Verifying ClickHouse server status..."
sudo systemctl status clickhouse-server.service --no-pager

# Check ClickHouse process and open port
echo "Checking ClickHouse processes and ports..."
ps -ef | grep clickhouse
sudo lsof -i:9000

echo "ClickHouse installation and configuration completed."
