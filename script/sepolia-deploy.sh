#!/bin/sh
# Live Sepolia deploy: VetoManager + OptimisticExecutor wired to UMA OOV3.
# Usage: set env first (see .env.example), then: sh script/sepolia-deploy.sh
# Needs: Sepolia ETH on deployer (~0.02), existing Safe address.
set -e
cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a

: "${SEPOLIA_RPC:?set SEPOLIA_RPC}"
: "${DEPLOY_PK:?set DEPLOY_PK (64 hex, no 0x)}"
: "${SAFE:?set SAFE (0x Safe on Sepolia)}"

OOV3=0xFd9e2642a170aDD10F53Ee14a93FcF2F31924944
USDC=0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
LIVENESS=7200
BOND=400000000
ID=$(cast --format-bytes32-string "ASSERT_TRUTH2" 2>/dev/null)

echo "== preflight (live)"
cast call $OOV3 "getMinimumBond(address)(uint256)" $USDC --rpc-url "$SEPOLIA_RPC" 2>/dev/null

echo "== deploy VetoManager"
VETO=$(forge create src/VetoManager.sol:VetoManager \
  --rpc-url "$SEPOLIA_RPC" --private-key "$DEPLOY_PK" --broadcast --json 2>/dev/null | jq -r .deployedTo)
echo "VETO=$VETO"

echo "== deploy OptimisticExecutor"
EX=$(forge create src/OptimisticExecutor.sol:OptimisticExecutor \
  --rpc-url "$SEPOLIA_RPC" --private-key "$DEPLOY_PK" --broadcast --json \
  --constructor-args "$SAFE" $OOV3 $USDC $LIVENESS $BOND "$ID" "$VETO" 2>/dev/null | jq -r .deployedTo)
echo "EX=$EX"

echo "== next: enable module from a Safe owner:"
echo "Safe.enableModule($EX)"
echo "cast send \$SAFE \"enableModule(address)\" $EX --rpc-url \$SEPOLIA_RPC --private-key <SAFE_OWNER_PK>"
echo
echo "LIVE_VETO=$VETO"
echo "LIVE_EX=$EX"
