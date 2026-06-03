#!/bin/bash

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${BASEDIR}/../../lib/goodies-lib.sh"

# Link git environment (completion + prompt)
ensure_dir ~/.git_env
safe_link "${BASEDIR}/env/git-completion.bash" ~/.git_env/git-completion.bash
safe_link "${BASEDIR}/env/git-prompt.sh" ~/.git_env/git-prompt.sh

# Link git-clang-format to ~/.local/bin
ensure_dir ~/.local/bin
safe_link "${BASEDIR}/git-clang-format" ~/.local/bin/git-clang-format
