#!/bin/sh
command -v kwick-agents >/dev/null 2>&1 || { echo '{"available":false}'; exit 0; }
printf '{"available":true,"status":'
kwick-agents inference status --json 2>/dev/null || printf 'null'
printf ',"models":'
kwick-agents inference models --json 2>/dev/null || printf '{"models":[]}'
printf '}\n'
