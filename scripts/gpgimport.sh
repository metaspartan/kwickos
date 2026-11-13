#!/bin/bash
set -u
k=${KWICK_SIGNING_KEY:-}
if [ -z "$k" ]; then echo "gpgimport: KWICK_SIGNING_KEY is empty (secret not available to this job?)" >&2; exit 1; fi
k=$(printf '%s' "$k" | tr -d '\r')
case "$k" in *"BEGIN PGP"*) ;; *) k=$(printf '%s' "$k" | base64 -d 2>/dev/null || true) ;; esac
case "$k" in *"BEGIN PGP"*) ;; *) echo "gpgimport: secret is neither armored PGP text nor base64 of it (len=${#KWICK_SIGNING_KEY})" >&2; exit 1 ;; esac
printf '%s\n' "$k" | gpg --batch --pinentry-mode loopback --passphrase "${KWICK_SIGNING_PASSPHRASE:-}" --import || { echo "gpgimport: gpg --import failed" >&2; exit 1; }
gpg --batch --list-secret-keys --keyid-format long | grep -q '^sec' || { echo "gpgimport: imported key has no secret part (is it the PUBLIC key?)" >&2; exit 1; }