# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal dotfiles and tooling repository organized into self-contained modules. Each module has its own `install.sh` that symlinks configs and adds tools to PATH.

## Workflow

All changes must go through a feature branch + PR with Copilot review before merging to master. Never push directly to master. Use `/watch-pr` to monitor Copilot review results and fix findings automatically. Only merge after `/watch-pr` reports LGTM (all findings addressed).

## Repository Structure

- **install.sh** — Orchestrator that runs all module installers (or specific ones: `./install.sh git tmux`)
  - `--full` flag additionally runs `bootstrap.sh` for modules that have one (e.g., package installs, validation)
- **modules/** — Self-contained modules, each with `install.sh`
- **lib/goodies-lib.sh** — Shared helpers (safe_link, ensure_dir, path_append, logging, platform detection)
- **tests/** — BATS test suite with per-module and integration tests
- **.github/workflows/test.yml** — CI runs BATS on push/PR

## Modules

| Module | Purpose |
|--------|---------|
| bash | Shell aliases, bash_profile (macOS) |
| claude | Claude Code settings.json, custom commands |
| clickhouse | ClickHouse build/bench/launch scripts, SSB/ClickBench harnesses |
| emacs | .emacs config |
| git | Git config, clang-format, git_env |
| kernel | corescale.py (CPU scaling), kboot.sh (kexec) |
| packer | VM provisioning templates (Chromium dev, Ubuntu dev) |
| perf | pt.sh (perf record/report/c2c wrapper) |
| proxy | switchproxy.sh |
| tmux | .tmux.conf, TPM (git submodule) |

## Testing

```bash
# Run all tests
bash tests/run.sh

# Run a single module's tests
tests/bats/bats-core/bin/bats tests/modules/bash.bats

# Run integration tests
tests/bats/bats-core/bin/bats tests/integration.bats
```

BATS submodules (bats-core, bats-support, bats-assert) live under `tests/bats/`.

## Module Install Pattern

Each module's `install.sh` sources the shared library and uses `safe_link` / `path_append`:

```bash
#!/bin/bash
BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${BASEDIR}/../../lib/goodies-lib.sh"
safe_link "${BASEDIR}/config" ~/.config
```

`safe_link` skips if destination is a regular file (not a symlink) and returns non-zero in that case. Module installers end with `true` to avoid failing under `set -e` when a skip occurs.

Modules can optionally include a `bootstrap.sh` for heavier setup (package installs, validation, compilation). It only runs when `--full` is passed to the orchestrator.

## Key Tools

- `corescale.py` — CPU online/offline + cgroup-based core scaling for ClickHouse benchmarks (requires root)
- `kboot.sh` — kexec-based kernel switching from /boot
- `pt.sh <label> <command>` — Perf tracing with hotspot + c2c reports
- `ck_build.sh` / `ck_bench.sh` / `ck_launch.sh` — ClickHouse build and benchmark automation
