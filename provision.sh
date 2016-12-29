#!/bin/bash
curl -s https://packagecloud.io/install/repositories/Hypriot/Schatzkiste/script.deb.sh | sudo bash
sudo apt-get -y dist-upgrade
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y kodi docker-hypriot=1.10.3-1 docker-compose=1.9.0-23
sudo sed -i -e "\$i service docker start\n" /etc/rc.local
sudo perl -pi -e "s/ENABLED=0/ENABLED=1/g" /etc/default/kodi
sudo systemctl enable docker
sudo gpasswd -a $USER docker
sudo usermod -a -G audio kodi
sudo usermod -a -G video kodi
sudo usermod -a -G input kodi
sudo usermod -a -G dialout kodi
sudo usermod -a -G plugdev kodi
sudo usermod -a -G tty kodi
