#!/bin/bash
test "$3" = "" && curl https://raw.github.com/tokko/mediacentre/master/provision.sh | bash
test "$3" = "" && curl https://raw.github.com/tokko/mediacentre/master/docker.sh  | bash $1 $2

test "$3" != "" &&sudo ./provision.sh
test "$3" != "" &&sudo ./docker.sh $1 $2
sudo reboot
