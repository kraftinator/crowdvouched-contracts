// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./CampaignTreasury.sol";

contract Campaign {
    address public owner;
    string public campaignName;
    string public campaignDescription;
    uint256 public createdAt;
    // contracts
    CampaignTreasury public treasury;

    constructor(string memory _campaignName, string memory _campaignDescription) {
        owner = msg.sender;
        treasury = new CampaignTreasury(address(this));
        campaignName = _campaignName;
        campaignDescription = _campaignDescription;
        createdAt = block.timestamp;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

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

    // Function to withdraw ERC20 tokens from the treasury
    function withdrawTreasuryERC20(address tokenAddress, uint256 amount, address recipient) external onlyOwner {
        treasury.withdrawERC20(tokenAddress, amount, recipient);
    }
}
