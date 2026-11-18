# Shift DeFi Strategies

Upgradeable strategy contracts that plug external DeFi protocols (Curve,
Fluid, Morpho, Aave v3) into the Shift core system (`@shift-defi/core`).

## Setup

Requires [Foundry](https://getfoundry.sh) v1.8.3 (`foundryup -i v1.8.3`),
[just](https://github.com/casey/just), Node.js and npm.

```shell
just setup   # npm install + point git at the hooks in .githooks
```

Tests fork live networks at pinned blocks, so the RPCs must serve archive
state. Put the RPC URLs in `.env` (gitignored), which forge loads on its
own: `ETH_RPC_URL`, `BASE_RPC_URL`, `MONAD_RPC_URL` (and `ARB_RPC_URL` for
scripts).

## Usage

```shell
just              # list recipes
just build        # compile contracts/ and check sizes
just fmt          # forge fmt
just test         # every test (fork tests pin their blocks)
just check        # what CI runs
just analyze      # slither + aderyn
```

Git hooks: `commit-msg` enforces `<type>(<scope>): <summary>` (see
`AGENTS.md`); `pre-commit` runs `forge fmt --check`, `just build` and every
test when Solidity or build config is staged.

## Agent harness

Agent instructions live in `AGENTS.md`, read natively by Codex and Cursor.
`CLAUDE.md` is a symlink to it, so Claude Code reads the same file. Edit
`AGENTS.md` only.

- `AGENTS.md`: repo-wide context, conventions and rules
- `test/AGENTS.md` (with `test/CLAUDE.md` symlinked to it): test
  conventions, loaded when working under `test/`
- `.claude/settings.json`, `.codex/`, `.cursorignore`: keep `.env` files out
  of agent reach, sandbox shell commands, and run
  `.agents/hooks/sol-change-check.sh` (format + compile `contracts/`) when an
  agent stops; tests compile and run in the pre-commit hook and CI

Symlinks do not survive every Windows checkout; on Windows, enable
`core.symlinks` or replace each `CLAUDE.md` with a one-line pointer to
`AGENTS.md`.
