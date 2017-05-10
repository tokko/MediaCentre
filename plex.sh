#!/bin/bash
docker run -d \
    --name plex \
    -p 32400:32400 \
    -v /mnt/PiDrive/settings/plex:/config \
    -v /mnt/PiDrive/Videos:/media \
    remlabm/rpi-plex-server
