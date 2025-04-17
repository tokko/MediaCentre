#!/bin/bash

# Script to update replica counts and force redistribution across Docker Swarm cluster

set -e

echo "Updating replica counts and redistributing Swarm services..."

# Define service replica counts
declare -A replicas=(
  ["infra_portainer"]=1
  ["infra_portainer-agent"]="global"
  ["infra_registry"]=1
  ["infra_watchtower"]=1
  ["infra_traefik"]=2
  ["infra_unbound"]=2
  ["media_lidarr"]=1
  ["media_overseerr"]=1
  ["media_plex"]=1
  ["media_prowlarr"]=1
  ["media_radarr"]=1
  ["media_sonarr"]=1
  ["media_tor_proxy"]=1
  ["media_transmission"]=1
  ["monitoring_cadvisor"]="global"
  ["monitoring_elasticsearch"]=1
  ["monitoring_filebeat"]="global"
  ["monitoring_grafana"]=1
  ["monitoring_kibana"]=1
  ["monitoring_node-exporter"]="global"
  ["monitoring_prometheus"]=1
  ["privacy_adguard"]=2
  ["privacy_privoxy"]=1
  ["vacuum_vacuum"]=2
  ["vacuum_plejd"]=1
  ["vacuum_nodered"]=1
)

# Update vacuum stack (in ~/MediaCentre/vacuum)
echo "Deploying vacuum stack with updated replicas..."
cd ~/MediaCentre/vacuum
docker build -f vacuum/Dockerfile -t mediaserver:5000/vacuum:latest vacuum/vacuum
docker build -f nodered/Dockerfile -t mediaserver:5000/nodered:latest vacuum/nodered
docker push mediaserver:5000/vacuum:latest
docker push mediaserver:5000/nodered:latest
docker stack deploy -c vacuum/docker-compose.yml vacuum

# Update other stacks (assumed in ~/MediaCentre/<category>)
# Adjust paths if different
for stack in infra media monitoring privacy; do
  if [ -d "~/MediaCentre/$stack" ]; then
    echo "Deploying $stack stack..."
    cd "~/MediaCentre/$stack"
    if [ -f "docker-compose.yml" ]; then
      docker stack deploy -c docker-compose.yml "$stack"
    else
      echo "No docker-compose.yml found in ~/MediaCentre/$stack"
    fi
  else
    echo "Directory ~/MediaCentre/$stack not found"
  fi
done

# Force redistribution of services
for service in "${!replicas[@]}"; do
  if [[ "${replicas[$service]}" == "global" ]]; then
    echo "Updating $service (global mode)..."
    docker service update --force "$service"
  else
    echo "Updating $service with ${replicas[$service]} replicas..."
    docker service update --replicas "${replicas[$service]}" --force "$service"
  fi
done

echo "Swarm redistribution complete. Checking services..."
docker service ls

echo "Done. Verify service distribution with 'docker service ps <service>'."
