#!/bin/bash
docker stop $(docker ps -aq)
sudo service kodi stop
echo "on 0" | cec-client -s
moonlight stream -app Steam -1080 -60fps -localaudio
sudo service kodi start
docker start $(docker ps -aq)
echo "on 0" | cec-client -s
