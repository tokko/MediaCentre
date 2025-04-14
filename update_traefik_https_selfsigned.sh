#!/bin/bash

# Exit on error
set -e

# Base directory
BASE_DIR="/home/pi/MediaCentre"

# Backup existing docker-compose.yml files
echo "Backing up existing docker-compose.yml files..."
for stack in ingress infra media privacy monitoring; do
    if [ -f "$BASE_DIR/$stack/docker-compose.yml" ]; then
        cp "$BASE_DIR/$stack/docker-compose.yml" "$BASE_DIR/$stack/docker-compose.yml.bak-$(date +%F-%H%M%S)"
        echo "Backed up $stack/docker-compose.yml"
    else
        echo "Error: $stack/docker-compose.yml not found"
        exit 1
    fi
done

# Write new ingress/docker-compose.yml
echo "Writing new ingress/docker-compose.yml..."
cat > "$BASE_DIR/ingress/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  traefik:
    image: traefik:v2.11
    command:
      - "--api.insecure=true"
      - "--api.dashboard=true"
      - "--providers.docker=true"
      - "--providers.docker.swarmMode=true"
      - "--providers.docker.exposedByDefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.traefik.address=:8080"
      - "--metrics.prometheus=true"
      - "--metrics.prometheus.buckets=0.1,0.3,1.2,5.0"
      - "--log.level=DEBUG"
    deploy:
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.traefik.rule=Host(`traefik.granbacken`)"
        - "traefik.http.routers.traefik.service=api@internal"
        - "traefik.http.routers.traefik.entrypoints=web,websecure"
        - "traefik.http.routers.traefik.tls=true"
        - "traefik.http.services.traefik.loadbalancer.server.port=8080"
        - "traefik.http.routers.metrics.rule=Host(`traefik.granbacken`) && Path(`/metrics`)"
        - "traefik.http.routers.metrics.service=prometheus@internal"
        - "traefik.http.routers.metrics.entrypoints=traefik"
        - "traefik.http.routers.redirect-to-https.rule=HostRegexp(`{any:.+}`)"
        - "traefik.http.routers.redirect-to-https.entrypoints=web"
        - "traefik.http.routers.redirect-to-https.middlewares=redirect-to-https"
        - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"
        - "traefik.http.middlewares.redirect-to-https.redirectscheme.permanent=true"
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - ingress_network

  unbound:
    image: klutchell/unbound:latest
    deploy:
      placement:
        constraints:
          - node.hostname == mediaserver
    ports:
      - "54:53/udp"
      - "54:53/tcp"
    volumes:
      - ./unbound.conf:/etc/unbound/unbound.conf:ro
    networks:
      - ingress_network

networks:
  ingress_network:
    external: true
EOF

# Write new infra/docker-compose.yml
echo "Writing new infra/docker-compose.yml..."
cat > "$BASE_DIR/infra/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  portainer:
    image: portainer/portainer-ce:latest
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks:
      - ingress_network
    deploy:
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.portainer.rule=Host(`portainer.granbacken`)"
        - "traefik.http.routers.portainer.entrypoints=web,websecure"
        - "traefik.http.routers.portainer.tls=true"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"
        - "traefik.docker.network=ingress_network"

  portainer-agent:
    image: portainer/agent:latest
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - ingress_network
    deploy:
      mode: global

  watchtower:
    image: containrrr/watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - ingress_network
    environment:
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_SCHEDULE=0 0 4 * * *
      - DISABLE_HTTP=false
    deploy:
      placement:
        constraints: [node.role == manager]

volumes:
  portainer_data:

networks:
  ingress_network:
    external: true
EOF

# Write new media/docker-compose.yml
echo "Writing new media/docker-compose.yml..."
cat > "$BASE_DIR/media/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  tor_proxy:
    image: dperson/torproxy:latest
    ports:
      - "9050:9050"
    networks:
      - ingress_network
    deploy:
      placement:
        constraints:
          - node.hostname == mediaserver

  transmission:
    image: haugene/transmission-openvpn:latest
    environment:
      - PUID=1000
      - PGID=1000
      - OPENVPN_PROVIDER=NORDVPN
      - OPENVPN_USERNAME=6LF3z2srZKveb6qm6hiUJUmx
      - OPENVPN_PASSWORD=ZEC6inpHbH8psyHL1TguLeV4
      - OPENVPN_CONFIG=sg514
      - TRANSMISSION_DOWNLOAD_DIR=/downloads/completed
      - TRANSMISSION_INCOMPLETE_DIR=/downloads/incomplete
      - LOCAL_NETWORK=192.168.68.0/24
    volumes:
      - /mnt/nfs_share/media/downloads:/downloads
      - /mnt/nfs_share/media/config/transmission:/config
    networks:
      - ingress_network
    deploy:
      placement:
        constraints:
          - node.hostname == mediaserver
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.transmission.rule=Host(`transmission.granbacken`)"
        - "traefik.http.routers.transmission.entrypoints=web,websecure"
        - "traefik.http.routers.transmission.tls=true"
        - "traefik.http.services.transmission.loadbalancer.server.port=9091"
        - "traefik.docker.network=ingress_network"
    cap_add:
      - NET_ADMIN

  prowlarr:
    image: linuxserver/prowlarr:latest
    environment:
      - PUID=911
      - PGID=911
      - LOG_LEVEL=trace
      - PROXY_HOST=tor_proxy
      - PROXY_PORT=9050
    volumes:
      - /mnt/nfs_share/media/config/prowlarr:/config
      - ./prowlarr-indexers/Custom:/config/Indexers
    networks:
      - ingress_network
    deploy:
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.prowlarr.rule=Host(`prowlarr.granbacken`)"
        - "traefik.http.routers.prowlarr.entrypoints=web,websecure"
        - "traefik.http.routers.prowlarr.tls=true"
        - "traefik.http.services.prowlarr.loadbalancer.server.port=9696"
        - "traefik.docker.network=ingress_network"

  sonarr:
    image: linuxserver/sonarr
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - /mnt/nfs_share/media/config/sonarr:/config
      - /mnt/nfs_share/media/tv:/tv
      - /mnt/nfs_share/media/downloads:/downloads
    networks:
      - ingress_network
    deploy:
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.sonarr.rule=Host(`sonarr.granbacken`)"
        - "traefik.http.routers.sonarr.entrypoints=web,websecure"
        - "traefik.http.routers.sonarr.tls=true"
        - "traefik.http.services.sonarr.loadbalancer.server.port=8989"
        - "traefik.docker.network=ingress_network"

  radarr:
    image: linuxserver/radarr
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - /mnt/nfs_share/media/config/radarr:/config
      - /mnt/nfs_share/media/movies:/movies
      - /mnt/nfs_share/media/downloads:/downloads
    networks:
      - ingress_network
    deploy:
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.radarr.rule=Host(`radarr.granbacken`)"
        - "traefik.http.routers.radarr.entrypoints=web,websecure"
        - "traefik.http.routers.radarr.tls=true"
        - "traefik.http.services.radarr.loadbalancer.server.port=7878"
        - "traefik.docker.network=ingress_network"

  lidarr:
    image: linuxserver/lidarr
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - /mnt/nfs_share/media/config/lidarr:/config
      - /mnt/nfs_share/media/music:/music
      - /mnt/nfs_share/media/downloads:/downloads
    networks:
      - ingress_network
    deploy:
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.lidarr.rule=Host(`lidarr.granbacken`)"
        - "traefik.http.routers.lidarr.entrypoints=web,websecure"
        - "traefik.http.routers.lidarr.tls=true"
        - "traefik.http.services.lidarr.loadbalancer.server.port=8686"
        - "traefik.docker.network=ingress_network"

  overseerr:
    image: sctx/overseerr:latest
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Stockholm
    volumes:
      - /mnt/nfs_share/media/config/overseerr:/app/config
    networks:
      - ingress_network
    deploy:
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.overseerr.rule=Host(`overseerr.granbacken`)"
        - "traefik.http.routers.overseerr.entrypoints=web,websecure"
        - "traefik.http.routers.overseerr.tls=true"
        - "traefik.http.services.overseerr.loadbalancer.server.port=5055"
        - "traefik.docker.network=ingress_network"

  plex:
    image: linuxserver/plex
    environment:
      - PUID=1000
      - PGID=1000
      - PLEX_CLAIM=claim-fVcPQGeBVfDqcbYBx1r_
    volumes:
      - /mnt/nfs_share/media/config/plex:/config
      - /mnt/nfs_share/media/movies:/movies
      - /mnt/nfs_share/media/tv:/tv
      - /mnt/nfs_share/media/music:/music
    networks:
      - ingress_network
    deploy:
      placement:
        constraints:
          - node.hostname == mediaserver
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.plex.rule=Host(`plex.granbacken`)"
        - "traefik.http.routers.plex.entrypoints=web,websecure"
        - "traefik.http.routers.plex.tls=true"
        - "traefik.http.services.plex.loadbalancer.server.port=32400"
        - "traefik.docker.network=ingress_network"

networks:
  ingress_network:
    external: true
EOF

# Write new privacy/docker-compose.yml
echo "Writing new privacy/docker-compose.yml..."
cat > "$BASE_DIR/privacy/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  adguard:
    image: adguard/adguardhome:latest
    volumes:
      - /mnt/nfs_share/privacy/work:/opt/adguardhome/work
      - /mnt/nfs_share/privacy/conf:/opt/adguardhome/conf
    networks:
      - ingress_network
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "8081:80"
    deploy:
      placement:
        constraints: [node.hostname == mediaserver]
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.adguard.rule=Host(`adguard.granbacken`)"
        - "traefik.http.routers.adguard.entrypoints=web,websecure"
        - "traefik.http.routers.adguard.tls=true"
        - "traefik.http.services.adguard.loadbalancer.server.port=80"
        - "traefik.http.services.adguard.loadbalancer.passhostheader=true"
        - "traefik.http.services.adguard.loadbalancer.sticky=true"
        - "traefik.http.services.adguard.loadbalancer.sticky.cookie.name=adguard_session"
        - "traefik.http.services.adguard.loadbalancer.sticky.cookie.httponly=true"
        - "traefik.docker.network=ingress_network"

  privoxy:
    image: dockage/tor-privoxy:latest
    volumes:
      - /mnt/nfs_share/privacy/privoxy:/etc/privoxy
    ports:
      - "8118:8118/tcp"
    networks:
      - ingress_network
    deploy:
      placement:
        constraints: [node.hostname == mediaserver]
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.privoxy.rule=Host(`privoxy.granbacken`)"
        - "traefik.http.routers.privoxy.entrypoints=web,websecure"
        - "traefik.http.routers.privoxy.tls=true"
        - "traefik.http.services.privoxy.loadbalancer.server.port=8118"
        - "traefik.http.services.privoxy.loadbalancer.passhostheader=true"
        - "traefik.docker.network=ingress_network"

networks:
  ingress_network:
    external: true
EOF

# Write new monitoring/docker-compose.yml
echo "Writing new monitoring/docker-compose.yml..."
cat > "$BASE_DIR/monitoring/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:v2.30.3
    volumes:
      - prometheus_data:/prometheus
      - /home/pi/MediaCentre/monitoring/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
    networks:
      - ingress_network
    deploy:
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.prometheus.rule=Host(`prometheus.granbacken`)"
        - "traefik.http.routers.prometheus.entrypoints=web,websecure"
        - "traefik.http.routers.prometheus.tls=true"
        - "traefik.http.services.prometheus.loadbalancer.server.port=9090"
        - "traefik.docker.network=ingress_network"
      resources:
        limits:
          memory: 512m

  grafana:
    image: grafana/grafana:8.2.1
    volumes:
      - grafana_data:/var/lib/grafana
      - /home/pi/MediaCentre/monitoring/grafana/provisioning:/etc/grafana/provisioning
      - /home/pi/MediaCentre/monitoring/grafana/dashboards:/var/lib/grafana/dashboards
    networks:
      - ingress_network
    environment:
      - GF_INSTALL_PLUGINS=grafana-piechart-panel
    deploy:
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.grafana.rule=Host(`grafana.granbacken`)"
        - "traefik.http.routers.grafana.entrypoints=web,websecure"
        - "traefik.http.routers.grafana.tls=true"
        - "traefik.http.services.grafana.loadbalancer.server.port=3000"
        - "traefik.docker.network=ingress_network"
      resources:
        limits:
          memory: 512m

  node-exporter:
    image: prom/node-exporter:v1.3.1
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    networks:
      - ingress_network
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
    deploy:
      mode: global
      placement:
        constraints: [node.role == manager]

  cadvisor:
    image: zcube/cadvisor:latest
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
      - /etc/machine-id:/etc/machine-id:ro
    networks:
      - ingress_network
    user: "0:0"
    deploy:
      mode: global
      placement:
        constraints: [node.role == manager]
      resources:
        limits:
          memory: 128m
        reservations:
          memory: 64m

  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.14.0
    volumes:
      - elasticsearch_data:/usr/share/elasticsearch/data
    networks:
      - ingress_network
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - "ES_JAVA_OPTS=-Xms256m -Xmx256m"
    deploy:
      placement:
        constraints: [node.role == manager]
      resources:
        limits:
          memory: 512m
        reservations:
          memory: 256m

  kibana:
    image: docker.elastic.co/kibana/kibana:8.14.0
    volumes:
      - /home/pi/MediaCentre/monitoring/config/kibana.yml:/usr/share/kibana/config/kibana.yml
    networks:
      - ingress_network
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    deploy:
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.kibana.rule=Host(`kibana.granbacken`)"
        - "traefik.http.routers.kibana.entrypoints=web,websecure"
        - "traefik.http.routers.kibana.tls=true"
        - "traefik.http.services.kibana.loadbalancer.server.port=5601"
        - "traefik.http.services.kibana.loadbalancer.healthcheck.path=/api/status"
        - "traefik.http.services.kibana.loadbalancer.healthcheck.interval=15s"
        - "traefik.http.services.kibana.loadbalancer.healthcheck.timeout=10s"
        - "traefik.docker.network=ingress_network"
      resources:
        limits:
          memory: 256m
        reservations:
          memory: 128m
    depends_on:
      - elasticsearch

  filebeat:
    image: docker.elastic.co/beats/filebeat:8.14.0
    volumes:
      - /home/pi/MediaCentre/monitoring/filebeat/filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
      - /var/lib/docker:/var/lib/docker:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - filebeat_logs:/var/log/filebeat
      - filebeat_data:/usr/share/filebeat/data
    networks:
      - ingress_network
    user: root
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
      - KIBANA_HOST=http://kibana:5601
    deploy:
      mode: global
      placement:
        constraints: [node.role == manager]
      resources:
        limits:
          memory: 128m
        reservations:
          memory: 64m
    depends_on:
      - elasticsearch
      - kibana

volumes:
  prometheus_data:
  grafana_data:
  elasticsearch_data:
  filebeat_data:
  filebeat_logs:

networks:
  ingress_network:
    external: true
EOF

# Set permissions
echo "Setting permissions..."
for stack in ingress infra media privacy monitoring; do
    chmod 644 "$BASE_DIR/$stack/docker-compose.yml"
done

# Redeploy stacks
echo "Redeploying stacks..."
for stack in ingress infra media privacy monitoring; do
    echo "Deploying $stack stack..."
    cd "$BASE_DIR/$stack"
    docker stack deploy -c docker-compose.yml "$stack"
done

echo "Update complete! Check Traefik logs and test HTTPS URLs."
echo "Note: You'll see self-signed certificate warnings in browsers."
echo "Run: docker service logs ingress_traefik --no-trunc"
echo "Test: curl -v --insecure https://kibana.granbacken"
