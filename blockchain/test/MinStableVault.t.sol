// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {MiniStableVault} from "../src/MinStableVault.sol";

// ==============================================================================
// Mock Price Feed Contract
// ==============================================================================
contract MockPriceFeed {
    int256 public price;
    uint8 public constant decimals = 8;
    uint256 public updatedAt;

    constructor(int256 _price) {
        price = _price;
        updatedAt = block.timestamp;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 _updatedAt, uint80 answeredInRound)
    {
        return (1, price, block.timestamp, updatedAt, 1);
    }

    function setPrice(int256 _price) external {
        price = _price;
        updatedAt = block.timestamp;
    }
}

// ==============================================================================
// Test Contract
// ==============================================================================
contract MinStableVaultTest is Test {
    MiniStableVault public vault;
    MockPriceFeed public priceFeed;

    /// @dev helper to mirror ethNeededForMint math (includes minHF)
    function _expectedEthNeeded(uint256 usdAmount) internal view returns (uint256) {
        uint256 price = uint256(priceFeed.price());
        uint256 oracleDecimals = priceFeed.decimals();
        uint256 mintAmount = usdAmount * 1e18;
        uint256 collateralUsdNeeded = (mintAmount * vault.minHF()) / 1e18;
        return (collateralUsdNeeded * (10 ** oracleDecimals)) / price;
    }

    // Test constants
    uint256 public constant ETH_PRICE_USD = 3100; // $3100 per ETH
    uint256 public constant ETH_PRICE_8_DECIMALS = 3100 * 1e8; // Price with 8 decimals
    uint256 public constant ONE_ETH = 1 ether;
    uint256 public constant ONE_USD = 1 ether; // 1 USD in token decimals

    address public user = address(0x1);
    address public liquidator = address(0x2);

    function setUp() public {
        // Deploy mock price feed with ETH price of $3100
        priceFeed = new MockPriceFeed(int256(ETH_PRICE_8_DECIMALS));

        // Deploy vault
        vault = new MiniStableVault(address(priceFeed));

        // Give users some ETH
        vm.deal(user, 100 ether);
        vm.deal(liquidator, 100 ether);
    }

    // ========================================================================
    // Price Calculation Tests
    // ========================================================================

    function test_CollateralUsd_1ETH_Returns3100USD() public view {
        // 1 ETH should be worth $3100 USD
        uint256 usdValue = vault.collateralUsd(ONE_ETH);
        // 1 ether * 3100e8 / 1e8 = 3100 ether
        uint256 expected = 3100 * ONE_ETH;
        assertEq(usdValue, expected, "1 ETH should be worth $3100 USD");
    }

    function test_CollateralUsd_0_1ETH_Returns310USD() public view {
        // 0.1 ETH should be worth $310 USD
        uint256 ethAmount = 0.1 ether; // 0.1 * 1e18
        uint256 usdValue = vault.collateralUsd(ethAmount);
        
        // Expected: 0.1e18 * 3100e8 / 1e8 = 310e18
        uint256 expected = 310 * 1e18;
        assertEq(usdValue, expected, "0.1 ETH should be worth $310 USD");
    }

    function test_EthNeededForMint_1USD_ReturnsValue() public view {
        // To mint 1 USD, we need enough ETH for 1.2 USD (minHF = 1.2)
        uint256 ethNeeded = vault.ethNeededForMint(1); // 1 USD (human-readable)

        uint256 expected = _expectedEthNeeded(1);
        assertEq(ethNeeded, expected, "ETH needed should include minHF");
    }

    function test_EthNeededForMint_100USD_ReturnsValue() public view {
        // To mint 100 USD (human-readable)
        uint256 ethNeeded = vault.ethNeededForMint(100);
        
        uint256 expected = _expectedEthNeeded(100);
        assertEq(ethNeeded, expected, "ETH needed should include minHF");
    }

    // ========================================================================
    // Minting Tests
    // ========================================================================

    function test_OpenPosition_Mint1USD_WithSufficientCollateral() public {
        vm.startPrank(user);

        // For 1 USD, we need collateral worth 1.2 USD (minHF = 1.2)
        // 1.2 USD / $3100 per ETH = 0.000387096... ETH
        uint256 ethToDeposit = 0.001 ether; // 0.001 ETH should be enough for 1 USD

        // Open position with 1 USD (human-readable)
        uint256 positionId = vault.openPosition{value: ethToDeposit}(1);

        // Verify position was created
        assertEq(positionId, 1, "Position ID should be 1");
        assertEq(vault.balanceOf(user), ONE_USD, "User should have 1 mUSD");
        
        // Verify position data
        (address owner, uint256 collateral, uint256 debt, bool isOpen) = vault.positions(positionId);
        assertEq(owner, user, "Owner should be user");
        assertEq(collateral, ethToDeposit, "Collateral should match deposited amount");
        assertEq(debt, ONE_USD, "Debt should be 1 USD");
        assertTrue(isOpen, "Position should be open");

        vm.stopPrank();
    }

    function test_OpenPosition_Mint100USD_WithSufficientCollateral() public {
        vm.startPrank(user);

        // For 100 USD, we need collateral worth 120 USD
        // 120 USD / $3100 per ETH = ~0.0387 ETH
        uint256 ethToDeposit = 0.05 ether; // 0.05 ETH should be enough

        // Open position with 100 USD (human-readable)
        uint256 positionId = vault.openPosition{value: ethToDeposit}(100);

        assertEq(vault.balanceOf(user), 100 * ONE_USD, "User should have 100 mUSD");
        (,, uint256 debt,) = vault.positions(positionId);
        assertEq(debt, 100 * ONE_USD, "Debt should be 100 USD");

        vm.stopPrank();
    }

    function test_OpenPosition_InsufficientCollateral_Reverts() public {
        vm.startPrank(user);

        uint256 insufficientEth = 0.001 ether; // Very little ETH

        vm.expectRevert("insufficient collateral");
        vault.openPosition{value: insufficientEth}(1000); // Try to mint 1000 USD

        vm.stopPrank();
    }

    // ========================================================================
    // Health Factor Tests
    // ========================================================================

    function test_HealthFactor_NewPosition_ShouldBeAboveMin() public {
        vm.startPrank(user);

        uint256 ethToDeposit = 0.001 ether; // Enough for 1 USD

        uint256 positionId = vault.openPosition{value: ethToDeposit}(1); // 1 USD

        uint256 hf = vault.healthFactor(positionId);
        uint256 minHF = vault.minHF();

        assertGe(hf, minHF, "Health factor should be >= minimum");

        vm.stopPrank();
    }

    function test_HealthFactor_AfterPriceDrop_ShouldDecrease() public {
        vm.startPrank(user);

        // Open position with 1 USD debt
        uint256 ethToDeposit = 0.001 ether; // Enough for 1 USD

        uint256 positionId = vault.openPosition{value: ethToDeposit}(1); // 1 USD
        uint256 hfBefore = vault.healthFactor(positionId);

        // Drop price by 70% (from $3100 to $930) to make it unhealthy
        priceFeed.setPrice(int256(ETH_PRICE_8_DECIMALS * 30 / 100));
        
        uint256 hfAfter = vault.healthFactor(positionId);

        assertLt(hfAfter, hfBefore, "Health factor should decrease after price drop");
        assertLt(hfAfter, vault.minHF(), "Health factor should be below minimum after 70% price drop");

        vm.stopPrank();
    }

    // ========================================================================
    // Liquidation Tests
    // ========================================================================

    function test_NeedsLiquidation_HealthyPosition_ReturnsFalse() public {
        vm.startPrank(user);

        uint256 ethToDeposit = 0.001 ether; // Enough for 1 USD

        uint256 positionId = vault.openPosition{value: ethToDeposit}(1); // 1 USD

        assertFalse(vault.needsLiquidation(positionId), "Healthy position should not need liquidation");

        vm.stopPrank();
    }

    function test_NeedsLiquidation_UnhealthyPosition_ReturnsTrue() public {
        vm.startPrank(user);

        // Open position
        uint256 ethToDeposit = 0.001 ether; // Enough for 1 USD

        uint256 positionId = vault.openPosition{value: ethToDeposit}(1); // 1 USD

        // Drop price by 70% to make it unhealthy
        priceFeed.setPrice(int256(ETH_PRICE_8_DECIMALS * 30 / 100));

        assertTrue(vault.needsLiquidation(positionId), "Unhealthy position should need liquidation");

        vm.stopPrank();
    }

    function test_Liquidate_UnhealthyPosition_Succeeds() public {
        vm.startPrank(user);

        // Open position
        uint256 ethToDeposit = 0.001 ether; // Enough for 1 USD

        uint256 positionId = vault.openPosition{value: ethToDeposit}(1); // 1 USD

        vm.stopPrank();

        // Liquidator opens position first (before price drop)
        vm.startPrank(liquidator);
        vault.openPosition{value: 1 ether}(100); // 100 USD
        vm.stopPrank();

        // Now drop price by 70% to make position unhealthy
        priceFeed.setPrice(int256(ETH_PRICE_8_DECIMALS * 30 / 100));

        // Liquidator liquidates
        vm.startPrank(liquidator);
        vault.liquidate(positionId);

        (,, uint256 debtAfter, bool isOpenAfter) = vault.positions(positionId);
        assertFalse(isOpenAfter, "Position should be closed after liquidation");
        assertEq(debtAfter, 0, "Debt should be cleared");

        vm.stopPrank();
    }

    // ========================================================================
    // Edge Cases
    // ========================================================================

    function test_OpenPosition_ZeroValue_Reverts() public {
        vm.startPrank(user);
        vm.expectRevert("no collateral");
        vault.openPosition{value: 0}(1); // 1 USD
        vm.stopPrank();
    }

    function test_OpenPosition_ZeroMintAmount_Reverts() public {
        vm.startPrank(user);
        vm.expectRevert("No Mint");
        vault.openPosition{value: 1 ether}(0);
        vm.stopPrank();
    }
}
