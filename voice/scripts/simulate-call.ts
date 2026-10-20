// Talk to the phone agent from the terminal: no Twilio, no phone needed.
// Uses the real core API and the real Claude model, so bookings are real.
//
//   ANTHROPIC_API_KEY=... CORE_API_URL=http://localhost:3000 INTERNAL_API_TOKEN=... \
//     npm run simulate -- +41445550000 [+41795551234]
//
// Arg 1: the firm's voice number (as configured in Settings / Admin).
// Arg 2: the caller ID to pretend to call from (optional).
import { createInterface } from "node:readline/promises";
import { stdin, stdout } from "node:process";
import { HttpCoreApi } from "../src/core/client.js";
import { AnthropicRunner } from "../src/agent/llm.js";
import { defaultGreeting } from "../src/agent/prompt.js";
import { CallSession } from "../src/relay/session.js";
import { setLogLevel } from "../src/logger.js";

const [firmNumber, callerId] = process.argv.slice(2);
if (!firmNumber) {
  console.error("usage: npm run simulate -- <firm voice number> [caller id]");
  process.exit(1);
}

setLogLevel("warn");
const core = new HttpCoreApi(process.env.CORE_API_URL ?? "http://localhost:3000", process.env.INTERNAL_API_TOKEN ?? "");
const tenant = await core.tenantForNumber(firmNumber);
if (!tenant) {
  console.error(`No firm has voice number ${firmNumber}.`);
  process.exit(1);
}

let ended = false;
const session = new CallSession({
  core,
  llm: new AnthropicRunner(
    process.env.ANTHROPIC_MODEL ?? "claude-opus-5-5",
    (process.env.ANTHROPIC_EFFORT as "low" | "medium" | "high" | undefined) ?? "medium",
  ),
  send: (message) => {
    if (message.type === "text") stdout.write(message.last ? "\n" : message.token);
    if (message.type === "language") stdout.write(`\n[voice switched to ${message.ttsLanguage}]\n`);
    if (message.type === "end") {
      stdout.write(`\n[call ended: ${message.handoffData}]\n`);
      ended = true;
    }
  },
  resolveTenant: async () => tenant,
  languages: { de: "de-DE", en: "en-US" },
  maxCallSeconds: 900,
});

await session.handle({ type: "setup", sessionId: "sim", callSid: `SIM${Date.now()}`, from: callerId, to: firmNumber });
console.log(`\n${tenant.name} (agent): ${defaultGreeting(tenant)}`);

const rl = createInterface({ input: stdin, output: stdout });
while (!ended) {
  const line = (await rl.question("\nyou: ")).trim();
  if (!line || line === "/hangup") break;
  stdout.write("agent: ");
  await session.handle({ type: "prompt", voicePrompt: line, last: true });
}
rl.close();
await session.close();
console.log(`\noutcome: ${session.outcome()} (recorded in the core's call log)`);
