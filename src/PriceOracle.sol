// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

contract PriceOracle is Ownable {
    mapping(address => AggregatorV3Interface) public chainlinkFeeds;
    mapping(address => address) public uniswapPairs; // Simplified, in production would use Uniswap V3

    uint256 public constant MAX_PRICE_DEVIATION = 500; // 5% max deviation (basis points)
    uint256 public constant STALENESS_THRESHOLD = 3600; // 1 hour

    bool public paused = false;

    error PriceOracle__Paused();
    error PriceOracle__StalePrice();
    error PriceOracle__PriceDeviationTooHigh();
    error PriceOracle__InvalidPrice();

    constructor() Ownable(msg.sender) {}

    modifier whenNotPaused() {
        if (paused) revert PriceOracle__Paused();
        _;
    }

    function addPriceFeed(
        address asset,
        address chainlinkFeed,
        address uniswapPair
    ) external onlyOwner {
        chainlinkFeeds[asset] = AggregatorV3Interface(chainlinkFeed);
        uniswapPairs[asset] = uniswapPair;
    }

    function getPrice(
        address asset
    ) external view whenNotPaused returns (uint256) {
        AggregatorV3Interface chainlinkFeed = chainlinkFeeds[asset];
        require(address(chainlinkFeed) != address(0), "Feed not found");

        // Get Chainlink price
        (, int256 chainlinkPrice, , uint256 updatedAt, ) = chainlinkFeed
            .latestRoundData();

        // Check for staleness
        if (block.timestamp - updatedAt > STALENESS_THRESHOLD) {
            revert PriceOracle__StalePrice();
        }

        if (chainlinkPrice <= 0) {
            revert PriceOracle__InvalidPrice();
        }

        uint256 price = uint256(chainlinkPrice);

        // In production, would also get Uniswap price and compare
        // For simplicity, we're just using Chainlink price
        // uint256 uniswapPrice = _getUniswapPrice(asset);
        // _validatePriceDeviation(price, uniswapPrice);

        return price;
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    // Internal function for price validation (would be used with Uniswap integration)
    function _validatePriceDeviation(
        uint256 price1,
        uint256 price2
    ) internal pure {
        uint256 deviation = price1 > price2
            ? ((price1 - price2) * 10000) / price2
            : ((price2 - price1) * 10000) / price1;

        if (deviation > MAX_PRICE_DEVIATION) {
            revert PriceOracle__PriceDeviationTooHigh();
        }
    }
}
