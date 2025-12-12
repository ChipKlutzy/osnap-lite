// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Council veto gate checked by OptimisticExecutor before execute.
/// @dev No tokens, no voting. Owner + council flag veto inside liveness.
contract VetoManager {
    address public owner;
    mapping(address => bool) public council;
    mapping(bytes32 => bool) public vetoed;

    event CouncilSet(address indexed member, bool allowed);
    event Vetoed(bytes32 indexed proposalId, address indexed by);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setCouncil(address member, bool allowed) external onlyOwner {
        council[member] = allowed;
        emit CouncilSet(member, allowed);
    }

    function setVeto(bytes32 proposalId, bool _vetoed) external {
        require(msg.sender == owner || council[msg.sender], "not council");
        vetoed[proposalId] = _vetoed;
        if (_vetoed) emit Vetoed(proposalId, msg.sender);
    }

    function isVetoed(bytes32 proposalId) external view returns (bool) {
        return vetoed[proposalId];
    }
}
