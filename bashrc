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
shopt -s histappend
HISTSIZE=5000
HISTFILESIZE=10000
export HISTTIMEFORMAT="%F %T "

# -----------------------------
# Shell behavior
# -----------------------------
shopt -s checkwinsize

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
# Prompt (colored)
# -----------------------------
# Colors: user=green, @=white, host=cyan, path=blue, $=white
__prompt_color() {
    local reset='\[\e[0m\]'
    local green='\[\e[1;32m\]'
    local cyan='\[\e[1;36m\]'
    local blue='\[\e[1;34m\]'
    local white='\[\e[0m\]'

    PS1="${green}\u${white}@${cyan}\h${white}:${blue}\w${white}\$ ${reset}"
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
export PATH="$HOME/.local/bin:/usr/local/air360:$PATH"

# -----------------------------
# Bash completion
# -----------------------------
if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
fi

# -----------------------------
# fzf — history search (Ctrl+F)
# -----------------------------
__fzf_history() {
    command -v fzf >/dev/null 2>&1 || return
    local selected
    selected=$(history | fzf --tac --no-sort | awk '{$1=""; sub(/^ /,""); print}')
    if [ -n "$selected" ]; then
        READLINE_LINE="$selected"
        READLINE_POINT=${#READLINE_LINE}
    fi
}
bind -x '"\C-f": __fzf_history'
