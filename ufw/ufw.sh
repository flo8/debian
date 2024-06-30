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
