case ":$PATH:" in
*:/usr/local/lib/kwick-arch/bin:*) ;;
*) [ -d /usr/local/lib/kwick-arch/bin ] && PATH=$PATH:/usr/local/lib/kwick-arch/bin && export PATH ;;
esac
