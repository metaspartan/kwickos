kwick_prompt_setup() {
	kp_cfg=${XDG_CONFIG_HOME:-$HOME/.config}/kwick
	KWICK_PROMPT_STYLE=${KWICK_PROMPT:-}
	[ -z "$KWICK_PROMPT_STYLE" ] && [ -r "$kp_cfg/prompt" ] && read -r KWICK_PROMPT_STYLE <"$kp_cfg/prompt"
	[ -z "$KWICK_PROMPT_STYLE" ] && [ -r /etc/kwick/prompt ] && read -r KWICK_PROMPT_STYLE </etc/kwick/prompt
	case $KWICK_PROMPT_STYLE in kwick | minimal | powerline | starship) ;; *) KWICK_PROMPT_STYLE=kwick ;; esac
	kp_layout=macos
	[ -r "$kp_cfg/layout" ] && read -r kp_layout <"$kp_cfg/layout"
	KWICK_PS_COLOR=
	KWICK_PS_256=
	KWICK_PS_UTF=
	if [ -n "${TERM:-}" ] && [ "$TERM" != dumb ] && [ -z "${NO_COLOR:-}" ]; then
		KWICK_PS_COLOR=1
		case $TERM in
		*256color* | foot* | alacritty* | kitty* | wezterm* | xterm-direct* | konsole*) KWICK_PS_256=1 ;;
		esac
	fi
	case $TERM in linux | vt* | dumb | '') ;; *) case ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} in *UTF-8* | *utf8* | *UTF8* | *utf-8*) KWICK_PS_UTF=1 ;; esac ;; esac
	case $kp_layout in
	windows) KWICK_PS_HI=32 ;;
	linux) KWICK_PS_HI=69 ;;
	*) KWICK_PS_HI=33 ;;
	esac
	KWICK_PS_ROOT=
	[ "$(id -u)" -eq 0 ] && KWICK_PS_ROOT=1
	unset kp_cfg kp_layout
}

kwick_git_branch() {
	kg_d=$PWD
	while :; do
		if [ -f "$kg_d/.git/HEAD" ]; then
			read -r kg_h <"$kg_d/.git/HEAD"
			case $kg_h in
			"ref: refs/heads/"*) printf '%s' "${kg_h#ref: refs/heads/}" ;;
			*) printf '%.7s' "$kg_h" ;;
			esac
			return 0
		fi
		[ -z "$kg_d" ] || [ "$kg_d" = / ] && return 1
		kg_d=${kg_d%/*}
	done
}

kwick_git_seg() {
	kg_b=$(kwick_git_branch) || return 0
	if [ -n "$KWICK_PS_UTF" ]; then printf ' \356\202\240 %s ' "$kg_b"; else printf ' git:%s ' "$kg_b"; fi
}

kwick_ps1() {
	kp_st=${1:-0}
	kp_o='\['
	kp_c='\]'
	if [ -z "$KWICK_PS_COLOR" ]; then
		case $KWICK_PROMPT_STYLE in
		minimal | powerline) PS1='\W > ' ;;
		*) PS1='\u@\h \W \$ ' ;;
		esac
		return 0
	fi
	kp_r="$kp_o\e[0m$kp_c"
	if [ -n "$KWICK_PS_256" ]; then
		kp_hi="38;5;$KWICK_PS_HI"
		kp_bghi="48;5;$KWICK_PS_HI"
		kp_grey='38;5;245'
	else
		kp_hi=34
		kp_bghi=44
		kp_grey=90
	fi
	kp_who="$kp_o\e[${kp_grey}m$kp_c\\u@\\h$kp_r"
	[ -n "$KWICK_PS_ROOT" ] && kp_who="$kp_o\e[31m$kp_c\\u@\\h$kp_r"
	kp_ch='\$'
	[ "$kp_st" != 0 ] && kp_ch="$kp_o\e[31m$kp_c\\\$$kp_r"
	case $KWICK_PROMPT_STYLE in
	minimal)
		kp_arrow='>'
		[ -n "$KWICK_PS_UTF" ] && kp_arrow=$(printf '\342\235\257')
		kp_ac=$kp_hi
		[ "$kp_st" != 0 ] && kp_ac=31
		PS1="$kp_o\e[1;${kp_hi}m$kp_c\\W$kp_r $kp_o\e[${kp_ac}m$kp_c$kp_arrow$kp_r "
		;;
	powerline)
		if [ -n "$KWICK_PS_256" ]; then kp_bgu='48;5;238'; kp_fgu='38;5;252'; kp_au='38;5;238'; kp_bgg='48;5;236'; kp_ag='38;5;236'; kp_ah="38;5;$KWICK_PS_HI"; else kp_bgu=100; kp_fgu=97; kp_au=90; kp_bgg=40; kp_ag=30; kp_ah=34; fi
		[ -n "$KWICK_PS_ROOT" ] && kp_bgu=41 && kp_au=31
		if [ -n "$KWICK_PS_UTF" ]; then kp_sep=$(printf '\356\202\260'); else kp_sep=''; fi
		kp_end=$kp_ah
		[ "$kp_st" != 0 ] && kp_end=31
		kp_gb=
		KWICK_GIT_SEG=
		if [ -n "${BASH_VERSION:-}" ] && kp_gb=$(kwick_git_branch 2>/dev/null); then KWICK_GIT_SEG=$(kwick_git_seg); fi
		PS1="$kp_o\e[${kp_bgu};${kp_fgu}m$kp_c \\u@\\h $kp_o\e[0;${kp_au};${kp_bghi}m$kp_c$kp_sep$kp_o\e[1;97;${kp_bghi}m$kp_c \\W "
		if [ -n "$kp_gb" ] || [ -z "${BASH_VERSION:-}" ]; then
			if [ -n "${BASH_VERSION:-}" ]; then
				PS1="$PS1$kp_o\e[0;${kp_ah};${kp_bgg}m$kp_c$kp_sep$kp_o\e[0;38;5;250;${kp_bgg}m$kp_c\${KWICK_GIT_SEG}$kp_o\e[0;$([ "$kp_st" != 0 ] && echo 31 || echo "$kp_ag")m$kp_c$kp_sep$kp_r "
			else
				PS1="$PS1$kp_o\e[0;${kp_ah}m$kp_c$kp_sep$kp_o\e[0;${kp_grey}m$kp_c\$(kwick_git_seg)$kp_r "
			fi
		else
			PS1="$PS1$kp_o\e[0;${kp_end}m$kp_c$kp_sep$kp_r "
		fi
		;;
	*)
		PS1="$kp_who $kp_o\e[1;${kp_hi}m$kp_c\\W$kp_r $kp_ch "
		;;
	esac
	if [ -n "${BASH_VERSION:-}" ]; then
		case ${TERM:-} in xterm* | foot* | alacritty* | kitty* | wezterm* | konsole*) PS1='\[\e]0;\u@\h: \w\a\]'"$PS1" ;; esac
	fi
	unset kp_st kp_o kp_c kp_r kp_hi kp_bghi kp_grey kp_who kp_ch kp_arrow kp_ac kp_bgu kp_fgu kp_au kp_bgg kp_ag kp_ah kp_sep kp_end kp_gb
}

kwick_prompt_setup
if [ "$KWICK_PROMPT_STYLE" = starship ] && [ -n "${BASH_VERSION:-}" ] && command -v starship >/dev/null 2>&1; then
	[ -z "${STARSHIP_CONFIG:-}" ] && [ ! -e "${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml" ] && export STARSHIP_CONFIG=/usr/share/kwick/shell/starship.toml
	eval "$(starship init bash)"
else
	[ "$KWICK_PROMPT_STYLE" = starship ] && KWICK_PROMPT_STYLE=kwick
	if [ -n "${BASH_VERSION:-}" ]; then
		KWICK_PS_FRESH=1
		kwick_prompt_command() { kp_s=$?; if [ -n "${KWICK_PS_FRESH:-}" ]; then kp_s=0; unset KWICK_PS_FRESH; fi; kwick_ps1 "$kp_s"; }
		case ";${PROMPT_COMMAND:-};" in
		*";kwick_prompt_command;"*) ;;
		*) PROMPT_COMMAND="kwick_prompt_command${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
		esac
	fi
	kwick_ps1 0
fi
