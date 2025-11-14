// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ------------------------------------------------------------------------------|
// ------------  Chainlink Price Feed Interface ---------------------------------|
// This interface is used to get the latest price of the collateral asset        |
// Address: 0x694AA1769357215DE4FAC081bf1f309aDC325306
// Network: Ethereum Sepolia Testnet
// Pair: ETH/USD
// ------------------------------------------------------------------------------|
interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (uint80, int256 answer, uint256, uint256, uint80);
    function decimals() external view returns (uint8);
}

// --------------------------------------------------------------------------------------------------|
// ------------ MiniStableVault Contract ------------------------------------------------------------|
// MiniStableVault is a stablecoin that is backed by a collateral asset and minted as debt  ---------|
// This contract is for educational purposes only and is not suitable for production ----------------|
// --------------------------------------------------------------------------------------------------|
contract MiniStableVault is ERC20 {
    struct Position {
        address owner;
        uint256 collateralAmount;
        uint256 debt;
        bool open;
    }

    // -- state --
    AggregatorV3Interface public immutable priceFeed;

    //position storage
    uint256 public nextPositionId = 1;
    mapping(uint256 => Position) public positions;

    // HF required = 1.2 => 120% (scale 1e18)
    uint256 public minHF = 1.2e18;

    uint8 public oracleDecimals;

    // Events for CRE / Supabase Indexing
    event PositionOpened(
        uint256 indexed id,
        address indexed owner,
        uint256 collateralAmount,
        uint256 minted
    );
    event PositionClosed(uint256 indexed id, address indexed owner);
    event PositionLiquidated(uint256 indexed id, address indexed liquidator);

    constructor(address _priceFeed) ERC20("MiniUSD", "mUSD") {
        require(_priceFeed != address(0), "Invalid addresses");
        priceFeed = AggregatorV3Interface(_priceFeed);
        oracleDecimals = priceFeed.decimals();
    }

    // Get latest price of collateral in USD with priceFeedDecimals
    function _getLatestPrice() internal view returns (uint256 price) {
        (, int256 answer, , uint256 updatedAt, ) = priceFeed.latestRoundData();
        require(answer > 0 && updatedAt != 0, "invalid price");
        return uint256(answer);
    }

    function collateralUsd(uint256 amount) public view returns (uint256) {
        uint256 price = _getLatestPrice();
        // USD scaled 1e18;
        return (amount * price) / (10 ** oracleDecimals);
    }

    // Calculate how much ETH (in wei) is needed to mint a specific amount of stablecoin
    // @param mintAmount: Amount of stablecoin to mint (in 18 decimals, e.g., 1e18 for 1 USD)
    // @return: Amount of ETH needed in wei
    function ethNeededForMint(uint256 mintAmount) public view returns (uint256) {
        uint256 price = _getLatestPrice();
        
        // Calculate required collateral in USD (with minHF)
        // collateralUSD = mintAmount * minHF / 1e18
        uint256 collateralUsdNeeded = (mintAmount * minHF) / 1e18;
        
        // Convert USD to ETH: ETH = (USD * 10^oracleDecimals * 1e18) / price
        // Result in wei (18 decimals)
        return (collateralUsdNeeded * (10 ** oracleDecimals) * 1e18) / price;
    }

    function healthFactor(uint256 id) public view returns (uint256) {
        Position memory pos = positions[id];
        if (!pos.open || pos.debt == 0) return type(uint256).max;
        uint256 usd = collateralUsd(pos.collateralAmount);
        return (usd * 1e18) / pos.debt;
    }

    // --- core actions ---
    // user approve collateral first
    function openPosition(
        uint256 mintAmount
    ) external payable returns (uint256 id) {
        require(msg.value > 0, "no collateral");
        require(mintAmount > 0, "No Mint");

        // check collateralization
        uint256 usd = collateralUsd(msg.value);
        require((usd * 1e18) / mintAmount >= minHF, "insufficient collateral");

        id = nextPositionId++;
        positions[id] = Position(msg.sender, msg.value, mintAmount, true);

        _mint(msg.sender, mintAmount);

        emit PositionOpened(id, msg.sender, msg.value, mintAmount);
    }

    // Check if a position needs to be liquidated
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

    // anyone can liquidate if HF < minHF
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

    // withdraw collateral after debt is cleared
    function withdraw(uint256 id) external {
        Position storage pos = positions[id];
        require(pos.open == false, "Position still open");
        require(pos.owner == msg.sender, "Only owner can withdraw");
        uint256 amount = pos.collateralAmount;
        pos.collateralAmount = 0;
        payable(msg.sender).transfer(amount);
    }
}
