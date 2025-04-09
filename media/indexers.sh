#!/bin/bash

# Exit on error
set -e

# Define base directory
BASE_DIR="$HOME/MediaCentre/media"
INDEXER_DIR="$BASE_DIR/prowlarr-indexers/Custom"

echo "Generating Prowlarr indexer configuration..."

# Create subfolder if it doesn't exist
mkdir -p "$INDEXER_DIR"
cd "$INDEXER_DIR"

# Function to create YAML file
create_yaml() {
  local id="$1"
  local name="$2"
  local base_url="$3"
  cat <<EOF > "${id}.yml"
id: ${id}
name: ${name}
description: ${name} indexer for Prowlarr
language: en-us
type: torznab
caps:
  categories:
    - id: 2000
      name: TV
settings:
  - name: baseUrl
    value: ${base_url}
  - name: apiPath
    value: /torznab/api
EOF
  echo "Created $INDEXER_DIR/${id}.yml"
}

# Generate YAML files for each indexer
create_yaml "1337x-custom" "1337x (Custom)" "https://1337x.to"
create_yaml "eztv-custom" "EZTV (Custom)" "https://eztv.re"
create_yaml "rarbg-custom" "RARBG (Custom)" "https://rarbg.to"
create_yaml "piratebay-custom" "The Pirate Bay (Custom)" "https://thepiratebay.org"
create_yaml "limetorrents-custom" "LimeTorrents (Custom)" "https://www.limetorrents.lol"

# Set permissions
chown -R pi:pi "$INDEXER_DIR"
chmod -R 644 "$INDEXER_DIR"/*.yml

# Update docker-compose.yml to mount the indexers
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"
if ! grep -q "prowlarr-indexers" "$COMPOSE_FILE"; then
  echo "Updating $COMPOSE_FILE to mount indexer definitions..."
  sed -i '/prowlarr:/,/networks:/c\
  prowlarr:\
    image: linuxserver/prowlarr:latest\
    deploy:\
      labels:\
        - "traefik.enable=true"\
        - "traefik.http.routers.prowlarr.rule=Host(`prowlarr.granbacken`)"\
        - "traefik.http.services.prowlarr.loadbalancer.server.port=9696"\
        - "traefik.http.routers.prowlarr.entrypoints=web"\
    volumes:\
      - /mnt/nfs_share/media/config/prowlarr:/config\
      - ./prowlarr-indexers:/config/Indexers\
    networks:\
      - ingress_network' "$COMPOSE_FILE"
else
  echo "Indexer mount already exists in $COMPOSE_FILE"
fi

# Redeploy the stack
echo "Redeploying media stack..."
docker stack deploy -c "$COMPOSE_FILE" media

echo "Indexer setup complete. Check Prowlarr UI at http://prowlarr.granbacken."
