#!/bin/bash
set -euo pipefail
R=${1:-/work/repo}
PORT=${2:-8080}
cat > /tmp/nginx.conf <<CONF
daemon off;
pid /tmp/nginx.pid;
error_log /tmp/nginx.err;
events {}
http { access_log /tmp/nginx.acc; server { listen $PORT; root $R; autoindex on; } }
CONF
exec nginx -c /tmp/nginx.conf
