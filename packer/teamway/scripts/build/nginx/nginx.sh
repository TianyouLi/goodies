#!/bin/bash

# import environment variables
. ../env.sh

# install nginx
${aptool} install nginx
