#!/bin/bash
ID=`sudo docker ps -a --format '{{.ID}}' --filter name=lity-chrome-dev`

if [ -z "$ID" ]; then
		exit 0
fi

sudo docker stop $ID
sudo docker rm $ID

