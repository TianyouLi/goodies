# ~/.bash_aliases: executed by bash(1) for non-login shells.
alias mux='pgrep -vx tmux > /dev/null && \
      tmux new -d -s delete-me && \
      tmux run-shell ~/.tmux/plugins/tmux-resurrect/scripts/restore.sh && \
      tmux kill-session -t delete-me && \
      tmux attach || tmux attach'

alias sudo='sudo -E'

alias

export TERM="screen-256color"