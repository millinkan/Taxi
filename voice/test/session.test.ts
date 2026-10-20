import { test } from "node:test";
import assert from "node:assert/strict";
import { CallSession } from "../src/relay/session.js";
import { FakeCore, ScriptedLlm, recorder, noWait, type Step } from "./helpers.js";

const setup = { type: "setup" as const, sessionId: "s1", callSid: "CA_test", from: "+41795551234", to: "+41445550000" };
const say = (text: string) => ({ type: "prompt" as const, voicePrompt: text, last: true });

function session(steps: Step[], core = new FakeCore()) {
  const llm = new ScriptedLlm(steps);
  const out = recorder();
  const s = new CallSession({
    core, llm, send: out.send,
    resolveTenant: (msg) => core.tenantForNumber(msg.to ?? ""),
    languages: { de: "de-DE", en: "en-US" },
    maxCallSeconds: 600,
    wait: noWait,
  });
  return { s, llm, core, out };
}

const quoteCall = {
  type: "tool_use" as const, id: "toolu_q1", name: "get_quote",
  input: { pickup: "Vaduz", dropoff: "ZRH", pickup_time: "2026-10-20T06:00", passengers: 2 },
};
const bookCall = {
  type: "tool_use" as const, id: "toolu_b1", name: "create_booking",
  input: { pickup: "Vaduz", dropoff: "ZRH", pickup_time: "2026-10-20T06:00", passengers: 2, name: "Maria Beck" },
};

test("quotes, books and ends a call; history is append-only", async () => {
  const { s, llm, core, out } = session([
    { blocks: [{ type: "text", text: "Einen Moment, ich prüfe den Preis." }, quoteCall] },
    { blocks: [{ type: "text", text: "Das kostet zweihundertneunzig Franken. Soll ich buchen?" }] },
    { blocks: [bookCall] },
    { blocks: [{ type: "text", text: "Gebucht, Sie erhalten eine SMS. Auf Wiederhören." },
               { type: "tool_use", id: "toolu_e1", name: "end_call", input: { reason: "booked" } }] },
  ]);

  await s.handle(setup);
  await s.handle(say("Morgen um sechs von Vaduz zum Flughafen Zürich, zwei Personen."));
  await s.handle(say("Ja, bitte. Maria Beck."));
  await s.close();

  // The core got the right requests, with the tool id as idempotency key.
  assert.equal(core.quotes[0]?.pickup_at, "2026-10-20T06:00");
  assert.equal(core.bookings[0]?.phone, "+41795551234");
  assert.equal(core.bookings[0]?.idempotency_key, "toolu_b1");
  assert.equal(core.bookings[0]?.call_sid, "CA_test");

  // Text streamed to Twilio, each utterance closed with last=true, then end.
  assert.ok(out.sent.some((m) => m.type === "text" && m.token.includes("zweihundertneunzig")));
  const end = out.sent.at(-1);
  assert.equal(end?.type, "end");
  assert.equal(JSON.parse((end as { handoffData: string }).handoffData).reason, "completed");

  // Every request's history is a prefix of the next one (nothing edited).
  for (let i = 1; i < llm.requests.length; i++) {
    const before = llm.requests[i - 1]!.messages;
    const after = llm.requests[i]!.messages;
    assert.deepEqual(after.slice(0, before.length), before);
  }

  const call = core.calls[0]!;
  assert.equal(call.outcome, "booked");
  assert.equal(call.summary, "Booked ABC234.");
  assert.ok(call.transcript.some((t) => t.role === "caller" && t.text.startsWith("Ja, bitte")));
});

test("invalid tool input is returned to the model as an error, not sent to the core", async () => {
  const { s, llm, core } = session([
    { blocks: [{ type: "tool_use", id: "toolu_bad", name: "get_quote", input: { pickup: "Vaduz" } }] },
    { blocks: [{ type: "text", text: "Wohin möchten Sie?" }] },
  ]);
  await s.handle(setup);
  await s.handle(say("Ein Taxi bitte"));

  assert.equal(core.quotes.length, 0);
  const lastRequest = llm.requests[1]!.messages as { role: string; content: { is_error?: boolean }[] }[];
  assert.equal(lastRequest.at(-1)?.content[0]?.is_error, true);
});

test("barge-in keeps what was said and continues with the next utterance", async () => {
  const { s, llm, out } = session([
    { blocks: [{ type: "text", text: "Wir haben morgen früh noch Fahrzeuge frei und" }], hangAfterText: true },
    { blocks: [{ type: "text", text: "Natürlich, um sieben Uhr." }] },
  ]);
  await s.handle(setup);
  const first = s.handle(say("Ich brauche morgen ein Taxi"));
  await new Promise((r) => setImmediate(r));
  await s.handle({ type: "interrupt", utteranceUntilInterrupt: "Wir haben morgen" });
  await first;
  await s.handle(say("Um sieben bitte"));

  const history = llm.requests[1]!.messages as { role: string; content: unknown }[];
  assert.deepEqual(history.map((m) => m.role), ["user", "assistant", "user"]);
  assert.ok(out.sent.some((m) => m.type === "text" && m.token.includes("sieben Uhr")));
});

test("a model failure hands the caller to the dispatcher instead of going silent", async () => {
  const { s, core, out } = session([{ blocks: [], throws: new Error("overloaded") }]);
  await s.handle(setup);
  await s.handle(say("Hallo?"));
  await new Promise((r) => setImmediate(r));
  await s.close();

  assert.ok(out.sent.some((m) => m.type === "text" && m.token.includes("Disposition")));
  const end = out.sent.find((m) => m.type === "end") as { handoffData: string } | undefined;
  const handoff = JSON.parse(end!.handoffData);
  assert.equal(handoff.reason, "error");
  assert.equal(handoff.dispatcherPhone, "+41791234567");
  assert.equal(core.calls[0]?.outcome, "transferred");
});

test("core outage during a tool tells the model and keeps the call alive", async () => {
  const core = new FakeCore();
  core.failQuotes = true;
  const { s, llm } = session([
    { blocks: [quoteCall] },
    { blocks: [{ type: "text", text: "Ich verbinde Sie." }, { type: "tool_use", id: "toolu_t", name: "transfer_to_human", input: { reason: "system down" } }] },
  ], core);
  await s.handle(setup);
  await s.handle(say("Was kostet es zum Flughafen?"));

  const toolResult = (llm.requests[1]!.messages.at(-1) as { content: { content: string }[] }).content[0]!.content;
  assert.match(toolResult, /SERVICE_UNAVAILABLE/);
  assert.equal(s.outcome(), "transferred");
});

test("an English caller switches the voice and the booking locale", async () => {
  const { s, core, out } = session([
    { blocks: [{ type: "tool_use", id: "toolu_l", name: "switch_language", input: { language: "en" } }] },
    { blocks: [bookCall] },
    { blocks: [{ type: "text", text: "Booked." }] },
  ]);
  await s.handle(setup);
  await s.handle(say("Hello, do you speak English? Book me to Zurich airport tomorrow at six."));

  assert.ok(out.sent.some((m) => m.type === "language" && m.ttsLanguage === "en-US"));
  assert.equal(core.bookings[0]?.locale, "en");
});
