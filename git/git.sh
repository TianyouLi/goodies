#!/bin/bash

### git info
git config --global user.name "Tianyou Li"
git config --global user.email "tianyou.li@intel.com"
git config --global core.autocrlf false
git config --global core.filemode false
git config --global color.ui true

### configure git cache
git config --global credential.helper 'cache --timeout=604800'
