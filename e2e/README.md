# End-to-end scenario tests

The unit and integration tests (`core/test`) check each piece in isolation.
These scenarios check the **running system**: a real server, real HTTP
requests with sessions and CSRF tokens, real WebSocket connections,
background jobs firing on their own clock, signed Twilio webhooks, and the
voice service's integration check. Each scenario follows one person through
one real situation.

```bash
bash e2e/run.sh          # ~3 minutes; prints PASS/FAIL per step, exit code 1 on any failure
```

`run.sh` starts an isolated server on port 3070 with a fresh, throwaway
database (`core/storage/e2e.sqlite3`, seeded with the demo firm). Your
development data is never touched. It needs Ruby, Node, and `npm install` in
`voice/`.

## Scenarios

| # | Who | Situation | What must happen |
|---|---|---|---|
| S1 | Customer at a bar, driver, dispatcher | 23:00, needs a taxi **now**, shares GPS | Request without lead time · dispatcher gets "TAXI SOFORT" SMS · taps ETA 10 min · customer SMS "Ankunft in ca. 10 Min." · driver starts · **live positions reach the customer over WebSocket**, distance shrinking · customer cannot inject positions · ride completed, position deleted |
| S2 | Customer, nobody answers | Taxi-now request, dispatcher busy | After the firm's response window the customer is told "kein Fahrzeug frei" by SMS, dispatcher gets a "VERPASST" SMS, status page offers to try again (**real timer**, ~1 min) |
| S3 | Traveller, second customer | Vaduz → Zurich Airport tomorrow 06:00, flight LX318 | Fixed price CHF 290 · confirmed from the SMS link · **empty leg** ZRH → Liechtenstein published at a discount · a second customer books it · deal disappears |
| S4 | Customer | Changes plans | Cancels online · dispatcher gets a cancellation SMS |
| S5 | Traveller from S3 | Wants the way back | One-tap return link pre-fills the reversed route · booking linked to the outward ride |
| S6 | Caller, AI phone agent | Calls at night | Voice service ↔ core check passes (`check-core`) · agent sees "too soon" but taxi-now available · agent books a taxi-now request · call linked · dispatcher taps "no car free" · API refuses requests without the token |
| S7 | Caller, AI down | Voice service unreachable, dispatcher doesn't answer | Signed Twilio webhooks: ring dispatcher → voicemail → SMS recording to dispatcher + booking link to caller · unsigned or forged webhooks refused |
| S8 | Someone asking Google / an AI | "taxi bendern", "taxi zurich airport liechtenstein" | robots + sitemap list the pages · llms.txt and discovery.json carry the Taxi-now link · the AI's pre-filled link opens a filled form · booking attributed to `ai_assistant` · locality and transfer pages show real prices · schema.org order action present |
| S9 | Platform admin | Runs the platform in English | Login · switch to EN · onboard a new firm · discovery page · push (IndexNow/Google correctly skipped on localhost) · Google Ads CSV · locality sync |
| S10 | Dispatcher | Takes a phone booking | Manual booking confirmed at once · board and live map load |
| S11 | Rival firm | Tries to look at another firm's data | Rides, status pages, fleet WebSocket, admin area, bad SMS tokens: all refused |
| S12 | Spammer | Floods the booking form | Rate limit stops it; no more than 10 bookings per 10 minutes from one client |

## What this does not cover

* **The spoken conversation with Claude.** It needs `ANTHROPIC_API_KEY` and a
  phone line. Its decisions are covered by `voice/test/session.test.ts`
  (scripted model), and its tool calls are what S6 exercises. Try it by hand
  with `npm run simulate`.
* **Real SMS delivery and real GPS.** SMS run through the log adapter and
  are checked in the message log; positions are synthetic.
* **Mobile browsers.** Geolocation permission, Wake Lock and the map are
  browser features; check them on a phone before the pilot.
