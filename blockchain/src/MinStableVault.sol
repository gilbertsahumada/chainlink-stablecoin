// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ==============================================================================
// Chainlink Price Feed Interface
// ==============================================================================
// This interface is used to get the latest price of the collateral asset (ETH)
//
// Oracle Details:
//   - Address: 0x694AA1769357215DE4FAC081bf1f309aDC325306
//   - Network: Ethereum Sepolia Testnet
//   - Pair: ETH/USD
//   - Decimals: 8
// ==============================================================================
interface AggregatorV3Interface {
    function latestRoundData() external view returns (uint80, int256 answer, uint256, uint256, uint80);
    function decimals() external view returns (uint8);
}

// ==============================================================================
// MiniStableVault Contract
// ==============================================================================
// A stablecoin (mUSD) that is backed by ETH collateral and minted as debt.
// Users can deposit ETH as collateral and mint stablecoins up to a certain
// collateralization ratio (minimum health factor of 1.2 = 120%).
//
// WARNING: This contract is for educational/demo purposes only and is NOT
//          suitable for production use.
// ==============================================================================
contract MiniStableVault is ERC20 {
    struct Position {
        address owner;
        uint256 collateralAmount;
        uint256 debt;
        bool open;
    }

    // ========================================================================
    // State Variables
    // ========================================================================

    /// @notice Chainlink price feed for ETH/USD
    AggregatorV3Interface public immutable priceFeed;

    /// @notice Next position ID to be assigned
    uint256 public nextPositionId = 1;

    /// @notice Mapping of position ID to Position struct
    mapping(uint256 => Position) public positions;

    /// @notice Minimum health factor required (1.2 = 120% collateralization)
    /// @dev Scaled by 1e18 (1.2e18 = 120%)
    uint256 public minHF = 1.2e18;

    /// @notice Number of decimals used by the price feed oracle
    uint8 public oracleDecimals;

    /// @notice Mock price mode (for workshop/demo purposes)
    bool public mockPriceEnabled;

    /// @notice Mock price value (with oracle decimals)
    uint256 public mockPrice;

    // ========================================================================
    // Events
    // ========================================================================

    /// @notice Emitted when a new position is opened
    event PositionOpened(uint256 indexed id, address indexed owner, uint256 collateralAmount, uint256 minted);
    /// @notice Emitted when a position is closed by the owner
    event PositionClosed(uint256 indexed id, address indexed owner);

    /// @notice Emitted when a position is liquidated
    event PositionLiquidated(uint256 indexed id, address indexed liquidator);

    /// @notice Emitted when mock price is enabled/disabled
    event MockPriceToggled(bool enabled, uint256 price);

    constructor(address _priceFeed) ERC20("MiniUSD", "mUSD") {
        require(_priceFeed != address(0), "Invalid addresses");
        priceFeed = AggregatorV3Interface(_priceFeed);
        oracleDecimals = priceFeed.decimals();
    }

    // ========================================================================
    // Internal Helper Functions
    // ========================================================================

    /// @notice Get the latest price from Chainlink oracle or mock price if enabled
    /// @return price The price in USD with oracle decimals (typically 8)
    function _getLatestPrice() internal view returns (uint256 price) {
        // If mock price is enabled, return the mock price
        if (mockPriceEnabled) {
            require(mockPrice > 0, "mock price not set");
            return mockPrice;
        }

        // Otherwise, get price from oracle
        (, int256 answer,, uint256 updatedAt,) = priceFeed.latestRoundData();
        require(answer > 0 && updatedAt != 0, "invalid price");
        return uint256(answer);
    }

    /// @notice Calculate the USD value of a given amount of ETH
    /// @param amount Amount of ETH in wei (18 decimals)
    /// @return The USD value scaled by 1e18
    function collateralUsd(uint256 amount) public view returns (uint256) {
        uint256 price = _getLatestPrice();
        // Convert: (ETH in wei * price with oracle decimals) / oracle decimals
        // Result is in USD with 18 decimals
        return (amount * price) / (10 ** oracleDecimals);
    }

    /// @notice Calculate how much ETH (in wei) is needed to mint a specific amount of stablecoin
    /// @param usdAmount Amount of stablecoin to mint in USD (e.g., 10 for 10 USD, will be converted to 10e18 internally)
    /// @return Amount of ETH needed in wei to meet the minimum health factor requirement
    function ethNeededForMint(uint256 usdAmount) public view returns (uint256) {
        uint256 price = _getLatestPrice();

        // Convert human-readable USD amount to wei (10 USD = 10e18 wei)
        uint256 mintAmount = usdAmount * 1e18;

        // Calculate required collateral in USD (with minHF)
        // collateralUSD = mintAmount * minHF / 1e18
        uint256 collateralUsdNeeded = (mintAmount * minHF) / 1e18;

        // Convert USD to ETH: ETH = (USD * 10^oracleDecimals * 1e18) / price
        // Result in wei (18 decimals)
        return (collateralUsdNeeded * (10 ** oracleDecimals) * 1e18) / price;
    }

    /// @notice Calculate the health factor of a position
    /// @param id Position ID
    /// @return Health factor scaled by 1e18 (1.2e18 = 120%). Returns max uint256 if position is closed or has no debt
    function healthFactor(uint256 id) public view returns (uint256) {
        Position memory pos = positions[id];
        if (!pos.open || pos.debt == 0) return type(uint256).max;
        uint256 usd = collateralUsd(pos.collateralAmount);
        return (usd * 1e18) / pos.debt;
    }

    // ========================================================================
    // Mock Price Functions (for workshop/demo)
    // ========================================================================

    /// @notice Enable mock price mode and set a custom price
    /// @dev This is for workshop/demo purposes to simulate price changes
    /// @param _price Price in USD with oracle decimals (e.g., 1550e8 for $1550)
    function enableMockPrice(uint256 _price) external {
        require(_price > 0, "price must be > 0");
        mockPrice = _price;
        mockPriceEnabled = true;
        emit MockPriceToggled(true, _price);
    }

    /// @notice Disable mock price mode and return to using real oracle
    function disableMockPrice() external {
        mockPriceEnabled = false;
        emit MockPriceToggled(false, 0);
    }

    /// @notice Update mock price while mock mode is enabled
    /// @param _price New price in USD with oracle decimals
    function setMockPrice(uint256 _price) external {
        require(mockPriceEnabled, "mock price not enabled");
        require(_price > 0, "price must be > 0");
        mockPrice = _price;
        emit MockPriceToggled(true, _price);
    }

    // ========================================================================
    // Core Functions
    // ========================================================================

    /// @notice Open a new position by depositing ETH as collateral and minting stablecoins
    /// @dev User must send ETH as msg.value. The amount must meet the minimum health factor.
    /// @param usdAmount Amount of stablecoins to mint in USD (e.g., 20 for 20 USD, will be converted to 20e18 internally)
    /// @return id The ID of the newly created position
    function openPosition(uint256 usdAmount) external payable returns (uint256 id) {
        require(msg.value > 0, "no collateral");
        require(usdAmount > 0, "No Mint");

        // Convert human-readable USD amount to wei (20 USD = 20e18 wei)
        uint256 mintAmount = usdAmount * 1e18;

        // check collateralization
        uint256 usd = collateralUsd(msg.value);
        require((usd * 1e18) / mintAmount >= minHF, "insufficient collateral");

        id = nextPositionId++;
        positions[id] = Position(msg.sender, msg.value, mintAmount, true);

        _mint(msg.sender, mintAmount);

        emit PositionOpened(id, msg.sender, msg.value, mintAmount);
    }

    /// @notice Check if a position needs to be liquidated
    /// @param id Position ID
    /// @return true if the position's health factor is below the minimum threshold
    function needsLiquidation(uint256 id) external view returns (bool) {
        Position memory pos = positions[id];

        // If position is closed, it doesn't need liquidation
        if (!pos.open) {
            return false;
        }

        // If position has no debt, it doesn't need liquidation
        if (pos.debt == 0) {
            return false;
        }

        // Check if health factor is below minimum
        uint256 hf = healthFactor(id);
        return hf < minHF;
    }

    /// @notice Close a position by burning the debt and returning the collateral
    /// @dev Position must be healthy (HF >= minHF) and caller must be the owner
    /// @param id Position ID to close
    function closePosition(uint256 id) external {
        Position storage pos = positions[id];
        require(pos.open, "Position closed");
        require(pos.owner == msg.sender, "Only owner can close");
        require(healthFactor(id) >= minHF, "Position unhealthy");

        uint256 debt = pos.debt;
        uint256 collateral = pos.collateralAmount;
        require(balanceOf(msg.sender) >= debt, "Insufficient balance");

        pos.open = false;
        pos.collateralAmount = 0;

        // Burn debt
        _burn(msg.sender, debt);

        // Transfer collateral to owner
        payable(msg.sender).transfer(collateral);

        emit PositionClosed(id, msg.sender);
    }

    /// @notice Liquidate a position that is below the minimum health factor
    /// @dev Anyone can call this function. The liquidator burns their stablecoins to pay the debt.
    ///      The collateral remains in the contract and can be withdrawn by the position owner.
    /// @param id Position ID to liquidate
    function liquidate(uint256 id) external {
        Position storage pos = positions[id];
        require(pos.open, "Position closed");
        require(healthFactor(id) < minHF, "Position healthy");

        uint256 debt = pos.debt;
        require(balanceOf(msg.sender) >= pos.debt, "Insufficient balance");

        pos.open = false;
        pos.debt = 0;

        // Burn the liquidator's stablecoins to pay for the debt
        _burn(msg.sender, debt);
        emit PositionLiquidated(id, msg.sender);
    }

    /// @notice Withdraw collateral after a position has been liquidated
    /// @dev Only the position owner can withdraw. Position must be closed (liquidated).
    /// @param id Position ID to withdraw collateral from
    function withdraw(uint256 id) external {
        Position storage pos = positions[id];
        require(pos.open == false, "Position still open");
        require(pos.owner == msg.sender, "Only owner can withdraw");
        uint256 amount = pos.collateralAmount;
        pos.collateralAmount = 0;
        payable(msg.sender).transfer(amount);
    }
}
