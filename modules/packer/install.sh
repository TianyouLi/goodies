#!/bin/bash

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${BASEDIR}/../../lib/goodies-lib.sh"

log_info "Packer templates available at: ${BASEDIR}"
log_info "No installation needed — use templates directly with packer build."
