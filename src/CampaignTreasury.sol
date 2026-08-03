// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICampaignToken {
    function totalSupply() external view returns (uint256);
    function burnFrom(address from, uint256 amount) external;
}

interface ISubmissionManager {
    function totalRecords() external view returns (uint256);
    function validatedCount() external view returns (uint256);
}

/// @title  CampaignTreasury
/// @notice Holds ETH deposits for a single campaign. Anyone can contribute
///         ETH (donations, NFT mint proceeds, retroactive contributions).
///         Once the campaign is complete — i.e. every locator record has
///         validated — token holders may redeem their CampaignTokens for
///         a pro-rata share of the treasury's ETH. Redeemed tokens are
///         burned.
///
///         DeFi yield integration is left for a follow-up (see roadmap).
contract CampaignTreasury {
    /// -----------------------------------------------------------------------
    /// References
    /// -----------------------------------------------------------------------

    ICampaignToken     public immutable token;
    ISubmissionManager public immutable submissionManager;

    /// -----------------------------------------------------------------------
    /// State
    /// -----------------------------------------------------------------------

    bool public complete;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error ZeroAddress();
    error NotYetComplete();
    error AlreadyMarked();
    error ZeroAmount();
    error EthTransferFailed();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event Deposit(address indexed from, uint256 amount);
    event MarkedComplete(uint256 treasuryAtCompletion, uint256 tokenSupplyAtCompletion);
    event Redeemed(address indexed holder, uint256 tokensBurned, uint256 ethOut);

    /// -----------------------------------------------------------------------
    /// Construction
    /// -----------------------------------------------------------------------

    constructor(address _token, address _submissionManager) {
        if (_token == address(0) || _submissionManager == address(0)) revert ZeroAddress();
        token = ICampaignToken(_token);
        submissionManager = ISubmissionManager(_submissionManager);
    }

    /// -----------------------------------------------------------------------
    /// Deposits
    /// -----------------------------------------------------------------------

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    /// -----------------------------------------------------------------------
    /// Completion flip
    /// -----------------------------------------------------------------------

    /// @notice Marks the campaign as complete once every record in the
    ///         SubmissionManager has been validated. Permissionless — anyone
    ///         can flip the switch once the on-chain condition is met.
    function markComplete() external {
        if (complete) revert AlreadyMarked();
        if (submissionManager.validatedCount() < submissionManager.totalRecords()) {
            revert NotYetComplete();
        }
        complete = true;
        emit MarkedComplete(address(this).balance, token.totalSupply());
    }

    /// -----------------------------------------------------------------------
    /// Redemption
    /// -----------------------------------------------------------------------

    /// @notice Burn `amount` of the caller's tokens and pay them a pro-rata
    ///         share of the current treasury balance in ETH.
    /// @dev    Uses the CURRENT treasury balance and CURRENT token supply.
    ///         Because redemptions burn tokens, the per-token payout naturally
    ///         accretes for later redeemers if the treasury has continued
    ///         growth (retroactive donations, NFT royalties, DeFi yield).
    function redeem(uint256 amount) external {
        if (!complete) revert NotYetComplete();
        if (amount == 0) revert ZeroAmount();

        uint256 supply = token.totalSupply();
        uint256 balance = address(this).balance;

        // Integer division: dust remains in treasury; that's fine.
        uint256 ethOut = (balance * amount) / supply;

        // Burn first (reverts if the caller doesn't have the tokens), then pay.
        token.burnFrom(msg.sender, amount);

        if (ethOut > 0) {
            (bool ok, ) = payable(msg.sender).call{value: ethOut}("");
            if (!ok) revert EthTransferFailed();
        }

        emit Redeemed(msg.sender, amount, ethOut);
    }
}
