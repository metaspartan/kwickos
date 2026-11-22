#!/bin/sh
command -v kwick-agents >/dev/null 2>&1 || { echo '{"available":false}'; exit 0; }
printf '{"available":true,"list":'
kwick-agents list --json 2>/dev/null || printf '{"agents":[]}'
printf ',"grants":'
kwick-agents grants --json 2>/dev/null || printf '{"agents":{},"capabilities":[]}'
printf ',"keys":'
kwick-agents key list --json 2>/dev/null || printf '{"keys":[]}'
printf ',"audit":'
kwick-agents audit --json -n 60 2>/dev/null || printf '{"entries":[]}'
printf ',"consent":'
kwick-agents consent list --json 2>/dev/null || printf '{"pending":[]}'
printf ',"doctor":'
kwick-agents doctor --json 2>/dev/null
printf '}\n'
