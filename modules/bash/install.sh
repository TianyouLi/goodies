#!/bin/bash

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${BASEDIR}/../../lib/goodies-lib.sh"

safe_link "${BASEDIR}/.bash_aliases" ~/.bash_aliases

if is_macos; then
    safe_link "${BASEDIR}/bash_profile.mac" ~/.bash_profile
fi
