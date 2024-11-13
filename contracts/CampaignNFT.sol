// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./CampaignTreasury.sol";
import "./Campaign.sol";

contract CampaignNFT is ERC721Enumerable, Ownable {
    uint256 public mintFee;
    CampaignTreasury public treasury;
    Campaign public campaign;

    event RecordMinted(address indexed owner, uint256 recordId);

    constructor(
        string memory name,
        string memory symbol,
        uint256 _mintFee,
        address treasuryAddress,
        address campaignAddress
    ) ERC721(name, symbol) {
        mintFee = _mintFee;
        treasury = CampaignTreasury(payable(treasuryAddress));
        campaign = Campaign(campaignAddress);
    }

    // Function to mint a validated record as an NFT
    function mintRecord(uint256 recordId) external payable {
        require(msg.value >= mintFee, "Insufficient minting fee");
        require(!_exists(recordId), "Record already minted");
        require(campaign.validatedRecord(recordId), "Record not validated");

        (bool sent, ) = address(treasury).call{value: msg.value}("");
        require(sent, "Minting fee transfer failed");

        _safeMint(msg.sender, recordId);
        emit RecordMinted(msg.sender, recordId);
    }

    // Override tokenURI to reference Campaign's base URI
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return string(abi.encodePacked(campaign.getBaseURI(), Strings.toString(tokenId)));
    }

    function setMintFee(uint256 newMintFee) external onlyOwner {
        mintFee = newMintFee;
    }
}
