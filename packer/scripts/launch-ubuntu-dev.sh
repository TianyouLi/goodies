#!/bin/bash

#######################################################################
## The command line to start a container for costa testing
#  The parameters explained as below:
#
#  1. current stable image: tli7-sto.sh.intel.com:5000/costa-dev:0.6
#  2. port mapping:
#     ssh:                host 7022  -> container 22
#     vnc:                host 40389 -> container 3389
#######################################################################
## Above information will update according to any changes of system!!!
#######################################################################

sudo docker run --privileged -d -h lity-ubuntu-dev --name "lity-ubuntu-dev" -p 7022:22 -p 40389:3389  lity/ubuntu-dev:0.2 /bin/bash -e /etc/init.d/run.sh
