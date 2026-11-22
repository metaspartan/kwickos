#!/bin/sh
t=$(kwick-shell list --json 2>/dev/null)
p=$(kwick-shell prompt list --json 2>/dev/null)
d=$(kwick-desktop shell list --json 2>/dev/null)
h=$(cat /proc/sys/kernel/hostname 2>/dev/null)
printf '{"user":"%s","host":"%s","layout":"%s","terminal":%s,"prompts":%s,"desktop":%s}\n' "$(id -un)" "${h:-kwick}" "$(kwick-layout 2>/dev/null || echo macos)" "${t:-null}" "${p:-null}" "${d:-null}"
