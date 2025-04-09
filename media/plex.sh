#!/bin/bash
docker exec -it $(docker ps -q -f name=media_plex) bash
curl -X POST -H "X-Plex-Claim-Token: claim-7LEMsyqmKAtDu17wcL6s" http://localhost:32400/api/v2/server/claim
exit
docker service update --force media_plex
