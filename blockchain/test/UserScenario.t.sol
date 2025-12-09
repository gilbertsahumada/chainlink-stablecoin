// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {MiniStableVault} from "../src/MinStableVault.sol";
import {MockPriceFeed} from "./MinStableVault.t.sol"; // Reusing MockPriceFeed from existing test

contract UserScenarioTest is Test {
    MiniStableVault public vault;
    MockPriceFeed public priceFeed;

    address public user = address(0x123);

    // Test Parameters
    // ETH Price = $1,000
    // Target Mint = 1,000 mUSD
    // Required Collateral Rato = 120%
    // Required Collateral Value = $1,200
    // Required ETH Amount = 1.2 ETH (at $1,000/ETH)

    int256 public constant ETH_PRICE_USD = 1000;
    int256 public constant ETH_PRICE_8_DECIMALS = 1000 * 1e8;

    function setUp() public {
        // Deploy mock price feed with ETH price of $1,000
        priceFeed = new MockPriceFeed(ETH_PRICE_8_DECIMALS);

        // Deploy vault
        vault = new MiniStableVault(address(priceFeed));

        // Give user enough ETH
        vm.deal(user, 100 ether);
    }

    function test_Scenario_Mint1000mUSD_With1point2ETH() public {
        vm.startPrank(user);

        // 1. Setup variables
        uint256 depositAmount = 1.2 ether; // 1.2 ETH
        uint256 mintAmount = 1000; // 1,000 mUSD (human readable input to contract)

        // 2. Open position
        vault.openPosition{value: depositAmount}(mintAmount);

        // 3. Verify balances
        uint256 userBalance = vault.balanceOf(user);
        assertEq(userBalance, 1000 * 1e18, "User should have 1000 mUSD");

        // 4. Verify position health
        // Collateral Value = 1.2 ETH * $1000 = $1,200
        // Debt = $1,000
        // Ratio = 1200 / 1000 = 1.2 = 120%
        // The contract uses 1e18 scale for health check.
        // openPosition checks: (collateralValue * 1e18) / mintAmountWei >= minHF
        // (1200 * 1e18 * 1e18) / (1000 * 1e18) = 1.2 * 1e18.
        // This is EXACTLY equal to minHF (1.2e18).

        // Let's verify we got the ID 1
        (address owner, uint256 collateral, uint256 debt, bool isOpen) = vault
            .positions(1);
        assertEq(owner, user);
        assertEq(collateral, depositAmount);
        assertEq(debt, 1000 * 1e18);
        assertTrue(isOpen);

        vm.stopPrank();
    }

    function test_Scenario_CannotMint_WithLessCollateral() public {
        vm.startPrank(user);

        // Try with slightly less than 1.2 ETH
        // 1.199 ETH * $1000 = $1,199 Collateral Value
        // Required for $1,000 debt is $1,200
        uint256 depositAmount = 1.199 ether;
        uint256 mintAmount = 1000;

        vm.expectRevert("insufficient collateral");
        vault.openPosition{value: depositAmount}(mintAmount);

        vm.stopPrank();
    }

    function test_Refactor_OpenPosition_UsesEthNeeded() public {
        vm.startPrank(user);

        uint256 mintAmount = 1000; // 1000 USD
        uint256 requiredEth = vault.ethNeededForMint(mintAmount);

        // Should succeed with exactly the required amount
        vault.openPosition{value: requiredEth}(mintAmount);

        assertEq(vault.balanceOf(user), 1000 * 1e18);
        vm.stopPrank();
    }

    function test_Refactor_OpenPosition_RevertsIfLess() public {
        vm.startPrank(user);

        uint256 mintAmount = 1000; // 1000 USD
        uint256 requiredEth = vault.ethNeededForMint(mintAmount);

        // Should revert with 1 wei less
        vm.expectRevert("insufficient collateral");
        vault.openPosition{value: requiredEth - 1}(mintAmount);

        vm.stopPrank();
    }
}
