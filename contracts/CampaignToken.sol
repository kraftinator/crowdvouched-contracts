// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CampaignToken is ERC20, Ownable {

    constructor(
        string memory name,
        string memory symbol,
        address initialOwner
    ) ERC20(name, symbol)  {
        transferOwnership(initialOwner);
    }

    // Mint function restricted to the owner (initially the CampaignTreasury)
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
