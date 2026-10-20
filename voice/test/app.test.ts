import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import { createApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { computeSignature } from "../src/twilio/signature.js";
import { FakeCore, ScriptedLlm } from "./helpers.js";

const PUBLIC = "https://voice.example.com";
const config = loadConfig({
  PUBLIC_BASE_URL: PUBLIC,
  CORE_API_URL: "http://core.internal:3000",
  CORE_PUBLIC_URL: "https://core.example.com",
  INTERNAL_API_TOKEN: "internal-token-123456",
  TWILIO_AUTH_TOKEN: "twilio-token",
  LOG_LEVEL: "error",
});

let server: Server;
let base: string;

before(async () => {
  server = createApp(config, { core: new FakeCore(), llm: new ScriptedLlm([]) });
  await new Promise<void>((resolve) => server.listen(0, resolve));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});

after(() => new Promise<void>((resolve) => server.close(() => resolve())));

async function twilioPost(path: string, params: Record<string, string>, sign = true) {
  const signature = computeSignature("twilio-token", PUBLIC + path, params);
  return fetch(base + path, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", ...(sign ? { "X-Twilio-Signature": signature } : {}) },
    body: new URLSearchParams(params).toString(),
  });
}

test("health check", async () => {
  const res = await fetch(`${base}/healthz`);
  assert.equal(res.status, 200);
});

test("unsigned webhooks are rejected", async () => {
  const res = await twilioPost("/twilio/voice/incoming", { To: "+41445550000", CallSid: "CA1" }, false);
  assert.equal(res.status, 403);
});

test("an incoming call to a firm number connects the AI relay", async () => {
  const res = await twilioPost("/twilio/voice/incoming", { To: "+41445550000", From: "+41795551234", CallSid: "CA2" });
  const xml = await res.text();
  assert.match(xml, /<ConversationRelay url="wss:\/\/voice.example.com\/twilio\/relay"/);
  assert.match(xml, /action="https:\/\/voice.example.com\/twilio\/voice\/relay-ended"/);
  assert.match(xml, /Grüezi, Taxi Test/);
});

test("unknown numbers go to the core's safety net", async () => {
  const res = await twilioPost("/twilio/voice/incoming", { To: "+41000000000", CallSid: "CA3" });
  assert.match(await res.text(), /<Redirect method="POST">https:\/\/core.example.com\/twilio\/voice\/fallback<\/Redirect>/);
});

test("a transfer handoff dials the dispatcher with no-answer handled by the core", async () => {
  const handoff = JSON.stringify({ reason: "transfer", dispatcherPhone: "+41791234567", language: "de" });
  const res = await twilioPost("/twilio/voice/relay-ended", { CallSid: "CA4", HandoffData: handoff });
  const xml = await res.text();
  assert.match(xml, /<Number>\+41791234567<\/Number>/);
  assert.match(xml, /action="https:\/\/core.example.com\/twilio\/voice\/dial_status"/);
});

test("a completed call hangs up", async () => {
  const res = await twilioPost("/twilio/voice/relay-ended", { CallSid: "CA5", HandoffData: JSON.stringify({ reason: "completed", language: "de" }) });
  assert.match(await res.text(), /<Hangup\/>/);
});
