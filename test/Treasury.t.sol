// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Treasury} from "../src/Treasury.sol";

contract MockUSDC {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract TreasuryTest is Test {
    MockUSDC usdc;
    Treasury treasury;
    address agent = address(0xA11CE);
    address vendor = address(0xBEEF);
    address attacker = address(0xBAD);
    bytes32 inv1 = keccak256("INV-001");
    bytes32 inv2 = keccak256("INV-002");

    function setUp() public {
        usdc = new MockUSDC();
        treasury = new Treasury(address(usdc), agent, 1_000e6);
        usdc.mint(address(treasury), 10_000e6);
        treasury.setVendor(vendor, 500e6);
    }

    function test_paysApprovedVendor() public {
        vm.prank(agent);
        treasury.pay(vendor, 200e6, inv1);
        assertEq(usdc.balanceOf(vendor), 200e6);
        assertTrue(treasury.invoicePaid(inv1));
    }

    function test_revertsUnapprovedVendor() public {
        vm.prank(agent);
        vm.expectRevert(Treasury.VendorNotApproved.selector);
        treasury.pay(attacker, 1e6, inv1);
    }

    function test_revertsOverVendorCap() public {
        vm.prank(agent);
        vm.expectRevert(Treasury.OverVendorCap.selector);
        treasury.pay(vendor, 501e6, inv1);
    }

    function test_revertsDuplicateInvoice() public {
        vm.startPrank(agent);
        treasury.pay(vendor, 100e6, inv1);
        vm.expectRevert(Treasury.InvoiceAlreadyPaid.selector);
        treasury.pay(vendor, 100e6, inv1);
        vm.stopPrank();
    }

    function test_dailyCapBlocksThenResetsNextDay() public {
        treasury.setVendor(vendor, 1_000e6);
        vm.startPrank(agent);
        treasury.pay(vendor, 900e6, inv1);
        vm.expectRevert(Treasury.OverDailyCap.selector);
        treasury.pay(vendor, 200e6, inv2);
        vm.warp(block.timestamp + 1 days);
        treasury.pay(vendor, 200e6, inv2);
        vm.stopPrank();
        assertEq(usdc.balanceOf(vendor), 1_100e6);
    }

    function test_onlyAgentCanPay() public {
        vm.prank(attacker);
        vm.expectRevert(Treasury.NotAgent.selector);
        treasury.pay(vendor, 1e6, inv1);
    }

    function test_agentCannotApproveVendors() public {
        vm.prank(agent);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.setVendor(attacker, 1_000e6);
    }

    function test_pauseBlocksPay() public {
        treasury.setPaused(true);
        vm.prank(agent);
        vm.expectRevert(Treasury.ContractPaused.selector);
        treasury.pay(vendor, 1e6, inv1);
    }

    function test_zeroAmountReverts() public {
        vm.prank(agent);
        vm.expectRevert(Treasury.ZeroAmount.selector);
        treasury.pay(vendor, 0, inv1);
    }

    function test_insufficientBalanceReverts() public {
        Treasury empty = new Treasury(address(usdc), agent, 1_000e6);
        empty.setVendor(vendor, 500e6);
        vm.prank(agent);
        vm.expectRevert(Treasury.TransferFailed.selector);
        empty.pay(vendor, 10e6, inv1);
    }
}
