import type { BookingRequest, BookingResponse, CallLogPayload, CoreApi, QuoteRequest, QuoteResponse, TenantConfig } from "../src/core/client.js";
import type { LlmRunner, Message, TurnRequest } from "../src/agent/llm.js";
import type { OutboundMessage } from "../src/relay/protocol.js";

export const tenant: TenantConfig = {
  id: 7,
  name: "Taxi Test",
  slug: "taxi-test",
  time_zone: "Europe/Vaduz",
  now_local: "2026-10-19T22:14:00+02:00",
  currency: "CHF",
  default_locale: "de",
  voice_agent_enabled: true,
  voice_greeting: null,
  dispatcher_phone: "+41791234567",
  public_phone: "+4232300000",
  home_area_label: "Liechtenstein",
  min_lead_minutes: 20,
  max_advance_days: 180,
  free_cancellation_hours: 2,
  asap_enabled: true,
  asap_response_minutes: 3,
  booking_url: "https://app.example.com/taxi-test",
  places: [{ id: 1, name: "Flughafen Zürich", kind: "airport", aliases: ["ZRH"] }],
};

export const quote: QuoteResponse = {
  ok: true,
  error: null,
  price_cents: 29000,
  price_text: "CHF 290",
  price_source: "fixed_route",
  estimated: false,
  vehicle_category: "standard",
  distance_km: 104,
  duration_min: 80,
  pickup: { label: "Vaduz", located: true },
  dropoff: { label: "Flughafen Zürich", located: true },
  pickup_at_local: "2026-10-20T06:00:00+02:00",
  lead_time_ok: true,
  asap_available: true,
  capacity_available: true,
};

export class FakeCore implements CoreApi {
  quotes: QuoteRequest[] = [];
  bookings: BookingRequest[] = [];
  calls: CallLogPayload[] = [];
  failQuotes = false;

  async tenantForNumber(number: string) {
    return number === "+41445550000" ? tenant : null;
  }
  async quote(request: QuoteRequest) {
    if (this.failQuotes) throw new Error("core down");
    this.quotes.push(request);
    return quote;
  }
  async createBooking(request: BookingRequest): Promise<BookingResponse> {
    this.bookings.push(request);
    return {
      ok: true,
      booking: {
        reference: "ABC234", status: "pending", pickup_at_local: request.pickup_at, pickup_address: request.pickup_address,
        dropoff_address: request.dropoff_address, price_text: "CHF 290", status_url: "https://x/b/t",
      },
    };
  }
  async recordCall(payload: CallLogPayload) {
    this.calls.push(payload);
  }
}

type Block = { type: "text"; text: string } | { type: "tool_use"; id: string; name: string; input: unknown };
export interface Step {
  blocks: Block[];
  stop_reason?: "end_turn" | "tool_use" | "max_tokens" | "refusal";
  // Stream the text then hang until aborted (simulates a barge-in).
  hangAfterText?: boolean;
  throws?: Error;
}

// Scripted model: each runTurn() consumes the next step.
export class ScriptedLlm implements LlmRunner {
  requests: { messages: unknown[] }[] = [];
  constructor(private readonly steps: Step[]) {}

  async runTurn({ messages, onText, signal }: TurnRequest): Promise<Message> {
    // Snapshot: the session must never mutate earlier history.
    this.requests.push({ messages: structuredClone(messages) });
    const step = this.steps.shift();
    if (!step) throw new Error("script exhausted");
    if (step.throws) throw step.throws;

    for (const block of step.blocks) if (block.type === "text") onText(block.text);
    if (step.hangAfterText) {
      await new Promise((_, reject) => signal.addEventListener("abort", () => reject(new Error("aborted"))));
    }
    const hasTool = step.blocks.some((b) => b.type === "tool_use");
    return {
      id: "msg_test",
      type: "message",
      role: "assistant",
      model: "claude-opus-5-5",
      content: step.blocks,
      stop_reason: step.stop_reason ?? (hasTool ? "tool_use" : "end_turn"),
      stop_sequence: null,
      usage: { input_tokens: 1, output_tokens: 1 },
    } as unknown as Message;
  }
}

export function recorder() {
  const sent: OutboundMessage[] = [];
  return { sent, send: (m: OutboundMessage) => sent.push(m) };
}

export const noWait = async () => {};
