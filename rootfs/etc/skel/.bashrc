case $- in *i*) ;; *) return ;; esac
HISTCONTROL=ignoreboth
HISTSIZE=5000
HISTFILESIZE=10000
shopt -s histappend checkwinsize 2>/dev/null
case "$TERM" in
	xterm*|screen*|tmux*|linux|vt100|vt220|alacritty|foot*|kitty*|wezterm) color=1 ;;
	*) color= ;;
esac
if [ -n "$color" ]; then
	if [ "$(id -u)" -eq 0 ]; then
		PS1='\[\e[1;31m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '
	else
		PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '
	fi
else
	PS1='\u@\h:\w\$ '
fi
unset color
case "$TERM" in
	xterm*|foot*|alacritty|kitty*|wezterm) PS1='\[\e]0;\u@\h: \w\a\]'"$PS1" ;;
esac
if ! shopt -oq posix 2>/dev/null && [ -r /usr/share/bash-completion/bash_completion ]; then
	. /usr/share/bash-completion/bash_completion
fi
alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias grep='grep --color=auto'
[ -f ~/.bash_aliases ] && . ~/.bash_aliases
