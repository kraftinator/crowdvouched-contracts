// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Campaign} from "../src/Campaign.sol";

contract CampaignTest is Test {
    Campaign campaign;

    address owner = address(0xA11CE);
    address stranger = address(0xB0B);
    address submissionManager = address(0x1);
    address token = address(0x2);
    address treasury = address(0x3);
    address nft = address(0x4);

    function setUp() public {
        campaign = new Campaign(
            owner,
            "1850 US Census",
            "Digitize the 1850 US population schedule",
            submissionManager,
            token,
            treasury,
            nft
        );
    }

    function test_ConstructorSetsMetadata() public view {
        assertEq(campaign.name(), "1850 US Census");
        assertEq(campaign.description(), "Digitize the 1850 US population schedule");
        assertEq(campaign.owner(), owner);
    }

    function test_ConstructorWiresSubContracts() public view {
        assertEq(campaign.submissionManager(), submissionManager);
        assertEq(campaign.token(), token);
        assertEq(campaign.treasury(), treasury);
        assertEq(campaign.nft(), nft);
    }

    function test_ConstructorSetsCreatedAt() public view {
        assertEq(campaign.createdAt(), block.timestamp);
    }

    function test_RevertOnEmptyName() public {
        vm.expectRevert(Campaign.EmptyName.selector);
        new Campaign(owner, "", "", submissionManager, token, treasury, nft);
    }

    function test_RevertOnZeroAddress() public {
        vm.expectRevert(Campaign.ZeroAddress.selector);
        new Campaign(owner, "n", "", address(0), token, treasury, nft);
        vm.expectRevert(Campaign.ZeroAddress.selector);
        new Campaign(owner, "n", "", submissionManager, address(0), treasury, nft);
        vm.expectRevert(Campaign.ZeroAddress.selector);
        new Campaign(owner, "n", "", submissionManager, token, address(0), nft);
        vm.expectRevert(Campaign.ZeroAddress.selector);
        new Campaign(owner, "n", "", submissionManager, token, treasury, address(0));
    }

    function test_OwnerCanUpdateName() public {
        vm.prank(owner);
        campaign.setName("New Name");
        assertEq(campaign.name(), "New Name");
    }

    function test_StrangerCannotUpdateName() public {
        vm.prank(stranger);
        vm.expectRevert();
        campaign.setName("Hostile Takeover");
    }

    function test_OwnerCanUpdateDescription() public {
        vm.prank(owner);
        campaign.setDescription("New desc");
        assertEq(campaign.description(), "New desc");
    }

    function test_RevertOnEmptyNameUpdate() public {
        vm.prank(owner);
        vm.expectRevert(Campaign.EmptyName.selector);
        campaign.setName("");
    }
}
