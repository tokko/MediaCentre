#!/bin/bash

# Script to build, upload, and deploy Xiaomi vacuum Swarm stack

cd ~/MediaCentre/vacuum

# Build vacuum image
docker build -f vacuum/Dockerfile -t mediaserver:5000/vacuum:latest vacuum

# Build Node-RED image
# docker build -f nodered/Dockerfile -t mediaserver:5000/nodered:latest nodered

# Build alarm_poller image
docker build -f alarm/Dockerfile -t mediaserver:5000/alarm_poller:latest alarm

# Upload images to registry
docker push mediaserver:5000/vacuum:latest
#docker push mediaserver:5000/nodered:latest
docker push mediaserver:5000/alarm_poller:latest

# Deploy Swarm stack
docker stack deploy -c docker-compose.yml vacuum

echo "Deployment complete. Access API at https://vacuum.granbacken/list"
echo "Swagger UI at https://vacuum.granbacken/apidocs"
echo "Plejd webhook at https://vacuum.granbacken/plejd"
echo "Node-RED at https://vacuum.granbacken/nodered"
