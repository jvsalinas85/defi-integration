// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {PriceOracle} from "./PriceOracle.sol";

contract LendingPools is Ownable, ReentrancyGuard {
    struct Position {
        uint256 collateralAmount; // Cantidad de colateral depositado
        uint256 debtAmount; // Cantidad de deuda pendiente
    }

    struct CollateralConfig {
        bool isSupported; // Indica si el colateral es soportado
        uint256 liquidationThreshold; // Umbral de liquidación (en basis points, 7500 = 75%)
        uint256 liquidationPenalty; // Penalización por liquidación (en basis points, 1000 = 10%)
    }

    mapping(address => Position) public positions; // Mapeo de direcciones a sus posiciones
    mapping(address => CollateralConfig) public collateralConfigs; // Configuraciones de colateral

    PriceOracle public immutable priceOracle; // Oráculo de precios
    IERC20 public immutable usdcToken; // Token estable utilizado para préstamos

    uint256 public constant PRECISION = 10000; // Precisión para cálculos en basis points
    uint256 public constant HEALTH_FACTOR_PRECISION = 100; // Precisión para el factor de salud
    uint256 public nextPositionId = 1; // ID incremental para posiciones

    //EVENTOS
    event Deposit(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 amount);
    event Liquidation(
        address indexed liquidator,
        address indexed user,
        uint256 debtRepaid,
        uint256 collateralSeized
    );

    //CUSTOM ERRORS
    error LendingPool__ColleteralNotSupported();
    error LendingPool__InsufficientCollateral();
    error LendingPool__PositionLiquidatable();
    error LendingPool__PositionHealthy();
    error LendingPool__InsufficientDeposit();

    //Constructor
    constructor(address _priceOracle, address _usdcToken) Ownable(msg.sender) {
        priceOracle = PriceOracle(_priceOracle);
        usdcToken = IERC20(_usdcToken);
    }

    //modifier onlyLiquidator
    modifier onlyLiquidator() {
        //Add validations here as it depends from production
        _;
    }

    //Functions
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
        if (msg.value == 0) {
            revert LendingPool__InsufficientDeposit();
        }
        if (!collateralConfigs[address(0)].isSupported) {
            revert LendingPool__ColleteralNotSupported();
        }
        positions[msg.sender].collateralAmount += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function borrow() external nonReentrant {}
}
