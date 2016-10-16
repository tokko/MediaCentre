#!/bin/bash

docker run -d --restart=always --net=mediacentre -v /media/Elements/Downloads/deluge/config:/config -v /media/Elements/Downloads/:/data -p 58846:58846 -p 8112:8112 --name=deluge jordancrawford/rpi-deluge
