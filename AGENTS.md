# AGENTS.md

## Project

Foundry project holding the DeFi strategy contracts for the Shift platform.
Each contract under `contracts/<protocol>/` is an upgradeable strategy that
plugs a single external protocol (Curve, Fluid, Morpho, Aave v3) into the
Shift core system, which lives in the separate npm package `@shift-defi/core`
(`node_modules/@shift-defi/core/contracts`, remapped to `@shift-defi/core`).
Read `StrategyTemplate.sol` and `StrategyContainer.sol` there before changing
strategy logic: the lifecycle, roles and slippage checks all live in core,
not here.

These contracts are audited. Every changed line, formatting included, lands
in the next audit diff: change only what the task needs, and never touch
existing code just to make it follow the conventions below. They apply to
code you write or rewrite.

## Commands

`just` wraps the common commands; `just` alone lists them. Forge is pinned
to v1.8.3 (`foundryup -i v1.8.3`).

```shell
just setup        # npm install + git hooks; once per clone
just build        # forge build contracts --sizes
just build-all    # tests and scripts too, via the `ir` profile (via-IR)
just fmt          # forge fmt
just test         # every test, as the pre-commit hook runs it
just test-eth     # Ethereum fork suite (also test-base, test-monad)
just test --mt test_Harvest          # one test
just test --mc MorphoVaultPyusd      # one contract
just check        # fmt check + build + every test
just lint         # forge lint (not run on build)
just analyze      # slither + aderyn (report in reports/aderyn.md)
```

Tests are **mainnet-fork tests**, each pinned to a fixed block, so results
are reproducible and repeat runs come from forge's RPC cache. Forge loads
`ETH_RPC_URL`, `BASE_RPC_URL` and `MONAD_RPC_URL` from `.env`, which agent
sandboxes cannot read. Before running tests, ask the human to start the
agent with those variables exported; if a fork test cannot reach its RPC,
say so instead of skipping it.

Formatting is `forge fmt` with the `[fmt]` section of `foundry.toml`, tuned
so existing code does not reflow. Files in its `ignore` list are audited code
that `forge fmt` would rewrap; take a file off the list only in a change
that is going to audit anyway.

Deploy and upgrade scripts (`script/deploy`, `script/upgrade`) read their
inputs from env vars and are run by a human. `UpgradeBase` defaults to _not_
broadcasting the upgrade: it deploys the new implementation and prints the
`ProxyAdmin.upgradeAndCall` calldata for the multisig; `EXECUTE_UPGRADE=true`
is only for when the broadcasting EOA owns the proxy's `ProxyAdmin`.

`tools/merkl-claim.mjs` builds `MorphoVault.manualClaim` calldata from the
Merkl API and, with `--propose`, queues it on the claimer Safe (`just claim`
/ `just claim-propose`). Its only config is `tools/merkl-claim.env`
(gitignored; template `tools/merkl-claim.env.example`); usage and internals
are in `tools/README.md`. Two design choices not to undo:

- Claims are batched into **one all-or-nothing transaction** via
  `MultiSendCallOnly`: if any claim fails pre-flight, nothing is queued. A
  partial claim is deliberately not an outcome.
- The proposing key is a **delegate-only** `cast wallet` keystore account,
  never an owner key, and the script never handles the key itself.

## Strategy architecture

A strategy is a `TransparentUpgradeableProxy` over a contract that extends
`StrategyTemplate` (from core) and usually `AccessControlUpgradeable`, and
implements a per-protocol interface in `contracts/interfaces/`.

**State machine.** Every strategy declares its positions as `bytes32` state
IDs (`keccak256("...")`) registered in `initialize` via
`_setState(stateId, isTargetState, isProtocolState, isTokenState, height)`:

- _token state_: funds sit as the raw underlying asset in the strategy
  (height 0/1, the emergency-exit destination);
- _protocol state_: funds are deposited in the external protocol;
- _target state_: where `enter()` puts funds by default; exactly one per
  strategy, and it cannot also be a token state;
- _height_: depth of the position, used to order emergency exits (see
  `CurveGauge`, which has three stacked states: underlying → Curve LP →
  gauge).

The template drives the state machine and calls these hooks, which each
strategy overrides and which must `revert StateNotFound(stateId)` for
unknown states: `stateNav(stateId)` (view, in notion terms), `_enterTarget`,
`_enterState`, `_exitTarget`, `_exitFromState(stateId, share)`,
`_emergencyExit(toStateId, share)`, `_harvest(stateId, treasury, feePct)`.

`share` is always in bps with `MAX_BPS = 1e18`. NAV is expressed in the
container's _notion_ token via `getTokenAmountInNotion(token, amount)`; the
template enforces `minNavDelta` slippage bounds around enter/exit, so a
strategy hook only moves funds and never checks slippage itself.

**Access control.** Most entry points are gated by the template's
modifiers, which read roles off the _strategy container_, not off the
strategy (`onlyStrategyContainer`, `onlyStrategyContainerOrHarvestManager`,
`onlyEmergencyManager`, `onlyEmergencyExecutor`,
`onlyReshufflingExecutorOrStrategyContainer`). The only role granted locally
is `MERKLE_CLAIMER_ROLE` for `manualClaim`.

**Rewards.** Two paths: `_harvest` (called by the container/harvest manager)
swaps reward tokens back to the input token through `_swapToInputTokens` and
reinvests; `manualClaim` is a separate `MERKLE_CLAIMER_ROLE` entry point for
off-chain Merkle reward distributors (Angle for Morpho, Fluid's own
distributor). Both take the performance fee in _vault/LP tokens_ to
`treasury`, computed from `feePct` on the growth since `lastAssetsValue` plus
the LP delta gained by reinvesting, then bump `lastAssetsValue`. Keep those
two code paths in sync when changing fee accounting. `manualClaim` must
reject while `isNavResolutionMode()` is true.

**Upgrades.** Strategies are live behind proxies: never reorder, retype or
remove a state variable; append new ones after the last. A change to storage
layout says so in the commit body.

## Comments

- Comment only what the code cannot say: an invariant, a unit, a trust
  assumption, or the reason for a non-obvious choice. Keep it to one line
  unless that loses meaning.
- Do not explain what the code does; if it needs explaining, rename or
  restructure it.
- Describe the code as it is, not how it got here: no "previously",
  "fixed", "now handles", "was reverting when", or bug and issue
  backstories. History belongs in the commit message.
- External functions carry NatSpec in the interface: `@notice`, and
  `@param` and `@return` for each parameter and return value. Each tag is
  one sentence. Add `@dev` only for behaviour a caller would not expect.
  The implementation carries `/// @inheritdoc <Interface>`.

## Code style

**Pragma.** `pragma solidity ^0.8.28;`, as in the rest of the repo.

**Imports.** Named imports only, nothing unused. Groups separated by one
blank line, in this order: OpenZeppelin, `@shift-defi/core`, this repo's
interfaces, vendored protocol interfaces (`../dependencies/...`). Inside
`contracts/` import this repo's files by relative path.

**Interfaces.** Each strategy implements `contracts/interfaces/I<Strategy>.sol`,
which declares its structs (including `LocalVars`), events, custom errors
and external functions. External protocol interfaces are vendored under
`contracts/dependencies/<protocol>/` rather than pulled in as dependencies,
and keep upstream naming (the `mixed-case-*` lints are off for that reason).

**Errors.** Custom errors only. Shared ones come from
`@shift-defi/core/libraries/Errors.sol` (`Errors.ZeroAddress()`,
`Errors.Unauthorized()`, …); strategy-specific ones are declared in the
strategy's interface. Use `require(cond, SomeError())`, not `revert`
statements or string messages.

**Initialization.** Implementations call `_disableInitializers()` in the
constructor; all setup happens in `initialize`, which validates every
address against zero.

**Visibility.** A function not called from inside its contract or a
contract that inherits it is `external`, not `public`.

**Naming.** Internal and private functions are prefixed with an underscore;
state variables are not. Events are named in the past tense
(`RewardTokensUpdated`).

**Storage.** Cache storage reads in locals suffixed `Cached` before loops or
repeated use. Never read a cached copy after that variable is written or
after an external call.

**Loops.** `++i`, never `i++`. Cache a storage array's length before
iterating.

**Local variables.** When a function hits stack-too-deep, first scope
temporaries in `{ }` blocks or split the function. Only if that fails, group
its locals into a `<FunctionName>LocalVars` struct declared in the
strategy's interface (as harvest/claim already do).

**Reentrancy.** State-changing functions follow
checks-effects-interactions. `StrategyTemplate` inherits OpenZeppelin's
`ReentrancyGuardUpgradeable`; a new external entry point that calls a token
or an external protocol takes `nonReentrant`.

**unchecked.** Every `unchecked` block carries a one-line comment stating
why it cannot overflow or underflow.

**Arithmetic.** Downcast and convert between signed and unsigned with
OpenZeppelin `SafeCast`; a bare narrowing cast needs a comment stating why
the value fits. Compute `a * b / c` with `Math.mulDiv` and an explicit `Math.Rounding`.

**Tokens.** Move ERC-20s through `SafeERC20` (`safeTransfer`,
`safeTransferFrom`, `forceApprove`). Strategies support no fee-on-transfer
or rebasing tokens unless the interface `@dev` says so.

**Events.** A state-changing configuration function emits an event carrying
the new value. Index the fields consumers filter by (addresses, ids), not
amounts.

## Dependencies

Solidity libraries are git submodules under `lib/`, pinned in
`foundry.lock`; add them with `forge install`, never by hand, and add the
remapping to `remappings.txt`. Shift core comes from npm
(`@shift-defi/core` in `package.json`); bumping it changes the code the
strategies inherit, so it is its own commit.

## Commits

- One logical change per commit. Keep `forge fmt`-only changes, dependency
  updates and refactors apart from changes in behaviour.
- Header: `<type>(<scope>): <summary>`, at most 72 characters, no trailing
  period. `<type>` is one of `feat`, `fix`, `perf` (gas; the body gives the
  `forge snapshot --diff` result), `refactor`, `test`, `docs`, `style`
  (`forge fmt` only), `chore` (dependencies, tooling), `wip`. `<scope>` is
  lower-case and optional.
- A change to an external function, event or custom error signature takes
  `!` before the colon (`feat(morpho)!: …`) and the body says what changed.
- Body only when the header is not enough: wrapped at 72 characters, says
  why the change is made, not how the code works.
- No `Co-Authored-By` or other AI attribution trailer.
- `.githooks/commit-msg` checks the message and `.githooks/pre-commit` runs
  `forge fmt --check`, `just build` and every test once `just setup` has
  run in the clone.

## Rules

- Never sign or send a transaction except to a local `anvil` node: no
  `--broadcast` on `forge script` or `forge create`, and no `cast send`,
  `cast publish`, `cast mktx` or `cast wallet sign` against any other RPC.
  The deploy, upgrade and claim commands above are for the human.
- Never read or write a private key, keystore, or `.env` file (including
  `tools/merkl-claim.env`), and never write code that reads one
  (`vm.envUint("PRIVATE_KEY")`). Scripts call `vm.startBroadcast()` with no
  argument; the signer comes from the human's `--account` flag.
