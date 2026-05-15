#!/bin/sh

if [ -z "${ETH_RPC_URL:-}" ]; then
  echo "Error: ETH_RPC_URL is not set" >&2
  exit 1
fi

forge test -vvv --mp "test/ethereum/**" --fork-url $ETH_RPC_URL --via-ir
if [ $? -ne 0 ]; then
    echo "Forge tests failed! Commit aborted."
    exit 1
fi
