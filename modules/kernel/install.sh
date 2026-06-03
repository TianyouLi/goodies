#!/bin/bash

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${BASEDIR}/../../lib/goodies-lib.sh"

path_append "$HOME/.bashrc" "${BASEDIR}"
