#!/bin/bash

# Load configuration from config.env
if [ -f config.env ]; then
  source config.env
else
  echo "Error: config.env not found. Please create it with NFS_SERVER, NFS_SHARE, and DOMAIN."
  exit 1
fi

# Validate required variables
if [ -z "$NFS_SERVER" ] || [ -z "$NFS_SHARE" ]; then
  echo "Error: NFS_SERVER, NFS_SHARE, and DOMAIN must be defined in config.env."
  exit 1
fi

# Set user UID and GID for permissions
USER_UID=$(id -u)
USER_GID=$(id -g)

# Mount NFS share if not already mounted
if ! mount | grep -q "/mnt/nfs_share"; then
  sudo mkdir -p /mnt/nfs_share
  sudo mount -t nfs "$NFS_SERVER:$NFS_SHARE" /mnt/nfs_share
  if [ $? -ne 0 ]; then
    echo "Error: Failed to mount NFS share."
    exit 1
  fi
fi

# Create directory structure on NFS mount
sudo mkdir -p /mnt/nfs_share/media/{movies,tv,music,downloads/{complete,incomplete},watch,config/{sonarr,radarr,lidarr,overseerr,prowlarr,plex,transmission}}
sudo chown $USER_UID:$USER_GID /mnt/nfs_share/media -R

