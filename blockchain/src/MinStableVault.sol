// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80, int256 answer, uint256, uint256, uint80
    );
    function decimals() external view returns(uint8);
}

contract MiniStableVault is ERC20 {
  using SafeERC20 for IERC20;

  struct Position {
    address owner;
    uint256 collateralAmount;
    uint256 debt;
    bool open;
  }

  // -- state --
  IERC20 public immutable collateral;
  AggregatorV3Interface public immutable priceFeed;

  //position storage
  uint256 public nextPositionId = 1;
  mapping(uint256 => Position) public positions;

  // HF required = 1.2 => 120% (scale 1e18)
  uint256 public minHF = 1.2e18;

  uint8 public collateralDecimals;
  uint8 public oracleDecimals;

  // Events for CRE / Supabase Indexing
  event PositionOpened(uint256 indexed id, address indexed owner, uint256 collateralAmount, uint256 minted);
  event PositionLiquidated(uint256 indexed id, address indexed liquidator);

  constructor(
    address _collateral,
    address _priceFeed
  ) ERC20("MiniUSD", "mUSD") {
    require(_collateral != address(0) && _priceFeed != address(0), "Invalid addresses");
    collateral = IERC20(_collateral);
    priceFeed = AggregatorV3Interface(_priceFeed);

    collateralDecimals = 18;
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
    return amount * price * 1e18;
  }

  function healthFactor(uint256 id) public view returns(uint256) {
    Position memory pos = positions[id];
    if(!pos.open || pos.debt == 0) return type(uint256).max;
    uint256 usd = collateralUsd(pos.collateralAmount);
    return usd * 1e18 / pos.debt;
  }

  // --- core actions ---

  // user approve collateral first
  function openPosition(uint256 collateralAmount, uint256 mintAmount) external returns (uint256 id){
    require(collateralAmount > 0, "no collateral");
    require(mintAmount > 0, "No Mint");

    collateral.transferFrom(msg.sender, address(this), collateralAmount);

    // check collateralization
    uint256 usd = collateralUsd(collateralAmount);
    require((usd * 1e18) / mintAmount >= minHF, "insufficient collateral");

    id = nextPositionId++;
    positions[id] = Position(msg.sender, collateralAmount, mintAmount, true);

    _mint(msg.sender, mintAmount);
    
    emit PositionOpened(id, msg.sender, collateralAmount, mintAmount);
  }
  // ANYONE can liquidate 
  function liquidate(uint256 id) external {
    Position storage pos = positions[id];
    require(pos.open, "Position closed");
    require(healthFactor(id) < minHF, "Position healthy");

    pos.open = false;

    // collateral stays in contract (simple demo - we should sell it)
    // debt is simply removed -> burn caller's stablecoins
    _transfer(msg.sender, address(this), pos.debt);
    _burn(address(this), pos.debt);

    emit PositionLiquidated(id, msg.sender);
  } 
}