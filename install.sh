#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GOODIES_ROOT="$SCRIPT_DIR"
source "$SCRIPT_DIR/lib/goodies-lib.sh"

FULL=false
MODULES=()

for arg in "$@"; do
    if [[ "$arg" == "--full" ]]; then
        FULL=true
    else
        MODULES+=("$arg")
    fi
done

export GOODIES_FULL="$FULL"

install_module() {
    local mod_dir="$1"
    log_info "Installing module: $(basename "$mod_dir")"
    bash "$mod_dir/install.sh"
    if [[ "$FULL" == "true" ]] && [ -f "$mod_dir/bootstrap.sh" ]; then
        log_info "Bootstrapping module: $(basename "$mod_dir")"
        bash "$mod_dir/bootstrap.sh"
    fi
}

if [ ${#MODULES[@]} -eq 0 ]; then
    for mod_dir in "$SCRIPT_DIR"/modules/*/; do
        if [ -f "$mod_dir/install.sh" ]; then
            install_module "$mod_dir"
        fi
    done
else
    for mod in "${MODULES[@]}"; do
        if [[ "$mod" == */* ]] || [[ "$mod" == ".." ]]; then
            log_error "Invalid module name: $mod"
            exit 1
        fi
        if [ -f "$SCRIPT_DIR/modules/$mod/install.sh" ]; then
            install_module "$SCRIPT_DIR/modules/$mod"
        else
            log_error "Module not found: $mod"
            exit 1
        fi
    done
fi
