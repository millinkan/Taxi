# Internal API (voice → core)

Base path `/internal/v1`. JSON in and out. Every request needs
`Authorization: Bearer <INTERNAL_API_TOKEN>`. Without the token configured in
the core, the API answers `503 internal_api_disabled`.

Times are firm-local wall-clock strings (`2026-10-20T06:00`); an explicit
offset is honoured. Errors are `{ "ok": false, "error" | "errors": … }`.

## GET /voice/tenant?number=+41445550000
The firm whose voice number was dialled. `404 unknown_number` otherwise.
```json
{ "ok": true, "tenant": { "id": 1, "name": "Taxi Demo Vaduz", "slug": "taxi-demo", "time_zone": "Europe/Vaduz",
  "now_local": "2026-10-19T21:24:36+02:00", "currency": "CHF", "default_locale": "de",
  "voice_agent_enabled": true, "voice_greeting": null, "dispatcher_phone": "+41791234567",
  "public_phone": "+4232300000", "home_area_label": "Liechtenstein", "min_lead_minutes": 20,
  "max_advance_days": 180, "free_cancellation_hours": 2, "booking_url": "https://…/taxi-demo",
  "places": [ { "id": 14, "name": "Flughafen Zürich", "kind": "airport", "aliases": ["ZRH", "…"] } ] } }
```

## POST /quotes
```json
{ "tenant_id": 1, "pickup_address": "Vaduz", "dropoff_address": "ZRH", "pickup_at": "2026-10-20T06:00",
  "passengers": 2, "vehicle_category": "standard" }
```
→
```json
{ "ok": true, "error": null, "price_cents": 29000, "price_text": "CHF 290", "price_source": "fixed_route",
  "estimated": false, "vehicle_category": "standard", "distance_km": 104.1, "duration_min": 82,
  "pickup": { "label": "Vaduz", "located": true }, "dropoff": { "label": "Flughafen Zürich", "located": true },
  "pickup_at_local": "2026-10-20T06:00:00+02:00", "lead_time_ok": true, "capacity_available": true }
```
`error: "outside_service_area"` when neither end is in the firm's area.
`price_source: "on_request"` when an address couldn't be located.

## POST /bookings
Quote fields plus `name`, `phone`, optional `luggage`, `flight_number`,
`notes`, `locale`, `call_sid`, `asap` (true for a "taxi now" request: no lead
time, the dispatcher answers with an ETA by SMS within the firm's
`asap_response_minutes`; the quote response reports `asap_available`), and **`idempotency_key`** (required by the
voice agent: the tool-use ID). The same key returns the original booking.
→ `201 { "ok": true, "booking": { "reference": "ZH4K7P", "status": "pending", "pickup_at_local": "…",
"pickup_address": "…", "dropoff_address": "…", "price_text": "CHF 290", "status_url": "…" } }`
or `422 { "ok": false, "errors": ["Abholzeit muss mindestens 20 Minuten in der Zukunft liegen"] }`.
When `call_sid` is given, the call log is linked to the booking.

## POST /call_logs
Upsert by `call_sid`: `tenant_id, call_sid, from_number, to_number, started_at, ended_at, duration_s,
outcome (booked|transferred|information|abandoned|failed|…), language, summary, handled_by, transcript[{role, text}]`.
A call with a booking always stays `booked`. Abandoned callers get the
missed-call SMS (at most once per number per day).
