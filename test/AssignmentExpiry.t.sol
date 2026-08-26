// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SubmissionManager} from "../src/SubmissionManager.sol";

/// The assignment window: how long a caller has to submit. Letting it lapse
/// frees the record for anyone, including the caller who lapsed — no penalty
/// attaches, they simply lose their hold on it.
contract AssignmentExpiryTest is Test {
    SubmissionManager sm;
    bytes32 constant H = keccak256("A");

    address alice = address(0xA11CE);
    address bob   = address(0xB0B);
    address carol = address(0xCA401);

    uint32 constant TIMEOUT = 1 days;

    function setUp() public {
        sm = new SubmissionManager(address(this), 100, TIMEOUT, 2);
    }

    function test_SubmitWithinWindowStillWorks() public {
        vm.startPrank(alice);
        uint256 id = sm.assignBounty();
        vm.warp(block.timestamp + TIMEOUT); // exactly at the boundary
        sm.submit(id, H, "cid");
        vm.stopPrank();
        assertTrue(sm.hasSubmitted(alice, id));
    }

    function test_SubmitAfterWindowReverts() public {
        vm.startPrank(alice);
        uint256 id = sm.assignBounty();
        vm.warp(block.timestamp + TIMEOUT + 1);
        vm.expectRevert(SubmissionManager.SubmissionWindowClosed.selector);
        sm.submit(id, H, "cid");
        vm.stopPrank();
    }

    function test_LapsedRecordGoesToSomeoneElse() public {
        vm.prank(alice);
        uint256 id = sm.assignBounty();

        vm.warp(block.timestamp + TIMEOUT + 1);

        vm.prank(bob);
        assertEq(sm.assignBounty(), id, "bob should inherit the lapsed record");
        assertEq(sm.activeRecordCount(), 1, "no duplicate record minted");
    }

    function test_LapsedCallerMayBeAssignedTheRecordAgain() public {
        vm.prank(alice);
        uint256 id = sm.assignBounty();
        vm.warp(block.timestamp + TIMEOUT + 1);

        // Nobody else is asking, so alice gets it back on a fresh window.
        vm.prank(alice);
        assertEq(sm.assignBounty(), id, "lapsing should not bar the caller");

        // And the fresh window is real: she can submit again.
        vm.prank(alice);
        sm.submit(id, H, "cid");
        assertTrue(sm.hasSubmitted(alice, id));
    }

    function test_HolderGetsAFreshWindowAfterLapsing() public {
        vm.prank(alice);
        uint256 id = sm.assignBounty();
        vm.warp(block.timestamp + TIMEOUT + 1);

        // Nobody else has taken it, but alice's window is gone.
        vm.prank(alice);
        uint256 got = sm.assignBounty();
        assertEq(got, id, "record is free, so alice may take it again");
        assertEq(sm.assignedTo(alice), got);
        // The window restarted, so the earlier lapse no longer blocks her.
        vm.prank(alice);
        sm.submit(id, H, "cid");
    }

    function test_RecordPassesOnEachTimeAWindowLapses() public {
        vm.prank(alice);
        uint256 id = sm.assignBounty();
        vm.warp(block.timestamp + TIMEOUT + 1);
        vm.prank(bob);
        assertEq(sm.assignBounty(), id);
        assertEq(sm.assignedTo(alice), 0);

        vm.warp(block.timestamp + TIMEOUT + 1);
        vm.prank(carol);
        assertEq(sm.assignBounty(), id);
        assertEq(sm.assignedTo(bob), 0);
        assertEq(sm.assignedTo(carol), id);
        assertEq(sm.activeRecordCount(), 1, "still one record, just changing hands");
    }

    /// Regression: the previous holder's assignedTo pointer must be cleared,
    /// or they are shown a record they no longer hold and submit() reverts.
    function test_PreviousHolderAssignmentPointerIsCleared() public {
        vm.prank(alice);
        uint256 id = sm.assignBounty();
        assertEq(sm.assignedTo(alice), id);

        vm.warp(block.timestamp + TIMEOUT + 1);
        vm.prank(bob);
        sm.assignBounty();

        assertEq(sm.assignedTo(alice), 0, "stale pointer left on previous holder");
        assertEq(sm.assignedTo(bob), id);
    }

    function test_ExpiryEmitsEvent() public {
        vm.prank(alice);
        uint256 id = sm.assignBounty();
        vm.warp(block.timestamp + TIMEOUT + 1);

        vm.expectEmit(true, true, false, false);
        emit SubmissionManager.AssignmentExpired(id, alice);
        vm.prank(bob);
        sm.assignBounty();
    }

    function test_ExpiryDoesNotBlockValidationByOthers() public {
        vm.prank(alice);
        uint256 id = sm.assignBounty();
        vm.warp(block.timestamp + TIMEOUT + 1);

        vm.startPrank(bob);   sm.assignBounty(); sm.submit(id, H, "cid"); vm.stopPrank();
        vm.startPrank(carol); sm.assignBounty(); sm.submit(id, H, "cid"); vm.stopPrank();

        assertEq(sm.validatedCount(), 1);
        assertEq(sm.activeRecordCount(), 0);
    }
}
