containers_arch() { echo any; }
containers_desc() { echo "Docker with Compose and rootless Podman, the Unraid apps equivalent"; }

containers_state() {
  a=no; b=no
  pkg_installed docker.io && a=yes
  pkg_installed podman && b=yes
  combine_state "$a" "$b"
}

containers_install() {
  apt_get docker.io docker-compose podman uidmap slirp4netns || return 1
  load_modules overlay br_netfilter veth
  svc_enable docker
  u=$(target_user)
  [ -n "$u" ] && getent group docker >/dev/null && usermod -aG docker "$u" 2>/dev/null && say "$u is in the docker group after the next login"
  say "Run apps with docker compose up -d; manage Podman containers in Cockpit."
  return 0
}

containers_remove() {
  svc_disable docker docker.socket
  apt_remove docker-compose docker.io podman
  return 0
}
