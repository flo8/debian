# ~/.config/bash/bashrc_custom — clean Debian server setup

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

if [ -x /usr/bin/dircolors ]; then
    eval "$(dircolors -b)"

    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
fi

export LS_COLORS="di=1;34:ln=36:so=35:pi=33:ex=1;32"

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
# bat / cat
# -----------------------------
# bat is installed as batcat on Debian
if command -v batcat >/dev/null 2>&1; then
    alias bat='batcat --pager=never'
    alias cat='batcat --pager=never'
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
if command -v fzf >/dev/null 2>&1; then
    eval "$(fzf --bash)"
fi
