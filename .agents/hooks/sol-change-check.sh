#!/usr/bin/env bash
# Runs when an agent stops. Fork tests need RPC access, so they are left
# to the agent and CI; this only keeps changed Solidity formatted and compiling.
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

if ! out=$(just build-all 2>&1); then
    { echo "just build-all failed:"; tail -n 60 <<<"$out"; } >&2
    exit 2
fi
