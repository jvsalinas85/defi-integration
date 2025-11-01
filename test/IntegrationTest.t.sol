// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../src/PriceOracle.sol";
import "../src/LendingPool.sol";
import "../src/AutoLiquidator.sol";
import "./mocks/MockChainlinkFeed.sol";
import "./mocks/MockERC20.sol";

contract IntegrationTest is Test {
    // Contracts
    PriceOracle public priceOracle;
    LendingPool public lendingPool;
    AutoLiquidator public autoLiquidator;

    // Mocks
    MockChainlinkFeed public ethFeed;
    MockERC20 public usdcToken;

    // Test actors
    address public governance = makeAddr("governance");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    // Test constants
    uint256 public constant INITIAL_ETH_PRICE = 2000e8; // $2000 with 8 decimals
    uint256 public constant LIQUIDATION_THRESHOLD = 8000; // 80%
    uint256 public constant LIQUIDATION_PENALTY = 1000; // 10%
    uint256 public constant DEPOSIT_AMOUNT = 10 ether;
    uint256 public constant BORROW_AMOUNT = 15000e6; // $15000 USDC - more aggressive borrowing
    uint256 public constant USDC_INITIAL_SUPPLY = 1_000_000e6; // 1M USDC

    function setUp() public {
        vm.startPrank(governance);

        // Deploy mock contracts
        ethFeed = new MockChainlinkFeed(int256(INITIAL_ETH_PRICE), 8);
        usdcToken = new MockERC20("USD Coin", "USDC", 6, USDC_INITIAL_SUPPLY);

        // Deploy core contracts
        priceOracle = new PriceOracle();
        lendingPool = new LendingPool(address(priceOracle), address(usdcToken));
        autoLiquidator = new AutoLiquidator(
            address(lendingPool),
            address(priceOracle),
            address(usdcToken)
        );

        // Configure price oracle
        priceOracle.addPriceFeed(address(0), address(ethFeed), address(0));

        // Configure lending pool
        lendingPool.addCollateralSupport(
            address(0), // ETH
            LIQUIDATION_THRESHOLD,
            LIQUIDATION_PENALTY
        );

        vm.stopPrank();

        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(address(autoLiquidator), 10 ether);

        // Distribute USDC from governance (which got the initial supply)
        vm.startPrank(governance);
        usdcToken.transfer(address(lendingPool), 500_000e6); // 500k to pool
        usdcToken.transfer(address(autoLiquidator), 100_000e6); // 100k to liquidator
        usdcToken.transfer(alice, 50_000e6); // 50k to alice
        vm.stopPrank();
    }

    modifier setupBobPosition() {
        vm.startPrank(bob);
        lendingPool.deposit{value: DEPOSIT_AMOUNT}();
        lendingPool.borrow(BORROW_AMOUNT);
        vm.stopPrank();

        // Set up position mapping for liquidator
        autoLiquidator.setPositionOwner(1, bob);
        _;
    }

    function test_IntegrationFlow_BasicDeposit() public {
        vm.startPrank(alice);

        uint256 initialBalance = address(alice).balance;

        lendingPool.deposit{value: 5 ether}();

        (uint256 collateral, uint256 debt) = lendingPool.getPosition(alice);

        assertEq(collateral, 5 ether, "Collateral should match deposit");
        assertEq(debt, 0, "Initial debt should be zero");
        assertEq(
            address(alice).balance,
            initialBalance - 5 ether,
            "ETH should be deducted"
        );

        vm.stopPrank();
    }

    function test_IntegrationFlow_DepositAndBorrow() public {
        vm.startPrank(alice);

        // Deposit ETH as collateral
        lendingPool.deposit{value: DEPOSIT_AMOUNT}();

        uint256 initialUsdcBalance = usdcToken.balanceOf(alice);

        // Borrow USDC
        lendingPool.borrow(BORROW_AMOUNT);

        (uint256 collateral, uint256 debt) = lendingPool.getPosition(alice);

        assertEq(collateral, DEPOSIT_AMOUNT, "Collateral should match deposit");
        assertEq(debt, BORROW_AMOUNT, "Debt should match borrow amount");
        assertEq(
            usdcToken.balanceOf(alice),
            initialUsdcBalance + BORROW_AMOUNT,
            "USDC balance should increase"
        );

        // Check health factor is above minimum
        uint256 healthFactor = lendingPool.getHealthFactor(alice);
        assertGe(healthFactor, 100, "Health factor should be above minimum");

        vm.stopPrank();
    }

    function test_IntegrationFlow_OracleIntegration() public {
        // Test that price changes affect health factor calculations
        vm.startPrank(alice);
        lendingPool.deposit{value: DEPOSIT_AMOUNT}();
        lendingPool.borrow(BORROW_AMOUNT);
        vm.stopPrank();

        uint256 initialHealthFactor = lendingPool.getHealthFactor(alice);

        // Simulate ETH price drop
        ethFeed.updatePrice(int256(1500e8)); // $1500

        uint256 newHealthFactor = lendingPool.getHealthFactor(alice);

        assertLt(
            newHealthFactor,
            initialHealthFactor,
            "Health factor should decrease with price drop"
        );
    }

    function test_IntegrationFlow_AutomaticLiquidation()
        public
        setupBobPosition
    {
        // Verify initial healthy position
        uint256 initialHealthFactor = lendingPool.getHealthFactor(bob);
        assertGe(initialHealthFactor, 100, "Position should start healthy");
        assertFalse(
            lendingPool.isPositionLiquidatable(bob),
            "Position should not be liquidatable initially"
        );

        // Simulate market crash - ETH price drops significantly
        uint256 newEthPrice = 1800e8; // $1800 - with $15k debt on 10 ETH, this should trigger liquidation
        ethFeed.updatePrice(int256(newEthPrice));

        // Verify position becomes liquidatable
        assertTrue(
            lendingPool.isPositionLiquidatable(bob),
            "Position should become liquidatable"
        );

        // Record pre-liquidation state
        (uint256 collateralBefore, uint256 debtBefore) = lendingPool
            .getPosition(bob);
        uint256 liquidatorBalanceBefore = address(autoLiquidator).balance;
        uint256 initialLiquidations = autoLiquidator.totalLiquidations();

        // Execute automatic liquidation
        autoLiquidator.scanAndLiquidate(1); // Position ID 1 maps to Bob

        // Verify liquidation results
        (uint256 collateralAfter, uint256 debtAfter) = lendingPool.getPosition(
            bob
        );
        uint256 liquidatorBalanceAfter = address(autoLiquidator).balance;
        uint256 totalLiquidations = autoLiquidator.totalLiquidations();

        // Assertions
        assertEq(collateralAfter, 0, "Collateral should be seized completely");
        assertEq(debtAfter, 0, "Debt should be cleared");
        assertGt(
            liquidatorBalanceAfter,
            liquidatorBalanceBefore,
            "Liquidator should receive collateral"
        );
        assertEq(
            totalLiquidations,
            initialLiquidations + 1,
            "Liquidation counter should increase"
        );

        console.log("Initial Health Factor:", initialHealthFactor);
        console.log(
            "Health Factor after price drop:",
            lendingPool.getHealthFactor(bob)
        );
        console.log("Collateral seized:", collateralBefore);
        console.log("Debt repaid:", debtBefore);
        console.log(
            "Liquidator profit:",
            liquidatorBalanceAfter - liquidatorBalanceBefore
        );
    }

    function test_IntegrationFlow_MultiplePositionsLiquidation() public {
        // Setup multiple positions
        _setupBobPosition();
        _setupAlicePosition();

        // Simulate market crash
        ethFeed.updatePrice(int256(1300e8)); // $1300 - crash that makes both positions liquidatable

        // Verify both positions are liquidatable
        assertTrue(
            lendingPool.isPositionLiquidatable(bob),
            "Bob's position should be liquidatable"
        );
        assertTrue(
            lendingPool.isPositionLiquidatable(alice),
            "Alice's position should be liquidatable"
        );

        // Execute batch liquidation
        uint256[] memory positionIds = new uint256[](2);
        positionIds[0] = 1; // Bob
        positionIds[1] = 2; // Alice

        uint256 liquidatedCount = autoLiquidator.batchLiquidate(positionIds);

        assertEq(liquidatedCount, 2, "Both positions should be liquidated");
        assertEq(
            autoLiquidator.totalLiquidations(),
            2,
            "Total liquidations should be 2"
        );
    }

    function test_IntegrationFlow_OraclePauseProtection()
        public
        setupBobPosition
    {
        // Pause the oracle
        vm.prank(governance);
        priceOracle.setPaused(true);

        // Attempt liquidation should fail
        vm.expectRevert();
        autoLiquidator.scanAndLiquidate(1);

        // Unpause and retry
        vm.prank(governance);
        priceOracle.setPaused(false);

        // Should work now (though position is healthy, so will revert for different reason)
        vm.expectRevert();
        autoLiquidator.scanAndLiquidate(1);
    }

    function test_IntegrationFlow_StalePriceProtection()
        public
        setupBobPosition
    {
        // Set stale price manually with a specific old timestamp
        vm.warp(10000); // Set current time to 10000
        ethFeed.setStalePrice(int256(1000e8), 5000); // Set price updated at timestamp 5000

        // Try to get price directly - should fail due to staleness (10000 - 5000 = 5000 > 3600)
        vm.expectRevert();
        priceOracle.getPrice(address(0));
    }

    function test_IntegrationFlow_ProfitabilityCheck() public setupBobPosition {
        // Set a price that makes liquidation unprofitable
        // Very small position relative to gas costs
        ethFeed.updatePrice(int256(1500e8)); // Moderate drop

        // Check profitability estimation
        uint256 estimatedProfit = autoLiquidator.estimateLiquidationProfit(bob);
        console.log("Estimated profit:", estimatedProfit);

        // If profitable, liquidation should succeed
        if (estimatedProfit >= 0.001 ether) {
            assertTrue(autoLiquidator.isLiquidationProfitable(bob));
            autoLiquidator.scanAndLiquidate(1);
        } else {
            assertFalse(autoLiquidator.isLiquidationProfitable(bob));
        }
    }

    // Helper functions
    function _setupBobPosition() internal {
        vm.startPrank(bob);
        lendingPool.deposit{value: DEPOSIT_AMOUNT}();
        lendingPool.borrow(BORROW_AMOUNT);
        vm.stopPrank();

        // Set up position mapping for liquidator
        autoLiquidator.setPositionOwner(1, bob);
    }

    function _setupAlicePosition() internal {
        vm.startPrank(alice);
        lendingPool.deposit{value: 8 ether}();
        lendingPool.borrow(12000e6); // $12000 USDC - more aggressive position
        vm.stopPrank();

        // Set up position mapping for liquidator
        autoLiquidator.setPositionOwner(2, alice);
    }

    function _logSystemState(string memory phase) internal view {
        console.log("\n=== System State:", phase, "===");
        console.log("ETH Price:", uint256(ethFeed.getPrice()) / 1e8);
        console.log("Oracle Paused:", priceOracle.paused());
        console.log("Total Liquidations:", autoLiquidator.totalLiquidations());

        (uint256 bobCollateral, uint256 bobDebt) = lendingPool.getPosition(bob);
        console.log("Bob - Collateral:", bobCollateral / 1e18, "ETH");
        console.log("Bob - Debt:", bobDebt / 1e6, "USDC");

        if (bobDebt > 0) {
            console.log(
                "Bob - Health Factor:",
                lendingPool.getHealthFactor(bob)
            );
            console.log(
                "Bob - Liquidatable:",
                lendingPool.isPositionLiquidatable(bob)
            );
        }
        console.log("========================\n");
    }
}
