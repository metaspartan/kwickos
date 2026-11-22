case ":${PATH}:" in
  *":${HOME}/.local/bin:"*) ;;
  *) [ -n "${HOME:-}" ] && PATH="${HOME}/.local/bin:${PATH}" && export PATH ;;
esac
