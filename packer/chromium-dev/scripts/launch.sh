#!/bin/bash
ID=`sudo docker ps -a | grep lity-chrome-dev | cut -d " " -f 1`

sudo docker stop $ID
sudo docker rm $ID
sudo docker run --privileged -d -h lity-chrome-dev --name "lity-chrome-dev" -p 6022:22 tli7-sto.sh.intel.com:8080/chrome-dev:0.3 /bin/bash -e /etc/init.d/run.sh 
