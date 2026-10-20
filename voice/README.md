# RideDesk voice (Node)

The AI phone agent: Twilio ConversationRelay plus Claude, booking through the
core's internal API. Design and setup: [../docs/VOICE_AGENT.md](../docs/VOICE_AGENT.md).

```powershell
npm install
npm run typecheck; npm test; npm run build
npm run dev                                       # needs the variables in .env.example
npm run check-core -- +41445550000                # core reachable? (no Claude)
npm run simulate -- +41445550000 +41795551234     # talk to the agent in the terminal
```

| Path | What |
|---|---|
| `src/app.ts` | Webhooks, signature checks, websocket, handoff |
| `src/relay/session.ts` | One call: streaming, barge-in, tools, failure → human |
| `src/agent/` | Prompt, tools (zod-validated), Claude runner |
| `src/core/client.ts` | Internal API client |
| `src/twilio/` | Signature verification, TwiML |
| `test/` | Unit and HTTP tests with a scripted model and a fake core |
| `scripts/` | `simulate-call.ts`, `check-core.ts` |
