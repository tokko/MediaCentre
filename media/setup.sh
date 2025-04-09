#!/bin/bash

# Load configuration from config.env
if [ -f config.env ]; then
  source config.env
else
  echo "Error: config.env not found. Please create it with NFS_SERVER, NFS_SHARE, and DOMAIN."
  exit 1
fi

# Validate required variables
if [ -z "$NFS_SERVER" ] || [ -z "$NFS_SHARE" ] || [ -z "$DOMAIN" ]; then
  echo "Error: NFS_SERVER, NFS_SHARE, and DOMAIN must be defined in config.env."
  exit 1
fi

# Set user UID and GID for permissions
USER_UID=$(id -u)
USER_GID=$(id -g)

# Mount NFS share if not already mounted
if ! mount | grep -q "/mnt/nfs_share"; then
  sudo mkdir -p /mnt/nfs_share
  sudo mount -t nfs "$NFS_SERVER:$NFS_SHARE" /mnt/nfs_share
  if [ $? -ne 0 ]; then
    echo "Error: Failed to mount NFS share."
    exit 1
  fi
fi

# Create directory structure on NFS mount
sudo mkdir -p /mnt/nfs_share/media/{movies,tv,music,downloads,config/{sonarr,radarr,lidarr,overseerr,prowlarr,plex,transmission}}
sudo chown $USER_UID:$USER_GID /mnt/nfs_share/media -R

# Generate Docker Compose file for the media stack
cat <<EOF > docker-compose.yml
version: '3.8'

services:
  transmission:
    image: linuxserver/transmission
    environment:
      - PUID=$USER_UID
      - PGID=$USER_GID
    volumes:
      - /mnt/nfs_share/media/downloads:/downloads
      - /mnt/nfs_share/media/config/transmission:/config
    networks:
      - ingress_network
    deploy:
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.transmission.rule=Host(\`transmission.$DOMAIN\`)"
        - "traefik.http.routers.transmission.entrypoints=web"
        - "traefik.http.services.transmission.loadbalancer.server.port=9091"

  prowlarr:
    image: linuxserver/prowlarr
    environment:
      - PUID=$USER_UID
      - PGID=$USER_GID
    volumes:
      - /mnt/nfs_share/media/config/prowlarr:/config
    networks:
      - ingress_network
    deploy:
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.prowlarr.rule=Host(\`prowlarr.$DOMAIN\`)"
        - "traefik.http.routers.prowlarr.entrypoints=web"
        - "traefik.http.services.prowlarr.loadbalancer.server.port=9696"

  sonarr:
    image: linuxserver/sonarr
    environment:
      - PUID=$USER_UID
      - PGID=$USER_GID
    volumes:
      - /mnt/nfs_share/media/config/sonarr:/config
      - /mnt/nfs_share/media/tv:/tv
      - /mnt/nfs_share/media/downloads:/downloads
    networks:
      - ingress_network
    deploy:
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.sonarr.rule=Host(\`sonarr.$DOMAIN\`)"
        - "traefik.http.routers.sonarr.entrypoints=web"
        - "traefik.http.services.sonarr.loadbalancer.server.port=8989"

  radarr:
    image: linuxserver/radarr
    environment:
      - PUID=$USER_UID
      - PGID=$USER_GID
    volumes:
      - /mnt/nfs_share/media/config/radarr:/config
      - /mnt/nfs_share/media/movies:/movies
      - /mnt/nfs_share/media/downloads:/downloads
    networks:
      - ingress_network
    deploy:
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.radarr.rule=Host(\`radarr.$DOMAIN\`)"
        - "traefik.http.routers.radarr.entrypoints=web"
        - "traefik.http.services.radarr.loadbalancer.server.port=7878"

  lidarr:
    image: linuxserver/lidarr
    environment:
      - PUID=$USER_UID
      - PGID=$USER_GID
    volumes:
      - /mnt/nfs_share/media/config/lidarr:/config
      - /mnt/nfs_share/media/music:/music
      - /mnt/nfs_share/media/downloads:/downloads
    networks:
      - ingress_network
    deploy:
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.lidarr.rule=Host(\`lidarr.$DOMAIN\`)"
        - "traefik.http.routers.lidarr.entrypoints=web"
        - "traefik.http.services.lidarr.loadbalancer.server.port=8686"

  overseerr:
    image: sctx/overseerr
    environment:
      - PUID=$USER_UID
      - PGID=$USER_GID
    volumes:
      - /mnt/nfs_share/media/config/overseerr:/config
    networks:
      - ingress_network
    deploy:
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.overseerr.rule=Host(\`overseerr.$DOMAIN\`)"
        - "traefik.http.routers.overseerr.entrypoints=web"
        - "traefik.http.services.overseerr.loadbalancer.server.port=5055"

  plex:
    image: linuxserver/plex
    environment:
      - PUID=$USER_UID
      - PGID=$USER_GID
    volumes:
      - /mnt/nfs_share/media/config/plex:/config
      - /mnt/nfs_share/media/movies:/movies
      - /mnt/nfs_share/media/tv:/tv
      - /mnt/nfs_share/media/music:/music
    networks:
      - ingress_network
    deploy:
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.plex.rule=Host(\`plex.$DOMAIN\`)"
        - "traefik.http.routers.plex.entrypoints=web"
        - "traefik.http.services.plex.loadbalancer.server.port=32400"

networks:
  ingress_network:
    external: true
EOF

# Deploy the stack
docker stack deploy -c docker-compose.yml media

# Print manual configuration steps
echo "Media stack setup complete. Please follow these steps to configure the services:"
echo ""
echo "1. Access Prowlarr at http://prowlarr.$DOMAIN, set up indexers, and note the API key (Settings > General)."
echo "2. Access Sonarr at http://sonarr.$DOMAIN, go to Settings > Download Clients, add Transmission (Host: transmission.$DOMAIN, Port: 9091). Then, Settings > Indexers, add Prowlarr with its API key."
echo "3. Repeat step 2 for Radarr (movies) and Lidarr (music)."
echo "4. Access Overseerr at http://overseerr.$DOMAIN, configure Plex, Sonarr, and Radarr with their URLs and API keys."
echo "5. Access Plex at http://plex.$DOMAIN, set up libraries for /movies, /tv, /music."
