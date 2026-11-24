#!/usr/bin/env bash
# Runs when an agent stops. Compiling tests (via-IR) costs 30-40 s per edit,
# so tests are left to the pre-commit hook; this only keeps changed
# Solidity formatted and contracts/ compiling.
set -u

input=$(cat)
[ "$(jq -r '.stop_hook_active' <<<"$input")" = "true" ] && exit 0

cd "$(git rev-parse --show-toplevel)" || exit 0
[ -z "$(git status --porcelain -- '*.sol')" ] && exit 0

just fmt >/dev/null 2>&1

if ! out=$(just build 2>&1); then
    { echo "just build failed:"; tail -n 60 <<<"$out"; } >&2
    exit 2
fi
