#!/bin/sh
command -v kwick-storage >/dev/null 2>&1 || exit 0
kwick-storage status --machine 2>/dev/null
kwick-storage overview --machine 2>/dev/null
