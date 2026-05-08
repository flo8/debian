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
HISTCONTROL=ignoreboth
HISTSIZE=5000
HISTFILESIZE=10000

# Append to history instead of overwriting
shopt -s histappend

# Show timestamps in history output
export HISTTIMEFORMAT="%F %T "

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

# -----------------------------
# Less / paging
# -----------------------------
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# -----------------------------
# Colors
# -----------------------------
export COLORTERM=truecolor

# Custom minimal LS_COLORS — intentionally not running dircolors,
# since its output would be overwritten by the export below.
export LS_COLORS="di=1;34:ln=36:so=35:pi=33:ex=1;32"

alias ls='ls --color=auto'
alias grep='grep --color=auto'

# -----------------------------
# Prompt
# -----------------------------
__prompt_color() {
    PS1="\[\e[45;1;97m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ "
}
__prompt_color

# -----------------------------
# Aliases
# -----------------------------
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

alias ..='cd ..'
alias ...='cd ../..'

# -----------------------------
# bat
# -----------------------------
# bat is installed as batcat on Debian. Only alias `bat` — leave `cat`
# alone so scripts and pipelines pasted into the shell behave normally.
if command -v batcat >/dev/null 2>&1; then
    alias bat='batcat --pager=never'
fi

# -----------------------------
# Editor
# -----------------------------
export EDITOR=micro
export VISUAL=micro

# -----------------------------
# PATH
# -----------------------------
export PATH="$HOME/.local/bin:/usr/local/air360:$PATH:/usr/sbin:/sbin"

# -----------------------------
# Useful aliases
# -----------------------------
alias myip='ip=$(dig +short myip.opendns.com @resolver1.opendns.com | head -n1); printf "\033[1;35m%s\033[0m\n" "$ip"'

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
# `fzf --bash` only exists in fzf >= 0.48. Debian 12 ships 0.38 and even
# Debian 13 stable is older than 0.48, so we source the helper scripts
# from the apt package and only fall back to `fzf --bash` on newer fzf.
if command -v fzf >/dev/null 2>&1; then

    # Debian-shipped key bindings (CTRL+R, ALT+C, etc.)
    if [ -f /usr/share/doc/fzf/examples/key-bindings.bash ]; then
        . /usr/share/doc/fzf/examples/key-bindings.bash
    fi

    # Debian-shipped completion (** TAB triggers)
    if [ -f /usr/share/bash-completion/completions/fzf ]; then
        . /usr/share/bash-completion/completions/fzf
    fi

    # Newer fzf (>= 0.48) — single-command setup, used when the helper files are absent.
    if [ ! -f /usr/share/doc/fzf/examples/key-bindings.bash ] && fzf --bash >/dev/null 2>&1; then
        eval "$(fzf --bash)"
    fi
fi
