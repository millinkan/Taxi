import { loadConfig } from "./config.js";
import { HttpCoreApi } from "./core/client.js";
import { AnthropicRunner } from "./agent/llm.js";
import { createApp } from "./app.js";
import { log, setLogLevel } from "./logger.js";

const config = loadConfig();
setLogLevel(config.LOG_LEVEL);

const app = createApp(config, {
  core: new HttpCoreApi(config.CORE_API_URL, config.INTERNAL_API_TOKEN),
  // Reads ANTHROPIC_API_KEY (or another configured credential) from the environment.
  llm: new AnthropicRunner(config.ANTHROPIC_MODEL, config.ANTHROPIC_EFFORT),
});

app.listen(config.PORT, () => {
  log.info("voice service listening", { port: config.PORT, model: config.ANTHROPIC_MODEL });
});

for (const signal of ["SIGTERM", "SIGINT"] as const) {
  process.on(signal, () => {
    log.info("shutting down", { signal });
    app.close(() => process.exit(0));
    // Hard stop if calls do not wind down.
    setTimeout(() => process.exit(0), 10_000).unref();
  });
}
