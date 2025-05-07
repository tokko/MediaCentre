#!/bin/bash
pgloader sqlite:///mnt/nfs_share/media/config/sonarr/sonarr.db postgresql://media_user:media_pass@10.0.1.57:5432/sonarr
pgloader sqlite:///mnt/nfs_share/media/config/radarr/radarr.db postgresql://media_user:media_pass@10.0.1.57:5432/radarr
pgloader sqlite:///mnt/nfs_share/media/config/prowlarr/prowlarr.db postgresql://media_user:media_pass@10.0.1.57:5432/prowlarr
pgloader sqlite:///mnt/nfs_share/media/config/overseerr/overseerr.db postgresql://media_user:media_pass@10.0.1.57:5432/overseerr
