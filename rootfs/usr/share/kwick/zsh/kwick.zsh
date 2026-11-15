[[ -o interactive ]] || return 0
(( ${+KWICK_ZSH} )) && return 0
typeset -g KWICK_ZSH=1

autoload -Uz add-zsh-hook compinit up-line-or-beginning-search down-line-or-beginning-search

() {
  local layout=macos cfg=${XDG_CONFIG_HOME:-$HOME/.config}/kwick/layout hi=blue
  local who='%n@%m'
  [[ -r $cfg ]] && read -r layout <$cfg
  zmodload zsh/terminfo 2>/dev/null
  if (( ${terminfo[colors]:-0} >= 256 )); then
    case $layout in
      windows) hi=32 ;;
      linux) hi=69 ;;
      *) hi=33 ;;
    esac
    who='%F{245}%n@%m%f'
    typeset -g ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=241'
  else
    typeset -g ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
  fi
  (( EUID == 0 )) && who='%F{red}%n@%m%f'
  typeset -g PROMPT="$who %B%F{$hi}%1~%f%b %(?.%#.%F{red}%#%f) "
}

if [[ $TERM == (xterm*|foot*|alacritty*|kitty*|screen*|tmux*|rxvt*|wezterm*) ]]; then
  kwick_title() { print -Pn '\e]0;%n@%m: %~\a' }
  add-zsh-hook precmd kwick_title
fi

HISTFILE=${HISTFILE:-$HOME/.zsh_history}
HISTSIZE=50000
SAVEHIST=50000
setopt share_history hist_ignore_dups hist_ignore_space hist_reduce_blanks hist_expire_dups_first
setopt auto_cd auto_pushd pushd_ignore_dups pushd_silent interactive_comments no_beep no_flow_control complete_in_word
WORDCHARS=${WORDCHARS//\//}
KEYTIMEOUT=10

export CLICOLOR=1
export LS_COLORS=${LS_COLORS:-'di=1;34:ln=36:so=35:pi=33:ex=1;32:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=34;42'}
alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'

() {
  setopt localoptions extendedglob
  local dir=${XDG_CACHE_HOME:-$HOME/.cache}/zsh dump
  dump=$dir/zcompdump-$ZSH_VERSION
  [[ -d $dir ]] || mkdir -p $dir 2>/dev/null
  if [[ -n $dump(#qN.mh+24) ]]; then
    compinit -d $dump
  else
    compinit -C -d $dump
  fi
  [[ -s $dump && ( ! -s $dump.zwc || $dump -nt $dump.zwc ) ]] && zcompile $dump 2>/dev/null
  return 0
}

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' group-name ''
zstyle ':completion:*' special-dirs true
zstyle ':completion:*:descriptions' format '%F{245}%d%f'
zstyle ':completion:*:warnings' format '%F{red}no matches%f'
zstyle ':completion:*' use-cache yes
zstyle ':completion:*' cache-path ${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompcache

zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey -e
bindkey '^[[H' beginning-of-line
bindkey '^[OH' beginning-of-line
bindkey '^[[1~' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[OF' end-of-line
bindkey '^[[4~' end-of-line
bindkey '^[[3~' delete-char
bindkey '^[[3;5~' kill-word
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word
bindkey '^[[1;3C' forward-word
bindkey '^[[1;3D' backward-word
bindkey '^[[5C' forward-word
bindkey '^[[5D' backward-word
bindkey '^[^[[C' forward-word
bindkey '^[^[[D' backward-word
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[OA' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
bindkey '^[OB' down-line-or-beginning-search
bindkey '^[[Z' reverse-menu-complete
bindkey '^[[127;5u' backward-kill-word

ZSH_AUTOSUGGEST_STRATEGY=(history)
ZSH_AUTOSUGGEST_MANUAL_REBIND=1
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main)
[[ -r /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -r /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
