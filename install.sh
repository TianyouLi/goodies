#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GOODIES_ROOT="$SCRIPT_DIR"
source "$SCRIPT_DIR/lib/goodies-lib.sh"

if [ $# -eq 0 ]; then
    for mod_dir in "$SCRIPT_DIR"/modules/*/; do
        if [ -f "$mod_dir/install.sh" ]; then
            log_info "Installing module: $(basename "$mod_dir")"
            bash "$mod_dir/install.sh"
        fi
    done
else
    for mod in "$@"; do
        if [[ "$mod" == */* ]] || [[ "$mod" == ".." ]]; then
            log_error "Invalid module name: $mod"
            exit 1
        fi
        if [ -f "$SCRIPT_DIR/modules/$mod/install.sh" ]; then
            log_info "Installing module: $mod"
            bash "$SCRIPT_DIR/modules/$mod/install.sh"
        else
            log_error "Module not found: $mod"
            exit 1
        fi
    done
fi
