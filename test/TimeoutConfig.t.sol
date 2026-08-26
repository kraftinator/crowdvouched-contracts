// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Campaign} from "../src/Campaign.sol";
import {SubmissionManager} from "../src/SubmissionManager.sol";

/// assignmentTimeout is configurable through the Campaign contract rather than
/// frozen at deployment.
contract TimeoutConfigTest is Test {
    SubmissionManager sm;
    Campaign campaign;
    bytes32 constant H = keccak256("A");

    address owner = address(0x0E);
    address alice = address(0xA11CE);
    address bob   = address(0xB0B);

    function setUp() public {
        sm = new SubmissionManager(address(this), 100, 1 days, 2);
        campaign = new Campaign(
            owner, "C", "d", address(sm), address(0xC0DE), address(0xBEEF), address(0xFEED)
        );
        sm.setCampaign(address(campaign)); // hand over, as Deploy.s.sol does
    }

    function test_CampaignOwnerCanChangeTimeout() public {
        assertEq(sm.assignmentTimeout(), 1 days);
        vm.prank(owner);
        campaign.setAssignmentTimeout(1 hours);
        assertEq(sm.assignmentTimeout(), 1 hours);
        assertEq(campaign.assignmentTimeout(), 1 hours, "campaign read-through");
    }

    function test_StrangerCannotChangeTimeoutViaCampaign() public {
        vm.prank(alice);
        vm.expectRevert();
        campaign.setAssignmentTimeout(1 hours);
    }

    function test_StrangerCannotCallSubmissionManagerDirectly() public {
        vm.prank(alice);
        vm.expectRevert(SubmissionManager.NotCampaign.selector);
        sm.setAssignmentTimeout(1 hours);
    }

    function test_DeployerLosesControlAfterHandover() public {
        // setUp already handed control to the Campaign contract
        vm.expectRevert(SubmissionManager.NotCampaign.selector);
        sm.setAssignmentTimeout(1 hours);
    }

    function test_TimeoutOfZeroRejected() public {
        vm.prank(owner);
        vm.expectRevert(SubmissionManager.InvalidConfig.selector);
        campaign.setAssignmentTimeout(0);
    }

    function test_NewTimeoutGovernsSubsequentSubmissions() public {
        vm.prank(owner);
        campaign.setAssignmentTimeout(1 hours);

        vm.prank(alice);
        uint256 id = sm.assignBounty();

        vm.warp(block.timestamp + 2 hours); // past the new window, inside the old one
        vm.prank(alice);
        vm.expectRevert(SubmissionManager.SubmissionWindowClosed.selector);
        sm.submit(id, H, "cid");
    }

    /// Shortening the window applies to records already held.
    function test_ShorteningTimeoutLapsesInFlightAssignments() public {
        vm.prank(alice);
        uint256 id = sm.assignBounty();
        vm.warp(block.timestamp + 2 hours); // still fine under a 1-day window

        vm.prank(owner);
        campaign.setAssignmentTimeout(1 hours); // now retroactively lapsed

        vm.prank(bob);
        assertEq(sm.assignBounty(), id, "bob should inherit the now-lapsed record");
        assertEq(sm.assignedTo(alice), 0);
    }

    function test_LengtheningTimeoutRescuesInFlightAssignments() public {
        vm.prank(owner);
        campaign.setAssignmentTimeout(1 hours);
        vm.prank(alice);
        uint256 id = sm.assignBounty();
        vm.warp(block.timestamp + 2 hours); // lapsed under 1 hour

        vm.prank(owner);
        campaign.setAssignmentTimeout(1 days); // no longer lapsed

        vm.prank(alice);
        sm.submit(id, H, "cid"); // window is live again
        assertTrue(sm.hasSubmitted(alice, id));
    }
}
