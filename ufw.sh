# Update system and install UFW
echo "Updating system and installing UFW..."
sudo apt update && sudo apt install -y ufw

# Set default policies
echo "Setting default UFW policies..."
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH connections
echo "Allowing SSH access on port 22..."
sudo ufw allow 22/tcp

# Enable rate limiting on SSH to mitigate brute-force attacks
echo "Enabling rate limiting for SSH..."
sudo ufw limit 22/tcp

# Enable UFW logging for monitoring purposes
echo "Enabling UFW logging..."
sudo ufw logging on

# Enable UFW
echo "Enabling UFW..."
echo "y" | sudo ufw enable  # The 'echo "y"' part automatically confirms the operation

# Display UFW status and rules
echo "UFW status:"
sudo ufw status verbose

echo "Firewall setup complete."

# Adds fail2ban configuration
sudo wget -O /etc/fail2ban/jail.local https://raw.githubusercontent.com/flo8/debian/main/jail.local
sudo systemctl start fail2ban
sudo systemctl enable fail2ban

# Display status of fail2ban
sudo fail2ban-client status
sudo fail2ban-client status sshd

# Adds UFW and configure it
wget -qO- https://raw.githubusercontent.com/flo8/debian/main/ufw.sh | bash

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

echo "Machine secured."
