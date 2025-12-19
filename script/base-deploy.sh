#!/bin/sh
# Live Base Sepolia deploy: Safe (1/1) + VetoManager + OptimisticExecutor + enableModule.
# Auth: cast keystore account omnichain/escrow-deployer (password file).
# Usage: sh script/base-deploy.sh
set -e
cd "$(dirname "$0")/.."

RPC=https://sepolia.base.org
ACC=omnichain/escrow-deployer
PW=~/.foundry/keystores/.omnichain-pw
OWNER=0xde418B0E3815A9B88e20e83d49c7060c3dF2f21c
AUTH="--rpc-url $RPC --account $ACC --password-file $PW"

OOV3=0x0F7fC5E6482f096380db6158f978167b57388deE
CCY=0x7E6d9618Ba8a87421609352d6e711958A97e2512
LIVENESS=${LIVENESS:-7200}
BOND=0
ID=$(cast --format-bytes32-string "ASSERT_TRUTH" 2>/dev/null)
SALT=777001

echo "== 0. GnosisSafeProxyFactory (none on base-sepolia)"
FACTORY=${FACTORY:-$(forge create lib/safe-smart-account/contracts/proxies/GnosisSafeProxyFactory.sol:GnosisSafeProxyFactory \
  $AUTH --broadcast --json 2>/dev/null | jq -r .deployedTo)}
echo "FACTORY=$FACTORY"

echo "== 1. GnosisSafe mastercopy"
SINGLETON=${SINGLETON:-$(forge create lib/safe-smart-account/contracts/GnosisSafe.sol:GnosisSafe \
  $AUTH --broadcast --json 2>/dev/null | jq -r .deployedTo)}
echo "SINGLETON=$SINGLETON"

if [ -z "${SAFE:-}" ]; then
echo "== 2. Safe proxy (1/1 owner)"
INIT=$(cast calldata "setup(address[],uint256,address,bytes,address,address,uint256,address)" "[$OWNER]" 1 0x0000000000000000000000000000000000000000 0x 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 0 0x0000000000000000000000000000000000000000 2>/dev/null)
TX=$(cast send $FACTORY "createProxyWithNonce(address,bytes,uint256)" $SINGLETON $INIT $SALT \
  $AUTH --json 2>/dev/null | jq -r .transactionHash)
SAFE=$(cast receipt $TX --rpc-url $RPC --json 2>/dev/null | jq -r '.logs[] | select(.topics[0]=="0x4f51faf6c4561ff95f067657e43439f0f856d97c04d9ec9070a6199ad418e235") | ("0x"+(.data[26:66]))')
echo "SAFE=$SAFE tx=$TX"
[ -z "$SAFE" ] || [ "$SAFE" = "0x" ] && { echo "proxy parse failed"; exit 1; }
else
echo "== 2. reuse SAFE=$SAFE"
fi

echo "== 3. VetoManager + Executor"
VETO=${VETO:-$(forge create src/VetoManager.sol:VetoManager $AUTH --broadcast --json 2>/dev/null | jq -r .deployedTo)}
EX=$(forge create src/OptimisticExecutor.sol:OptimisticExecutor $AUTH --broadcast --json \
  --constructor-args "$SAFE" $OOV3 $CCY $LIVENESS $BOND "$ID" "$VETO" 2>/dev/null | jq -r .deployedTo)
echo "VETO=$VETO"
echo "EX=$EX"

echo "== 4. enableModule via owner execTransaction"
ONOXCLEAN=$(echo $OWNER | sed 's/0x//')
SIG="0x000000000000000000000000${ONOXCLEAN}000000000000000000000000000000000000000000000000000000000000000001"
DATA=$(cast calldata "enableModule(address)" $EX 2>/dev/null)
cast send $SAFE "execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes)" \
  $SAFE 0 $DATA 0 0 0 0 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 $SIG \
  $AUTH --silent > /dev/null
echo -n "isModuleEnabled: "
cast call $SAFE "isModuleEnabled(address)(bool)" $EX --rpc-url $RPC 2>/dev/null

echo
echo "LIVE_SAFE=$SAFE"
echo "LIVE_VETO=$VETO"
echo "LIVE_EX=$EX"
