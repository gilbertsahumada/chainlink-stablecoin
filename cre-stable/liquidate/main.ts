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
      minStableVaultAddress: z.string(),
      proxyAddress: z.string(),
      chainSelectorName: z.string(),
      gasLimit: z.string(),
    })
  ),
});

type Config = z.infer<typeof configSchema>;

const onCronTrigger = (runtime: Runtime<Config>): boolean => {
  //runtime.log("Hello world! Workflow triggered.");
  //return "Hello world!";
  return isPositionLiquidatable(runtime, runtime.config.evms[0]);
};

const liquidatePosition = (
  runtime: Runtime<Config>,
  evmConfig: Config["evms"][0]
): string => {
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
      args: [2n],
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
        receiver: evmConfig.proxyAddress as Address,
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

    return "Liquidated";
  } catch (error) {
    runtime.log(`Error in liquidatePosition: ${error}`);
    return "Error in liquidatePosition";
  }
};

const isPositionLiquidatable = (
  runtime: Runtime<Config>,
  evmConfig: Config["evms"][0]
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
      functionName: "needsLiquidation",
      args: [2n],
    });

    const contractCall = evmClient
      .callContract(runtime, {
        call: encodeCallMsg({
          from: zeroAddress,
          to: evmConfig.minStableVaultAddress as Address,
          data: callData,
        }),
        blockNumber: LATEST_BLOCK_NUMBER,
      })
      .result();

    const liquidatable = decodeFunctionResult({
      abi: MiniStableVault,
      functionName: "needsLiquidation",
      data: bytesToHex(contractCall.data),
    });

    runtime.log(`Liquidatable: ${liquidatable}`);

    return liquidatable;
  } catch (error) {
    runtime.log(`Error in isPositionLiquidatable: ${error}`);
    return false;
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
