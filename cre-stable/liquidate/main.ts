import {
  cre,
  Runner,
  type Runtime,
  getNetwork,
  LAST_FINALIZED_BLOCK_NUMBER,
  LATEST_BLOCK_NUMBER,
  encodeCallMsg,
  hexToBase64,
  TxStatus,
} from "@chainlink/cre-sdk";
import {
  encodeFunctionData,
  zeroAddress,
  Address,
  bytesToHex,
  decodeFunctionResult,
} from "viem";
import { z } from "zod";
import { MiniStableVault } from "../contracts/abi/MiniStableVault";

const configSchema = z.object({
  schedule: z.string(),
  url: z.string(),
  evms: z.array(
    z.object({
      mintStableConsumerAddress: z.string(),
      chainSelectorName: z.string(),
      gasLimit: z.string(),
    })
  ),
});

type Config = z.infer<typeof configSchema>;

const onCronTrigger = (runtime: Runtime<Config>): boolean => {
  const { liquidatable, idPosition } = mustBeLiquidated(runtime, runtime.config.evms[0]);
  if (liquidatable) {
    return liquidatePosition(runtime, runtime.config.evms[0], idPosition);
  } else {
    runtime.log("No positions to liquidate at this time.");
    return false;
  }
};

const liquidatePosition = (
  runtime: Runtime<Config>,
  evmConfig: Config["evms"][0],
  idPosition: bigint
): boolean => {
  try {
    const network = getNetwork({
      chainFamily: "evm",
      chainSelectorName: evmConfig.chainSelectorName,
      isTestnet: true,
    });

    if (!network) {
      throw new Error(
        `Network not found for chain selector name: ${evmConfig.chainSelectorName}`
      );
    }

    const evmClient = new cre.capabilities.EVMClient(
      network.chainSelector.selector
    );

    const callData = encodeFunctionData({
      abi: MiniStableVault,
      functionName: "liquidate",
      args: [idPosition], 
    });

    // Write report
    const reportResponse = runtime
      .report({
        encodedPayload: hexToBase64(callData),
        encoderName: "evm",
        signingAlgo: "ecdsa",
        hashingAlgo: "keccak256",
      })
      .result();

    const resp = evmClient
      .writeReport(runtime, {
        receiver: evmConfig.mintStableConsumerAddress as Address,
        report: reportResponse,
        gasConfig: {
          gasLimit: evmConfig.gasLimit,
        },
      })
      .result();

      const txtStatus = resp.txStatus;
      if (txtStatus !== TxStatus.SUCCESS) {
        throw new Error(`Failed to write report: ${resp.errorMessage || txtStatus}`);
      }

      const txHash = resp.txHash || new Uint8Array(32);
      runtime.log(`Liquidate transaction succeeded at txHash: ${bytesToHex(txHash)}`);

    return true;
  } catch (error) {
    runtime.log(`Error in liquidatePosition: ${error}`);
    return false;
  }
};

const mustBeLiquidated = (
  runtime: Runtime<Config>,
  evmConfig: Config["evms"][0]
): { liquidatable: boolean; idPosition: bigint } => {
  const idPosition = 2n; // hardcoded position ID for demo purposes

  try {

    const network = getNetwork({
      chainFamily: "evm",
      chainSelectorName: evmConfig.chainSelectorName,
      isTestnet: true,
    });

    if (!network) {
      throw new Error(
        `Network not found for chain selector name: ${evmConfig.chainSelectorName}`
      );
    }

    const evmClient = new cre.capabilities.EVMClient(
      network.chainSelector.selector
    );

    const callData = encodeFunctionData({
      abi: MiniStableVault,
      functionName: "needsLiquidation",
      args: [idPosition],
    });

    const contractCall = evmClient
      .callContract(runtime, {
        call: encodeCallMsg({
          from: zeroAddress,
          to: evmConfig.mintStableConsumerAddress as Address,
          data: callData,
        }),
        blockNumber: LATEST_BLOCK_NUMBER,
      })
      .result();

    const liquidatable = decodeFunctionResult({
      abi: MiniStableVault,
      functionName: "needsLiquidation",
      data: bytesToHex(contractCall.data),
    }) as boolean;

    runtime.log(`Liquidatable: ${liquidatable}`);

    return {liquidatable: liquidatable, idPosition: idPosition};
  } catch (error) {
    runtime.log(`Error in isPositionLiquidatable: ${error}`);
    return {liquidatable: false, idPosition: idPosition};
  }
};

const initWorkflow = (config: Config) => {
  const cron = new cre.capabilities.CronCapability();

  return [
    cre.handler(cron.trigger({ schedule: config.schedule }), onCronTrigger),
  ];
};

export async function main() {
  const runner = await Runner.newRunner<Config>();
  await runner.run(initWorkflow);
}

main();
