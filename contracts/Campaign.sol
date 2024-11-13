// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/utils/Strings.sol";
import "./CampaignNFT.sol";
import "./CampaignTreasury.sol";

contract Campaign {
    using Strings for uint256;

    address public owner;
    string public campaignName;
    string public campaignDescription;
    string public baseURI;
    uint256 public createdAt;
    
    CampaignNFT public campaignNFT;
    CampaignTreasury public treasury;

    constructor(
        string memory _campaignName, 
        string memory _campaignDescription,
        string memory _tokenName,
        string memory _tokenSymbol,
        string memory _baseURI,
        string memory _nftName,
        string memory _nftSymbol,
        uint256 _mintFee
    ) {
        owner = msg.sender;
        campaignName = _campaignName;
        campaignDescription = _campaignDescription;
        baseURI = _baseURI;

        CampaignToken token = new CampaignToken(_tokenName, _tokenSymbol, address(this));
        campaignNFT = new CampaignNFT(_nftName, _nftSymbol, _mintFee, address(treasury), address(this));
        treasury = new CampaignTreasury(address(this), address(token));
        token.transferOwnership(address(treasury));
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

    function mintTokens(address recipient, uint256 amount) external onlyOwner {
        treasury.mintTokens(recipient, amount);
    }

    function getBaseURI() external view returns (string memory) {
        return baseURI;
    }

    function getRecordURI(uint256 recordId) external view returns (string memory) {
        return string(abi.encodePacked(baseURI, recordId.toString()));
    }

    function validatedRecord(uint256 recordId) external pure returns (bool) {
        return true;
    }

}
