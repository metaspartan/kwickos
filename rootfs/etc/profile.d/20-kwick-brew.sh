if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
	eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv sh)"
	__kb_path=
	__kb_ifs=$IFS
	IFS=:
	for __kb_d in $PATH; do
		case $__kb_d in
		/home/linuxbrew/.linuxbrew/bin | /home/linuxbrew/.linuxbrew/sbin) ;;
		*) __kb_path=${__kb_path:+$__kb_path:}$__kb_d ;;
		esac
	done
	IFS=$__kb_ifs
	PATH=$__kb_path:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin
	export PATH
	unset __kb_path __kb_ifs __kb_d
fi
