# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a personal dotfiles and tooling repository containing shell configurations, development environment setup scripts, and performance benchmarking tools — primarily focused on ClickHouse database performance analysis and Linux kernel/CPU management.

## Repository Structure

- **Root `install.sh`** — Symlinks dotfiles (emacs, tmux, bash_aliases, git_env) into `$HOME` and adds `kernel/` and `clickhouse/scripts/` to PATH via `.bashrc`
- **clickhouse/** — ClickHouse build scripts, benchmark harnesses (ClickBench, SSB), and server config
- **kernel/** — CPU management tools: `corescale.py` (CPU online/offline, cgroup-based core scaling for benchmarks), `kboot.sh` (kexec-based kernel switching)
- **perf/** — `pt.sh` wraps `perf record`/`perf report`/`perf c2c` for hotspot and cache-line contention analysis
- **git/** — Git config setup, clang-format integration, commit counting
- **packer/** — Packer templates for VM provisioning (Chromium dev, Ubuntu dev environments)
- **tmux/, emacs/, git_env/** — Editor/terminal dotfiles

## Key Tools

### ClickHouse Scripts (`clickhouse/scripts/`)

- `ck_source.sh -s <dir>` — Clone ClickHouse fork and configure upstream remote
- `ck_build.sh -s <src> -t <tag> -b <build_dir>` — Checkout tag, init submodules, build with clang/ninja
- `ck_launch.sh` — Launch ClickHouse server
- `ck_bench.sh` — Run benchmarks

### Core Scaling (`kernel/corescale.py`)

Used for ClickHouse core-scaling performance experiments. Requires root/sudo for CPU hotplug.

```
# Enable only specific CPUs (others go offline)
python3 corescale.py --cpuset 0-7

# Run full scaling experiment
python3 corescale.py --output ./results --ck_root /path/to/ck --config scale.conf

# Generate reports only
python3 corescale.py --output ./results --ck_root /path/to/ck --report
```

### Perf Tracing (`perf/pt.sh`)

```
pt.sh <platform_label> <command...>
# Example: pt.sh spr.opt1 ./clickhouse-benchmark ...
```

Produces hotspot (cycles/instructions) and c2c (cache contention) reports in a labeled output folder.

## SSB Benchmark

```
cd clickhouse/benchmarks/ssb
./setup_ssb_db.sh [PORT]       # PORT defaults to 9000
../run_query.sh QUERY [PORT]   # QUERY: "2.1", "all", etc.
```
