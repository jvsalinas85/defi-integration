// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./LendingPool.sol";
import "./PriceOracle.sol";

contract AutoLiquidator is ReentrancyGuard {
    LendingPool public immutable lendingPool;
    PriceOracle public immutable priceOracle;
    IERC20 public immutable usdcToken;

    uint256 public totalLiquidations;
    mapping(address => uint256) public liquidationCount;

    uint256 public constant LIQUIDATION_PENALTY = 1000; // 10%
    uint256 public constant MIN_PROFIT_THRESHOLD = 0.0001 ether; // Minimum profit to execute liquidation

    event LiquidationExecuted(
        address indexed user,
        address indexed liquidator,
        uint256 collateralSeized,
        uint256 debtRepaid,
        uint256 profit
    );

    error AutoLiquidator__NoLiquidatablePositions();
    error AutoLiquidator__LiquidationUnprofitable();
    error AutoLiquidator__InsufficientFunds();

    constructor(
        address _lendingPool,
        address _priceOracle,
        address _usdcToken
    ) {
        lendingPool = LendingPool(payable(_lendingPool));
        priceOracle = PriceOracle(_priceOracle);
        usdcToken = IERC20(_usdcToken);
    }

    function scanAndLiquidate(
        uint256 positionId
    ) external nonReentrant returns (bool) {
        address user = _getPositionOwner(positionId);

        // Check if position is liquidatable
        if (!lendingPool.isPositionLiquidatable(user)) {
            revert AutoLiquidator__NoLiquidatablePositions();
        }

        // Get position details before liquidation
        (uint256 collateralBefore, uint256 debtBefore) = lendingPool
            .getPosition(user);

        // Calculate expected profit
        uint256 ethPrice = priceOracle.getPrice(address(0)); // ETH price (8 decimals)
        uint256 collateralValue = (collateralBefore * ethPrice) / 1e8; // Convert to USD with 18 decimals
        uint256 expectedProfit = (collateralValue * LIQUIDATION_PENALTY) /
            10000; // USD profit

        // Convert USD profit back to ETH for comparison with MIN_PROFIT_THRESHOLD
        expectedProfit = (expectedProfit * 1e8) / ethPrice; // Convert back to ETH

        if (expectedProfit < MIN_PROFIT_THRESHOLD) {
            revert AutoLiquidator__LiquidationUnprofitable();
        }

        // Ensure we have enough USDC to repay the debt
        if (usdcToken.balanceOf(address(this)) < debtBefore) {
            revert AutoLiquidator__InsufficientFunds();
        }

        // Approve USDC for the liquidation (if needed)
        usdcToken.approve(address(lendingPool), debtBefore);

        // Record balance before liquidation
        uint256 ethBalanceBefore = address(this).balance;

        // Execute liquidation
        (uint256 collateralSeized, uint256 debtRepaid) = lendingPool.liquidate(
            user
        );

        // Calculate actual profit
        uint256 ethBalanceAfter = address(this).balance;
        uint256 actualProfit = ethBalanceAfter - ethBalanceBefore;

        // Update statistics
        totalLiquidations++;
        liquidationCount[user]++;

        emit LiquidationExecuted(
            user,
            msg.sender,
            collateralSeized,
            debtRepaid,
            actualProfit
        );

        return true;
    }

    function batchLiquidate(
        uint256[] calldata positionIds
    ) external nonReentrant returns (uint256 liquidatedCount) {
        for (uint256 i = 0; i < positionIds.length; i++) {
            // Call internal liquidation logic instead of external function to avoid reentrancy issue
            if (_liquidatePosition(positionIds[i])) {
                liquidatedCount++;
            }
        }

        if (liquidatedCount == 0) {
            revert AutoLiquidator__NoLiquidatablePositions();
        }
    }

    function _liquidatePosition(uint256 positionId) internal returns (bool) {
        address user = _getPositionOwner(positionId);

        // Check if position is liquidatable
        if (!lendingPool.isPositionLiquidatable(user)) {
            return false;
        }

        // Get position details before liquidation
        (uint256 collateralBefore, uint256 debtBefore) = lendingPool
            .getPosition(user);

        // Calculate expected profit
        uint256 ethPrice = priceOracle.getPrice(address(0)); // ETH price (8 decimals)
        uint256 collateralValue = (collateralBefore * ethPrice) / 1e8; // Convert to USD with 18 decimals
        uint256 expectedProfit = (collateralValue * LIQUIDATION_PENALTY) /
            10000; // USD profit

        // Convert USD profit back to ETH for comparison with MIN_PROFIT_THRESHOLD
        expectedProfit = (expectedProfit * 1e8) / ethPrice; // Convert back to ETH

        if (expectedProfit < MIN_PROFIT_THRESHOLD) {
            return false; // Skip unprofitable liquidations in batch
        }

        // Ensure we have enough USDC to repay the debt
        if (usdcToken.balanceOf(address(this)) < debtBefore) {
            return false; // Skip if insufficient funds
        }

        // Approve USDC for the liquidation (if needed)
        usdcToken.approve(address(lendingPool), debtBefore);

        // Record balance before liquidation
        uint256 ethBalanceBefore = address(this).balance;

        // Execute liquidation
        (uint256 collateralSeized, uint256 debtRepaid) = lendingPool.liquidate(
            user
        );

        // Calculate actual profit
        uint256 ethBalanceAfter = address(this).balance;
        uint256 actualProfit = ethBalanceAfter - ethBalanceBefore;

        // Update statistics
        totalLiquidations++;
        liquidationCount[user]++;

        emit LiquidationExecuted(
            user,
            msg.sender,
            collateralSeized,
            debtRepaid,
            actualProfit
        );

        return true;
    }

    function estimateLiquidationProfit(
        address user
    ) external view returns (uint256) {
        if (!lendingPool.isPositionLiquidatable(user)) {
            return 0;
        }

        (uint256 collateral, ) = lendingPool.getPosition(user);
        uint256 ethPrice = priceOracle.getPrice(address(0));
        uint256 collateralValue = (collateral * ethPrice) / 1e18;

        return (collateralValue * LIQUIDATION_PENALTY) / 10000;
    }

    function isLiquidationProfitable(
        address user
    ) external view returns (bool) {
        uint256 profit = this.estimateLiquidationProfit(user);
        return profit >= MIN_PROFIT_THRESHOLD;
    }

    // Simplified mapping for demo - maps position IDs to addresses
    // In production, this would be a proper mapping maintained by the protocol
    mapping(uint256 => address) public positionOwners;

    function setPositionOwner(uint256 positionId, address owner) external {
        positionOwners[positionId] = owner;
    }

    function _getPositionOwner(
        uint256 positionId
    ) internal view returns (address) {
        return positionOwners[positionId];
    }

    // Allow contract to receive ETH from liquidations
    receive() external payable {}

    // Emergency functions for the demo
    function fundWithUSDC(uint256 amount) external {
        require(
            usdcToken.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
    }

    function withdrawUSDC(uint256 amount) external {
        require(usdcToken.transfer(msg.sender, amount), "Transfer failed");
    }

    function withdrawETH(uint256 amount) external {
        payable(msg.sender).transfer(amount);
    }

    // View functions for monitoring
    function getContractBalances()
        external
        view
        returns (uint256 ethBalance, uint256 usdcBalance)
    {
        ethBalance = address(this).balance;
        usdcBalance = usdcToken.balanceOf(address(this));
    }

    function getLiquidationStats()
        external
        view
        returns (uint256 total, uint256 userCount)
    {
        return (totalLiquidations, liquidationCount[msg.sender]);
    }
}
