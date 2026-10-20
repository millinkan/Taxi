// Deployment check: can the voice service reach the core and does the
// internal API behave? Runs the same calls the agent makes, without Claude.
//
//   CORE_API_URL=... INTERNAL_API_TOKEN=... npm run check-core -- +41445550000
//
// Creates one clearly-marked test booking (pass --no-booking to skip it).
import { HttpCoreApi } from "../src/core/client.js";

const [number, flag] = process.argv.slice(2);
if (!number) {
  console.error("usage: npm run check-core -- <firm voice number> [--no-booking]");
  process.exit(1);
}

const core = new HttpCoreApi(process.env.CORE_API_URL ?? "http://localhost:3000", process.env.INTERNAL_API_TOKEN ?? "");
const tenant = await core.tenantForNumber(number);
if (!tenant) throw new Error(`no firm for ${number}`);
console.log(`firm      : ${tenant.name} (#${tenant.id}), ${tenant.places.length} places, local time ${tenant.now_local}`);

const tomorrow = new Date(Date.parse(tenant.now_local) + 24 * 3600 * 1000).toISOString().slice(0, 10);
const quote = await core.quote({
  tenant_id: tenant.id, pickup_address: "Vaduz", dropoff_address: "ZRH", pickup_at: `${tomorrow}T06:00`, passengers: 2,
});
console.log(`quote     : ${quote.price_text} (${quote.price_source}) ${quote.pickup.label} -> ${quote.dropoff.label}, capacity ${quote.capacity_available}`);

if (flag !== "--no-booking") {
  const booking = await core.createBooking({
    tenant_id: tenant.id, pickup_address: "Vaduz", dropoff_address: "ZRH", pickup_at: `${tomorrow}T06:00`, passengers: 2,
    name: "TEST check-core", phone: "+41790000000", notes: "Automated deployment check - please decline.",
    locale: "de", call_sid: `CHECK${Date.now()}`, idempotency_key: `check-${tomorrow}`,
  });
  console.log(`booking   : ${booking.ok ? `${booking.booking?.reference} ${booking.booking?.status}` : booking.errors?.join("; ")}`);
}

await core.recordCall({
  tenant_id: tenant.id, call_sid: `CHECK${Date.now()}`, started_at: new Date().toISOString(), ended_at: new Date().toISOString(),
  duration_s: 0, outcome: "information", language: "de", summary: "check-core script", handled_by: "ai", transcript: [],
});
console.log("call log  : recorded\nOK");
