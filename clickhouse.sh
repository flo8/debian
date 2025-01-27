# Install Clickhouse
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
GNUPGHOME=$(mktemp -d)
sudo GNUPGHOME="$GNUPGHOME" gpg --no-default-keyring --keyring /usr/share/keyrings/clickhouse-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 8919F6BD2B48D754
sudo rm -rf "$GNUPGHOME"
sudo chmod +r /usr/share/keyrings/clickhouse-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/clickhouse-keyring.gpg] https://packages.clickhouse.com/deb stable main" | sudo tee \/etc/apt/sources.list.d/clickhouse.list
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y clickhouse-server clickhouse-client clickhouse-common-static

# Update clickhouse server conf file and permissions
sudo sed -i 's|<user_files_path>/var/lib/clickhouse/user_files/</user_files_path>|<user_files_path>/home/debian/apps</user_files_path>|g' /etc/clickhouse-server/config.xml
sudo chown -R clickhouse /var/lib/clickhouse /var/log/clickhouse-server /etc/clickhouse-server /etc/clickhouse-client
mkdir /home/debian/apps
mkdir /home/debian/agent

# Set read/execute permission for everyone on this folder (important for clickhouse)
sudo chmod -R o+x /home/debian/apps

# This can be used to check later on if it worked
# sudo -u clickhouse ls ./apps/8muolqjjt3cwsnjp/v5

# This finally didn't work, removing it!
# Install ACL tool
# sudo apt-get install -y acl
# sudo setfacl -R -m u:clickhouse:rx /home/debian/apps
# sudo setfacl -R -m d:u:clickhouse:rx /home/debian/apps
# Set default ACL for the directory and all future subdirectories and files
# sudo setfacl -m default:u:clickhouse:rx /home/debian/apps

# Make sure ClickHouse server is not started automatically after every reboot.
sudo systemctl enable clickhouse-server.service
sudo systemctl daemon-reload service

# Restart Clickhouse server
sudo service clickhouse-server restart
