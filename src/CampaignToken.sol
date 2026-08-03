// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

/// @title  CampaignToken
/// @notice The per-campaign reward token. One is minted to each validating
///         submitter every time a record hits the required-matches threshold.
///         After the campaign completes, tokens are burned in exchange for a
///         pro-rata share of the treasury.
///
///         Only the `minter` (SubmissionManager) can mint. Only the `burner`
///         (Treasury) can burn from arbitrary holders during redemption.
///         Both are set once by the owner immediately after deployment.
///
///         Freely transferable, per the whitepaper: contributors can trade
///         their tokens before campaign completion if they choose.
contract CampaignToken is ERC20, Ownable {
    address public minter;
    address public burner;

    error NotMinter();
    error NotBurner();
    error AlreadySet();

    event MinterSet(address indexed minter);
    event BurnerSet(address indexed burner);

    constructor(string memory _name, string memory _symbol, address _owner)
        ERC20(_name, _symbol)
        Ownable(_owner)
    {}

    /// @notice Set the minter (usually the SubmissionManager). One-shot.
    function setMinter(address _minter) external onlyOwner {
        if (minter != address(0)) revert AlreadySet();
        minter = _minter;
        emit MinterSet(_minter);
    }

    /// @notice Set the burner (usually the Treasury). One-shot.
    function setBurner(address _burner) external onlyOwner {
        if (burner != address(0)) revert AlreadySet();
        burner = _burner;
        emit BurnerSet(_burner);
    }

    /// @notice Mint reward tokens to a validator.
    function mint(address to, uint256 amount) external {
        if (msg.sender != minter) revert NotMinter();
        _mint(to, amount);
    }

    /// @notice Burn a redeemer's tokens as part of treasury payout.
    function burnFrom(address from, uint256 amount) external {
        if (msg.sender != burner) revert NotBurner();
        _burn(from, amount);
    }
}
