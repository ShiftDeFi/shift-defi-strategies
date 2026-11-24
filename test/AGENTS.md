# AGENTS.md — tests

- Do not weaken or delete a test to make a suite pass; if a test is wrong,
  say so.
- Report failing tests with their output rather than as passing. A fork
  test that cannot reach its RPC has not passed.
- Layout: `test/BaseConfig.sol` (roles, users, constants) →
  `test/ethereum/EthContext.t.sol` (mainnet addresses, deploys
  `MockStrategyContainer`, wires Chainlink oracles into the live
  `PriceOracleAggregator`, helpers `_proxify` / `_addStrategy` /
  `_whitelistTokenIfNeeded`) → per-strategy `*Base.t.sol` abstract with the
  shared setup and shared test bodies → concrete per-asset files (e.g.
  `MorphoVault.Pyusd.t.sol`) that only set addresses. New mainnet addresses
  belong in `EthContext`, new shared assertions in the strategy's
  `*Base.t.sol`. Other chains follow the same shape (`test/monad/MonadContext.t.sol`).
- Test names: `test_<Behavior>` and `testRevert_<Function>_<Reason>`.
- Use `vm.expectRevert` with the specific custom error selector, not a bare
  `vm.expectRevert()`.
- Every fork pins its block: `ETH_FORK_BLOCK` in `EthContext`,
  `MONAD_FORK_BLOCK` in `MonadContext`, `_forkBlock()` in each live upgrade
  test, `FORK_BLOCK_NUMBER` in the Merkle claim tests. Never fork the latest
  block. Bump a block deliberately, in its own `test:` commit, after the
  suite passes at the new block.
- NAV assertions use percentage tolerances (`NAV_TOLERANCE_PCT`) rather than
  exact equality, so a block bump does not break them.
- Tests compile only with via-IR: run them through `just test*`, which use
  the `ir` profile (`FOUNDRY_PROFILE=ir`) and its own build cache.
