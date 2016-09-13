#!/bin/bash
sudo echo "export TRAKT_USERNAME=tokko" >> /etc/profile
sudo echo "export TRAKT_ACCOUNT=tokko" >> /etc/profile
sudo echo "export MEDIA_PATH=/media/Elements" >> /etc/profile
sudo echo "export UPDATE_IP=84.55.125.28 #don't touch" >> /etc/profile
sudo echo "export UPDATE_PORT=1337 #don't touch" >> /etc/profile
sudo echo "UUID=$1 /media/Elements ntfs-3g auto,users,permissions 0 0" >> /etc/fstab
