# Fork tests read RPC URLs from .env, which forge loads by itself, and pin
# their blocks, so repeated runs are served from forge's RPC cache.
forge_version := "1.8.3"

# Pass recipe args to the shell as "$@", so quoted args (e.g. `--mc "A|B"`) survive.
set positional-arguments

# List recipes
default:
    @just --list

# Install npm dependencies and use the versioned git hooks in .githooks
setup:
    npm install
    git config core.hooksPath .githooks
    @forge --version | grep -q "{{forge_version}}" || echo "warning: forge is not v{{forge_version}}; run 'foundryup -i v{{forge_version}}'"

# Compile contracts/ with size check, as deployed (no via-IR)
build *args:
    forge build contracts --sizes "$@"

# Compile everything with the via-IR `ir` profile, tests and scripts included
build-all *args:
    FOUNDRY_PROFILE=ir forge build "$@"

# Run every test; each fork test pins its own block. Extra args pass through, e.g. `just test --mt test_Harvest`
test *args:
    FOUNDRY_PROFILE=ir forge test "$@"

# Ethereum fork suite
test-eth *args:
    FOUNDRY_PROFILE=ir forge test -vvv --mp "test/ethereum/**" "$@"

# Base fork suite
test-base *args:
    FOUNDRY_PROFILE=ir forge test -vvv --mp "test/base/**" "$@"

# Monad fork suite
test-monad *args:
    FOUNDRY_PROFILE=ir forge test -vvv --mp "test/monad/**" "$@"

# Format sources
fmt:
    forge fmt

# Format check, contracts build, every test (what the pre-commit hook runs)
check:
    forge fmt --check
    {{just_executable()}} build
    {{just_executable()}} test

# Run slither over contracts/; extra args pass through, e.g. `just slither --exclude-low`
slither *args:
    slither . "$@"

# Run aderyn over contracts/; report in reports/aderyn.md
aderyn *args:
    aderyn . --skip-update-check --output reports/aderyn.md "$@"

# Run slither and aderyn before deployment
analyze:
    -{{just_executable()}} slither
    {{just_executable()}} aderyn

# Build Merkl claim calldata; see tools/README.md
claim *args:
    npm run claim -- "$@"

# Build Merkl claim calldata and queue it on the claimer Safe
claim-propose *args:
    npm run claim:propose -- "$@"
