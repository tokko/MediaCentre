#!/bin/bash

# Exit on any error
set -e

# Ensure script runs with sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo"
  exit 1
fi

echo "Starting Raspberry Pi 4 (1GB) update and configuration..."

# Step 1: Consolidated system update, upgrade, and package installation
echo "Updating system and installing packages..."
apt-get update && apt-get full-upgrade -y --no-install-recommends && apt-get install -y --no-install-recommends nfs-common raspi-config vim git gcc python3-dev rpi-update network-manager && apt-get autoremove -y && apt-get autoclean -y

# Step 2: Raspberry Pi-specific updates
echo "Applying Raspberry Pi-specific updates..."

# Expand filesystem
echo "Expanding filesystem..."
raspi-config --expand-rootfs

# Update firmware (optional, uncomment if needed)
# echo "Updating firmware with rpi-update..."
# rpi-update

# Optimize boot configuration
echo "Configuring boot parameters..."
if ! grep -q "gpu_mem=16" /boot/config.txt; then
  echo "gpu_mem=16" >> /boot/config.txt
fi
if ! grep -q "dtoverlay=disable-bt" /boot/config.txt; then
  echo "dtoverlay=disable-bt" >> /boot/config.txt
fi

# Increase swap size for 1GB RAM stability
echo "Configuring swap size..."
SWAP_FILE="/etc/dphys-swapfile"
if [ -f "$SWAP_FILE" ]; then
  sed -i 's/CONF_SWAPSIZE=.*/CONF_SWAPSIZE=512/' "$SWAP_FILE"
  systemctl restart dphys-swapfile
fi

# Step 3: Configure Wi-Fi for Anik-IoT using nmcli
echo "Configuring Wi-Fi for Anik-IoT..."
nmcli device wifi rescan
sleep 2  # Wait for scan to complete
nmcli device wifi connect "Anik-IoT" password "Granbacken2022"
sleep 5  # Wait for connection
# Verify Wi-Fi connection
if nmcli connection show --active | grep -q "Anik-IoT"; then
  echo "Wi-Fi connected to Anik-IoT"
else
  echo "Wi-Fi connection failed. Check SSID, password, or signal."
  exit 1
fi

# Step 4: Install Docker
echo "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh
usermod -aG docker pi  # Add pi user to docker group

# Step 5: Install Docker Compose
echo "Installing Docker Compose v2..."
DOCKER_COMPOSE_VERSION="v2.30.2"  # Latest stable version as of April 2025; check https://github.com/docker/compose/releases
ARCH="aarch64"  # For Raspberry Pi 4 (ARMv8-A)
curl -SL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-${ARCH}" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose  # Ensure it's in PATH

# Verify Docker Compose
if ! docker-compose --version; then
  echo "Docker Compose installation failed"
  exit 1
fi

# Step 6: Configure NFS mount
echo "Configuring NFS mount from 192.168.68.10:/mnt/nfs_share..."
mkdir -p /mnt/nfs_share
cp /etc/fstab /etc/fstab.bak
if ! grep -q "192.168.68.10:/mnt/nfs_share" /etc/fstab; then
  echo "192.168.68.10:/mnt/nfs_share /mnt/nfs_share nfs defaults 0 0" >> /etc/fstab
else
  echo "NFS mount already exists in /etc/fstab"
fi

# Test NFS mount
echo "Testing NFS mount..."
mount -a
if [ $? -eq 0 ]; then
  echo "NFS mount successful"
else
  echo "NFS mount failed. Check network or server config."
  exit 1
fi

# Step 7: Clean up
echo "Cleaning up..."
apt-get clean

# Step 8: Reboot
echo "Rebooting system in 5 seconds..."
sleep 5
reboot

echo "Script completed. System will reboot."
