#!/bin/sh
# Local end-to-end demo: anvil + mocks + executor (no external RPC, no Sepolia DVM).
# Usage: sh script/demo.sh
set -e
cd "$(dirname "$0")/.."

PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7b4d3ff3c
ME=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
RPC=http://127.0.0.1:8545
ID=$(cast --format-bytes32-string "ASSERT_TRUTH2")

anvil --silent > /tmp/osnap-anvil.log 2>&1 &
ANVIL_PID=$!
trap "kill $ANVIL_PID" EXIT INT TERM
sleep 2

echo "== deploy mocks + contracts"
CCY=$(forge create test/OptimisticExecutor.t.sol:MockERC20 --rpc-url $RPC --private-key $PK --broadcast --json | jq -r .deployedTo)
OO=$(forge create test/OptimisticExecutor.t.sol:MockOOV3 --rpc-url $RPC --private-key $PK --broadcast --json | jq -r .deployedTo)
SAFE=$(forge create test/OptimisticExecutor.t.sol:MockSafe --rpc-url $RPC --private-key $PK --broadcast --json | jq -r .deployedTo)
VETO=$(forge create src/VetoManager.sol:VetoManager --rpc-url $RPC --private-key $PK --broadcast --json | jq -r .deployedTo)
EX=$(forge create src/OptimisticExecutor.sol:OptimisticExecutor --rpc-url $RPC --private-key $PK --broadcast --json \
  --constructor-args $SAFE $OO $CCY 7200 1000000000000000 $ID $VETO | jq -r .deployedTo)
echo "CCY=$CCY OO=$OO SAFE=$SAFE VETO=$VETO EX=$EX"

echo "== fund + approve bond"
cast send $CCY "mint(address,uint256)" $ME 1000000000000000000 --rpc-url $RPC --private-key $PK --silent
cast send $CCY "approve(address,uint256)" $EX 1000000000000000000 --rpc-url $RPC --private-key $PK --silent

echo "== propose"
TX=$(cast send $EX "propose(address,uint256,bytes,uint8,string)" 0x00000000000000000000000000000000CafE 0 0x1234 0 "pay 0.001 eth test" \
  --rpc-url $RPC --private-key $PK --json | jq -r .transactionHash)
PID=$(cast receipt $TX --rpc-url $RPC --json | jq -r '.logs[0].topics[1]')
echo "proposal=$PID tx=$TX"

echo "== settle (mock OO resolves true)"
cast send $EX "settle(bytes32)" $PID --rpc-url $RPC --private-key $PK --silent
echo -n "canExecute: "; cast call $EX "canExecute(bytes32)(bool)" $PID --rpc-url $RPC

echo "== execute"
cast send $EX "execute(bytes32)" $PID --rpc-url $RPC --private-key $PK --silent
echo -n "safe call[0].to: "; cast call $SAFE "calls(uint256)(address,uint256,bytes,uint8)" 0 --rpc-url $RPC | head -1

echo "OK demo complete"
