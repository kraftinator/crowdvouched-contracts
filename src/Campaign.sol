// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

interface ISubmissionManager {
    function setAssignmentTimeout(uint32 assignmentTimeout) external;
    function assignmentTimeout() external view returns (uint32);
}

/// @title  Campaign
/// @notice Top-level contract for a single Crowdvouched campaign. Holds
///         campaign metadata and the addresses of the sub-contracts
///         (SubmissionManager, CampaignToken, CampaignTreasury, CampaignNFT).
///         Sub-contracts are wired in via the constructor to keep this
///         contract itself minimal — deployment orchestration happens in a
///         separate factory or Foundry script.
contract Campaign is Ownable {
    /// -----------------------------------------------------------------------
    /// Immutable metadata
    /// -----------------------------------------------------------------------

    string public name;
    string public description;
    uint256 public immutable createdAt;

    /// -----------------------------------------------------------------------
    /// Sub-contract addresses (set at construction)
    /// -----------------------------------------------------------------------

    address public immutable submissionManager;
    address public immutable token;
    address public immutable treasury;
    address public immutable nft;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error EmptyName();
    error ZeroAddress();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event NameUpdated(string newName);
    event AssignmentTimeoutUpdated(uint32 assignmentTimeout);
    event DescriptionUpdated(string newDescription);

    /// -----------------------------------------------------------------------
    /// Construction
    /// -----------------------------------------------------------------------

    constructor(
        address _owner,
        string memory _name,
        string memory _description,
        address _submissionManager,
        address _token,
        address _treasury,
        address _nft
    ) Ownable(_owner) {
        if (bytes(_name).length == 0) revert EmptyName();
        if (
            _submissionManager == address(0) ||
            _token == address(0) ||
            _treasury == address(0) ||
            _nft == address(0)
        ) revert ZeroAddress();

        name = _name;
        description = _description;
        submissionManager = _submissionManager;
        token = _token;
        treasury = _treasury;
        nft = _nft;
        createdAt = block.timestamp;
    }

    /// -----------------------------------------------------------------------
    /// Owner-only setters
    /// -----------------------------------------------------------------------

    function setName(string calldata _name) external onlyOwner {
        if (bytes(_name).length == 0) revert EmptyName();
        name = _name;
        emit NameUpdated(_name);
    }

    function setDescription(string calldata _description) external onlyOwner {
        description = _description;
        emit DescriptionUpdated(_description);
    }

    /// @notice Set how long a crowdsourcer has to submit an assigned record
    ///         before it is released back to the pool.
    /// @dev    Campaign is the configuration surface; SubmissionManager stores
    ///         and enforces the value.
    function setAssignmentTimeout(uint32 _assignmentTimeout) external onlyOwner {
        ISubmissionManager(submissionManager).setAssignmentTimeout(_assignmentTimeout);
        emit AssignmentTimeoutUpdated(_assignmentTimeout);
    }

    /// @notice Current submission window, read through from SubmissionManager.
    function assignmentTimeout() external view returns (uint32) {
        return ISubmissionManager(submissionManager).assignmentTimeout();
    }
}
