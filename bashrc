# ~/.config/bash/bashrc — clean Debian server setup

# -----------------------------
# Interactive shell guard
# -----------------------------
case $- in
    *i*) ;;
      *) return;;
esac

# -----------------------------
# History
# -----------------------------
HISTCONTROL=ignoreboth:erasedups
HISTSIZE=20000
HISTFILESIZE=50000

# Append to history instead of overwriting
shopt -s histappend

# Store multi-line commands (heredocs, multi-line loops) as a single entry
# instead of one entry per line — makes history replay much saner.
shopt -s cmdhist

# Disable timestamps in history output
unset HISTTIMEFORMAT

# -----------------------------
# Shell behavior
# -----------------------------

# Update terminal dimensions after resize
shopt -s checkwinsize

# Fix minor spelling mistakes in cd paths
shopt -s cdspell

# Expand completed paths to full paths
shopt -s direxpand

# Automatically cd into directory names
# Example:
#   Downloads
# acts like:
#   cd Downloads
shopt -s autocd

# Enable recursive glob with **
# Example:
#   ls **/*.go    → matches every .go file at any depth below cwd
shopt -s globstar

# -----------------------------
# Less / paging
# -----------------------------
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# -----------------------------
# Colors
# -----------------------------
export COLORTERM=truecolor

# Minimal LS_COLORS — no dircolors dependency.
export LS_COLORS="di=1;34:ln=36:so=35:pi=33:ex=1;32"

alias ls='ls -lah --group-directories-first --color=auto'
alias grep='grep --color=auto'

# -----------------------------
# Prompt
# -----------------------------

# Color definitions (24-bit ANSI escape codes).
# \[...\] markers tell bash these bytes are non-printing — required so
# line wrapping stays correct on long commands.
RESET="\[\e[0m\]"

# All foreground text: white
WHITE_FG="\[\e[38;2;255;255;255m\]"

# user@host segment
USERHOST_BG="\[\e[48;2;183;189;248m\]"
USERHOST_FG="${WHITE_FG}"

# path segment
PATH_BG="\[\e[48;2;95;95;215m\]"
PATH_FG="${WHITE_FG}"

# trailing prompt character ($)
PROMPT_COLOR="\[\e[38;2;0;221;25m\]"

# ---------------------------------------------------------------------------
# Git prompt — single git invocation, pure-bash parsing, zero extra forks
# ---------------------------------------------------------------------------
# Symbols:  + staged  M modified  ? untracked  ↑ ahead  ↓ behind
#
# Branch color logic:
#   green   — clean, in sync with remote
#   magenta — local changes (ahead / staged / modified / untracked)
#   magenta — remote is ahead (you need to pull)
# ---------------------------------------------------------------------------
__git_info() {

    # Single git call, porcelain v2 gives us branch + ahead/behind + file states
    local raw
    raw=$(git --no-optional-locks status --porcelain=v2 --branch 2>/dev/null) \
        || return

    # Counters populated from the porcelain output
    local branch="" ahead=0 behind=0 staged=0 modified=0 untracked=0

    # Parse each porcelain line — pure bash, no extra forks
    while IFS= read -r line; do
        case "$line" in
            '# branch.head '*)
                branch="${line#'# branch.head '}"
                ;;
            '# branch.ab '*)
                ahead="${line#*+}";  ahead="${ahead%% *}"
                behind="${line##*-}"
                ;;
            [12]' '??*)

                # XY status field: first char = staged, second = unstaged
                local xy="${line:2:2}"
                [[ "${xy:0:1}" != '.' ]] && (( staged++ ))
                [[ "${xy:1:1}" != '.' ]] && (( modified++ ))
                ;;
            '? '*)
                (( untracked++ ))
                ;;
        esac
    done <<< "$raw"

    # Skip detached HEAD or empty branch (no useful info to show)
    [[ -z "$branch" || "$branch" == "(detached)" ]] && return

    # PS1 expects non-printing bytes wrapped in \001..\002 when emitted from
    # a command substitution (the \[..\] form only works at the PS1 level).
    local R=$'\001\e[0m\002'

    # Magenta when anything is out-of-sync (local changes or remote ahead),
    # green only when everything is clean and in sync with remote.
    local color
    if (( behind > 0 || ahead > 0 || staged > 0 || modified > 0 || untracked > 0 )); then
        color=$'\001\e[38;2;255;255;255;48;2;255;95;255m\002'
    else
        color=$'\001\e[38;2;255;255;255;48;2;46;205;104m\002'
    fi

    # Build the info string with counts for non-zero states
    local info="${branch}"
    (( staged    > 0 )) && info+=" +${staged}"
    (( modified  > 0 )) && info+=" M${modified}"
    (( untracked > 0 )) && info+=" ?${untracked}"
    (( ahead     > 0 )) && info+=" ↑${ahead}"
    (( behind    > 0 )) && info+=" ↓${behind}"

    printf "%s[%s]%s" "$color" "$info" "$R"
}

# Two-line prompt:
#   line 1: user@host  /path  (git branch)
#   line 2: $
export PS1="${USERHOST_BG}${USERHOST_FG}\u@\h ${RESET}${PATH_BG}${PATH_FG} \w ${RESET}\$(__git_info)\n${PROMPT_COLOR}\\$ ${RESET}"

# On xterm-like terminals, also set the window/tab title to "user@host: cwd".
# The \e]0;...\a sequence is wrapped in \[..\] so bash doesn't count it
# toward the prompt width.
case "$TERM" in
    xterm*|rxvt*|tmux*|screen*)
        PS1="\[\e]0;\u@\h: \w\a\]$PS1"
        ;;
esac

# PS1 is now baked — drop the helper color vars so they don't pollute the
# user's environment (they were only needed to build PS1 above).
unset RESET WHITE_FG USERHOST_BG USERHOST_FG PATH_BG PATH_FG PROMPT_COLOR

# Display MOTD as a fallback for systems where nothing else prints it.
#   - skip on SSH         → sshd's PAM motd already printed it
#   - skip when /run/motd.dynamic exists → pam_motd already printed it (Debian/Ubuntu/WSL)
#   - login shells only   → we don't want it on every `bash` subshell
# This way `01-status` runs exactly once on bare systems without PAM motd, and zero
# extra times on the common case where PAM has it covered.
if shopt -q login_shell && [ -z "$SSH_CLIENT" ] && [ ! -e /run/motd.dynamic ] && [ -x /etc/update-motd.d/01-status ]; then
    /etc/update-motd.d/01-status
fi

# -----------------------------
# Aliases
# -----------------------------
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

alias ..='cd ..'
alias ...='cd ../..'

alias myip='ip=$(dig +short myip.opendns.com @resolver1.opendns.com | head -n1); printf "\033[1;35m%s\033[0m\n" "$ip"'

# bat is installed as batcat on Debian. Only alias `bat` — leave `cat`
# alone so scripts and pipelines pasted into the shell behave normally.
if command -v batcat >/dev/null 2>&1; then
    alias bat='batcat --pager=never'
fi

# Short alias for lazygit TUI
alias lg='lazygit'

# -----------------------------
# Editor
# -----------------------------
export EDITOR=micro
export VISUAL=micro

# -----------------------------
# PATH
# -----------------------------
export PATH="$HOME/.local/bin:$PATH:/usr/sbin:/sbin"

# air360 install dir — only added when present, so the template stays
# portable across machines that don't have it.
if [ -d /usr/local/air360 ]; then
    export PATH="/usr/local/air360:$PATH"
fi

# -----------------------------
# tmux
# -----------------------------
# Calling `tmux` with no args reattaches to the "main" session if it's
# already running, otherwise creates it. Sessions live in the tmux server
# and survive SSH disconnects until the machine reboots or the server is
# killed — no disk state needed.
#
# Any explicit subcommand (e.g. `tmux ls`, `tmux kill-server`) bypasses
# this wrapper and runs unmodified via `command tmux`.
tmux() {

    # Forward any explicit args straight to the real tmux
    if [ $# -gt 0 ]; then
        command tmux "$@"
        return
    fi

    # No args — attach to "main" if it exists, otherwise create it
    if command tmux has-session -t main 2>/dev/null; then
        command tmux attach -t main
    else
        command tmux new-session -s main
    fi
}

# -----------------------------
# User-local aliases
# -----------------------------
# Drop your own aliases into ~/.bash_aliases — they layer on top of (and can
# override) anything defined above without forking this file.
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# -----------------------------
# Bash completion
# -----------------------------
if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
fi

# -----------------------------
# fzf
# -----------------------------
# Enable:
# - CTRL+R fuzzy history search
# - fuzzy file/path completion
# - SSH host completion
# - process completion
#
# Examples:
#   vim **<TAB>
#   cd **<TAB>
#   kill -9 <TAB>
#
# Debian 13 ships fzf 0.60.3, which supports `fzf --bash` (single-command setup
# covering both key bindings and completion). Prefer it: avoids matching
# per-file paths that drift between Debian releases (e.g. the completion file
# moved from /usr/share/bash-completion/completions/fzf to
# /usr/share/doc/fzf/examples/completion.bash in newer packages, which broke
# the `**<TAB>` trigger). Fall back to sourcing the individual helpers on
# older fzf (< 0.48) where `--bash` doesn't exist.
if command -v fzf >/dev/null 2>&1; then

    # Newer fzf (>= 0.48) — single-command setup
    if fzf --bash >/dev/null 2>&1; then
        eval "$(fzf --bash)"
    else

        # Older fzf — source whichever Debian-shipped helpers exist
        [ -f /usr/share/doc/fzf/examples/key-bindings.bash ] && . /usr/share/doc/fzf/examples/key-bindings.bash
        [ -f /usr/share/doc/fzf/examples/completion.bash ]   && . /usr/share/doc/fzf/examples/completion.bash
        [ -f /usr/share/bash-completion/completions/fzf ]    && . /usr/share/bash-completion/completions/fzf
    fi
fi

