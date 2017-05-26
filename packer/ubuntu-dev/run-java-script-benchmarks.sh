#!/bin/bash

# launch nginx
/etc/init.d/nginx restart

# last: lauch sshd
/usr/sbin/sshd -D

