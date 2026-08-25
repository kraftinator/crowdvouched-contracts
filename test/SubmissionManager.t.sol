// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console, Vm} from "forge-std/Test.sol";
import {SubmissionManager} from "../src/SubmissionManager.sol";
import {CampaignToken} from "../src/CampaignToken.sol";

contract SubmissionManagerTest is Test {
    SubmissionManager sm;

    address campaign = address(0xCAFE);
    address alice = address(0xA11CE);
    address bob   = address(0xB0B);
    address carol = address(0xCA401);

    uint256 constant TOTAL_RECORDS = 3;
    uint32  constant TIMEOUT       = 1 days;
    uint8   constant REQUIRED      = 2;

    bytes32 constant HASH_A = keccak256("Chls. Howard");
    bytes32 constant HASH_B = keccak256("Charles Howard");

    function setUp() public {
        sm = new SubmissionManager(campaign, TOTAL_RECORDS, TIMEOUT, REQUIRED);
    }

    /* ---------------------------------------------------------------------- *
     * Construction
     * ---------------------------------------------------------------------- */

    function test_ConstructorStoresConfig() public view {
        assertEq(sm.campaign(), campaign);
        assertEq(sm.totalRecords(), TOTAL_RECORDS);
        assertEq(uint256(sm.assignmentTimeout()), TIMEOUT);
        assertEq(uint256(sm.requiredMatches()), REQUIRED);
    }

    function test_RevertZeroCampaign() public {
        vm.expectRevert(SubmissionManager.ZeroAddress.selector);
        new SubmissionManager(address(0), 1, 1, 2);
    }

    function test_RevertInvalidConfig() public {
        vm.expectRevert(SubmissionManager.InvalidConfig.selector);
        new SubmissionManager(campaign, 0, 1, 2);
        vm.expectRevert(SubmissionManager.InvalidConfig.selector);
        new SubmissionManager(campaign, 1, 0, 2);
        vm.expectRevert(SubmissionManager.InvalidConfig.selector);
        new SubmissionManager(campaign, 1, 1, 1);
    }

    /* ---------------------------------------------------------------------- *
     * Assignment
     * ---------------------------------------------------------------------- */

    function test_AssignBounty_MintsFreshRecord() public {
        vm.prank(alice);
        uint256 id = sm.assignBounty();
        assertEq(id, 1);
        assertEq(sm.assignedTo(alice), 1);
        (address assignee,,,,) = sm.record(1);
        assertEq(assignee, alice);
    }

    function test_AssignBounty_Idempotent() public {
        vm.prank(alice);
        uint256 first = sm.assignBounty();
        vm.prank(alice);
        uint256 again = sm.assignBounty();
        assertEq(first, again);
    }

    function test_AssignBounty_DifferentUsersGetDifferentRecords() public {
        vm.prank(alice);
        uint256 a = sm.assignBounty();
        vm.prank(bob);
        uint256 b = sm.assignBounty();
        assertTrue(a != b);
    }

    function test_AssignBounty_RevertsWhenAllRecordsTaken() public {
        SubmissionManager small = new SubmissionManager(campaign, 1, TIMEOUT, REQUIRED);
        vm.prank(alice);
        small.assignBounty();
        // record 1 assigned to alice; bob asks - no free record, only 1 total.
        vm.prank(bob);
        vm.expectRevert(SubmissionManager.NoRecordAvailable.selector);
        small.assignBounty();
    }

    function test_AssignBounty_ReassignsAfterTimeout() public {
        vm.prank(alice);
        uint256 id = sm.assignBounty();

        vm.warp(block.timestamp + TIMEOUT + 1);

        vm.prank(bob);
        uint256 idAgain = sm.assignBounty();
        assertEq(idAgain, id, "bob should be able to reclaim timed-out record");
        (address assignee,,,,) = sm.record(id);
        assertEq(assignee, bob);
    }

    /* ---------------------------------------------------------------------- *
     * Submission + validation
     * ---------------------------------------------------------------------- */

    function test_Submit_RecordsSubmission() public {
        vm.prank(alice);
        uint256 id = sm.assignBounty();

        vm.prank(alice);
        sm.submit(id, HASH_A, "QmAlice");

        assertTrue(sm.hasSubmitted(alice, id));
        // record should be un-assigned again (awaiting second submission).
        (address assignee,,,, uint256 count) = sm.record(id);
        assertEq(assignee, address(0));
        assertEq(count, 1);
        assertEq(sm.assignedTo(alice), 0);
    }

    function test_Submit_RevertsIfNotAssigned() public {
        vm.prank(alice);
        vm.expectRevert(SubmissionManager.NotYourAssignment.selector);
        sm.submit(1, HASH_A, "QmAlice");
    }

    function test_Submit_RevertsOnDoubleSubmit() public {
        vm.prank(alice);
        uint256 id = sm.assignBounty();
        vm.prank(alice);
        sm.submit(id, HASH_A, "QmAlice");

        // Alice tries to reassign — but she already submitted, so she should
        // get a different record.
        vm.prank(alice);
        uint256 second = sm.assignBounty();
        assertTrue(second != id, "alice must not be reassigned to a record she has submitted");
    }

    function test_Validate_TwoMatchingSubmissionsValidateRecord() public {
        _validateOneRecord(1);

        (,, bool validated, bytes32 hash, uint256 count) = sm.record(1);
        assertTrue(validated);
        assertEq(hash, HASH_A);
        assertEq(count, 2);
        assertEq(sm.validatedCount(), 1);
    }

    /// Alice and Bob submit HASH_A for the first fresh record.
    function _validateOneRecord(uint256 expectedId) internal {
        vm.prank(alice); uint256 aId = sm.assignBounty();
        assertEq(aId, expectedId);
        vm.prank(alice); sm.submit(expectedId, HASH_A, "QmAlice");
        vm.prank(bob);   uint256 bId = sm.assignBounty();
        assertEq(bId, expectedId);
        vm.prank(bob);   sm.submit(expectedId, HASH_A, "QmBob");
    }

    function test_Validate_MismatchDoesNotValidate() public {
        vm.prank(alice);
        uint256 id = sm.assignBounty();
        vm.prank(alice);
        sm.submit(id, HASH_A, "QmAlice");

        vm.prank(bob);
        sm.assignBounty();
        vm.prank(bob);
        sm.submit(id, HASH_B, "QmBob");

        (,, bool validated,,) = sm.record(id);
        assertFalse(validated);
    }

    function test_Validate_ThirdSubmissionCanUnstickMismatch() public {
        // Alice submits A. Bob submits B. Carol submits A -> Alice and Carol match.
        vm.prank(alice);
        uint256 id = sm.assignBounty();
        vm.prank(alice);
        sm.submit(id, HASH_A, "QmAlice");

        vm.prank(bob);
        sm.assignBounty();
        vm.prank(bob);
        sm.submit(id, HASH_B, "QmBob");

        vm.prank(carol);
        sm.assignBounty();
        vm.prank(carol);
        sm.submit(id, HASH_A, "QmCarol");

        (,, bool validated, bytes32 hash,) = sm.record(id);
        assertTrue(validated);
        assertEq(hash, HASH_A);
    }

    /* ---------------------------------------------------------------------- *
     * Reward accounting + claim()
     * ---------------------------------------------------------------------- */

    function test_Validation_CreditsUnclaimedRewardsToBothMatchers() public {
        _validateOneRecord(1);
        assertEq(sm.unclaimedRewards(alice), sm.REWARD_PER_VALIDATION());
        assertEq(sm.unclaimedRewards(bob), sm.REWARD_PER_VALIDATION());
    }

    function test_Validation_ThirdSubmitterMatchIsCredited() public {
        // Alice submits A, Bob submits B (mismatch), Carol submits A -> Alice+Carol match.
        vm.prank(alice); uint256 id = sm.assignBounty();
        vm.prank(alice); sm.submit(id, HASH_A, "QmAlice");
        vm.prank(bob);   sm.assignBounty();
        vm.prank(bob);   sm.submit(id, HASH_B, "QmBob");
        vm.prank(carol); sm.assignBounty();
        vm.prank(carol); sm.submit(id, HASH_A, "QmCarol");

        assertEq(sm.unclaimedRewards(alice), sm.REWARD_PER_VALIDATION());
        assertEq(sm.unclaimedRewards(carol), sm.REWARD_PER_VALIDATION());
        // Bob did not match; no reward.
        assertEq(sm.unclaimedRewards(bob), 0);
    }

    function test_SetToken_OnlyCampaign() public {
        CampaignToken tok = new CampaignToken("USC", "USC", address(this));
        vm.prank(alice);
        vm.expectRevert(SubmissionManager.NotCampaign.selector);
        sm.setToken(address(tok));

        vm.prank(campaign);
        sm.setToken(address(tok));
        assertEq(sm.token(), address(tok));
    }

    function test_SetToken_OneShot() public {
        CampaignToken tok1 = new CampaignToken("USC", "USC", address(this));
        CampaignToken tok2 = new CampaignToken("USC", "USC", address(this));

        vm.prank(campaign); sm.setToken(address(tok1));
        vm.prank(campaign);
        vm.expectRevert(SubmissionManager.AlreadySet.selector);
        sm.setToken(address(tok2));
    }

    function test_Claim_MintsUnclaimedRewards() public {
        CampaignToken tok = new CampaignToken("USC", "USC", address(this));
        vm.prank(campaign); sm.setToken(address(tok));
        tok.setMinter(address(sm));

        _validateOneRecord(1);

        vm.prank(alice); sm.claim();
        assertEq(tok.balanceOf(alice), sm.REWARD_PER_VALIDATION());
        assertEq(sm.unclaimedRewards(alice), 0);
    }

    function test_Claim_RevertsIfNothingToClaim() public {
        CampaignToken tok = new CampaignToken("USC", "USC", address(this));
        vm.prank(campaign); sm.setToken(address(tok));
        tok.setMinter(address(sm));

        vm.prank(alice);
        vm.expectRevert(SubmissionManager.NothingToClaim.selector);
        sm.claim();
    }

    function test_Claim_RevertsIfTokenNotSet() public {
        _validateOneRecord(1);
        vm.prank(alice);
        vm.expectRevert(SubmissionManager.TokenNotSet.selector);
        sm.claim();
    }

    /* ---------------------------------------------------------------------- *
     * Completion event
     * ---------------------------------------------------------------------- */

    function test_Validate_EmitsCampaignCompletedWhenAllValidated() public {
        SubmissionManager tiny = new SubmissionManager(campaign, 1, TIMEOUT, REQUIRED);
        vm.prank(alice);
        tiny.assignBounty();
        vm.prank(alice);
        tiny.submit(1, HASH_A, "QmAlice");

        vm.prank(bob);
        tiny.assignBounty();

        vm.recordLogs();
        vm.prank(bob);
        tiny.submit(1, HASH_A, "QmBob");

        // Confirm CampaignCompleted was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("CampaignCompleted(uint256)")) {
                found = true;
                break;
            }
        }
        assertTrue(found, "CampaignCompleted event not emitted");
    }
}
