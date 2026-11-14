streaming_arch() { echo any; }
streaming_desc() { echo "Sunshine game-stream host (pinned release) and the Moonlight client"; }

streaming_state() {
  a=no; b=no
  pkg_installed sunshine && a=yes
  fp_have com.moonlight_stream.Moonlight && b=yes
  combine_state "$a" "$b"
}

streaming_install() {
  rc=0
  case $ARCH in
    amd64) url=$SUNSHINE_URL_amd64; sha=$SUNSHINE_SHA256_amd64 ;;
    arm64) url=$SUNSHINE_URL_arm64; sha=$SUNSHINE_SHA256_arm64 ;;
    *) url=""; sha="" ;;
  esac
  if [ -z "$url" ]; then
    warn "Sunshine has no build for $ARCH; installing the Moonlight client only"
    rc=1
  elif ! pkg_installed sunshine; then
    t=$(mktemp -d /var/tmp/kwick-gaming.XXXXXX)
    if fetch_verify "$url" "$sha" "$t/sunshine.deb"; then
      apt_ready
      DEBIAN_FRONTEND=noninteractive apt-get install -y "$t/sunshine.deb" || rc=1
    else
      rc=1
    fi
    rm -rf "$t"
  fi
  fp_install com.moonlight_stream.Moonlight || rc=1
  load_modules uinput
  say "Start the host as your user: systemctl --user enable --now sunshine, then open https://localhost:47990 to set it up."
  return $rc
}

streaming_remove() {
  apt_remove sunshine
  fp_remove com.moonlight_stream.Moonlight
  return 0
}
