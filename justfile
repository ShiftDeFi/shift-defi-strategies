# Fork tests read RPC URLs from .env, which forge loads by itself.
forge_version := "1.8.3"

# List recipes
default:
    @just --list

# Install npm dependencies and use the versioned git hooks in .githooks
setup:
    npm install
    git config core.hooksPath .githooks
    @forge --version | grep -q "{{forge_version}}" || echo "warning: forge is not v{{forge_version}}; run 'foundryup -i v{{forge_version}}'"

# Compile contracts/ with size check; tests and scripts need via-ir, see `build-all`
build *args:
    forge build contracts --sizes {{args}}

# Compile everything, tests and scripts included
build-all *args:
    forge build --via-ir {{args}}

# Run tests; extra args pass through, e.g. `just test --mt test_Harvest --fork-url ethereum`
test *args:
    forge test --via-ir {{args}}

# Ethereum fork suite, as CI runs it
test-eth *args:
    forge test -vvv --mp "test/ethereum/**" --fork-url ethereum --via-ir {{args}}

# Base fork suite
test-base *args:
    forge test -vvv --mp "test/base/**" --fork-url base --via-ir {{args}}

# Monad fork suite
test-monad *args:
    forge test -vvv --mp "test/monad/**" --fork-url monad --via-ir {{args}}

# Format sources
fmt:
    forge fmt

# Run the same checks as CI
check:
    forge fmt --check
    {{just_executable()}} build
    {{just_executable()}} test-eth

# Run slither over contracts/; extra args pass through, e.g. `just slither --exclude-low`
slither *args:
    slither . {{args}}

# Run aderyn over contracts/; report in reports/aderyn.md
aderyn *args:
    aderyn . --skip-update-check --output reports/aderyn.md {{args}}

# Run slither and aderyn before deployment
analyze:
    -{{just_executable()}} slither
    {{just_executable()}} aderyn

# Build Merkl claim calldata; see tools/README.md
claim *args:
    npm run claim -- {{args}}

# Build Merkl claim calldata and queue it on the claimer Safe
claim-propose *args:
    npm run claim:propose -- {{args}}
