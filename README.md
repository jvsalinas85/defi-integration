# DeFi Integration - Price Oracle & Lending Protocol

## 🌟 Descripción en Español

Este proyecto implementa un protocolo DeFi completo utilizando [Foundry](https://book.getfoundry.sh/) como framework de desarrollo y pruebas. Incluye un oráculo de precios robusto y un protocolo de préstamos con liquidaciones automáticas.

### Componentes Principales

- **Oráculo de Precios (PriceOracle):**  
  Contrato que obtiene y valida precios de activos usando feeds de Chainlink. Incluye:

  - Validación de obsolescencia de precios
  - Pausable para emergencias
  - Soporte para múltiples fuentes de precios
  - Control de desviación de precios

- **Pool de Préstamos (LendingPool):**  
  Protocolo de préstamos que permite:

  - Depósitos de ETH como colateral
  - Préstamos en USDC
  - Cálculo de factor de salud
  - Sistema de liquidaciones

- **Liquidador Automático (AutoLiquidator):**  
  Bot que monitorea y ejecuta liquidaciones de posiciones no saludables.

### Pruebas

El proyecto incluye dos suites de pruebas:

1. **Tests de Integración** (`IntegrationTest.t.sol`):

   - Usa mocks para simular feeds de precios
   - Prueba la interacción entre componentes

2. **Tests con Fork de Mainnet** (`ForkIntegrationTest.t.sol`):
   - Prueba con feeds reales de Chainlink
   - Interactúa con USDC en mainnet
   - Requiere RPC URL de Ethereum

## 🌟 English Description

This project implements a complete DeFi protocol using [Foundry](https://book.getfoundry.sh/) as the development and testing framework. It includes a robust price oracle and a lending protocol with automatic liquidations.

### Main Components

- **Price Oracle (PriceOracle):**  
  Contract that fetches and validates asset prices using Chainlink feeds. Features:

  - Price staleness validation
  - Emergency pause functionality
  - Multiple price source support
  - Price deviation controls

- **Lending Pool (LendingPool):**  
  Lending protocol that enables:

  - ETH deposits as collateral
  - USDC borrowing
  - Health factor calculation
  - Liquidation system

- **Automatic Liquidator (AutoLiquidator):**  
  Bot that monitors and executes liquidations of unhealthy positions.

### Testing

The project includes two test suites:

1. **Integration Tests** (`IntegrationTest.t.sol`):

   - Uses mocks for price feeds
   - Tests component interaction

2. **Mainnet Fork Tests** (`ForkIntegrationTest.t.sol`):
   - Tests with real Chainlink feeds
   - Interacts with mainnet USDC
   - Requires Ethereum RPC URL

---

## Foundry

**Foundry es un toolkit rápido, portable y modular para el desarrollo de aplicaciones Ethereum escrito en Rust.**

Incluye:

- **Forge**: Framework de testing para Ethereum.
- **Cast**: Herramienta para interactuar con contratos inteligentes EVM.
- **Anvil**: Nodo local de Ethereum.
- **Chisel**: REPL de Solidity.

## Documentación

https://book.getfoundry.sh/

## Uso

### Compilar

```shell
$ forge build
```

### Configuración y Desarrollo / Setup & Development

Para ejecutar los tests con fork:

```bash
# Configurar variable de entorno (requerida para tests de fork)
export MAINNET_RPC_URL="tu-rpc-url-aquí"

# Ejecutar solo tests de fork
forge test --match-contract ForkIntegrationTest --fork-url $MAINNET_RPC_URL -vv

# Ejecutar todos los tests
forge test
```

### Comandos Útiles / Useful Commands

```bash
# Compilar / Compile
forge build

# Ejecutar tests / Run tests
forge test

# Formatear código / Format code
forge fmt

# Análisis de gas / Gas snapshots
forge snapshot

# Nodo local / Local node
anvil

# Ayuda / Help
forge --help
anvil --help
cast --help
```

## 📝 Licencia / License

Este proyecto está bajo la Licencia MIT - ver el archivo [LICENSE](LICENSE) para más detalles.
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
