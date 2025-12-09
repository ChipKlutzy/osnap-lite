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

}
