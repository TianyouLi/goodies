#!/bin/bash

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${BASEDIR}/../../lib/goodies-lib.sh"

safe_link "${BASEDIR}/.tmux.conf" ~/.tmux.conf

ensure_dir ~/.tmux/plugins
safe_link "${BASEDIR}/tpm" ~/.tmux/plugins/tpm
