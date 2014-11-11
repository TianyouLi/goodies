#!/bin/bash
sudo docker run --privileged -d -h lity-chrome-dev --name "lity-chrome-dev" -p 6022:22 -p 5901:5901 -p 6001:6001 tli7-sto.sh.intel.com:8080/chrome-dev:0.3 /bin/bash -e /etc/init.d/run.sh 
