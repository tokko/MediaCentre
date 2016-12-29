#!/bin/bash
sudo docker network create mediacentre

sudo docker run -d --restart=always \
--net=mediacentre \
-p 58846:58846 \
-p 8112:8112 \
-v $1/settings/deluge/config:/config \
-v $1/TV\ Shows/:/data \
-v $1:/root/Storage \
--name=deluge \
jordancrawford/rpi-deluge

sudo docker run -d --restart=always \
--net=mediacentre \
-p 8081:8081 \
-v $1:/root/Storage \
-v $1/settings/sickrage:/home \
-v $1/TV\ Shows:/media \
--name=sickrage \
napnap75/rpi-sickrage:latest

sudo docker run -d --restart=always \
--name=couchpotato \
-p 5050:5050 \
-v $1/Movies:/volumes/media \
-v $1:/root/Storage \
-v $1/settings/couchpotato:/volumes/data \
-v $1/settings/couchpotato:/volumes/config \
-v /etc/localtime:/etc/localtime:ro \
--net=mediacentre \
dtroncy/rpi-couchpotato
