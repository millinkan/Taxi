// WebSocket legs of the end-to-end scenarios. Prints one JSON line.
//
//   node ws_trip.mjs trip  <base> <dispatch_token> <public_token> <pickup_lat> <pickup_lng>
//     driver streams 4 positions closing in on the pickup; customer watches,
//     then tries to inject a fake position of its own.
//   node ws_trip.mjs fleet <base> <tenant_id> <cookie header>
//     is this login allowed to watch this firm's fleet?
import { createRequire } from "node:module";

const require = createRequire(new URL("../voice/package.json", import.meta.url));
const WebSocket = require("ws");
const [mode, base, ...args] = process.argv.slice(2);
const wsUrl = base.replace(/^http/, "ws") + "/cable";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function connect(identifier, cookie) {
  return new Promise((resolve) => {
    const headers = { Origin: base, ...(cookie ? { Cookie: cookie } : {}) };
    const ws = new WebSocket(wsUrl, ["actioncable-v1-json"], { headers });
    const messages = [];
    ws.on("message", (raw) => {
      const msg = JSON.parse(raw);
      if (msg.type === "welcome") ws.send(JSON.stringify({ command: "subscribe", identifier }));
      if (msg.type === "confirm_subscription") resolve({ ws, messages, confirmed: true });
      if (msg.type === "reject_subscription") resolve({ ws, messages, confirmed: false });
      if (msg.message) messages.push({ ...msg.message, receivedAt: performance.now() });
    });
    ws.on("error", () => resolve({ ws, messages, confirmed: false }));
  });
}

const perform = (conn, identifier, data) =>
  conn.ws.send(JSON.stringify({ command: "message", identifier, data: JSON.stringify(data) }));

if (mode === "trip") {
  const [dispatchToken, publicToken, pickupLat, pickupLng] = args;
  const driverId = JSON.stringify({ channel: "TripChannel", dispatch_token: dispatchToken });
  const customerId = JSON.stringify({ channel: "TripChannel", public_token: publicToken });
  const driver = await connect(driverId);
  const customer = await connect(customerId);

  // Approach from ~2 km north of the pickup.
  const sent = [];
  for (let i = 0; i < 4; i++) {
    const lat = Number(pickupLat) + 0.018 * (1 - i / 4);
    const point = { action: "update", lat: Number(lat.toFixed(6)), lng: Number(pickupLng), heading: 180, accuracy: 8 };
    sent.push({ lat: point.lat, at: performance.now() });
    perform(driver, driverId, point);
    await sleep(1150);
  }
  // A customer must not be able to move the car.
  perform(customer, customerId, { action: "update", lat: 10.0, lng: 10.0, accuracy: 5 });
  await sleep(1300);

  const positions = customer.messages.filter((m) => m.lat != null && m.lat !== 10);
  const latencies = positions.map((m) => {
    const s = sent.find((p) => p.lat === m.lat);
    return s ? Math.round(m.receivedAt - s.at) : null;
  }).filter((v) => v != null);
  console.log(JSON.stringify({
    driver_confirmed: driver.confirmed,
    customer_confirmed: customer.confirmed,
    sent: sent.length,
    received: positions.length,
    distances_m: positions.map((m) => m.distance_m),
    eta_min: positions.map((m) => m.eta_min),
    latencies_ms: latencies,
    fake_seen: customer.messages.some((m) => m.lat === 10),
    last_lat: sent.at(-1).lat,
  }));
  driver.ws.close();
  customer.ws.close();
} else if (mode === "fleet") {
  const [tenantId, cookie] = args;
  const conn = await connect(JSON.stringify({ channel: "FleetChannel", tenant_id: Number(tenantId) }), cookie);
  console.log(JSON.stringify({ confirmed: conn.confirmed }));
  conn.ws.close();
}
process.exit(0);
