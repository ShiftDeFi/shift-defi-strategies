# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Foundry project holding the DeFi strategy contracts for the Shift platform. Each contract under
`contracts/<protocol>/` is an upgradeable strategy that plugs a single external protocol (Curve, Fluid,
Morpho, Aave v3) into the Shift core system, which lives in the separate npm package
`@shift-defi/core` (`node_modules/@shift-defi/core/contracts`, remapped to `@shift-defi/core`).
Read `StrategyTemplate.sol` and `StrategyContainer.sol` there before changing strategy logic — the
lifecycle, roles and slippage checks all live in core, not here.

## Commands

Tests are **mainnet-fork tests**; they will not pass without an RPC URL. `.env` (gitignored) exports
`ETH_RPC_URL` / `ARB_RPC_URL` / `BASE_RPC_URL` and the deploy addresses — `source .env` first.

```shell
forge build                                    # add --sizes to check contract size limits
forge fmt                                      # CI runs `forge fmt --check`

# Full ethereum suite (what the pre-commit hook runs)
forge test -vvv --mp "test/ethereum/**" --fork-url $ETH_RPC_URL --via-ir

forge test --mp "test/ethereum/MorphoVault/**" --fork-url $ETH_RPC_URL   # one strategy
forge test --mt test_Harvest --fork-url $ETH_RPC_URL                     # one test
forge test --mc MorphoVaultPyusd --fork-url $ETH_RPC_URL                 # one contract
```

Deploy / upgrade scripts read everything from env vars (see `script/deploy/*.s.sol`):

```shell
forge script script/deploy/DeployMorphoVault.s.sol --rpc-url ethereum --broadcast
forge script script/upgrade/UpgradeMorphoVault.s.sol --rpc-url ethereum --broadcast
```

`UpgradeBase` defaults to _not_ broadcasting the upgrade: it deploys the new implementation and prints
the `ProxyAdmin.upgradeAndCall` calldata for the multisig. Set `EXECUTE_UPGRADE=true` only when the
broadcasting EOA owns the proxy's `ProxyAdmin`.

`tools/merkl-claim.mjs` (node ≥ 18, no npm deps, shells out to `cast`) builds the
`MorphoVault.manualClaim` calldata for the Safe UI from the Merkl rewards API — one transaction per
reward token, since `manualClaim` hardcodes a single-element `users` array and the Angle distributor
requires `users.length == tokens.length`:

Run it through the npm scripts, which `source` its config first — the script itself reads nothing
off disk:

```shell
npm run claim                                  # every strategy + on-chain pre-flight checks
npm run claim -- pyusd --safe-batch c.json     # flags for the script go after `--`
```

`tools/merkl-claim.env` is the tool's **only** config file — one `MERKL_STRATEGY_<ALIAS>=0x…` per
strategy (plus an optional `_LABEL`), `MERKL_CLAIM_SAFE`, `MERKL_CLAIM_RPC_URL` and
`SAFE_PROPOSER_ACCOUNT`, `MERKL_CLAIM_MULTISEND`. Nothing is hardcoded in the script and the repo-wide `.env` is deliberately
not involved, so the tool stands alone. It is gitignored by the existing `**/*.env` rule;
`tools/merkl-claim.env.example` is the committed template. It is sourced by `sh`, so **keep the
values quoted** — an unquoted `_LABEL` with a space in it is a shell syntax error, not a config bug.
An exported `$ETH_RPC_URL` stands in for an unset `MERKL_CLAIM_RPC_URL`. Note that `source` assigns
unconditionally, so the file wins over anything already in your environment — override on the command
line, not with an env var. A raw `0x` address as the strategy argument works with no config at all.

With `--propose` it skips the Safe UI entirely: it signs each claim and queues it on the Safe
transaction service (`https://api.safe.global/tx-service/<eip3770>/api/v1`), where the owners confirm
it as usual. The signing key only needs to be a **delegate** of the claimer Safe — delegates can
queue transactions but cannot confirm or execute them, so no key that can move funds is involved.
`--dry-run` signs and prints the payload without submitting.

**All the claims go in one transaction**, delegatecalled through `MultiSendCallOnly`
(`$MERKL_CLAIM_MULTISEND`, version-matched to the Safe), on a single nonce one past whatever the Safe
already has queued. That is deliberate and the failure semantics follow from it: **if any claim fails
pre-flight, nothing is queued at all.** A partial claim is not a useful outcome — one strategy that
cannot claim is a thing to investigate, not a reason to push the others through — and since every
strategy claims from the same Angle distributor against the same global Merkle root, the legs go
stale together anyway, so isolating them buys nothing. Batching also means one nonce rather than a
chain of coupled ones: Safe nonces are strictly sequential, so separate proposals strand each other
if the owners skip one. `--force` queues a batch despite a failed check; `--no-batch` falls back to
one proposal per claim on consecutive nonces, where a failing claim is skipped instead of fatal.

Inner calls come from the Safe itself (that is what the delegatecall into `MultiSendCallOnly` buys),
so each strategy still sees `msg.sender` holding `MERKLE_CLAIMER_ROLE`.

```shell
npm run claim:propose -- --dry-run             # show the batch, submit nothing
npm run claim:propose                          # one batched tx, signed by $SAFE_PROPOSER_ACCOUNT
npm run claim:propose -- --no-batch            # one transaction per claim instead
npm run claim:propose -- pyusd --account shift-dev   # a different `cast wallet` keystore
```

The signer is a **`cast wallet` keystore account** — `--account <name>`, or `$SAFE_PROPOSER_ACCOUNT`
in `tools/merkl-claim.env` so `--propose` needs no flags. The key stays encrypted at rest and is never handled by the
script: it splices `--account` into `cast wallet sign` and `cast` does the rest, prompting for the
password on the terminal (`castInteractive` keeps stdin/stderr attached for exactly that).
`$SAFE_PROPOSER_PASSWORD_FILE` unlocks it unattended for CI. `--ledger` signs on device instead, and
`$SAFE_PROPOSER_PRIVATE_KEY` is a last-resort fallback that puts the key in the `cast` child's argv —
avoid it. Set up an account with `cast wallet import <name> --interactive`; `cast wallet list` names
them and `cast wallet address --account <name>` reveals which address one holds (Foundry keystores do
not store the address in plaintext).

The Safe address comes from `--safe` or `$MERKL_CLAIM_SAFE`. `$SAFE_API_KEY`
(developer.safe.global) lifts the transaction service's unauthenticated 2 RPS / 5k-per-month limit.
The proposal digest is read off the Safe's own `getTransactionHash`, and the signature is checked back
through the ecrecover precompile before it is submitted.

Commits go through commitlint (conventional, `feat|fix|docs|chore|style|refactor|test|wip`, header ≤ 72
chars, non-empty body with lines ≤ 72 chars) and a pre-commit hook that runs prettier + the fork tests.

## Strategy architecture

A strategy is a `TransparentUpgradeableProxy` over a contract that extends
`StrategyTemplate` (from core) and usually `AccessControlUpgradeable`, and implements a
per-protocol interface in `contracts/interfaces/`.

**State machine.** Every strategy declares its positions as `bytes32` state IDs
(`keccak256("...")`) registered in `initialize` via
`_setState(stateId, isTargetState, isProtocolState, isTokenState, height)`:

- _token state_ — funds sit as the raw underlying asset in the strategy (height 0/1, the emergency-exit
  destination);
- _protocol state_ — funds are deposited in the external protocol;
- _target state_ — where `enter()` puts funds by default; exactly one per strategy, and it cannot also be
  a token state;
- _height_ — depth of the position, used to order emergency exits (see `CurveGauge`, which has three
  stacked states: underlying → Curve LP → gauge).

The template drives the state machine and calls these hooks, which each strategy overrides and which
must `revert StateNotFound(stateId)` for unknown states:

`stateNav(stateId)` (view, in notion terms), `_enterTarget`, `_enterState`, `_exitTarget`,
`_exitFromState(stateId, share)`, `_emergencyExit(toStateId, share)`, `_harvest(stateId, treasury, feePct)`.

`share` is always in bps with `MAX_BPS = 1e18`. NAV is expressed in the container's _notion_ token via
`getTokenAmountInNotion(token, amount)`; the template enforces `minNavDelta` slippage bounds around
enter/exit, so a strategy hook only moves funds and never checks slippage itself.

**Access control.** Most entry points are gated by the template's modifiers, which read roles off the
_strategy container_, not off the strategy (`onlyStrategyContainer`,
`onlyStrategyContainerOrHarvestManager`, `onlyEmergencyManager`, `onlyEmergencyExecutor`,
`onlyReshufflingExecutorOrStrategyContainer`). The only role granted locally is `MERKLE_CLAIMER_ROLE`
for `manualClaim`.

**Rewards.** Two paths: `_harvest` (called by the container/harvest manager) swaps reward tokens back to
the input token through `_swapToInputTokens` and reinvests; `manualClaim` is a separate
`MERKLE_CLAIMER_ROLE` entry point for off-chain Merkle reward distributors (Angle for Morpho, Fluid's own
distributor). Both take the performance fee in _vault/LP tokens_ to `treasury`, computed from
`feePct` on the growth since `lastAssetsValue` plus the LP delta gained by reinvesting, then bump
`lastAssetsValue`. Keep those two code paths in sync when changing fee accounting. `manualClaim` must
reject while `isNavResolutionMode()` is true.

**Stack depth.** Harvest/claim functions use `...LocalVars` structs declared in the strategy's interface
to stay under the stack limit; the pre-commit test run uses `--via-ir` for the same reason.

## Conventions

- Cache storage reads in locals suffixed `Cached` before loops or repeated use.
- Custom errors only — shared ones from `@shift-defi/core/libraries/Errors.sol` (`Errors.ZeroAddress()`,
  `Errors.Unauthorized()`, …), strategy-specific ones declared in the strategy's interface. Use
  `require(cond, SomeError())`, not `revert` statements or string messages.
- Implementations call `_disableInitializers()` in the constructor; all setup happens in `initialize`,
  which validates every address against zero.
- External protocol interfaces are vendored under `contracts/dependencies/<protocol>/` rather than pulled
  in as dependencies.
- Formatting: solidity at printWidth 120 / 4 spaces / no bracket spacing (prettier-plugin-solidity, then
  `forge fmt`). `mixed-case-function` and `mixed-case-variable` lints are disabled so vendored interfaces
  can keep upstream naming.

## Tests

`test/BaseConfig.sol` (roles, users, constants) → `test/ethereum/EthContext.t.sol` (mainnet addresses,
deploys `MockStrategyContainer`, wires Chainlink oracles into the live `PriceOracleAggregator`, helpers
`_proxify` / `_addStrategy` / `_whitelistTokenIfNeeded`) → per-strategy `*Base.t.sol` abstract with the
shared setup and shared test bodies → concrete per-asset files (e.g. `MorphoVault.Pyusd.t.sol`) that only
set `morphoVault`/token addresses. New mainnet addresses belong in `EthContext`, new shared assertions in
the strategy's `*Base.t.sol`.

Test names: `test_<Behavior>` and `testRevert_<Function>_<Reason>`. NAV assertions use percentage
tolerances (`NAV_TOLERANCE_PCT`) rather than exact equality, since fork prices move.
