// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Campaign}          from "../src/Campaign.sol";
import {SubmissionManager}  from "../src/SubmissionManager.sol";
import {CampaignToken}      from "../src/CampaignToken.sol";
import {CampaignTreasury}   from "../src/CampaignTreasury.sol";

/// @notice Deploy one full campaign locally for the smoke-test demo.
///         Wires up SubmissionManager → CampaignToken (minter) and
///         CampaignToken → CampaignTreasury (burner).
contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        // 1. SubmissionManager needs a campaign address up front to gate its
        //    setters, but Campaign needs SubmissionManager's address to be
        //    constructed. The deployer holds the role through wiring and hands
        //    it to the real Campaign contract at the end.
        SubmissionManager sm = new SubmissionManager(
            deployer,       // campaign owner
            5,              // totalRecords (5 for a tiny demo)
            1 days,         // assignmentTimeout
            2               // requiredMatches
        );

        // 2. Token — deployer becomes owner, will set minter/burner below.
        CampaignToken token = new CampaignToken("USC 1850", "USC1850", deployer);

        // 3. Treasury.
        CampaignTreasury treasury = new CampaignTreasury(address(token), address(sm));

        // 4. Campaign (metadata + sub-contract references).
        Campaign campaign = new Campaign(
            deployer,
            "1850 U.S. Census Pilot",
            "Digitize the Tioga Co. NY records from the 1850 U.S. Census.",
            address(sm),
            address(token),
            address(treasury),
            address(0xdEaD)   // NFT placeholder — CampaignNFT not yet built
        );

        // 5. Wire up: SubmissionManager mints from token; Treasury burns from token.
        sm.setToken(address(token));
        token.setMinter(address(sm));
        token.setBurner(address(treasury));

        // 6. Hand campaign control to the Campaign contract. Must come last:
        //    once transferred, the deployer can no longer call sm's setters.
        sm.setCampaign(address(campaign));

        vm.stopBroadcast();

        console.log("Campaign          :", address(campaign));
        console.log("SubmissionManager :", address(sm));
        console.log("CampaignToken     :", address(token));
        console.log("CampaignTreasury  :", address(treasury));
    }
}
