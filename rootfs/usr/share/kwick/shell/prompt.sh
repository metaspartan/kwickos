kwick_prompt() {
	if [ -z "${TERM:-}" ] || [ "$TERM" = dumb ] || [ -n "${NO_COLOR:-}" ]; then
		PS1='\u@\h:\w\$ '
		return 0
	fi
	kp_layout=macos
	kp_file=${XDG_CONFIG_HOME:-$HOME/.config}/kwick/layout
	[ -r "$kp_file" ] && read -r kp_layout <"$kp_file"
	case $TERM in
	*256color* | foot* | alacritty* | kitty* | wezterm* | xterm-direct*)
		case $kp_layout in
		windows) kp_hi=32 ;;
		linux) kp_hi=69 ;;
		*) kp_hi=33 ;;
		esac
		kp_who='\[\e[38;5;245m\]\u@\h\[\e[0m\]'
		kp_dir='\[\e[1;38;5;'$kp_hi'm\]\w\[\e[0m\]'
		;;
	*)
		kp_who='\[\e[90m\]\u@\h\[\e[0m\]'
		kp_dir='\[\e[1;34m\]\w\[\e[0m\]'
		;;
	esac
	[ "$(id -u)" -eq 0 ] && kp_who='\[\e[31m\]\u@\h\[\e[0m\]'
	PS1="$kp_who $kp_dir "'\$ '
	unset kp_layout kp_file kp_hi kp_who kp_dir
}
kwick_prompt
unset -f kwick_prompt 2>/dev/null || true
