#!/bin/bash
#source ~/.bashrc
mkdir -p $HOME/.transmission
if [ "$1" == "-rm" ] ; then
	sudo docker rm -f transmission
	$1 = ""
fi
RES=sudo docker ps --all | grep "transmission"
if [ "$RES" == "" ] ; then
	sudo docker create --restart=always -p 9091:9091 --net=mediacentre --name transmission -v $MEDIA_PATH:/media/Storage -v $HOME/.transmission:/var/lib/transmission-daemon tokko/transmission:latest
fi	

if [ "$1" == "" ] ; then
	sudo docker start transmission
fi
