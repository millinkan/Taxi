# Architecture

## Goals that shaped the design

1. **Never lose a booking.** Every external dependency (maps, the language
   model, SMS, even the voice service itself) has a fallback that still ends
   with a booking or a human.
2. **One codebase, many firms.** A new firm is configuration. Nothing in the
   code is specific to one firm.
3. **Prove the revenue.** Every call, message and status change is recorded,
   so the dashboard can show what the platform earned.
4. **Fit a 4-car firm whose dispatcher is also a driver.** Every dispatcher
   action has to work one-handed on a phone, without logging in.

## Services

| | `core/` (Rails 8.1, Ruby 3.3) | `voice/` (Node 22, TypeScript) |
|---|---|---|
| Owns | Firms, users, prices, places, bookings, customers, calls, SMS, empty legs, dashboards | Live phone conversations |
| State | SQLite (primary + Solid Queue/Cache/Cable) | None (in-memory per call) |
| Talks to | Twilio SMS API, Google Maps or OSM, Twilio voice webhooks (fallback) | Twilio ConversationRelay (websocket), Claude API, core internal API |
| Public URLs | Booking pages, staff app, dispatcher links, Twilio fallback webhooks | Twilio voice webhook and websocket |

The two services are split because their runtime profiles are opposites. The
core is classic request/response CRUD. Voice holds long-lived websockets and
streams tokens with low latency. Node is a natural fit for the second, and
keeping it stateless means a voice outage can never corrupt booking data. See
[adr/0001](adr/0001-two-services.md).

## Data model

```
Tenant (a taxi firm) ─┬─ User (owner / dispatcher / driver)
                      ├─ Vehicle
                      ├─ Tariff (per vehicle category: base, per km, per min, minimum, night %)
                      ├─ Place (airport, station, town… with radius and aliases)
                      ├─ FixedRoute (Place ⇄ Place, price per category)
                      ├─ Customer (unique per firm by phone)
                      ├─ Booking ─┬─ BookingEvent (audit trail: who did what)
                      │           ├─ MessageLog (every SMS, with delivery status)
                      │           └─ CallLog (call that produced it)
                      ├─ EmptyLeg (discounted return of a long trip)
                      └─ CallLog (every call, AI or fallback, with transcript)
User without a tenant = platform admin.
```

Money is always stored in integer minor units (`*_cents`, i.e. Rappen). Times
are stored in UTC and shown in the firm's time zone (`Europe/Vaduz`).

### Tenant isolation

Every firm-owned table has `tenant_id`. Controllers never call `Model.find` on
firm data; they always go through `Current.tenant.bookings.find(…)`, so a record
from another firm simply isn't found (404). Tests cover this for the staff
app, public status pages and settings forms (a forged place ID from another
firm is rejected). See [adr/0002](adr/0002-multi-tenancy.md).

## Pricing: one authority

`Pricing::Quoter` is the only code that produces prices. The web form, the
dispatcher form and the voice agent all call it, and a booking always stores
the **server-side** quote. A price sent by a browser or the model is never
trusted.

1. **Fixed route**: if pickup and drop-off fall inside the radius of two places
   joined by a fixed route for that vehicle category (both directions by
   default). The smallest matching areas win.
2. **Metered tariff**: `base + per_km × km + per_min × min`, plus the night
   surcharge inside the night window (which can cross midnight), at least the
   minimum fare, rounded (default CHF 1).
3. **On request**: when an address can't be located, the booking is still
   taken and the dispatcher sets the price. A missing map result never costs a
   booking.

Distances come from Google Routes or OSRM. If they fail, a straight-line
estimate (× 1.3 for roads, 55 km/h) is used and the price is flagged
`estimated` ("approx." to the customer).

Addresses resolve in this order: explicit place ID or coordinates → an exact
known place name or alias ("ZRH") → full geocoding of the address → the known
town mentioned in the address. The customer's wording is always kept as the
label the driver sees.

## Booking lifecycle

```
            ┌──────── declined
            │
 pending ───┼──────── cancelled
    │       │
    └─► confirmed ──► on_the_way ──► completed
             │             │
             ├─────────────┴──► cancelled / no_show
```

`Bookings::Creator` validates the request (lead time, phone, honeypot), resolves
addresses, prices the trip, finds or creates the customer by phone, stores the
booking and logs the event. It's the single entry point for all channels.
Retries are safe: a repeated `idempotency_key` returns the original booking.

`Bookings::Lifecycle` owns every status change and its side effects:

| Event | Side effects |
|---|---|
| Created | Auto-confirm if allowed (see below); otherwise SMS the dispatcher with a one-tap link, SMS "received" to the customer, and schedule an escalation reminder |
| Confirmed | SMS the customer; publish an empty leg if it qualifies |
| Declined / cancelled | SMS the other party; withdraw empty legs; free a sold empty-leg seat |
| On the way | SMS the customer |
| Completed | Final price recorded; Google review request one hour later (at most once per customer every 90 days) |

**Auto-confirm** happens only when it's switched on, the price is known and not
estimated, pickup is at least N hours away, and `DispatchCapacity` finds a free
car. Capacity counts committed bookings whose busy window overlaps. A trip out
of the area blocks the car for the drive back too.

**Empty legs**: when a confirmed trip ends at a named place outside the
service area and is at least 40 km long, the return to the firm's home area is
published at a discount (default 40%). The customer's own address is never
published. Selling a seat is an atomic check-and-set, so two buyers can't both
get it.

## The phone path and its safety net

```
Incoming call to the firm's Twilio number
  └─► voice POST /twilio/voice/incoming  (signature checked)
        ├─ firm unknown, AI disabled, or core lookup failed ──► <Redirect> core /twilio/voice/fallback
        └─ <Connect><ConversationRelay> ──► websocket /twilio/relay
              CallSession: caller speech (text) → Claude (streaming, tools) → text → Twilio TTS
              tools: get_quote · create_booking · transfer_to_human · end_call · switch_language
              on transfer / any error: speak one sentence ──► end with HandoffData
  └─► voice POST /twilio/voice/relay-ended
        ├─ completed ──► hang up
        └─ transfer / error ──► <Dial dispatcher action=core /twilio/voice/dial_status>
core /twilio/voice/dial_status: answered → done · no answer → <Record> voicemail
core /twilio/voice/voicemail: SMS the recording to the dispatcher, SMS the caller a booking link
If the voice service is down entirely, Twilio's "primary handler fails" URL points at the core fallback.
```

Details and the conversation design are in [VOICE_AGENT.md](VOICE_AGENT.md).

## Live tracking

```
driver phone (/d/<token> page)                     customer phone (/b/<token> page)
  watchPosition (fresh fixes only) ─► sends on ≥10 m moved / 10 s ─┐      ▲ live map, car glides between fixes
  Wake Lock keeps the screen on                                    │      │
                                                                   ▼      │
                        ActionCable WebSocket: TripChannel ──► "trip:<id>"  ──┘
                                                │
                    Tracking.record: 1 UPDATE (≥1 s apart, ride active, ≤250 m accuracy)
                                                └──► "fleet:<tenant>" ──► dispatcher /dispatch/live
```

* **Transport:** WebSockets via ActionCable, with no Redis and no MQTT broker
  to run. MQTT would only pay off with a native driver app on unreliable
  networks; the `Tracking` module would then take positions from the broker.
* **Latency:** production uses the `local_first` adapter
  (`lib/action_cable/subscription_adapter/local_first.rb`). Messages reach
  subscribers in the same process immediately, and Solid Cable carries them
  to other processes. Plain Solid Cable polls the database every 100 ms. The
  driver's and the customer's sockets share the web process, so positions
  skip that wait. The server work per position is one indexed `UPDATE` and
  two broadcasts: 1.4 ms median, measured. The channel keeps the ride in
  memory, so there are no reads.
  Measured end to end (driver send → customer receive) on the Windows
  development machine: median 71 ms → 23 ms in production mode. About 20 ms
  of that is Windows' 15.6 ms timer granularity (a 1 ms sleep takes 15 ms
  there), which Linux servers don't have. On the road, the mobile network
  (tens of ms each way) and the phone's GPS rate (about 1 fix/s) dominate.
  So the server stays in Switzerland, close to the riders.
* **Battery and data:** the GPS is on for the whole ride anyway, so each
  ~100-byte frame costs next to nothing. The phone sends every fresh fix once
  the car has moved 10 m (10 s heartbeat when standing), and the server keeps
  at most one point per second.
* **Web limit:** browsers stop location updates when the screen locks, so the
  driver page holds a Screen Wake Lock (phone mounted and charging).
  Background tracking needs a native app later; the server side is ready for one.
* **Access:** drivers and customers authenticate with the same secret tokens
  as their SMS links; customers are read-only and only see confirmed or
  active rides. The fleet map is for the firm's dispatchers only.
* **Privacy:** one row per ride holds only the *latest* point. It is written
  only between confirmation and the end of the ride, and cleared on
  completion, cancellation or no-show. There is no location history and no
  off-duty tracking.
* **ETA:** straight-line distance × 1.3 at 35 km/h. It's deliberately simple:
  there's no routing API call per position update.

## Background jobs

| Job | When |
|---|---|
| `DeliverMessageJob` | Every SMS; retried 5× with backoff, then marked failed |
| `EscalatePendingBookingJob` | N minutes after a booking that still needs confirming |
| `RequestReviewJob` | 1 h after completion |
| `ExpireEmptyLegsJob` | Every 15 minutes (`config/recurring.yml`) |
| `DataRetentionJob` | Daily at 03:00: anonymisation and transcript wipe |

Production runs Solid Queue inside Puma (`SOLID_QUEUE_IN_PUMA`). Development on
Windows uses the in-process `:async` adapter.

## Scaling path

The pilot runs on one small VPS. Taxi bookings are low-volume writes, so SQLite
in WAL mode comfortably serves dozens of firms. When you outgrow it:

1. Move the core database to PostgreSQL (`DATABASE_URL`). The code uses no
   SQLite-specific SQL. See [adr/0003](adr/0003-sqlite-first.md).
2. Run more voice instances behind the proxy. They're stateless.
3. Split Solid Queue into its own process (`bin/jobs`).
