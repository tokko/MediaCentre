#!/bin/bash
sudo echo "UUID=ad10f3c4-5f68-4703-a86e-e3a36f34cb11 /mnt/PiDrive ext4 auto,nofail 0 0" >> /etc/fstab
sudo echo "//192.168.2.1/Elements /mnt/Samba cifs _netdev,nofail,guest 0 0" >> /etc/fstab
sudo mount -a
