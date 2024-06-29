#!/bin/bash
echo "Running installation script"
# Add your script's commands here

apt-get update
apt-get upgrade

apt-get install micro tmux rsync cron htop

