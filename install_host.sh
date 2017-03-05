#!/bin/bash
test "$3" = "" && curl https://raw.github.com/tokko/mediacentre/master/provision.sh | bash
test "$3" = "" && curl https://raw.github.com/tokko/mediacentre/master/docker.sh  | bash

sudo ./provision.sh
sudo ./docker.sh $1 $2
sudo reboot
