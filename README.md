# Chainlink Stable

Proyecto de moneda estable (stablecoin) con garantía colateral usando Chainlink Price Feeds.

## Requisitos Previos

Antes de comenzar, asegúrate de tener instalado:

- **Git** (versión 2.13 o superior)
- **Foundry** - Toolkit para desarrollo de contratos inteligentes en Solidity
  - Instalación: `curl -L https://foundry.paradigm.xyz | bash`
  - Luego ejecuta: `foundryup`

Para verificar la instalación:
```bash
forge --version
```

## Configuración Inicial

### Paso 1: Clonar el Repositorio

```bash
git clone <URL-DEL-REPOSITORIO>
cd chainlink-stable
```

### Paso 2: Inicializar Submódulos

Este proyecto usa **submódulos de Git** para las dependencias (OpenZeppelin Contracts y Forge Std). Es **MUY IMPORTANTE** inicializarlos:

```bash
# Opción 1: Usando Git (recomendado)
git submodule update --init --recursive

# Opción 2: Usando Foundry (alternativa)
cd blockchain
forge install
cd ..
```

**IMPORTANTE: Si no haces este paso, el proyecto NO compilará** porque faltarán las dependencias.

### Paso 3: Verificar la Instalación

Navega al directorio del proyecto blockchain y compila:

```bash
cd blockchain
forge build
```

Si todo está correcto, deberías ver un mensaje de compilación exitosa.

## Estructura del Proyecto

```
chainlink-stable/
├── blockchain/              # Proyecto Foundry principal
│   ├── src/                 # Contratos fuente
│   │   ├── MinStableVault.sol
│   │   └── Counter.sol
│   ├── test/                # Tests
│   ├── script/              # Scripts de deployment
│   ├── lib/                 # Dependencias (submódulos)
│   │   ├── forge-std/       # Biblioteca estándar de Foundry
│   │   └── openzeppelin-contracts/  # Contratos de OpenZeppelin
│   ├── foundry.toml         # Configuración de Foundry
│   └── remappings.txt       # Mapeo de imports
└── .gitmodules              # Configuración de submódulos
```

## Comandos Útiles

### Compilar Contratos

```bash
cd blockchain
forge build
```

### Ejecutar Tests

```bash
cd blockchain
forge test
```

### Ejecutar Tests con Verbosidad

```bash
forge test -vvv
```

### Formatear Código

```bash
forge fmt
```

### Ejecutar Anvil (Nodo Local)

```bash
anvil
```

### Desplegar Contratos

```bash
forge script script/Counter.s.sol:CounterScript \
  --rpc-url <TU_RPC_URL> \
  --private-key <TU_PRIVATE_KEY>
```

## Dependencias

Este proyecto utiliza las siguientes dependencias como submódulos:

- **forge-std**: Biblioteca estándar de Foundry para testing
- **openzeppelin-contracts**: Contratos seguros y auditados de OpenZeppelin

Las dependencias se gestionan automáticamente a través de Git submódulos. No uses `npm install` o `yarn install` - este es un proyecto Foundry puro.

## Solución de Problemas

### Error: "Source not found" o "File import callback not supported"

**Problema**: Los submódulos no están inicializados.

**Solución**:
```bash
git submodule update --init --recursive
cd blockchain
forge build
```

### Error: "does not have a commit checked out"

**Problema**: Los submódulos no están correctamente inicializados.

**Solución**:
```bash
git submodule update --init --recursive
```

### Los cambios en submódulos no se reflejan

**Problema**: Los submódulos apuntan a commits específicos. Si necesitas actualizar:

```bash
cd blockchain/lib/openzeppelin-contracts
git pull origin main
cd ../../..
git add blockchain/lib/openzeppelin-contracts
git commit -m "Update OpenZeppelin contracts"
```

## Recursos

- [Foundry Book](https://book.getfoundry.sh/)
- [OpenZeppelin Contracts Documentation](https://docs.openzeppelin.com/contracts)
- [Chainlink Documentation](https://docs.chain.link/)

# Address

| Network | Contract Address |
|---------|-----------------|
| Mainnet | 0x5907d70Dcb0D658801d531F17D3952368f37b182 |



