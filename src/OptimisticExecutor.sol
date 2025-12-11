// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IERC20Min {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IOOV3Min {
    function assertTruth(
        bytes memory claim,
        address asserter,
        address callbackRecipient,
        address escalationManager,
        uint64 liveness,
        IERC20Min currency,
        uint256 bond,
        bytes32 identifier,
        bytes32 domainId
    ) external returns (bytes32);
    function settleAssertion(bytes32 assertionId) external;
    function getMinimumBond(address currency) external view returns (uint256);
}

interface ISafeMin {
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation
    ) external returns (bool);
}

interface IVetoManager {
    function isVetoed(bytes32 proposalId) external view returns (bool);
}

/// @notice Minimal optimistic Safe executor (oSnap-lite).
/// @dev Uses OOV3 `assertTruth` with explicit identifier, never `assertTruthWithDefaults`
///      (ASSERT_TRUTH deprecated Dec 2025, WithDefaults reverts).
contract OptimisticExecutor {
    address public owner;
    ISafeMin public safe;
    IOOV3Min public oo;
    IERC20Min public currency;
    uint64 public liveness;
    uint256 public bond;
    bytes32 public identifier;
    address public vetoManager;
    bool public paused;
    uint256 public nonce;

    struct Proposal {
        address to;
        uint256 value;
        bytes data;
        uint8 operation;
        address proposer;
        bytes32 assertionId;
        uint64 expiration;
        bool settled;
        bool truthful;
        bool disputed;
        bool executed;
    }

    mapping(bytes32 => Proposal) public proposals;
    mapping(bytes32 => bytes32) public assertionToProposal;

    event Proposed(bytes32 indexed proposalId, bytes32 indexed assertionId, address indexed proposer);
    event Settled(bytes32 indexed proposalId, bool truthful);
    event Disputed(bytes32 indexed proposalId);
    event Executed(bytes32 indexed proposalId);
    event Paused(bool paused);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(
        address _safe,
        address _oo,
        address _currency,
        uint64 _liveness,
        uint256 _bond,
        bytes32 _identifier,
        address _vetoManager
    ) {
        owner = msg.sender;
        safe = ISafeMin(_safe);
        oo = IOOV3Min(_oo);
        currency = IERC20Min(_currency);
        liveness = _liveness;
        bond = _bond;
        identifier = _identifier;
        vetoManager = _vetoManager;
    }

    function propose(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        string calldata explanation
    ) external returns (bytes32 proposalId, bytes32 assertionId) {
        require(!paused, "paused");
        require(to != address(0), "bad to");
        require(operation <= 1, "bad op");

        uint256 minBond = oo.getMinimumBond(address(currency));
        uint256 useBond = bond > minBond ? bond : minBond;

        bytes memory claim = abi.encodePacked(
            "Safe tx to 0x",
            _toHex(to),
            " value ",
            _toStr(value),
            " dataHash ",
            _toHex(keccak256(data)),
            " chain ",
            _toStr(block.chainid),
            " vote ",
            explanation
        );

        require(currency.transferFrom(msg.sender, address(this), useBond), "bond pull failed");
        require(currency.approve(address(oo), useBond), "approve failed");

        assertionId = oo.assertTruth(
            claim, msg.sender, address(this), address(0), liveness, currency, useBond, identifier, bytes32(0)
        );

        proposalId = keccak256(abi.encode(to, value, keccak256(data), operation, explanation, nonce++));
        require(proposals[proposalId].proposer == address(0), "exists");

        proposals[proposalId] = Proposal({
            to: to,
            value: value,
            data: data,
            operation: operation,
            proposer: msg.sender,
            assertionId: assertionId,
            expiration: uint64(block.timestamp) + liveness,
            settled: false,
            truthful: false,
            disputed: false,
            executed: false
        });
        assertionToProposal[assertionId] = proposalId;

        emit Proposed(proposalId, assertionId, msg.sender);
    }

    // shortcut: local expiration instead of oo.getAssertion, avoids OOV3 struct drift across versions. Upgrade when UI needs dispute timestamps.
    function settle(bytes32 proposalId) external {
        Proposal storage p = proposals[proposalId];
        require(p.proposer != address(0), "no proposal");
        oo.settleAssertion(p.assertionId);
    }

    function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) external {
        require(msg.sender == address(oo), "not OO");
        bytes32 proposalId = assertionToProposal[assertionId];
        require(proposals[proposalId].proposer != address(0), "no proposal");
        proposals[proposalId].settled = true;
        proposals[proposalId].truthful = assertedTruthfully;
        emit Settled(proposalId, assertedTruthfully);
    }

    function assertionDisputedCallback(bytes32 assertionId) external {
        require(msg.sender == address(oo), "not OO");
        bytes32 proposalId = assertionToProposal[assertionId];
        require(proposals[proposalId].proposer != address(0), "no proposal");
        proposals[proposalId].disputed = true;
        emit Disputed(proposalId);
    }

    function canExecute(bytes32 proposalId) public view returns (bool) {
        Proposal storage p = proposals[proposalId];
        if (p.proposer == address(0) || p.executed || !p.settled || !p.truthful || p.disputed || paused) return false;
        return true;
    }

    function execute(bytes32 proposalId) external returns (bool) {
        require(canExecute(proposalId), "cannot execute");
        proposals[proposalId].executed = true;
        Proposal storage p = proposals[proposalId];
        require(safe.execTransactionFromModule(p.to, p.value, p.data, p.operation), "safe exec failed");
        emit Executed(proposalId);
        return true;
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit Paused(_paused);
    }

    function setVetoManager(address _vetoManager) external onlyOwner {
        vetoManager = _vetoManager;
    }

    function _toHex(address a) internal pure returns (string memory) {
        bytes32 v = bytes32(uint256(uint160(a)));
        bytes16 alphabet = "0123456789abcdef";
        bytes memory s = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            s[i * 2] = alphabet[uint8(v[i + 12]) >> 4];
            s[i * 2 + 1] = alphabet[uint8(v[i + 12]) & 0xf];
        }
        return string(s);
    }

    function _toHex(bytes32 v) internal pure returns (string memory) {
        bytes16 alphabet = "0123456789abcdef";
        bytes memory s = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            s[i * 2] = alphabet[uint8(v[i]) >> 4];
            s[i * 2 + 1] = alphabet[uint8(v[i]) & 0xf];
        }
        return string(s);
    }

    function _toStr(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 len;
        uint256 t = v;
        while (t > 0) {
            len++;
            t /= 10;
        }
        bytes memory s = new bytes(len);
        while (v > 0) {
            s[--len] = bytes1(uint8(48 + v % 10));
            v /= 10;
        }
        return string(s);
    }
}
