// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./PriceOracle.sol";

contract LendingPool is Ownable, ReentrancyGuard {
    struct Position {
        uint256 collateral; // ETH amount in wei
        uint256 debt; // USD amount (18 decimals)
    }

    struct CollateralConfig {
        bool isSupported;
        uint256 liquidationThreshold; // In basis points (8000 = 80%)
        uint256 liquidationPenalty; // In basis points (1000 = 10%)
    }

    mapping(address => Position) public positions;
    mapping(address => CollateralConfig) public collateralConfigs;

    PriceOracle public immutable priceOracle;
    IERC20 public immutable usdcToken;

    uint256 public constant PRECISION = 10000; // 100.00%
    uint256 public constant HEALTH_FACTOR_PRECISION = 100;
    uint256 public nextPositionId = 1;

    event Deposit(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 amount);
    event Liquidation(
        address indexed user,
        address indexed liquidator,
        uint256 collateralSeized,
        uint256 debtRepaid
    );

    error LendingPool__CollateralNotSupported();
    error LendingPool__InsufficientCollateral();
    error LendingPool__PositionNotLiquidatable();
    error LendingPool__PositionHealthy();

    constructor(address _priceOracle, address _usdcToken) Ownable(msg.sender) {
        priceOracle = PriceOracle(_priceOracle);
        usdcToken = IERC20(_usdcToken);
    }

    modifier onlyLiquidator() {
        // In production, this would check for authorized liquidators
        _;
    }

    function addCollateralSupport(
        address asset,
        uint256 liquidationThreshold,
        uint256 liquidationPenalty
    ) external onlyOwner {
        collateralConfigs[asset] = CollateralConfig({
            isSupported: true,
            liquidationThreshold: liquidationThreshold,
            liquidationPenalty: liquidationPenalty
        });
    }

    function deposit() external payable nonReentrant {
        require(msg.value > 0, "Must deposit something");
        require(collateralConfigs[address(0)].isSupported, "ETH not supported");

        positions[msg.sender].collateral += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function borrow(uint256 amount) external nonReentrant {
        require(amount > 0, "Must borrow something");

        positions[msg.sender].debt += amount;

        // Check health factor after borrowing
        require(
            getHealthFactor(msg.sender) >= HEALTH_FACTOR_PRECISION,
            "Insufficient collateral"
        );

        // Transfer USDC to borrower
        require(usdcToken.transfer(msg.sender, amount), "Transfer failed");
        emit Borrow(msg.sender, amount);
    }

    function getHealthFactor(address user) public view returns (uint256) {
        Position memory pos = positions[user];
        if (pos.debt == 0) return type(uint256).max;

        // Get ETH price from oracle (assuming ETH address is address(0))
        uint256 ethPrice = priceOracle.getPrice(address(0));
        CollateralConfig memory config = collateralConfigs[address(0)];

        // Calculate weighted collateral value
        // ethPrice comes with 8 decimals from Chainlink, collateral is in wei (18 decimals)
        // Convert to common base: collateralValue in USD with 18 decimals
        uint256 collateralValue = (pos.collateral * ethPrice) / 1e8; // Convert price to 18 decimals
        uint256 weightedCollateral = (collateralValue *
            config.liquidationThreshold) / PRECISION;

        // Health factor = (weighted collateral * 100) / debt
        // debt is in USDC (6 decimals), weightedCollateral is in USD (18 decimals)
        // Normalize debt to 18 decimals: debt * 1e12
        uint256 normalizedDebt = pos.debt * 1e12;
        return (weightedCollateral * HEALTH_FACTOR_PRECISION) / normalizedDebt;
    }

    function isPositionLiquidatable(address user) external view returns (bool) {
        return getHealthFactor(user) < HEALTH_FACTOR_PRECISION;
    }

    function liquidate(
        address user
    ) external nonReentrant onlyLiquidator returns (uint256, uint256) {
        // Check if position is liquidatable
        if (getHealthFactor(user) >= HEALTH_FACTOR_PRECISION) {
            revert LendingPool__PositionHealthy();
        }

        Position storage pos = positions[user];
        CollateralConfig memory config = collateralConfigs[address(0)];

        uint256 debtToRepay = pos.debt;
        uint256 collateralToSeize = pos.collateral;

        // Apply liquidation penalty
        uint256 penaltyAmount = (collateralToSeize *
            config.liquidationPenalty) / PRECISION;
        uint256 totalCollateralToLiquidator = collateralToSeize + penaltyAmount;

        // Clear the position
        pos.collateral = 0;
        pos.debt = 0;

        // Transfer collateral to liquidator (ETH)
        payable(msg.sender).transfer(collateralToSeize);

        emit Liquidation(user, msg.sender, collateralToSeize, debtToRepay);

        return (collateralToSeize, debtToRepay);
    }

    // View function to get position details
    function getPosition(
        address user
    ) external view returns (uint256 collateral, uint256 debt) {
        Position memory pos = positions[user];
        return (pos.collateral, pos.debt);
    }

    // Allow the contract to receive ETH
    receive() external payable {}
}
