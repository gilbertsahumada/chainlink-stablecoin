# Chainlink Stable

MiniUSD (mUSD) es una stablecoin colateralizada con ETH en la red Sepolia. El contrato `MiniStableVault` usa Chainlink Price Feeds para valorar el colateral y expone un receiver (`onReport`) que permite automatizar liquidaciones con workflows de Chainlink CRE.

## Arquitectura
- **Smart contract** (`blockchain/src/MinStableVault.sol`): ERC20 que permite abrir posiciones depositando ETH, con factor de salud mínimo de `1.2` (120%). Soporta `openPosition`, `closePosition`, `needsLiquidation`, `liquidate` y `withdraw` de colateral. Incluye modo de precio mock para workshops.
- **Precio de referencia**: Chainlink ETH/USD en Sepolia (`0x694AA1769357215DE4FAC081bf1f309aDC325306`, 8 decimales).
- **Receiver para CRE** (`blockchain/src/interfaces/IReceiverTemplate.sol`): valida forwarder/autor/workflow y delega la lógica a `_processReport`. El vault lo usa para ejecutar `liquidate` cuando recibe un reporte.
- **Workflow de liquidación** (`cre-stable/liquidate/main.ts`): cron cada 30s (`*/30 * * * * *`) que consulta `needsLiquidation` y envía un `writeReport` con `liquidate` usando `@chainlink/cre-sdk`. El ID de posición a vigilar está hardcodeado en `main.ts` (`idPosition = 2n`).

## Requisitos previos
- Git `>= 2.13`
- Foundry (Solidity): `curl -L https://foundry.paradigm.xyz | bash` y luego `foundryup`
- Bun `>= 1.x` para el workflow Typescript: `curl -fsSL https://bun.sh/install | bash`
- CLI de Chainlink CRE (`cre`) para simular/desplegar workflows. Sigue la guía oficial e instala según tu entorno `https://docs.chain.link/cre/getting-started/cli-installation/macos-linux`.

## Configuración rápida
1) Clona el repo:
```bash
git clone <URL-DEL-REPOSITORIO>
cd chainlink-stable
```
2) Inicializa dependencias de Solidity (submódulos):
```bash
# Recomendado
git submodule update --init --recursive
# Alternativa
cd blockchain && forge install && cd ..
```
3) Compila y prueba contratos:
```bash
cd blockchain
forge build
forge test
```
4) Instala dependencias del workflow:
```bash
cd cre-stable/liquidate
bun install
```
5) (Opcional) Simula la automatización de liquidación con CRE:
```bash
cd cre-stable/liquidate
cre workflow simulate . --target=staging-settings
```

## Estructura del proyecto
```
chainlink-stable/
├── blockchain/                  # Contratos y tests con Foundry
│   ├── src/                     # MiniStableVault + interfaces Receiver
│   ├── test/                    # MinStableVault.t.sol
│   └── lib/                     # Submódulos (forge-std, openzeppelin)
├── cre-stable/                  # Configuración de CRE
│   ├── liquidate/               # Workflow Typescript de liquidación
│   │   ├── main.ts
│   │   ├── config.staging.json
│   │   ├── config.production.json
│   │   └── workflow.yaml
│   ├── project.yaml
│   └── secrets.yaml
└── README.md
```

## Configuración del workflow de liquidación (CRE)
- **Contrato objetivo**: `mintStableConsumerAddress` en `config.*.json` debe apuntar al `MiniStableVault` desplegado.
- **Red y gas**: `chainSelectorName` (p.ej. `ethereum-testnet-sepolia`) y `gasLimit` se ajustan en `config.*.json`.
- **Schedule**: cron en el mismo archivo (`*/30 * * * * *` por defecto).
- **Nombre del workflow**: definido en `workflow.yaml` (`liquidate-staging` / `liquidate-production`).
- **Project RPCs**: `cre-stable/project.yaml` configura los endpoints por target.

## Comandos útiles
- Compilar Solidity: `cd blockchain && forge build`
- Tests Solidity: `cd blockchain && forge test` (usa `-vvv` para verboso)
- Formatear Solidity: `cd blockchain && forge fmt`
- Nodo local: `anvil`
- Simular workflow CRE: `cd cre-stable/liquidate && cre workflow simulate . --target=staging-settings`

## Direcciones
| Descripción | Red | Dirección |
|-------------|-----|-----------|
| MiniStableVault (mUSD) | Sepolia Testnet | `0x8Fb01f3d9c4d0639F200E9ae5B1929fe1563c65a` |
| Chainlink Price Feed ETH/USD | Sepolia Testnet | `0x694AA1769357215DE4FAC081bf1f309aDC325306` |

## Problemas comunes
- **"Source not found" / "File import callback not supported"**: faltan submódulos. Ejecuta `git submodule update --init --recursive`.
- **"does not have a commit checked out"**: idem, re-inicializa submódulos.
- **El workflow no encuentra la red/contrato**: revisa `config.*.json` y `project.yaml` (RPC correcto, address del vault y `chainSelectorName`).

## Notas
- El vault es solo para demos/educación y simplifica lógica de riesgos.
- El ID de posición monitoreado por el workflow está fijo en `main.ts`; cámbialo si deseas automatizar otra posición.
