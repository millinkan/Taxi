import type Anthropic from "@anthropic-ai/sdk";
import { z } from "zod";
import type { CoreApi, TenantConfig } from "../core/client.js";

type Tool = Anthropic.Beta.Messages.BetaTool;

const localTime = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/, "local time as YYYY-MM-DDTHH:MM");
const category = z.enum(["standard", "van", "premium"]);

// Zod schemas are the runtime check; JSON schemas below are what Claude sees.
// With eager input streaming the API does not validate tool input, so every
// input is parsed here before it touches the core.
export const schemas = {
  get_quote: z.object({
    pickup: z.string().min(2),
    dropoff: z.string().min(2),
    pickup_time: localTime,
    passengers: z.number().int().min(1).max(16),
    vehicle_category: category.optional(),
  }),
  create_booking: z.object({
    pickup: z.string().min(2),
    dropoff: z.string().min(2),
    pickup_time: localTime,
    passengers: z.number().int().min(1).max(16),
    luggage: z.number().int().min(0).max(20).optional(),
    vehicle_category: category.optional(),
    name: z.string().min(1).max(80),
    phone: z.string().min(5).max(30).optional(),
    flight_number: z.string().max(10).optional(),
    notes: z.string().max(300).optional(),
    asap: z.boolean().optional(),
  }),
  transfer_to_human: z.object({ reason: z.string().min(2).max(200) }),
  end_call: z.object({ reason: z.enum(["booked", "information", "caller_done", "emergency"]) }),
  switch_language: z.object({ language: z.enum(["de", "en"]) }),
} as const;

export type ToolName = keyof typeof schemas;

const timeProp = { type: "string", description: "Pickup in the firm's local time, format YYYY-MM-DDTHH:MM." };
const categoryProp = {
  type: "string",
  enum: ["standard", "van", "premium"],
  description: "Only if the caller asks; otherwise chosen from the passenger count.",
};

export const TOOLS: Tool[] = [
  {
    name: "get_quote",
    description:
      "Price and availability for a trip. Resolves the addresses and returns the official price. Call this before quoting any price.",
    input_schema: {
      type: "object",
      properties: {
        pickup: { type: "string", description: "Pickup address or known place, as the caller said it." },
        dropoff: { type: "string", description: "Destination address or known place." },
        pickup_time: timeProp,
        passengers: { type: "integer", minimum: 1, maximum: 16 },
        vehicle_category: categoryProp,
      },
      required: ["pickup", "dropoff", "pickup_time", "passengers"],
      additionalProperties: false,
    },
    eager_input_streaming: true,
  },
  {
    name: "create_booking",
    description:
      "Books the trip. Only call after the caller has heard the price and clearly agreed. Call once per trip.",
    input_schema: {
      type: "object",
      properties: {
        pickup: { type: "string" },
        dropoff: { type: "string" },
        pickup_time: timeProp,
        passengers: { type: "integer", minimum: 1, maximum: 16 },
        luggage: { type: "integer", minimum: 0, maximum: 20 },
        vehicle_category: categoryProp,
        name: { type: "string", description: "Caller's name." },
        phone: { type: "string", description: "Only if different from the caller ID or caller ID is unknown." },
        flight_number: { type: "string", description: "For airport pickups, e.g. LX318." },
        notes: { type: "string", description: "Anything the driver must know: child seat, meeting point." },
        asap: {
          type: "boolean",
          description:
            "true for a taxi right now (pass the current local time as pickup_time). The dispatcher then confirms the arrival time by SMS.",
        },
      },
      required: ["pickup", "dropoff", "pickup_time", "passengers", "name"],
      additionalProperties: false,
    },
    eager_input_streaming: true,
  },
  {
    name: "transfer_to_human",
    description: "Connect the caller to the dispatcher. Say one short sentence first.",
    input_schema: {
      type: "object",
      properties: { reason: { type: "string" } },
      required: ["reason"],
      additionalProperties: false,
    },
    eager_input_streaming: true,
  },
  {
    name: "end_call",
    description: "End the call after saying goodbye.",
    input_schema: {
      type: "object",
      properties: { reason: { type: "string", enum: ["booked", "information", "caller_done", "emergency"] } },
      required: ["reason"],
      additionalProperties: false,
    },
    eager_input_streaming: true,
  },
  {
    name: "switch_language",
    description: "Switch speech recognition and voice to the caller's language.",
    input_schema: {
      type: "object",
      properties: { language: { type: "string", enum: ["de", "en"] } },
      required: ["language"],
      additionalProperties: false,
    },
    eager_input_streaming: true,
  },
];

// What a tool call changes about the call itself.
export type CallEffect =
  | { kind: "none" }
  | { kind: "booked"; reference: string }
  | { kind: "transfer"; reason: string }
  | { kind: "end"; reason: string }
  | { kind: "language"; language: "de" | "en" };

export interface ToolOutcome {
  content: string;
  isError: boolean;
  effect: CallEffect;
}

export interface ToolContext {
  core: CoreApi;
  tenant: TenantConfig;
  callSid: string;
  callerNumber: string | null;
  language: () => "de" | "en";
}

export async function runTool(name: string, rawInput: unknown, toolUseId: string, ctx: ToolContext): Promise<ToolOutcome> {
  if (!(name in schemas)) return error(`unknown tool ${name}`);
  const parsed = schemas[name as ToolName].safeParse(rawInput);
  if (!parsed.success) {
    return error(`INVALID_INPUT: ${parsed.error.issues.map((i) => `${i.path.join(".")} ${i.message}`).join("; ")}`);
  }

  switch (name as ToolName) {
    case "get_quote": {
      const input = parsed.data as z.infer<typeof schemas.get_quote>;
      const quote = await ctx.core.quote({
        tenant_id: ctx.tenant.id,
        pickup_address: input.pickup,
        dropoff_address: input.dropoff,
        pickup_at: input.pickup_time,
        passengers: input.passengers,
        vehicle_category: input.vehicle_category,
      });
      return ok(
        JSON.stringify({
          price: quote.price_text,
          price_is_estimate: quote.estimated,
          price_type: quote.price_source,
          error: quote.error,
          pickup: quote.pickup,
          dropoff: quote.dropoff,
          pickup_time: quote.pickup_at_local,
          duration_min: quote.duration_min,
          lead_time_ok: quote.lead_time_ok,
          asap_available: quote.asap_available,
          capacity_available: quote.capacity_available,
        }),
      );
    }

    case "create_booking": {
      const input = parsed.data as z.infer<typeof schemas.create_booking>;
      const phone = input.phone ?? ctx.callerNumber;
      if (!phone) return error("NO_PHONE: ask the caller for a mobile number first.");

      const result = await ctx.core.createBooking({
        tenant_id: ctx.tenant.id,
        pickup_address: input.pickup,
        dropoff_address: input.dropoff,
        pickup_at: input.pickup_time,
        passengers: input.passengers,
        luggage: input.luggage,
        vehicle_category: input.vehicle_category,
        name: input.name,
        phone,
        flight_number: input.flight_number,
        notes: input.notes,
        asap: input.asap,
        locale: ctx.language(),
        call_sid: ctx.callSid,
        idempotency_key: toolUseId,
      });
      if (!result.ok || !result.booking) {
        return error(`BOOKING_REJECTED: ${(result.errors ?? ["unknown"]).join("; ")}`);
      }
      return {
        content: JSON.stringify({ booked: true, ...result.booking, sms_confirmation: "sent to the caller" }),
        isError: false,
        effect: { kind: "booked", reference: result.booking.reference },
      };
    }

    case "transfer_to_human": {
      const input = parsed.data as z.infer<typeof schemas.transfer_to_human>;
      return { content: "Transferring now.", isError: false, effect: { kind: "transfer", reason: input.reason } };
    }

    case "end_call": {
      const input = parsed.data as z.infer<typeof schemas.end_call>;
      return { content: "Call ending.", isError: false, effect: { kind: "end", reason: input.reason } };
    }

    case "switch_language": {
      const input = parsed.data as z.infer<typeof schemas.switch_language>;
      return { content: `Switched to ${input.language}.`, isError: false, effect: { kind: "language", language: input.language } };
    }
  }
}

function ok(content: string): ToolOutcome {
  return { content, isError: false, effect: { kind: "none" } };
}

function error(content: string): ToolOutcome {
  return { content, isError: true, effect: { kind: "none" } };
}
