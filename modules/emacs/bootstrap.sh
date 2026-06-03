#!/bin/bash

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${BASEDIR}/../../lib/goodies-lib.sh"

require_cmd emacs || exit 0

log_info "Bootstrapping Emacs packages and validating config..."
if emacs --batch -l ~/.emacs --eval '(message "Emacs config loaded OK")' 2>&1; then
    log_info "Emacs config validated successfully"
else
    log_warn "Emacs config loaded with warnings (package install may be needed on first run)"
fi
