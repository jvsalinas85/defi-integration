## DeFi Integration - Price Oracle

Este proyecto es una simulación de un entorno DeFi utilizando [Foundry](https://book.getfoundry.sh/) como framework de desarrollo y pruebas para contratos inteligentes en Ethereum.

### ¿Qué incluye este proyecto?

- **Oráculo de Precios (PriceOracle):**  
  Un contrato inteligente que permite consultar precios de activos utilizando feeds de Chainlink y pares de Uniswap. El oráculo está diseñado para ser seguro, pausable y controlado por el owner, permitiendo la integración de diferentes fuentes de precios y validaciones de desviación y obsolescencia.

- **Simulación DeFi:**  
  Próximamente se incluirán contratos mock para simular la interacción de protocolos DeFi con el oráculo de precios, facilitando el desarrollo y pruebas de estrategias, préstamos, colaterales, etc.

### Objetivo

El objetivo es proporcionar una base sólida para experimentar y aprender sobre la integración de oráculos de precios en aplicaciones DeFi, así como probar la robustez y seguridad de estos mecanismos en un entorno controlado.

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

### Testear

```shell
$ forge test
```

### Formatear

```shell
$ forge fmt
```

### Snapshots de Gas

```shell
$ forge snapshot
```

### Nodo local (Anvil)

```shell
$ anvil
```

### Desplegar

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Ayuda

```shell
$ forge --help
$ anvil --help
$ cast --help
```
