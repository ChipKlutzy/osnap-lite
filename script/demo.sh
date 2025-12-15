#!/bin/sh
# Local end-to-end demo: anvil + mocks + executor (no external RPC, no Sepolia DVM).
# Uses anvil unlocked accounts, no keys needed.
# Usage: sh script/demo.sh
set -e
cd "$(dirname "$0")/.."

ME=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
RPC=http://127.0.0.1:8545
ID=$(cast --format-bytes32-string "ASSERT_TRUTH2")
BOND=1000000000000000

(pkill -f "anvil --silent" 2>/dev/null || true)
anvil --silent > /tmp/osnap-anvil.log 2>&1 &
ANVIL_PID=$!
trap "kill $ANVIL_PID" EXIT INT TERM
sleep 2

deploy() {
  # $1 = contract name, $2 = extra creation code suffix (encoded ctor args, no 0x) or empty
  CODE=$(forge inspect "$1" bytecode 2>/dev/null | tail -1)
  TX=$(cast send --unlocked --from $ME --rpc-url $RPC --create "${CODE}$2" --json 2>/dev/null | jq -r .transactionHash)
  cast receipt "$TX" --rpc-url $RPC --json 2>/dev/null | jq -r .contractAddress
}

echo "== deploy"
CCY=$(deploy MockERC20); echo "CCY=$CCY"
OO=$(deploy MockOOV3); echo "OO=$OO"
SAFE=$(deploy MockSafe); echo "SAFE=$SAFE"
VETO=$(deploy VetoManager); echo "VETO=$VETO"
ARGS=$(cast abi-encode "constructor(address,address,address,uint64,uint256,bytes32,address)" $SAFE $OO $CCY 7200 $BOND $ID $VETO | sed 's/^0x//')
EX=$(deploy OptimisticExecutor "$ARGS"); echo "EX=$EX"

echo "== fund + approve"
cast send --unlocked --from $ME $CCY "mint(address,uint256)" $ME 1000000000000000000 --rpc-url $RPC --silent > /dev/null
cast send --unlocked --from $ME $CCY "approve(address,uint256)" $EX 1000000000000000000 --rpc-url $RPC --silent > /dev/null

echo "== propose"
TX=$(cast send --unlocked --from $ME $EX "propose(address,uint256,bytes,uint8,string)" 0x000000000000000000000000000000000000CafE 0 0x1234 0 "pay test" --rpc-url $RPC --json | jq -r .transactionHash)
PID=$(cast receipt $TX --rpc-url $RPC --json | jq -r '.logs[0].topics[1]')
echo "proposal=$PID"

echo "== settle"
cast send --unlocked --from $ME $EX "settle(bytes32)" $PID --rpc-url $RPC --silent > /dev/null
echo -n "canExecute: "; cast call $EX "canExecute(bytes32)(bool)" $PID --rpc-url $RPC

echo "== execute"
cast send --unlocked --from $ME $EX "execute(bytes32)" $PID --rpc-url $RPC --silent > /dev/null
echo -n "safe.exec calls: "; cast call $SAFE "calls(uint256)(address,uint256,bytes,uint8)" 0 --rpc-url $RPC | head -1

echo "OK demo complete"
