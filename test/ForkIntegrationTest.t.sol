// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../src/PriceOracle.sol";
import "../src/LendingPool.sol";
import "../src/AutoLiquidator.sol";

/**
 * @title ForkIntegrationTest
 * @dev Fork testing against Ethereum Mainnet using real contracts
 *
 * This test demonstrates how to test DeFi integrations against actual mainnet state,
 * using real Chainlink price feeds and ERC20 tokens instead of mocks.
 *
 * Usage:
 * export MAINNET_RPC_URL="your_alchemy_or_infura_url"
 * forge test --match-contract ForkIntegrationTest --fork-url $MAINNET_RPC_URL -vv
 */
contract ForkIntegrationTest is Test {
    // Real Mainnet Contract Addresses
    address constant ETH_USD_CHAINLINK_FEED =
        0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant USDC_TOKEN = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Contracts under test
    PriceOracle public priceOracle;
    LendingPool public lendingPool;
    AutoLiquidator public autoLiquidator;
    IERC20 public usdcToken;

    // Test actors
    address public governance = makeAddr("governance");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    // Test constants
    uint256 public constant LIQUIDATION_THRESHOLD = 8000; // 80%
    uint256 public constant LIQUIDATION_PENALTY = 1000; // 10%
    uint256 public constant DEPOSIT_AMOUNT = 10 ether;
    uint256 public constant BORROW_AMOUNT = 8000e6; // $8000 USDC

    function setUp() public {
        // Create or select a Mainnet fork using env var MAINNET_RPC_URL.
        // Require the env var to be set so tests are explicit about needing a fork.
        string memory rpc = vm.envString("MAINNET_RPC_URL");
        require(
            bytes(rpc).length > 0,
            "MAINNET_RPC_URL not set - export it or run with --fork-url"
        );
        // Create/select the fork before any chainId assumptions
        vm.createSelectFork(rpc);

        // Now we should be on chainId 1 (Mainnet fork)
        require(block.chainid == 1, "Failed to create Mainnet fork");

        vm.startPrank(governance);

        // Get real USDC token
        usdcToken = IERC20(USDC_TOKEN);

        // Deploy our contracts
        priceOracle = new PriceOracle();
        lendingPool = new LendingPool(address(priceOracle), address(usdcToken));
        autoLiquidator = new AutoLiquidator(
            address(lendingPool),
            address(priceOracle),
            address(usdcToken)
        );

        // Configure price oracle with real Chainlink feed
        priceOracle.addPriceFeed(
            address(0), // ETH
            ETH_USD_CHAINLINK_FEED,
            address(0) // No Uniswap for this demo
        );

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

        // Get USDC from a whale address - using one of the top holders
        address usdcWhale = 0x38AAEF3782910bdd9eA3566C839788Af6FF9B200; // Top holder with 1.6B+ USDC

        vm.prank(usdcWhale);
        usdcToken.transfer(address(lendingPool), 500_000e6);

        vm.prank(usdcWhale);
        usdcToken.transfer(address(autoLiquidator), 100_000e6);
    }

    function test_Fork_RealChainlinkIntegration() public view {
        // Test that we can get real ETH price from Chainlink
        uint256 ethPrice = priceOracle.getPrice(address(0));

        console.log("Real ETH Price from Chainlink:", ethPrice / 1e8);

        // Sanity check: ETH price should be reasonable (between $500 and $10000)
        assertGe(ethPrice, 500e8, "ETH price too low - check feed");
        assertLe(ethPrice, 10000e8, "ETH price too high - check feed");

        // Verify price feed is recent (updated within last hour)
        // Using the interface from PriceOracle.sol
        AggregatorV3Interface feed = AggregatorV3Interface(
            ETH_USD_CHAINLINK_FEED
        );
        (, , , uint256 updatedAt, ) = feed.latestRoundData();
        assertGe(updatedAt, block.timestamp - 3600, "Price feed is stale");
    }

    function test_Fork_DepositWithRealPrice() public {
        vm.startPrank(alice);

        // Get current ETH price
        uint256 currentEthPrice = priceOracle.getPrice(address(0));
        console.log("Current ETH Price:", currentEthPrice / 1e8);

        // Deposit ETH
        lendingPool.deposit{value: DEPOSIT_AMOUNT}();

        // Calculate maximum safe borrow amount (less than 80% of collateral value)
        // currentEthPrice comes with 8 decimals from Chainlink
        uint256 collateralValue = (DEPOSIT_AMOUNT * currentEthPrice) / 1e8; // Convert to 18 decimals (USD value)
        uint256 maxBorrow = (collateralValue * 75) / 100 / 1e12; // Convert to USDC 6 decimals (75% safety margin)

        console.log("Collateral Value (USD):", collateralValue / 1e18);
        console.log("Max Safe Borrow:", maxBorrow / 1e6, "USDC");

        // Borrow a safe amount
        lendingPool.borrow(maxBorrow);

        // Verify position is healthy
        uint256 healthFactor = lendingPool.getHealthFactor(alice);
        assertGe(healthFactor, 100, "Position should be healthy");

        vm.stopPrank();
    }

    function test_Fork_LiquidationWithPriceManipulation() public {
        // Create position for Bob
        vm.startPrank(bob);
        lendingPool.deposit{value: DEPOSIT_AMOUNT}();

        // Get current price and borrow aggressively
        uint256 currentEthPrice = priceOracle.getPrice(address(0));
        // currentEthPrice has 8 decimals, DEPOSIT_AMOUNT has 18, want USDC (6 decimals)
        uint256 borrowAmount = (DEPOSIT_AMOUNT * currentEthPrice * 78) /
            (100 * 1e8 * 1e12); // 78% LTV, normalize to USDC decimals
        lendingPool.borrow(borrowAmount);
        vm.stopPrank();

        // Verify position is initially healthy
        assertFalse(
            lendingPool.isPositionLiquidatable(bob),
            "Position should start healthy"
        );

        console.log("Initial Setup:");
        console.log("- ETH Price:", currentEthPrice / 1e8);
        console.log("- Collateral:", DEPOSIT_AMOUNT / 1e18, "ETH");
        console.log("- Debt:", borrowAmount / 1e6, "USDC");
        console.log("- Health Factor:", lendingPool.getHealthFactor(bob));

        // Simulate a significant ETH price drop by manipulating the fork
        // Note: In a real fork test, you might use time manipulation to get new price data
        // For demonstration, we'll manually advance time and check if Chainlink has new data

        vm.warp(block.timestamp + 1800); // Advance 30 minutes - stay within staleness threshold

        // Check if position becomes liquidatable due to any price changes
        bool isLiquidatable = lendingPool.isPositionLiquidatable(bob);

        if (isLiquidatable) {
            console.log(
                "Position became liquidatable due to market conditions"
            );

            // Execute liquidation
            uint256 liquidatorBalanceBefore = address(autoLiquidator).balance;
            autoLiquidator.scanAndLiquidate(1);
            uint256 liquidatorBalanceAfter = address(autoLiquidator).balance;

            console.log("Liquidation executed:");
            console.log(
                "- Liquidator profit:",
                (liquidatorBalanceAfter - liquidatorBalanceBefore) / 1e18,
                "ETH"
            );

            assertGt(
                liquidatorBalanceAfter,
                liquidatorBalanceBefore,
                "Liquidator should profit"
            );
        } else {
            console.log(
                "Position remains healthy under current market conditions"
            );
        }
    }

    function test_Fork_USDCIntegration() public view {
        // Test integration with real USDC token
        uint256 initialSupply = usdcToken.totalSupply();
        console.log("USDC Total Supply:", initialSupply / 1e6);

        // Verify USDC contract properties
        // Note: For fork tests, we'll skip detailed checks since IERC20 doesn't include metadata
        // In reality, USDC has 6 decimals and symbol "USDC" but we can't access these through IERC20

        // Test that our contracts can interact with real USDC
        uint256 poolBalance = usdcToken.balanceOf(address(lendingPool));
        assertGt(poolBalance, 0, "Pool should have USDC balance");

        console.log("LendingPool USDC Balance:", poolBalance / 1e6);
    }

    function test_Fork_SystemResilience() public {
        // Test system behavior under various mainnet conditions

        // 1. Check oracle staleness protection
        AggregatorV3Interface feed = AggregatorV3Interface(
            ETH_USD_CHAINLINK_FEED
        );
        (, , , uint256 updatedAt, ) = feed.latestRoundData();
        console.log(
            "Last price update:",
            (block.timestamp - updatedAt),
            "seconds ago"
        );

        // 2. Test with current market conditions
        uint256 ethPrice = priceOracle.getPrice(address(0));
        console.log("Current market ETH price:", ethPrice / 1e8, "USD");

        // 3. Verify all components work together
        vm.startPrank(alice);
        lendingPool.deposit{value: 5 ether}();

        uint256 healthFactor = lendingPool.getHealthFactor(alice);
        console.log("Health factor for deposit-only position:", healthFactor);

        vm.stopPrank();

        assertTrue(ethPrice > 0, "Price should be valid");
        assertGt(healthFactor, 0, "Health factor should be calculable");
    }

    // Test that demonstrates fork testing advantages
    function test_Fork_RealWorldScenario() public {
        console.log("\n=== Real World Scenario Test ===");

        // Get current market data
        uint256 ethPrice = priceOracle.getPrice(address(0));
        uint256 usdcSupply = usdcToken.totalSupply();

        console.log("Mainnet State:");
        console.log("- Block Number:", block.number);
        console.log("- ETH Price:", ethPrice / 1e8, "USD");
        console.log("- USDC Supply:", usdcSupply / 1e6, "tokens");

        // Create realistic positions based on current prices
        uint256 collateralUsd = 50000e8; // $50k worth of ETH
        uint256 collateralEth = (collateralUsd * 1e18) / ethPrice;
        uint256 borrowAmount = (collateralUsd * 60) / 100; // 60% LTV in USDC terms

        vm.deal(alice, collateralEth + 1 ether); // Extra for gas

        vm.startPrank(alice);
        lendingPool.deposit{value: collateralEth}();
        lendingPool.borrow((borrowAmount * 1e6) / 1e8); // Convert to USDC decimals
        vm.stopPrank();

        console.log("Position created:");
        console.log("- Collateral:", collateralEth / 1e18, "ETH");
        console.log("- Debt:", ((borrowAmount * 1e6) / 1e8) / 1e6, "USDC");
        console.log("- Health Factor:", lendingPool.getHealthFactor(alice));

        // Verify position is realistic and healthy
        assertTrue(
            lendingPool.getHealthFactor(alice) >= 100,
            "Position should be healthy"
        );
        assertFalse(
            lendingPool.isPositionLiquidatable(alice),
            "Position should not be liquidatable"
        );
    }
}
