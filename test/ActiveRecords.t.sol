// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SubmissionManager} from "../src/SubmissionManager.sol";

/// Covers the active-record list: records enter on creation, leave on
/// validation, and assignment cost tracks work-in-progress rather than
/// how much of the campaign is already finished.
contract ActiveRecordsTest is Test {
    SubmissionManager sm;
    bytes32 constant HASH_A = keccak256("A");

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        sm = new SubmissionManager(address(this), 5000, 1 days, 2);
    }

    /// Validate `id` using two distinct throwaway submitters.
    function _validate(uint256 salt) internal returns (uint256 id) {
        address w1 = address(uint160(0x10000 + salt));
        address w2 = address(uint160(0x20000 + salt));
        vm.startPrank(w1);
        id = sm.assignBounty();
        sm.submit(id, HASH_A, "cid");
        vm.stopPrank();
        vm.startPrank(w2);
        sm.assignBounty();
        sm.submit(id, HASH_A, "cid");
        vm.stopPrank();
    }

    function test_RecordEntersActiveListOnCreation() public {
        assertEq(sm.activeRecordCount(), 0);
        vm.prank(alice);
        sm.assignBounty();
        assertEq(sm.activeRecordCount(), 1);
        assertEq(sm.activeRecordIds(0), 1);
    }

    function test_RecordLeavesActiveListOnValidation() public {
        _validate(1);
        assertEq(sm.validatedCount(), 1);
        assertEq(sm.activeRecordCount(), 0);
    }

    function test_UnvalidatedRecordStaysActive() public {
        vm.startPrank(alice);
        uint256 id = sm.assignBounty();
        sm.submit(id, HASH_A, "cid");
        vm.stopPrank();
        // one submission only — still needs a second submitter
        assertEq(sm.activeRecordCount(), 1);
    }

    function test_RemovalFromMiddleKeepsListConsistent() public {
        address carol = address(0xCA401);
        address dave = address(0xDA5E);

        vm.prank(alice); uint256 id1 = sm.assignBounty(); // 1
        vm.prank(bob);   uint256 id2 = sm.assignBounty(); // 2
        vm.prank(carol); uint256 id3 = sm.assignBounty(); // 3
        assertEq(sm.activeRecordCount(), 3);

        // Free record 2 (the middle of the list) and let dave match it.
        vm.prank(bob);  sm.submit(id2, HASH_A, "cid");
        vm.prank(dave); assertEq(sm.assignBounty(), id2, "dave should get the freed middle record");
        vm.prank(dave); sm.submit(id2, HASH_A, "cid");

        assertEq(sm.validatedCount(), 1);
        assertEq(sm.activeRecordCount(), 2, "middle record should have left the list");

        // Both survivors must still be present exactly once.
        uint256 a = sm.activeRecordIds(0);
        uint256 b = sm.activeRecordIds(1);
        assertTrue(a != b, "duplicate entry after swap-and-pop");
        assertTrue((a == id1 && b == id3) || (a == id3 && b == id1), "wrong survivors");

        // And the swapped element must still be assignable via the list.
        vm.warp(block.timestamp + 2 days);
        vm.prank(dave);
        uint256 got = sm.assignBounty();
        assertTrue(got == id1 || got == id3, "swapped record unreachable");
        assertEq(sm.activeRecordCount(), 2, "no spurious record created");
    }

    function test_TimedOutRecordIsStillReassignable() public {
        vm.prank(alice);
        uint256 id = sm.assignBounty();

        vm.warp(block.timestamp + 2 days);

        vm.prank(bob);
        uint256 got = sm.assignBounty();
        assertEq(got, id, "timed-out record should be handed to the next caller");
        assertEq(sm.activeRecordCount(), 1, "no duplicate record created");
    }

    /// The regression that matters: finished records must not make future
    /// assignments more expensive.
    function test_AssignGasFlatAsRecordsValidate() public {
        // Baseline: nothing finished yet. Alice keeps this record assigned,
        // so it stays in the list as a constant one-entry overhead.
        vm.cool(address(sm));
        vm.prank(alice);
        uint256 g0 = gasleft();
        sm.assignBounty();
        uint256 baseline = g0 - gasleft();

        // Finish 100 records with fresh wallet pairs. Each pair creates one
        // record and validates it, so it should leave the list again.
        for (uint256 i = 1; i <= 100; ++i) _validate(i);
        assertEq(sm.validatedCount(), 100);
        assertEq(sm.activeRecordCount(), 1, "finished records should not linger");

        vm.cool(address(sm));
        vm.prank(bob);
        uint256 g1 = gasleft();
        sm.assignBounty();
        uint256 after100 = g1 - gasleft();

        emit log_named_uint("assign gas, 0 validated  ", baseline);
        emit log_named_uint("assign gas, 100 validated", after100);
        assertLt(after100, baseline * 3 / 2, "assignment cost grew with validated records");
    }
}
