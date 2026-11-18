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
- NAV assertions use percentage tolerances (`NAV_TOLERANCE_PCT`) rather than
  exact equality, since fork prices move.
- Tests compile only with `--via-ir`; the `just test*` recipes pass it.
