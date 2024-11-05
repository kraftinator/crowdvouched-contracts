// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Campaign {
    // State variables for owner, name, description, and creation date
    address public owner;
    string public campaignName;
    string public campaignDescription;
    uint256 public createdAt;

    // Constructor to initialize the campaign
    constructor(string memory _campaignName, string memory _campaignDescription) {
        owner = msg.sender;  // Set the owner as the deployer of the contract
        campaignName = _campaignName;
        campaignDescription = _campaignDescription;
        createdAt = block.timestamp;  // Set creation date to current block timestamp
    }

    // Modifier to restrict functions to only the owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    // Event logging for updates
    event CampaignNameUpdated(string newName);
    event CampaignDescriptionUpdated(string newDescription);

    // Setters
    function setCampaignName(string memory _newName) public onlyOwner {
        campaignName = _newName;
        emit CampaignNameUpdated(_newName);
    }

    function setCampaignDescription(string memory _newDescription) public onlyOwner {
        campaignDescription = _newDescription;
        emit CampaignDescriptionUpdated(_newDescription);
    }
}
