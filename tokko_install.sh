#!/bin/bash
sudo echo "UUID=ad10f3c4-5f68-4703-a86e-e3a36f34cb11 /mnt/PiDrive ext4 auto,nofail 0 0" >> /etc/fstab
sudo echo "//192.168.2.1/Elements /mnt/Samba cifs _netdev,nofail,guest 0 0" >> /etc/fstab
sudo mount -a
sudo mkdir -p /opt/steamstream
sudo curl https://raw.github.com/tokko/mediacentre/master/steamstream/steamstream.sh > /opt/steamstream/steamstream.sh
sudo curl https://raw.github.com/tokko/mediacentre/master/steamstream/steamserver.py > /opt/steamstream/steamserver.py
sudo chmod +x /opt/steamstream
crontab -l > mycron
echo "@reboot /opt/steamstream/steamserver.py" >> mycron
crontab mycron
rm mycron
python /opt/steamstream/steamserver.py &
