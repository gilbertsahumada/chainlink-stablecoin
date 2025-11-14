// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80, int256 answer, uint256, uint256, uint80
    );
    function decimals() external view returns(uint8);
}

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
  event PositionOpened(uint256 indexed id, address indexed owner, uint256 collateralAmount, uint256 minted);
  event PositionClosed(uint256 indexed id, address indexed owner);
  event PositionLiquidated(uint256 indexed id, address indexed liquidator);

  constructor(
    address _priceFeed
  ) ERC20("MiniUSD", "mUSD") {
    require(_priceFeed != address(0), "Invalid addresses");
    priceFeed = AggregatorV3Interface(_priceFeed);
    oracleDecimals = priceFeed.decimals();
  }

  // -------------------
  // ---- Utilities ----
  // -------------------

  // Get latest price of collateral in USD with priceFeedDecimals
  function _getLatestPrice() internal view returns (uint256 price) {
    (, int256 answer, , uint256 updatedAt, ) = priceFeed.latestRoundData();
    require(answer > 0 && updatedAt != 0, "invalid price");
    return uint256(answer);
  }

  function collateralUsd(uint256 amount) public view returns (uint256) {
    uint256 price = _getLatestPrice();
    // USD scaled 1e18;
    return amount * price * 1e18 / (10**18) / (10**oracleDecimals);
  }

  function healthFactor(uint256 id) public view returns(uint256) {
    Position memory pos = positions[id];
    if(!pos.open || pos.debt == 0) return type(uint256).max;
    uint256 usd = collateralUsd(pos.collateralAmount);
    return usd * 1e18 / pos.debt;
  }

  // --- core actions ---

  // user approve collateral first
  function openPosition(uint256 mintAmount) external payable returns (uint256 id){
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

  function closePosition(uint256 id) external {
    Position storage pos = positions[id];
    require(pos.open, "Position closed");
    require(pos.owner == msg.sender, "Only owner can close");
    require(healthFactor(id) >= minHF, "Position unhealthy");

    uint256 debt = pos.debt;
    require(balanceOf(msg.sender) >= debt, "Insufficient balance");

    pos.open = false;
    pos.collateralAmount = 0;

    // Burn debt
    _burn(msg.sender, debt);

    // Transfer collateral to owner
    payable(msg.sender).transfer(pos.collateralAmount);

    emit PositionClosed(id, msg.sender);
  }

  // anyone can liquidate if HF < minHF
  function liquidate(uint256 id) external {
    Position storage pos = positions[id];
    require(pos.open, "Position closed");
    require(healthFactor(id) < minHF, "Position healthy");

    pos.open = false;

    // debt is simply removed -> burn caller's stablecoins
    _transfer(msg.sender, address(this), pos.debt);
    _burn(address(this), pos.debt);

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