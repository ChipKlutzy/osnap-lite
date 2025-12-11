// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../src/OptimisticExecutor.sol";

contract MockERC20 is IERC20Min {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "bal");
        uint256 a = allowance[from][msg.sender];
        if (a != type(uint256).max) {
            require(a >= amount, "allow");
            allowance[from][msg.sender] = a - amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockOOV3 is IOOV3Min {
    uint256 public minBond = 1e15;
    uint256 public n;
    mapping(bytes32 => address) public callback;

    function setMinBond(uint256 b) external {
        minBond = b;
    }

    function getMinimumBond(address) external view returns (uint256) {
        return minBond;
    }

    function assertTruth(
        bytes memory,
        address,
        address callbackRecipient,
        address,
        uint64,
        IERC20Min,
        uint256,
        bytes32,
        bytes32
    ) external returns (bytes32) {
        bytes32 id = keccak256(abi.encode(address(this), n++));
        callback[id] = callbackRecipient;
        return id;
    }

    function settleAssertion(bytes32 assertionId) external {
        address cb = callback[assertionId];
        require(cb != address(0), "no assertion");
        OptimisticExecutor(payable(cb)).assertionResolvedCallback(assertionId, true);
    }

}

contract MockSafe is ISafeMin {
    struct Call {
        address to;
        uint256 value;
        bytes data;
        uint8 op;
    }

    Call[] public calls;

    function execTransactionFromModule(address to, uint256 value, bytes calldata data, uint8 operation)
        external
        returns (bool)
    {
        calls.push(Call(to, value, data, operation));
        return true;
    }
}

contract OptimisticExecutorTest {
    MockERC20 ccy;
    MockOOV3 oo;
    MockSafe safe;
    OptimisticExecutor ex;

    address user = address(0xBEEF);

    function setUp() public {
        ccy = new MockERC20();
        oo = new MockOOV3();
        safe = new MockSafe();
        ex = new OptimisticExecutor(
            address(safe),
            address(oo),
            address(ccy),
            7200,
            1e15,
            bytes32("ASSERT_TRUTH2"),
            address(0)
        );
        ccy.mint(user, 1 ether);
    }

    function _approve() internal {
        // prank via direct calls: MockERC20 uses msg.sender, so mint to this and approve
        ccy.mint(address(this), 1 ether);
        ccy.approve(address(ex), type(uint256).max);
    }

    function testProposeSettleExecute() public {
        _approve();
        (bytes32 pid,) = ex.propose(address(0xCAFE), 0, hex"1234", 0, "vote yes");
        require(!ex.canExecute(pid), "early exec");
        ex.settle(pid);
        require(ex.canExecute(pid), "should exec");
        ex.execute(pid);
        (address to,,,) = safe.calls(0);
        require(to == address(0xCAFE), "wrong to");
    }

}
