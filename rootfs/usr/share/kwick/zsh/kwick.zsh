[[ -o interactive ]] || return 0
(( ${+KWICK_ZSH} )) && return 0
typeset -g KWICK_ZSH=1

if [[ -z ${KWICK_ENV:-} && -x /usr/lib/kwick/shell-env ]]; then
  () { local l; for l in ${(f)"$(/usr/lib/kwick/shell-env)"}; do export "$l"; done }
fi

autoload -Uz add-zsh-hook compinit up-line-or-beginning-search down-line-or-beginning-search

kwick_git_branch() {
  local d=$PWD h
  while :; do
    if [[ -f $d/.git/HEAD ]]; then
      read -r h <$d/.git/HEAD
      if [[ $h == 'ref: refs/heads/'* ]]; then REPLY=${h#ref: refs/heads/}; else REPLY=${h[1,7]}; fi
      return 0
    fi
    [[ -z $d || $d == / ]] && return 1
    d=${d%/*}
  done
}

() {
  local layout=macos cfg=${XDG_CONFIG_HOME:-$HOME/.config}/kwick hi=blue style=${KWICK_PROMPT:-}
  local who='%n@%m' utf= c256=
  [[ -r $cfg/layout ]] && read -r layout <$cfg/layout
  [[ -z $style && -r $cfg/prompt ]] && read -r style <$cfg/prompt
  [[ -z $style && -r /etc/kwick/prompt ]] && read -r style </etc/kwick/prompt
  [[ $style == (kwick|minimal|powerline|starship) ]] || style=kwick
  [[ $TERM != (linux|vt*|dumb) && ${(L)${LC_ALL:-${LC_CTYPE:-$LANG}}} == *utf(-|)8* ]] && utf=1
  zmodload zsh/terminfo 2>/dev/null
  if (( ${terminfo[colors]:-0} >= 256 )); then
    c256=1
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
  if [[ $style == starship ]]; then
    if (( $+commands[starship] )); then
      [[ -z ${STARSHIP_CONFIG:-} && ! -e ${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml ]] && export STARSHIP_CONFIG=/usr/share/kwick/shell/starship.toml
      eval "$(starship init zsh)"
      typeset -g KWICK_PROMPT_STYLE=starship
      return 0
    fi
    style=kwick
  fi
  typeset -g KWICK_PROMPT_STYLE=$style
  case $style in
    minimal)
      local arrow='>'
      [[ -n $utf ]] && arrow=$'❯'
      typeset -g PROMPT="%B%F{$hi}%1~%f%b %(?.%F{$hi}.%F{red})$arrow%f "
      ;;
    powerline)
      local bgu=238 fgu=252 bgg=236 fgg=250 sep='' br=$' '
      [[ -n $utf ]] && sep=$'' || br='git:'
      if [[ -z $c256 ]]; then bgu=8; fgu=15; bgg=0; fgg=7; hi=blue; fi
      (( EUID == 0 )) && bgu=red
      typeset -g KWICK_PL_HI=$hi KWICK_PL_BGG=$bgg KWICK_PL_FGG=$fgg KWICK_PL_SEP=$sep KWICK_PL_BR=$br
      typeset -g KWICK_PL_HEAD="%K{$bgu}%F{$fgu} %n@%m %F{$bgu}%K{$hi}$sep%B%F{15} %1~ %b"
      kwick_pl_precmd() {
        local REPLY
        if kwick_git_branch; then
          REPLY=${REPLY//\%/%%}
          PROMPT="$KWICK_PL_HEAD%F{$KWICK_PL_HI}%K{$KWICK_PL_BGG}$KWICK_PL_SEP%F{$KWICK_PL_FGG} $KWICK_PL_BR$REPLY %k%(?.%F{$KWICK_PL_BGG}.%F{red})$KWICK_PL_SEP%f "
        else
          PROMPT="$KWICK_PL_HEAD%k%(?.%F{$KWICK_PL_HI}.%F{red})$KWICK_PL_SEP%f "
        fi
      }
      add-zsh-hook precmd kwick_pl_precmd
      ;;
    *)
      typeset -g PROMPT="$who %B%F{$hi}%1~%f%b %(?.%#.%F{red}%#%f) "
      ;;
  esac
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
