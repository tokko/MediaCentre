#!/bin/bash

docker stack rm vacuum
docker build --no-cache -t mediaserver:5000/alarm_poller:latest .
docker push mediaserver:5000/alarm_poller:latest
docker stack deploy -c ../docker-compose.yml vacuum
