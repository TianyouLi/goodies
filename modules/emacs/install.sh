#!/bin/bash

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${BASEDIR}/../../lib/goodies-lib.sh"

safe_link "${BASEDIR}/.emacs" ~/.emacs
true
