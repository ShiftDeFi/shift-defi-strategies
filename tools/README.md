# tools

## merkl-claim.mjs

Builds the `MorphoVault.manualClaim` calldata from the Merkl rewards API and, with `--propose`, queues
it on the claimer Safe for the owners to confirm. Node ≥ 18, no npm deps, shells out to `cast`.

There is one claim per reward token: `manualClaim` hardcodes a single-element `users` array, and the
Angle distributor requires `users.length == tokens.length`.

```shell
npm run claim                                  # every strategy + on-chain pre-flight checks
npm run claim -- pyusd --safe-batch c.json     # flags for the script go after `--`
npm run claim:propose -- --dry-run             # show the batch, submit nothing
npm run claim:propose                          # one batched tx, signed by $SAFE_PROPOSER_ACCOUNT
npm run claim:propose -- --no-batch            # one transaction per claim instead
npm run claim:propose -- pyusd --account shift-dev   # a different `cast wallet` keystore
```

### Config

`tools/merkl-claim.env` is the tool's **only** config file. The npm scripts `source` it; the script
itself reads nothing off disk, and the repo-wide `.env` is deliberately not involved. It holds:

- one `MERKL_STRATEGY_<ALIAS>=0x…` per strategy, plus an optional `_LABEL`;
- `MERKL_CLAIM_SAFE`, `MERKL_CLAIM_RPC_URL`, `MERKL_CLAIM_MULTISEND` and `SAFE_PROPOSER_ACCOUNT`.

It is gitignored by the `**/*.env` rule, and `tools/merkl-claim.env.example` is the committed template.

- **Keep the values quoted.** The file is sourced by `sh`, so an unquoted `_LABEL` with a space in
  it is a shell syntax error.
- **The file overrides your environment.** `source` assigns unconditionally, so override settings on
  the command line, not with an env var.
- An exported `$ETH_RPC_URL` stands in for an unset `MERKL_CLAIM_RPC_URL`.
- A raw `0x` address as the strategy argument works with no config at all.

### Proposing

With `--propose` it signs the claim and queues it on the Safe transaction service
(`https://api.safe.global/tx-service/<eip3770>/api/v1`), where the owners confirm it as usual.
`--dry-run` signs and prints the payload without submitting.

The signing key only needs to be a **delegate** of the claimer Safe. Delegates can queue transactions
but cannot confirm or execute them, so no key that can move funds is involved.

**All the claims go in one transaction.** They are delegatecalled through `MultiSendCallOnly`
(`$MERKL_CLAIM_MULTISEND`, version-matched to the Safe), on a single nonce one past whatever the Safe
already has queued. The inner calls still come from the Safe itself, so each strategy sees
`msg.sender` holding `MERKLE_CLAIMER_ROLE`.

**If any claim fails pre-flight, nothing is queued.**

- A partial claim is not a useful outcome: a strategy that cannot claim is something to investigate.
- Every strategy claims against the same distributor root, so the claims go stale together anyway.
- One nonce avoids a chain of coupled ones. Safe nonces are strictly sequential, so separate
  proposals strand each other if the owners skip one.

`--force` queues the batch despite a failed check. `--no-batch` proposes each claim on its own nonce,
skipping a failing claim instead of aborting.

### Signer

The signer is a `cast wallet` keystore account, set with `--account <name>` or `$SAFE_PROPOSER_ACCOUNT`.
The key stays encrypted at rest and the script never handles it: it passes `--account` to
`cast wallet sign`, which prompts for the password on the terminal (`castInteractive` keeps
stdin/stderr attached for that).

The proposer address is recovered from the signature through the ecrecover precompile, so the keystore
is unlocked once per proposal. That address is then checked against the Safe's owners and delegates
before anything is submitted.

| Option                         | Use                                                              |
| ------------------------------ | ---------------------------------------------------------------- |
| `$SAFE_PROPOSER_PASSWORD_FILE` | Unlocks the keystore unattended (CI).                            |
| `--ledger`                     | Signs on the device instead.                                     |
| `$SAFE_PROPOSER_PRIVATE_KEY`   | Last resort: puts the key in the `cast` child's argv. Avoid it.  |
| `$SAFE_API_KEY`                | developer.safe.global key; lifts the 2 RPS / 5k-per-month limit. |

To set up an account, run `cast wallet import <name> --interactive`. `cast wallet list` names the
accounts, and `cast wallet address --account <name>` shows which address one holds (Foundry keystores
do not store the address in plaintext).

The proposal digest is read from the Safe's own `getTransactionHash`.

### Slack message

After proposing, it prints a Slack message (mrkdwn) for the co-signers:

- the network as `*[ETH]*`;
- the strategies, in bold;
- an `Expires:` line;
- the Safe UI link to each queued transaction, at the bottom.

Times are dd-mm-yyyy HH:MM at a fixed UTC+3 (`UTC_OFFSET_HOURS`).

The expiry comes from the distributor. `getMerkleRoot()` serves `lastTree` until
`endOfDisputePeriod` and `tree` after it.

- **A tree is pending:** the switch time is exact.
- **The tree is live:** the next switch is only bounded below by `_endOfDisputePeriod(now)`. The likely
  time is estimated from the last 8 days of `TreeUpdated` events: the next slot on Merkl's regular
  grid (every 8h at 05:00 / 13:00 / 21:00 UTC+3 on mainnet), or earlier if a tree went live at that
  time a week before (Merkl adds 11:00 and 19:00 trees on Mondays). Backtested over 12-09 to
  07-10-2026, it is exact 93% of the time. In 2% the root dies earlier than stated, and in 5% it
  lives longer (a skipped update).

The pre-flight prints the same as a "root expiry" line, which never blocks a proposal.
