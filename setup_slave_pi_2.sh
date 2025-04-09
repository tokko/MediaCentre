#!/bin/bash

# Exit on any error
set -e

# Ensure script runs with sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo"
  exit 1
fi

echo "Starting Raspberry Pi 2 update and configuration..."

# Step 1: Full system update and upgrade
echo "Updating package lists..."
apt-get update -y

echo "Upgrading all packages..."
apt-get full-upgrade -y

# Step 2: Clean up unused packages and prune
echo "Removing unused packages..."
apt-get autoremove -y

echo "Cleaning package cache..."
apt-get autoclean -y

# Step 3: Expand filesystem (for Raspberry Pi)
echo "Expanding filesystem..."
raspi-config --expand-rootfs

# Step 4: Update raspi-config
echo "Updating raspi-config..."
apt-get install -y raspi-config

# Step 5: Install required packages
echo "Installing nfs-common, docker, docker-compose, vim, and git..."

# Install nfs-common
apt-get install -y nfs-common

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh
usermod -aG docker pi  # Add pi user to docker group

# Install Docker Compose (standalone binary, no pip)
echo "Installing Docker Compose v2..."
DOCKER_COMPOSE_VERSION="v2.24.7"  # Latest stable version as of April 2025; check https://github.com/docker/compose/releases
ARCH="armv7"  # For Raspberry Pi 2 (ARMv7)
curl -SL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-${ARCH}" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose  # Ensure it's in PATH

# Install vim and git
apt-get install -y vim git

# Step 6: Configure NFS mount
echo "Configuring NFS mount from 192.168.68.10:/mnt/nfs_share..."

# Create mount point if it doesn't exist
mkdir -p /mnt/nfs_share

# Backup fstab
cp /etc/fstab /etc/fstab.bak

# Add NFS mount to /etc/fstab if not already present
if ! grep -q "192.168.68.10:/mnt/nfs_share" /etc/fstab; then
  echo "192.168.68.10:/mnt/nfs_share /mnt/nfs_share nfs defaults 0 0" >> /etc/fstab
else
  echo "NFS mount already exists in /etc/fstab"
fi

# Test the mount
echo "Testing NFS mount..."
mount -a
if [ $? -eq 0 ]; then
  echo "NFS mount successful"
else
  echo "NFS mount failed. Check network or server config."
  exit 1
fi

# Step 7: Reboot
echo "Rebooting system in 5 seconds..."
sleep 5
reboot

echo "Script completed. System will reboot."
