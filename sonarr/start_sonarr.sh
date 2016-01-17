#!/bin/bash
source ~/.flexget/export.sh
mkdir -p $HOME/.sonarr
if [ "$1" == "-rm" ] ; then
	sudo docker rm -f sonarr
fi
RES=$(sudo docker ps --all | grep "sonarr")
if [ "$RES" == "" ] ; then
	sudo docker run --restart=always --name sonar -p 8989:8989 -v $HOME/.sonarr:/root/.config/NzbDrone -v $MEDIA_PATH:/root/Storage tokko/sonarr:latest &
else
	sudo docker start sonarr
fi	
