// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CampaignTreasury} from "../src/CampaignTreasury.sol";
import {CampaignToken}    from "../src/CampaignToken.sol";
import {SubmissionManager} from "../src/SubmissionManager.sol";

contract CampaignTreasuryTest is Test {
    CampaignTreasury  treasury;
    CampaignToken     token;
    SubmissionManager sm;

    address owner   = address(0xA11CE);
    address alice   = address(0xAA);
    address bob     = address(0xBB);
    address carol   = address(0xCC);
    address campaign = address(0xCAFE);

    bytes32 constant HASH_A = keccak256("Chls. Howard");

    function setUp() public {
        // Campaign of 1 record so we can complete it cheaply.
        sm    = new SubmissionManager(campaign, 1, 1 days, 2);
        token = new CampaignToken("USC1850", "USC1850", owner);
        treasury = new CampaignTreasury(address(token), address(sm));

        // Wire up token minter/burner. In production the minter is the
        // SubmissionManager and the burner is the treasury; we wire them
        // the same way here.
        vm.prank(owner);
        token.setMinter(address(this)); // test itself mints for setup convenience
        vm.prank(owner);
        token.setBurner(address(treasury));
    }

    /* ---------------------------------------------------------------------- *
     * Deposits
     * ---------------------------------------------------------------------- */

    function test_AcceptsEth() public {
        vm.deal(alice, 5 ether);
        vm.prank(alice);
        (bool ok, ) = payable(treasury).call{value: 5 ether}("");
        assertTrue(ok);
        assertEq(address(treasury).balance, 5 ether);
    }

    /* ---------------------------------------------------------------------- *
     * markComplete
     * ---------------------------------------------------------------------- */

    function test_MarkComplete_RevertsIfNotComplete() public {
        vm.expectRevert(CampaignTreasury.NotYetComplete.selector);
        treasury.markComplete();
    }

    function test_MarkComplete_SucceedsAfterCampaignComplete() public {
        _validateOneRecord();
        treasury.markComplete();
        assertTrue(treasury.complete());
    }

    function test_MarkComplete_RevertsIfAlreadyMarked() public {
        _validateOneRecord();
        treasury.markComplete();
        vm.expectRevert(CampaignTreasury.AlreadyMarked.selector);
        treasury.markComplete();
    }

    /* ---------------------------------------------------------------------- *
     * Redemption
     * ---------------------------------------------------------------------- */

    function test_Redeem_RevertsBeforeComplete() public {
        token.mint(alice, 100);
        vm.expectRevert(CampaignTreasury.NotYetComplete.selector);
        vm.prank(alice);
        treasury.redeem(50);
    }

    function test_Redeem_PaysProRata() public {
        // 100 tokens total: alice has 60, bob has 40.
        token.mint(alice, 60);
        token.mint(bob, 40);

        vm.deal(address(treasury), 10 ether);
        _validateOneRecord();
        treasury.markComplete();

        // Alice redeems her 60 -> should get 60% of the treasury.
        uint256 startAlice = alice.balance;
        vm.prank(alice);
        treasury.redeem(60);
        assertEq(alice.balance - startAlice, 6 ether);
        assertEq(token.balanceOf(alice), 0);

        // Treasury now has 4 ether left, bob has 40 tokens, supply is 40.
        // Bob redeems all 40 -> 4 ether.
        uint256 startBob = bob.balance;
        vm.prank(bob);
        treasury.redeem(40);
        assertEq(bob.balance - startBob, 4 ether);
        assertEq(address(treasury).balance, 0);
    }

    function test_Redeem_PartialWorks() public {
        token.mint(alice, 100);
        vm.deal(address(treasury), 10 ether);
        _validateOneRecord();
        treasury.markComplete();

        vm.prank(alice);
        treasury.redeem(25); // 25% of the pool

        assertEq(token.balanceOf(alice), 75);
        // 25/100 of 10 ether = 2.5 ether
        assertEq(alice.balance, 2.5 ether);
    }

    function test_Redeem_RevertsOnZeroAmount() public {
        token.mint(alice, 100);
        _validateOneRecord();
        treasury.markComplete();

        vm.prank(alice);
        vm.expectRevert(CampaignTreasury.ZeroAmount.selector);
        treasury.redeem(0);
    }

    /* ---------------------------------------------------------------------- *
     * Helpers
     * ---------------------------------------------------------------------- */

    /// Push the SubmissionManager into the completed state.
    function _validateOneRecord() internal {
        vm.prank(alice);
        sm.assignBounty();
        vm.prank(alice);
        sm.submit(1, HASH_A, "QmAlice");
        vm.prank(carol);
        sm.assignBounty();
        vm.prank(carol);
        sm.submit(1, HASH_A, "QmCarol");
        assertEq(sm.validatedCount(), 1);
    }
}
