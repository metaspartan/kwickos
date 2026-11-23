export DISCOVER_BACKENDS=flatpak-backend
export SVGA_NO_LOGGING=1
export GVFS_REMOTE_VOLUME_MONITOR_IGNORE=1
case ":${XDG_CONFIG_DIRS:-}:" in
  *:/etc/xdg/kwick-kde:*) ;;
  *) export XDG_CONFIG_DIRS=/etc/xdg/kwick-kde:${XDG_CONFIG_DIRS:-/etc/xdg} ;;
esac
