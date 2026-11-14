#!/bin/sh
command -v kwick-gaming >/dev/null 2>&1 || exit 0
kwick-gaming status --machine 2>/dev/null
