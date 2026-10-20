# The AI phone agent

## What it does

When the firm can't answer (busy, no answer, or at night), the call goes to
the agent. It greets the caller in the firm's name. It collects pickup,
destination, time, passengers and name. It gets the **official price from the
core**, reads it back, books only after a clear yes, and tells the caller an
SMS confirmation is on its way. The dispatcher receives the usual new-booking
SMS with a one-tap confirm link.

The agent hands the caller to a person when they ask for one, for complaints,
lost property or invoices, for rides needed sooner than the minimum lead time,
after two failed attempts to understand, and on **any** technical problem. In
a medical emergency it tells the caller to dial 144 or 112.

## Phone setup (once per firm)

1. **Buy a Twilio number** for the firm (Console › Phone Numbers). A Swiss
   `+41` number needs a regulatory address bundle. Callers never see this
   number, because the firm's existing line forwards to it.
2. On the number, set **A call comes in → Webhook (POST)**:
   `https://voice.<your-domain>/twilio/voice/incoming`
   and **Primary handler fails → (POST)**:
   `https://app.<your-domain>/twilio/voice/fallback`
3. In RideDesk Admin, set the firm's **voice number** to this Twilio number
   and tick **AI phone assistant active**.
4. On the firm's own phone line, set **conditional call forwarding** to the
   Twilio number. On most mobile networks the standard GSM codes work
   (confirm with the operator):
   - busy: `**67*<twilio number>#`
   - no answer (after ~20 s): `**61*<twilio number>**20#`
   - unreachable: `**62*<twilio number>#`
   - all three at once: `**004*<twilio number>#`; cancel with `##004#`

   This way the dispatcher still takes every call they can, and the agent only
   gets the ones that would otherwise be lost. For night service, the
   dispatcher can forward all calls (`**21*<number>#`, cancel `##21#`).
5. Call the firm's number, let it ring, and check the agent answers. Then
   check that **Calls** in the staff app shows the call with its transcript.

## Languages and Swiss German

ConversationRelay does the speech recognition and the voice. The agent gets
text and replies in standard German (or English after `switch_language`).

- Defaults: `CR_LANGUAGE=de-DE`, `CR_SECONDARY_LANGUAGE=en-US`, Twilio's
  default speech providers.
- **Swiss German is the main risk.** Dialect recognition differs a lot between
  providers and models. During the pilot week, make 10–20 test calls in dialect
  with real Rhine-valley place names, and compare the providers Twilio offers
  for `de-CH` and `de-DE` (set `CR_TRANSCRIPTION_PROVIDER`, `CR_SPEECH_MODEL`
  and, if you use it, `CR_LANGUAGE=de-CH`). Keep the setting that understands
  callers best. Check Twilio's current ConversationRelay documentation for the
  supported provider/language/voice combinations before changing them.
- Place names from the firm's Places are sent to the recogniser as **hints**,
  which helps with Schaan, Triesenberg, Altenrhein and similar names.
- The prompt tells the agent to interpret imperfect transcripts generously and
  to confirm addresses and times, which matter most.

## Testing without a phone

```powershell
cd voice
$env:CORE_API_URL="http://localhost:3000"; $env:INTERNAL_API_TOKEN="…"
npm run check-core -- +41445550000          # core reachable? prices? booking? (no Claude)
$env:ANTHROPIC_API_KEY="sk-ant-…"
npm run simulate -- +41445550000 +41795551234
```

`simulate` lets you play the caller in the terminal against the real core and
the real model. Bookings it makes are real. It's the fastest way to tune the
prompt and to demo the agent to a firm owner.

## How a call is processed (code map)

| File | Role |
|---|---|
| `src/app.ts` | HTTP webhooks, signature checks, websocket upgrade, handoff TwiML |
| `src/relay/session.ts` | One call: turn queue, streaming, barge-in, tools, handoff, call log |
| `src/agent/prompt.ts` | Static instructions (cached) and per-call context |
| `src/agent/tools.ts` | Tool definitions, zod validation, execution against the core |
| `src/agent/llm.ts` | Claude streaming request (model, effort, adaptive thinking, refusal fallback, caching) |
| `src/core/client.ts` | Internal API client with timeouts, retries, last-known-good firm cache |

Design rules (see [adr/0004](adr/0004-voice-agent-design.md)):
- History is append-only. Interruptions are added as new messages.
- Every tool input is validated before use. A rejected input goes back to the
  model as an error so it can ask again.
- `create_booking` uses the tool-use ID as its idempotency key.
- Any exception, refusal, too many steps, or the call time limit leads to an
  apology and a transfer. Silence is never an outcome.

## Costs (estimates; measure in the pilot)

- **Twilio**: inbound minutes plus ConversationRelay per-minute pricing, plus
  SMS. Check current prices in the Twilio console.
- **Claude**: a typical booking call is 6–10 model turns. With
  `claude-opus-5-5` at $4 / $20 per million input/output tokens, that's
  roughly USD 0.10–0.30 per call before caching. The static instructions are
  marked for prompt caching.
- Compare this with the value of one saved airport transfer (CHF 290). One
  saved booking a month covers many hundreds of calls.
