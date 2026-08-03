// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CampaignToken} from "../src/CampaignToken.sol";

contract CampaignTokenTest is Test {
    CampaignToken token;

    address owner   = address(0xA11CE);
    address minter  = address(0x1);
    address burner  = address(0x2);
    address alice   = address(0xAA);
    address bob     = address(0xBB);

    function setUp() public {
        token = new CampaignToken("USC1850", "USC1850", owner);
    }

    function test_ConstructorSetsMetadata() public view {
        assertEq(token.name(), "USC1850");
        assertEq(token.symbol(), "USC1850");
        assertEq(token.owner(), owner);
    }

    function test_OwnerSetsMinter() public {
        vm.prank(owner);
        token.setMinter(minter);
        assertEq(token.minter(), minter);
    }

    function test_MinterCannotBeSetTwice() public {
        vm.prank(owner);
        token.setMinter(minter);
        vm.prank(owner);
        vm.expectRevert(CampaignToken.AlreadySet.selector);
        token.setMinter(address(0x9));
    }

    function test_OwnerSetsBurner() public {
        vm.prank(owner);
        token.setBurner(burner);
        assertEq(token.burner(), burner);
    }

    function test_OnlyMinterCanMint() public {
        vm.prank(owner);
        token.setMinter(minter);

        vm.prank(minter);
        token.mint(alice, 100);
        assertEq(token.balanceOf(alice), 100);

        vm.prank(alice);
        vm.expectRevert(CampaignToken.NotMinter.selector);
        token.mint(alice, 100);
    }

    function test_OnlyBurnerCanBurn() public {
        vm.prank(owner);
        token.setMinter(minter);
        vm.prank(minter);
        token.mint(alice, 100);

        vm.prank(owner);
        token.setBurner(burner);

        vm.prank(alice);
        vm.expectRevert(CampaignToken.NotBurner.selector);
        token.burnFrom(alice, 50);

        vm.prank(burner);
        token.burnFrom(alice, 50);
        assertEq(token.balanceOf(alice), 50);
    }

    function test_Transferable() public {
        vm.prank(owner);
        token.setMinter(minter);
        vm.prank(minter);
        token.mint(alice, 100);

        vm.prank(alice);
        token.transfer(bob, 40);
        assertEq(token.balanceOf(bob), 40);
        assertEq(token.balanceOf(alice), 60);
    }
}
