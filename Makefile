SHELL := /bin/bash
all: transmissionimage sickrage couchpotato

sickrage: sickrage/Dockerfile
	sudo docker build -t tokko/sickrage:latest sickrage

pushsickrage: sickrage
	sudo docker push tokko/sickrage:latest

couchpotato: couchpotato/Dockerfile
	sudo docker build -t tokko/couchpotato couchpotato

pushcouchpotato: couchpotato
	sudo docker push tokko/couchpotato:latest

pushtransmission: transmissionimage
	sudo docker push tokko/transmission:latest

transmissionimage: transmission/*
	#cat <(echo $(DOCKER_BASE_IMAGE)) <(tail -n +2 transmission/Dockerfile.template) > transmission/Dockerfile
	sudo docker build --rm=true -t tokko/transmission:latest transmission

runtransmission: transmissionimage
	(sudo docker ps --all | grep "transmission") && sudo docker rm -f transmission || echo "no need to remove"
	transmission/start_transmission.sh

pushall: all
	sudo docker push tokko/transmission:latest
	sudo docker push tokko/couchpotato:latest
	sudo docker push tokko/sickrage:latest

runpushfileserver: fileserverimage runfileserver pushfileserver

fileserverimage: fileserver/* update.sh
	sudo docker build --rm=true -t tokko/fileserver:latest -f fileserver/Dockerfile .

runfileserver: fileserverimage
	(sudo docker ps | grep fileserver && sudo docker start fileserver) || fileserver/start_fileserver.sh 


pushfileserver: fileserverimage
	sudo docker push tokko/fileserver:latest
