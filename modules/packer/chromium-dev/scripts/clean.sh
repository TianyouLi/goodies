#!/bin/bash
ID=`sudo docker ps -a | grep lity-chrome-dev | cut -d " " -f 1`

if [ -z "$ID" ]; then
		exit 0
fi

sudo docker stop $ID
sudo docker rm $ID

