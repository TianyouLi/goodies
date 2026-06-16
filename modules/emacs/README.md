# emacs module

`.emacs` config + `bootstrap.sh` validating it loads.

## Install

```bash
./install.sh emacs           # symlink ~/.emacs → modules/emacs/.emacs
./install.sh --full emacs    # additionally validate the config loads
```

## What's in here

- General editor preferences (line numbers, key bindings, `ido`, `company`, `flycheck`, theme).
- Linux kernel C-style for `~/sandbox/linux`.
- Language packages: `rust-mode`, `js2-mode`, `markdown-mode`, `yasnippet`, `clang-format`.
- **Claude Code integration via [`claude-code.el`](https://github.com/stevemolitor/claude-code.el)** — see below.

## Claude Code integration

The `claude-code.el` block at the end of `.emacs` activates only when both
conditions hold:

1. Emacs is **30.0 or newer** (the package's hard requirement).
2. The `claude` CLI is on `PATH`.

If either condition fails, the block is silently skipped — the rest of the
config still loads. So this module is safe to install on machines where you
either run an older Emacs or don't have the Claude Code CLI.

### Prefix and common bindings

The package owns the `C-c c` prefix. The most-used bindings:

| Binding | Command | Purpose |
|---------|---------|---------|
| `C-c c c` | `claude-code` | Start a session in the current project root |
| `C-c c d` | `claude-code-start-in-directory` | Start in a specific directory |
| `C-c c r` | `claude-code-send-region` | Send selected region (or whole buffer if no region) |
| `C-c c s` | `claude-code-send-command` | Prompt in the minibuffer for a command |
| `C-c c x` | `claude-code-send-command-with-context` | Send a command with current file:line context |
| `C-c c b` | `claude-code-switch-to-buffer` | Jump to the Claude buffer |
| `C-c c t` | `claude-code-toggle` | Show/hide the Claude window |
| `C-c c k` | `claude-code-kill` | Kill the Claude process |
| `C-c c m` | `claude-code-transient` | Full transient menu of every command |
| `C-c c y` / `C-c c n` | `claude-code-send-return` / `send-escape` | Quick yes/no without switching buffers |

The package's README has the full list (resume, fix-error-at-point, image
paste, read-only mode, mode cycling).

### Terminal backend

Defaults to **`eat`** (pure Elisp, no native compilation). To switch:

```elisp
;; in your local config, after the goodies .emacs has loaded:
(setq claude-code-terminal-backend 'vterm)   ;; needs vterm package + native compile
;; or
(setq claude-code-terminal-backend 'ghostel) ;; needs libghostty + ghostel package
```

### First-run package install

`claude-code.el` and its `inheritenv` dependency install via `:vc` on first
run, which pulls from GitHub. Behind a corporate proxy, the existing
`goodies--at-intel` block at the top of `.emacs` already configures
`url-proxy-services` so `package-vc-install` works through the proxy.

If first-run install is slow or fails, `M-x package-vc-install RET
https://github.com/stevemolitor/claude-code.el RET` retries it directly.

### Why `:vc` and not MELPA

`claude-code.el` is not on MELPA. `:vc` (Emacs 30+ builtin) is the upstream's
recommended install path; `straight.el` is the alternative. We use `:vc` to
avoid pulling in another package manager.
