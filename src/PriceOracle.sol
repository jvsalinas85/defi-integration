// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Interfaz exacta de Chainlink para oráculos de precios.
// Permite interactuar con los feeds de precios de Chainlink sin depender de librerías externas.
interface AggregatorV3Interface {
    // Devuelve la cantidad de decimales que usa el precio.
    function decimals() external view returns (uint8);

    // Devuelve la descripción del feed.
    function description() external view returns (string memory);

    // Devuelve la versión del contrato del feed.
    function version() external view returns (uint256);

    // Devuelve los datos de una ronda específica del feed.
    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer, // Precio reportado
            uint256 startedAt, // Timestamp de inicio de la ronda
            uint256 updatedAt, // Timestamp de actualización
            uint80 answeredInRound // Ronda en la que se respondió
        );

    // Devuelve los datos de la ronda más reciente del feed.
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

// Contrato PriceOracle: oráculo de precios que puede consultar precios de Chainlink y Uniswap.
// Hereda de Ownable para control de acceso.
contract PriceOracle is Ownable {
    // Mapeo de activos a sus feeds de Chainlink.
    mapping(address => AggregatorV3Interface) public chainlinkFeeds;
    // Mapeo de activos a sus pares de Uniswap.
    mapping(address => address) public uniswapPairs;

    // Indica si el oráculo está pausado.
    bool public paused;

    // Desviación máxima de precio permitida (en basis points, 500 = 5%).
    uint256 public constant MAX_PRICE_DEVIATION = 500;
    // Umbral de obsolescencia del precio (en segundos, 3600 = 1 hora).
    uint256 public constant STALENESS_THRESHOLD = 3600;

    // Errores personalizados para revertir con mensajes claros.
    error PriceOracle__Paused();
    error PriceOracle__StalePrice();
    error PriceOracle__PriceDeviationTooHigh();
    error PriceOracle_InvalidPrice();

    // Constructor: inicializa el contrato y asigna el owner.
    constructor() Ownable(msg.sender) {}

    // Modificador para permitir ejecución solo si el oráculo no está pausado.
    modifier whenNotPaused() {
        if (paused) {
            revert PriceOracle__Paused();
        }
        _;
    }

    // Permite al owner registrar un feed de Chainlink y un par de Uniswap para un activo.
    function addPriceFeed(
        address asset,
        address chainlinkFeed,
        address uniswapPair
    ) external onlyOwner {
        chainlinkFeeds[asset] = AggregatorV3Interface(chainlinkFeed);
        uniswapPairs[asset] = uniswapPair;
    }
}
