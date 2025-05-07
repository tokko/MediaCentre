#!/bin/bash

docker stack rm vacuum
docker build -t mediaserver:5000/vacuum:latest .
docker push mediaserver:5000/vacuum:latest
docker stack deploy -c ../docker-compose.yml vacuum
