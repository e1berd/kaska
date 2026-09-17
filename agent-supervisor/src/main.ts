import { CallbackClient } from "./callbacks.ts";
import { loadConfig } from "./config.ts";
import { DockerEngine } from "./docker_engine.ts";
import { createHandler } from "./http.ts";
import { RunManager } from "./run_manager.ts";

const config = loadConfig();

const engine = new DockerEngine(config.dockerSocket);
const network = await engine.ensureNetwork(config.runnerNetwork);
console.log(`agent-supervisor: runner network ${config.runnerNetwork} (${network})`);

const runs = new RunManager(
  engine,
  new CallbackClient(config.secret),
  {
    network: config.runnerNetwork,
    logFlushMs: config.logFlushMs,
    logFlushBytes: config.logFlushBytes,
  },
);

const recovered = await runs.recover();
console.log(`agent-supervisor: recovered ${recovered} run(s)`);

Deno.serve(
  { port: config.port, hostname: "0.0.0.0" },
  createHandler({
    secret: config.secret,
    runs,
    rules: {
      allowedImages: config.allowedImages,
      callbackBaseUrl: config.callbackBaseUrl,
      caps: config.caps,
    },
  }),
);
