#!/bin/sh
if [ "$(id -u)" = 0 ]; then exec "$@"; fi
if sudo -n true 2>/dev/null; then exec sudo -n "$@"; fi
exec "$@"
