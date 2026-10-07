# ---------------------------
# Auto-attach or create tmux
# ---------------------------
# Portable snippet: copy this file to any Linux machine and source it from
# your shell startup (e.g. ~/.bashrc or ~/.bashrc.user):
#
#     [ -f ~/.bashrc.tmux ] && . ~/.bashrc.tmux
#
# Outside of an existing tmux session, attach to the first non-attached
# session if one exists, otherwise start a new session.
if [[ -z "$TMUX" ]] && command -v tmux >/dev/null 2>&1; then
    EXISTING=$(tmux ls 2>/dev/null | grep -v attached | head -n1 | cut -d: -f1)
    if [ -n "$EXISTING" ]; then
        exec tmux attach -t "$EXISTING"
    else
        exec tmux new-session
    fi
fi
