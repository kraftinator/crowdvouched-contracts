// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CampaignTreasury {
    address public campaign;
    
    event ContributionReceived(address indexed contributor, uint256 amount);
    event ERC20Withdrawal(address indexed token, uint256 amount, address indexed to);

    constructor(address _campaign) {
        campaign = _campaign;
    }

    function contribute() external payable {
        require(msg.value > 0, "Must send ETH to contribute");
        emit ContributionReceived(msg.sender, msg.value);
    }

    // Contribute without using contribute function
    receive() external payable {
        emit ContributionReceived(msg.sender, msg.value);
    }

    modifier onlyCampaign() {
        require(msg.sender == campaign, "Not authorized");
        _;
    }

    function withdrawERC20(address tokenAddress, uint256 amount, address recipient) external onlyCampaign {
        IERC20 token = IERC20(tokenAddress);
        require(token.balanceOf(address(this)) >= amount, "Insufficient token balance");
        require(recipient != address(0), "Invalid recipient address");
        token.transfer(recipient, amount);
        emit ERC20Withdrawal(tokenAddress, amount, recipient);
    }

}
