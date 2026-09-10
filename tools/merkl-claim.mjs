#!/usr/bin/env node
/**
 * Builds the raw `MorphoVault.manualClaim(...)` calldata for the Safe UI from the Merkl rewards API.
 *
 * Merkl (Angle) hands out Morpho vault rewards through a Merkle distributor: the API returns the
 * *cumulative* amount a recipient is entitled to plus the proof for the currently published root,
 * and `manualClaim` forwards both to `IAngleMerkleDistributor.claim`. This script does the API call,
 * drops what is already claimed, runs a few on-chain pre-flight checks and prints the hex calldata to
 * paste into the Safe UI (Transaction Builder -> custom data), or a batch file to import there.
 *
 * Run it through npm, which sources `tools/merkl-claim.env` into the environment first:
 *
 *   npm run claim                             # every configured strategy + pre-flight checks
 *   npm run claim -- pyusd                    # one strategy (alias, or a 0x address)
 *   npm run claim -- --safe-batch claim.json
 *   npm run claim -- --no-preflight           # calldata only, no RPC
 *   npm run claim:propose -- --dry-run        # queue it in the Safe for the owners
 *
 * Needs node >= 18 (global fetch) and `cast` on PATH. Everything else — the strategy addresses, the
 * Safe, the RPC URL and the signing account — comes from `tools/merkl-claim.env`, which the npm
 * script sources; the repo-wide `.env` is deliberately not part of it, so this tool stands alone.
 *
 * With --propose the claim is signed and pushed to the Safe transaction service, so it shows up in
 * the Safe UI for the owners to confirm. The signing key only has to be a *delegate* of the Safe —
 * delegates can queue transactions but cannot confirm or execute them — so nothing that can move
 * funds has to live in the automation.
 */

import {execFileSync} from "node:child_process";
import {writeFileSync} from "node:fs";

const MERKL_API = "https://api.merkl.xyz/v4";

const STRATEGY_ENV_PREFIX = "MERKL_STRATEGY_";

const MANUAL_CLAIM_SIG = "manualClaim(address[],uint256[],bytes32[][])";
const MERKLE_CLAIMER_ROLE = "MERKLE_CLAIMER_ROLE";

const SAFE_TX_SERVICE = "https://api.safe.global/tx-service";

/** EIP-3770 short names the Safe transaction service is addressed by. */
const SAFE_CHAIN_SHORTNAME = {1: "eth", 42161: "arb1", 8453: "base"};

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const ECRECOVER_PRECOMPILE = "0x0000000000000000000000000000000000000001";

/** Every gas field zeroed — what the Safe UI builds for a contract interaction. */
const SAFE_TX_DEFAULTS = {
    value: "0",
    safeTxGas: "0",
    baseGas: "0",
    gasPrice: "0",
    gasToken: ZERO_ADDRESS,
    refundReceiver: ZERO_ADDRESS,
};

const MULTISEND_SIG = "multiSend(bytes)";

const SAFE_TX_HASH_SIG =
    "getTransactionHash(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,uint256)(bytes32)";

// ---- CLI ----

/**
 * The strategies to claim for, one `MERKL_STRATEGY_<ALIAS>=0x…` per MorphoVault proxy, with an
 * optional `MERKL_STRATEGY_<ALIAS>_LABEL` for the heading. Sorted by alias so a run is ordered the
 * same way however the variables reached us.
 */
function configuredStrategies() {
    return Object.keys(process.env)
        .filter((key) => new RegExp(`^${STRATEGY_ENV_PREFIX}[A-Z0-9]+$`).test(key))
        .sort()
        .map((key) => {
            const alias = key.slice(STRATEGY_ENV_PREFIX.length);
            const address = process.env[key].trim();
            if (!/^0x[0-9a-fA-F]{40}$/.test(address))
                throw new Error(`$${key} is not an address: "${address}"`);
            return {
                alias: alias.toLowerCase(),
                label: process.env[`${key}_LABEL`] || alias,
                address,
            };
        });
}

const NO_STRATEGIES =
    "no strategies configured: copy tools/merkl-claim.env.example to tools/merkl-claim.env, set" +
    ` ${STRATEGY_ENV_PREFIX}<ALIAS>=0x… for each one, and run through \`npm run claim\` so it is sourced`;

function parseArgs(argv) {
    const options = {
        targets: [],
        chainId: 1,
        rpc: process.env.MERKL_CLAIM_RPC_URL ?? process.env.ETH_RPC_URL ?? "",
        from: process.env.MERKL_CLAIM_SAFE ?? "",
        minUsd: 0,
        preflight: true,
        safeBatch: "",
        json: false,
        propose: false,
        safe: process.env.MERKL_CLAIM_SAFE ?? "",
        account: process.env.SAFE_PROPOSER_ACCOUNT ?? "",
        ledger: false,
        force: false,
        dryRun: false,
        batch: true,
    };

    for (let i = 0; i < argv.length; ++i) {
        const arg = argv[i];
        const next = () => {
            const value = argv[++i];
            if (value === undefined) throw new Error(`${arg} needs a value`);
            return value;
        };

        switch (arg) {
            case "--chain-id":
                options.chainId = Number(next());
                break;
            case "--rpc":
                options.rpc = next();
                break;
            case "--from":
                options.from = next();
                break;
            case "--min-usd":
                options.minUsd = Number(next());
                break;
            case "--no-preflight":
                options.preflight = false;
                break;
            case "--safe-batch":
                options.safeBatch = next();
                break;
            case "--propose":
                options.propose = true;
                break;
            case "--safe":
                options.safe = next();
                break;
            case "--account":
                options.account = next();
                break;
            case "--ledger":
                options.ledger = true;
                break;
            case "--force":
                options.force = true;
                break;
            case "--dry-run":
                options.dryRun = true;
                break;
            case "--no-batch":
                options.batch = false;
                break;
            case "--json":
                options.json = true;
                break;
            case "-h":
            case "--help":
                options.help = true;
                break;
            default:
                if (arg.startsWith("-")) throw new Error(`unknown option ${arg}`);
                options.targets.push(arg);
        }
    }

    return options;
}

function resolveStrategies(targets, configured) {
    if (targets.length === 0 || targets.includes("all")) {
        if (configured.length === 0) throw new Error(NO_STRATEGIES);
        return configured;
    }

    return targets.map((target) => {
        const known = configured.find(
            (strategy) =>
                strategy.alias === target.toLowerCase() || sameAddress(strategy.address, target),
        );
        if (known) return known;
        if (/^0x[0-9a-fA-F]{40}$/.test(target))
            return {alias: target, label: `strategy ${short(target)}`, address: target};
        throw new Error(
            `unknown strategy "${target}" (configured: ${configured.map((s) => s.alias).join(", ") || "none"}; or pass a 0x address)`,
        );
    });
}

// ---- helpers ----

const cast = (...args) => {
    try {
        return execFileSync("cast", args, {encoding: "utf8"}).trim();
    } catch (error) {
        const stderr = (error.stderr ?? "").toString().trim();
        throw new Error(`cast ${args[0]} failed: ${stderr || error.message}`);
    }
};

/** Same, but with stdin/stderr on the terminal so a keystore password or Ledger prompt gets through. */
const castInteractive = (...args) => {
    try {
        return execFileSync("cast", args, {
            encoding: "utf8",
            stdio: ["inherit", "pipe", "inherit"],
        }).trim();
    } catch (error) {
        throw new Error(`cast ${args[0]} ${args[1]} failed: ${error.message.split("\n")[0]}`);
    }
};

const short = (address) => `${address.slice(0, 6)}…${address.slice(-4)}`;

const sameAddress = (a, b) => a.toLowerCase() === b.toLowerCase();

function formatUnits(value, decimals) {
    const negative = value < 0n;
    const digits = (negative ? -value : value).toString().padStart(decimals + 1, "0");
    const whole = digits.slice(0, digits.length - decimals);
    const fraction = decimals === 0 ? "" : `.${digits.slice(-decimals).replace(/0+$/, "") || "0"}`;
    return `${negative ? "-" : ""}${whole}${fraction}`;
}

const usdValue = (amount, decimals, price) =>
    price ? Number(formatUnits(amount, decimals)) * price : 0;

// ---- Merkl API ----

async function fetchRewards(address, chainId) {
    const url = `${MERKL_API}/users/${address}/rewards?chainId=${chainId}`;
    const response = await fetch(url, {headers: {accept: "application/json"}});
    if (!response.ok)
        throw new Error(
            `Merkl API returned ${response.status} ${response.statusText} for ${address}`,
        );

    const body = await response.json();
    const group = body.find((entry) => Number(entry.chain?.id) === chainId);
    return group?.rewards ?? [];
}

/**
 * One claim per reward token: `manualClaim` builds a single-element `users` array, and the Angle
 * distributor requires `users.length == tokens.length`, so a two-token call would revert.
 */
function toClaims(rewards, minUsd) {
    const claims = [];

    for (const reward of rewards) {
        const cumulative = BigInt(reward.amount);
        const claimed = BigInt(reward.claimed);
        const claimable = cumulative - claimed;
        if (claimable <= 0n) continue;

        const {address: token, symbol, decimals, price} = reward.token;
        const usd = usdValue(claimable, decimals, price);
        if (minUsd > 0 && usd < minUsd) continue;

        claims.push({
            token,
            symbol,
            decimals,
            cumulative,
            claimed,
            claimable,
            pending: BigInt(reward.pending ?? "0"),
            usd,
            root: reward.root,
            proofs: reward.proofs,
        });
    }

    return claims;
}

function encodeManualClaim(claim) {
    return cast(
        "calldata",
        MANUAL_CLAIM_SIG,
        `[${claim.token}]`,
        `[${claim.cumulative}]`,
        `[[${claim.proofs.join(",")}]]`,
    );
}

// ---- on-chain pre-flight ----

/** Selectors of the errors a manualClaim simulation realistically hits, so the output stays readable. */
const KNOWN_ERRORS = {
    "0xe2517d3f": "AccessControlUnauthorizedAccount — the caller has no MERKLE_CLAIMER_ROLE",
    "0x1df89e8b": "InvalidLengths — the distributor got mismatched array lengths",
    "0x09bde339": "InvalidProof — the proof does not match the root the distributor serves",
    "0xe0b42056": "NavResolutionModeActivated — the strategy is resolving NAV",
};

function revertReason(error) {
    const selector = error.message.match(/data: "(0x[0-9a-f]{8})/)?.[1];
    const decoded = selector && KNOWN_ERRORS[selector];
    if (decoded) return `reverted: ${decoded}`;
    return `reverted${selector ? ` with ${selector}` : ""}: ${error.message.split("\n")[0].slice(0, 200)}`;
}

function preflight(strategy, claim, calldata, options) {
    const checks = [];
    const rpc = ["--rpc-url", options.rpc];
    const call = (target, sig, ...args) => cast("call", target, sig, ...args, ...rpc);

    const distributor = call(strategy.address, "merkleDistributor()(address)");

    // The proof only verifies against the root the distributor currently serves; the API can be ahead of it.
    const onChainRoot = call(distributor, "getMerkleRoot()(bytes32)");
    checks.push({
        name: "merkle root",
        ok: onChainRoot.toLowerCase() === claim.root.toLowerCase(),
        detail:
            onChainRoot.toLowerCase() === claim.root.toLowerCase()
                ? `${short(onChainRoot)} live`
                : `API root ${short(claim.root)} is not live yet (distributor serves ${short(onChainRoot)})`,
    });

    // Guards against a stale API response: the distributor's own counter is the source of truth.
    const onChainClaimed = BigInt(
        call(
            distributor,
            "claimed(address,address)(uint208,uint48,bytes32)",
            strategy.address,
            claim.token,
        )
            .split("\n")[0]
            .split(" ")[0],
    );
    checks.push({
        name: "claimed so far",
        ok: onChainClaimed < claim.cumulative,
        detail:
            onChainClaimed === claim.claimed
                ? `${formatUnits(onChainClaimed, claim.decimals)} ${claim.symbol}, matches API`
                : `on-chain ${formatUnits(onChainClaimed, claim.decimals)} vs API ${formatUnits(claim.claimed, claim.decimals)} ${claim.symbol}`,
    });

    // `manualClaim` reverts while the container is resolving NAV.
    const navResolution = call(strategy.address, "isNavResolutionMode()(bool)");
    checks.push({
        name: "nav resolution mode",
        ok: navResolution === "false",
        detail: navResolution,
    });

    if (options.from) {
        const role = cast("keccak", MERKLE_CLAIMER_ROLE);
        const hasRole = call(
            strategy.address,
            "hasRole(bytes32,address)(bool)",
            role,
            options.from,
        );
        checks.push({
            name: "caller role",
            ok: hasRole === "true",
            detail:
                hasRole === "true"
                    ? `${short(options.from)} holds MERKLE_CLAIMER_ROLE`
                    : `${short(options.from)} does NOT hold MERKLE_CLAIMER_ROLE`,
        });

        try {
            cast("call", strategy.address, calldata, "--from", options.from, ...rpc);
            checks.push({
                name: "simulation",
                ok: true,
                detail: `eth_call from ${short(options.from)} succeeds`,
            });
        } catch (error) {
            checks.push({name: "simulation", ok: false, detail: revertReason(error)});
        }
    } else {
        checks.push({
            name: "simulation",
            ok: true,
            skipped: true,
            detail: "skipped (no --from / $MERKL_CLAIM_SAFE)",
        });
    }

    return checks;
}

// ---- Safe transaction service ----

function safeApiUrl(chainId, path) {
    const shortName = SAFE_CHAIN_SHORTNAME[chainId];
    if (!shortName) throw new Error(`no Safe transaction service short name for chain ${chainId}`);
    return `${SAFE_TX_SERVICE}/${shortName}/api/${path}`;
}

/** Unauthenticated access is capped at 2 RPS / 5k requests a month; $SAFE_API_KEY lifts that. */
async function safeApi(chainId, path, init = {}) {
    const headers = {accept: "application/json", ...(init.headers ?? {})};
    if (process.env.SAFE_API_KEY) headers.authorization = `Bearer ${process.env.SAFE_API_KEY}`;

    const response = await fetch(safeApiUrl(chainId, path), {...init, headers});
    const body = await response.text();
    if (!response.ok)
        throw new Error(
            `Safe API ${response.status} ${response.statusText}: ${body.slice(0, 400)}`,
        );
    return body ? JSON.parse(body) : null;
}

/** Fail with the available names rather than cast's error when the account is a typo. */
function assertKeystoreExists(account) {
    const accounts = cast("wallet", "list")
        .split("\n")
        .map((line) => line.split(" ")[0].trim())
        .filter(Boolean);
    if (!accounts.includes(account))
        throw new Error(
            `no keystore named "${account}" — \`cast wallet list\` has: ${accounts.join(", ") || "(none)"}`,
        );
}

/**
 * `cast` flags selecting the proposing key. A keystore account is the intended path: the key stays
 * encrypted at rest and never passes through this process. `$SAFE_PROPOSER_PRIVATE_KEY` is the
 * last resort — it ends up in the argv of the `cast` child, which any process under the same uid
 * can read.
 */
function signerFlags(options) {
    if (options.ledger) return ["--ledger"];

    if (options.account) {
        assertKeystoreExists(options.account);
        const flags = ["--account", options.account];
        // Keystore signing prompts for the password; a file is how you keep it unattended.
        if (process.env.SAFE_PROPOSER_PASSWORD_FILE)
            flags.push("--password-file", process.env.SAFE_PROPOSER_PASSWORD_FILE);
        return flags;
    }

    if (process.env.SAFE_PROPOSER_PRIVATE_KEY)
        return ["--private-key", process.env.SAFE_PROPOSER_PRIVATE_KEY];

    throw new Error(
        "no proposal signer: pass --account <name> (see `cast wallet list`), set $SAFE_PROPOSER_ACCOUNT, or use --ledger",
    );
}

/**
 * The nonce the Safe UI would suggest: one past the highest nonce it already knows about, or the
 * on-chain nonce when nothing is queued. Reusing a queued nonce would make the two transactions
 * mutually exclusive alternatives instead of a queue.
 */
async function nextSafeNonce(options) {
    const onChain = BigInt(
        cast("call", options.safe, "nonce()(uint256)", "--rpc-url", options.rpc),
    );
    const {results} = await safeApi(
        options.chainId,
        `v1/safes/${options.safe}/multisig-transactions/?nonce__gte=${onChain}&ordering=-nonce&limit=1`,
    );
    return results.length > 0 ? BigInt(results[0].nonce) + 1n : onChain;
}

/**
 * The transaction service only accepts proposals from an owner or from a delegate registered by
 * one, so check before asking anyone to unlock a key.
 */
async function proposerCapacity(proposer, options) {
    const owners = cast("call", options.safe, "getOwners()(address[])", "--rpc-url", options.rpc)
        .replace(/[[\]\s]/g, "")
        .split(",");
    if (owners.some((owner) => sameAddress(owner, proposer))) return "owner";

    const {results} = await safeApi(options.chainId, `v2/delegates/?safe=${options.safe}`);
    const delegate = results.find((entry) => sameAddress(entry.delegate, proposer));
    if (delegate) return `delegate "${delegate.label}"`;

    const problem = `${proposer} is neither an owner of ${options.safe} nor one of its delegates — the transaction service would reject the proposal`;
    // A dry run still shows the payload; it just says up front that it would bounce.
    if (options.dryRun) return `NOT AUTHORIZED: ${problem}`;
    throw new Error(problem);
}

const buildSafeTx = (to, data, nonce, operation) => ({
    ...SAFE_TX_DEFAULTS,
    to,
    data,
    operation,
    nonce: nonce.toString(),
});

/** The Safe singleton that batches calls. Version specific, so it comes from the config like the rest. */
function multiSendAddress() {
    const address = process.env.MERKL_CLAIM_MULTISEND ?? "";
    if (!/^0x[0-9a-fA-F]{40}$/.test(address))
        throw new Error(
            `batching needs $MERKL_CLAIM_MULTISEND set to the MultiSendCallOnly singleton for your Safe's version (got "${address}") — or pass --no-batch`,
        );
    return address;
}

const hexPad = (value, bytes) =>
    BigInt(value)
        .toString(16)
        .padStart(bytes * 2, "0");

/**
 * `MultiSendCallOnly.multiSend` takes its transactions tightly packed rather than ABI encoded:
 * operation (uint8, 0 = CALL) ++ to (address) ++ value (uint256) ++ data length (uint256) ++ data.
 * It is reached by delegatecall, so each inner call still comes from the Safe itself and the
 * strategy sees `msg.sender` holding `MERKLE_CLAIMER_ROLE` exactly as in a direct call.
 */
function encodeMultiSend(transactions) {
    const packed = transactions
        .map(({to, data}) => {
            const body = data.replace(/^0x/, "");
            return (
                "00" +
                to.replace(/^0x/, "").toLowerCase() +
                hexPad(0, 32) +
                hexPad(body.length / 2, 32) +
                body
            );
        })
        .join("");

    return cast("calldata", MULTISEND_SIG, `0x${packed}`);
}

/** Ask the Safe itself for the digest rather than rebuilding its EIP-712 payload here. */
const safeTxHash = (tx, options) =>
    cast(
        "call",
        options.safe,
        SAFE_TX_HASH_SIG,
        tx.to,
        tx.value,
        tx.data,
        String(tx.operation),
        tx.safeTxGas,
        tx.baseGas,
        tx.gasPrice,
        tx.gasToken,
        tx.refundReceiver,
        tx.nonce,
        "--rpc-url",
        options.rpc,
    );

/**
 * Recover the signer from the digest we are about to submit, through the ecrecover precompile, so a
 * signature over the wrong hash fails here instead of being filed under someone else's name.
 */
function recoverSigner(hash, signature, options) {
    const encoded = cast(
        "abi-encode",
        "f(bytes32,uint256,bytes32,bytes32)",
        hash,
        BigInt(`0x${signature.slice(130, 132)}`).toString(),
        `0x${signature.slice(2, 66)}`,
        `0x${signature.slice(66, 130)}`,
    );
    const recovered = cast("call", ECRECOVER_PRECOMPILE, encoded, "--rpc-url", options.rpc);
    return `0x${recovered.slice(-40)}`;
}

async function proposeSafeTx({to, data, operation}, nonce, options) {
    const flags = signerFlags(options);
    const proposer = castInteractive("wallet", "address", ...flags);
    const capacity = await proposerCapacity(proposer, options);

    const tx = buildSafeTx(to, data, nonce, operation);
    const hash = safeTxHash(tx, options);
    // `--no-hash` signs the digest as it stands: Safe checks v=27/28 signatures against the EIP-712
    // hash itself, with no EIP-191 prefix in between.
    const signature = castInteractive("wallet", "sign", "--no-hash", hash, ...flags);

    const recovered = recoverSigner(hash, signature, options);
    if (!sameAddress(recovered, proposer))
        throw new Error(`signature recovers to ${recovered}, expected ${proposer}`);

    const payload = {
        ...tx,
        contractTransactionHash: hash,
        sender: proposer,
        signature,
        origin: JSON.stringify({name: "merkl-claim.mjs"}),
    };

    if (!options.dryRun)
        await safeApi(options.chainId, `v1/safes/${options.safe}/multisig-transactions/`, {
            method: "POST",
            headers: {"content-type": "application/json"},
            body: JSON.stringify(payload),
        });

    return {nonce, hash, proposer, capacity, payload};
}

const blockingChecks = (checks) => checks.filter((check) => !check.ok && !check.skipped);

function describeProposal(proposal, options, indent = "  ") {
    return [
        `${indent}${options.dryRun ? "would propose" : "proposed"} to ${short(options.safe)} as nonce ${proposal.nonce}`,
        `${indent}  signed by ${short(proposal.proposer)} (${proposal.capacity})`,
        `${indent}  safeTxHash ${proposal.hash}`,
        ...(options.dryRun
            ? [
                  `${indent}  POST ${safeApiUrl(options.chainId, `v1/safes/${options.safe}/multisig-transactions/`)}`,
                  JSON.stringify(proposal.payload, null, 2)
                      .split("\n")
                      .map((line) => `${indent}  ${line}`)
                      .join("\n"),
              ]
            : []),
        "",
    ].join("\n");
}

const recordProposal = (entry, proposal, options, batched) => {
    entry.proposal = {
        safe: options.safe,
        nonce: proposal.nonce.toString(),
        safeTxHash: proposal.hash,
        proposer: proposal.proposer,
        batched,
    };
};

/**
 * Everything the Safe should claim, as one transaction through `MultiSendCallOnly`. Claiming part of
 * what is owed is not a useful outcome — if one strategy cannot claim, that is the thing to look
 * into, not a reason to push the others through — so a batch with any failing pre-flight is refused
 * whole rather than trimmed down.
 */
async function proposeBatch(pending, options) {
    const blocked = pending.filter(({checks}) => blockingChecks(checks).length > 0);
    if (blocked.length > 0 && !options.force) {
        if (!options.json)
            console.log(
                [
                    "batch not proposed — pre-flight failed, so nothing was queued:",
                    ...blocked.map(
                        ({strategy, claim, checks}) =>
                            `  ${claim.symbol} on ${strategy.label}: ${blockingChecks(checks)
                                .map((check) => check.name)
                                .join(", ")}`,
                    ),
                    "look into that before claiming the rest. --force queues it anyway;",
                    "--no-batch proposes each claim on its own so the healthy ones can go through.",
                    "",
                ].join("\n"),
            );
        return;
    }

    const multiSend = multiSendAddress();
    const data = encodeMultiSend(
        pending.map(({strategy, calldata}) => ({to: strategy.address, data: calldata})),
    );
    const nonce = await nextSafeNonce(options);
    const proposal = await proposeSafeTx({to: multiSend, data, operation: 1}, nonce, options);

    for (const {entry} of pending) recordProposal(entry, proposal, options, true);

    if (!options.json)
        console.log(
            [
                `${pending.length} claim${pending.length === 1 ? "" : "s"} batched into one transaction via MultiSendCallOnly ${short(multiSend)}:`,
                ...pending.map(
                    ({strategy, claim}) =>
                        `  ${claim.symbol}  ${strategy.label}  ${short(strategy.address)}`,
                ),
                "",
                describeProposal(proposal, options),
            ].join("\n"),
        );
}

/** One proposal per claim, on consecutive nonces. Here a failing claim is skipped, not fatal. */
async function proposeSeparately(pending, options) {
    let nonce = await nextSafeNonce(options);

    for (const {strategy, claim, calldata, checks, entry} of pending) {
        const blocking = blockingChecks(checks);
        if (blocking.length > 0 && !options.force) {
            if (!options.json)
                console.log(
                    `${claim.symbol} on ${strategy.label}: not proposed, ${blocking.map((check) => check.name).join(", ")} failed (--force to propose anyway)\n`,
                );
            continue;
        }

        const proposal = await proposeSafeTx(
            {to: strategy.address, data: calldata, operation: 0},
            nonce++,
            options,
        );
        recordProposal(entry, proposal, options, false);

        if (!options.json)
            console.log(
                `${claim.symbol} on ${strategy.label}:\n${describeProposal(proposal, options)}`,
            );
    }
}

// ---- output ----

function printClaim(strategy, claim, calldata, checks) {
    const pending =
        claim.pending > 0n ? `, ${formatUnits(claim.pending, claim.decimals)} still pending` : "";
    console.log(
        `  ${claim.symbol}: claim ${formatUnits(claim.claimable, claim.decimals)}${claim.usd ? ` (~$${claim.usd.toFixed(2)})` : ""}${pending}`,
    );
    console.log(
        `    cumulative amount ${formatUnits(claim.cumulative, claim.decimals)} (what goes in the calldata), already claimed ${formatUnits(claim.claimed, claim.decimals)}`,
    );

    for (const check of checks) {
        console.log(
            `    ${check.skipped ? "-" : check.ok ? "✓" : "✗"} ${check.name}: ${check.detail}`,
        );
    }

    console.log("");
    console.log(`    To:    ${strategy.address}`);
    console.log(`    Value: 0`);
    console.log(`    Data:  ${calldata}`);
    console.log("");
}

function writeSafeBatch(path, chainId, transactions) {
    const batch = {
        version: "1.0",
        chainId: String(chainId),
        createdAt: Date.now(),
        meta: {
            name: "MorphoVault manualClaim",
            description: "Merkl reward claims generated by tools/merkl-claim.mjs",
            txBuilderVersion: "1.16.5",
        },
        transactions: transactions.map((tx) => ({to: tx.to, value: "0", data: tx.data})),
    };

    writeFileSync(path, `${JSON.stringify(batch, null, 2)}\n`);
    console.log(
        `Safe Transaction Builder batch written to ${path} (import it under Transaction Builder -> drag & drop).`,
    );
}

// ---- main ----

async function main() {
    const options = parseArgs(process.argv.slice(2));
    const configured = configuredStrategies();

    if (options.help) {
        console.log(
            [
                "Usage: npm run claim -- [strategy...] [options]",
                "       node tools/merkl-claim.mjs [strategy...] [options]   (env must be sourced)",
                "",
                `  strategy        ${configured.map((s) => s.alias).join(" | ") || "<none configured>"} | all | 0xaddress   (default: all)`,
                "  --chain-id <n>  chain to query on Merkl (default 1)",
                "  --rpc <url>     RPC for the pre-flight checks (default $MERKL_CLAIM_RPC_URL)",
                "  --from <addr>   caller to simulate from (default $MERKL_CLAIM_SAFE)",
                "  --min-usd <n>   skip rewards worth less than this",
                "  --no-preflight  skip every on-chain check, emit calldata only",
                "  --safe-batch <file>  also write a Safe Transaction Builder batch",
                "  --json          machine-readable output",
                "",
                " proposing straight into the Safe (needs --rpc):",
                "  --propose       sign the claims and queue them in the Safe for the owners to confirm",
                "  --no-batch      one transaction per claim instead of a single MultiSend batch",
                "  --safe <addr>   the Safe holding MERKLE_CLAIMER_ROLE (default $MERKL_CLAIM_SAFE)",
                "  --account <n>   cast keystore account to sign with, default $SAFE_PROPOSER_ACCOUNT",
                "  --ledger        sign the proposal on a Ledger instead",
                "  --force         propose even if a pre-flight check failed",
                "  --dry-run       build and sign the proposal, print it, but do not submit it",
                "",
                "",
                " every address, the RPC and the signer come from tools/merkl-claim.env, which",
                " `npm run claim` sources (see tools/merkl-claim.env.example).",
                " claims are batched into one all-or-nothing transaction: if any pre-flight fails,",
                " nothing is queued, since a partial claim just hides the problem.",
                " the proposing key only needs to be a delegate of the Safe, not an owner.",
                " $SAFE_PROPOSER_PASSWORD_FILE unlocks the keystore unattended (CI); otherwise it prompts.",
                " $SAFE_API_KEY (developer.safe.global) lifts the transaction service rate limit.",
            ].join("\n"),
        );
        return;
    }

    const strategies = resolveStrategies(options.targets, configured);
    const runPreflight = options.preflight && options.rpc !== "";
    if (options.preflight && !runPreflight && !options.json) {
        console.log("No RPC URL (--rpc or $MERKL_CLAIM_RPC_URL): skipping on-chain checks.\n");
    }

    if (options.propose) {
        if (options.rpc === "")
            throw new Error("--propose needs an RPC URL (--rpc or $MERKL_CLAIM_RPC_URL)");
        if (options.safe === "")
            throw new Error("--propose needs the Safe address (--safe or $MERKL_CLAIM_SAFE)");
    }

    const transactions = [];
    const report = [];
    const pending = [];

    for (const strategy of strategies) {
        const rewards = await fetchRewards(strategy.address, options.chainId);
        const claims = toClaims(rewards, options.minUsd);

        if (!options.json) console.log(`${strategy.label}  ${strategy.address}`);

        if (claims.length === 0) {
            if (!options.json) console.log("  nothing to claim\n");
            continue;
        }

        for (const claim of claims) {
            const calldata = encodeManualClaim(claim);
            const checks = runPreflight ? preflight(strategy, claim, calldata, options) : [];

            transactions.push({to: strategy.address, data: calldata});

            const entry = {
                strategy: strategy.address,
                label: strategy.label,
                token: claim.token,
                symbol: claim.symbol,
                cumulativeAmount: claim.cumulative.toString(),
                claimableAmount: claim.claimable.toString(),
                root: claim.root,
                to: strategy.address,
                value: "0",
                data: calldata,
                checks: checks.map(({name, ok, detail, skipped}) => ({
                    name,
                    ok,
                    detail,
                    skipped: Boolean(skipped),
                })),
            };
            report.push(entry);
            pending.push({strategy, claim, calldata, checks, entry});

            if (!options.json) printClaim(strategy, claim, calldata, checks);
        }
    }

    if (options.propose && pending.length > 0) {
        if (options.batch) await proposeBatch(pending, options);
        else await proposeSeparately(pending, options);
    }

    if (options.json) {
        console.log(JSON.stringify(report, null, 2));
    } else if (transactions.length === 0) {
        console.log("Nothing claimable right now.");
    }

    if (options.safeBatch && transactions.length > 0)
        writeSafeBatch(options.safeBatch, options.chainId, transactions);

    const failed = report.some((entry) =>
        entry.checks.some((check) => !check.ok && !check.skipped),
    );
    if (failed) process.exitCode = 1;
}

main().catch((error) => {
    console.error(`error: ${error.message}`);
    process.exitCode = 1;
});
