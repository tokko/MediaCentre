#!/bin/sh

docker stack rm ingress
docker stack rm infra
docker stack deploy -c ingress/docker-compose.yml ingress
docker stack deploy -c infra/docker-compose.yml infra
