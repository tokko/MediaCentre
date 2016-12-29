#!/bin/bash
test "$2" = "" && curl https://raw.github.com/tokko/mediacentre/master/provision.sh | bash
test "$2" = "" && curl https://raw.github.com/tokko/mediacentre/master/docker.sh  | bash

test "$2" != "" && && sudo ./provision.sh
test "$2" != "" && && sudo ./docker.sh
sudo reboot
