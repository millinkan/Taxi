import { log, errorFields } from "../logger.js";

// Typed client for the Rails core's internal API (/internal/v1). The core is
// the single source of truth for prices, bookings and firm configuration.

export interface TenantPlace {
  id: number;
  name: string;
  kind: string;
  aliases: string[];
}

export interface TenantConfig {
  id: number;
  name: string;
  slug: string;
  time_zone: string;
  now_local: string;
  currency: string;
  default_locale: "de" | "en";
  voice_agent_enabled: boolean;
  voice_greeting: string | null;
  dispatcher_phone: string | null;
  public_phone: string | null;
  home_area_label: string;
  min_lead_minutes: number;
  max_advance_days: number;
  free_cancellation_hours: number;
  // "Taxi now": booked without lead time; the dispatcher confirms an ETA by SMS.
  asap_enabled: boolean;
  asap_response_minutes: number;
  booking_url: string;
  places: TenantPlace[];
}

export interface QuoteRequest {
  tenant_id: number;
  pickup_address: string;
  dropoff_address: string;
  pickup_at: string;
  passengers: number;
  vehicle_category?: string;
}

export interface QuoteResponse {
  ok: boolean;
  error: string | null;
  price_cents: number | null;
  price_text: string | null;
  price_source: string;
  estimated: boolean;
  vehicle_category: string;
  distance_km: number | null;
  duration_min: number | null;
  pickup: { label: string | null; located: boolean };
  dropoff: { label: string | null; located: boolean };
  pickup_at_local: string;
  lead_time_ok: boolean;
  asap_available: boolean;
  capacity_available: boolean;
}

export interface BookingRequest extends QuoteRequest {
  name: string;
  phone: string;
  luggage?: number;
  flight_number?: string;
  notes?: string;
  asap?: boolean;
  locale: "de" | "en";
  call_sid: string;
  idempotency_key: string;
}

export interface BookingResponse {
  ok: boolean;
  errors?: string[];
  booking?: {
    reference: string;
    status: string;
    asap?: boolean;
    asap_response_minutes?: number | null;
    pickup_at_local: string;
    pickup_address: string;
    dropoff_address: string;
    price_text: string;
    status_url: string;
  };
}

export interface CallLogPayload {
  tenant_id: number;
  call_sid: string;
  from_number?: string;
  to_number?: string;
  started_at: string;
  ended_at: string;
  duration_s: number;
  outcome: string;
  language: string;
  summary: string;
  handled_by: "ai";
  transcript: { role: "caller" | "agent"; text: string }[];
}

export class CoreApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly body: unknown,
  ) {
    super(message);
    this.name = "CoreApiError";
  }
}

export interface CoreApi {
  tenantForNumber(number: string): Promise<TenantConfig | null>;
  quote(request: QuoteRequest): Promise<QuoteResponse>;
  createBooking(request: BookingRequest): Promise<BookingResponse>;
  recordCall(payload: CallLogPayload): Promise<void>;
}

export class HttpCoreApi implements CoreApi {
  // Last known good firm config per dialled number: if the core is briefly
  // unreachable, calls are still answered with yesterday's settings.
  private readonly tenantCache = new Map<string, { config: TenantConfig; fetchedAt: number }>();
  private static readonly CACHE_FRESH_MS = 60_000;

  constructor(
    private readonly baseUrl: string,
    private readonly token: string,
    private readonly timeoutMs = 6_000,
  ) {}

  async tenantForNumber(number: string): Promise<TenantConfig | null> {
    const cached = this.tenantCache.get(number);
    if (cached && Date.now() - cached.fetchedAt < HttpCoreApi.CACHE_FRESH_MS) return cached.config;

    try {
      const body = await this.request<{ ok: boolean; tenant: TenantConfig }>(
        "GET",
        `/internal/v1/voice/tenant?number=${encodeURIComponent(number)}`,
      );
      this.tenantCache.set(number, { config: body.tenant, fetchedAt: Date.now() });
      return body.tenant;
    } catch (error) {
      if (error instanceof CoreApiError && error.status === 404) return null;
      if (cached) {
        log.warn("core unreachable, using cached firm config", { number, ...errorFields(error) });
        return cached.config;
      }
      throw error;
    }
  }

  quote(request: QuoteRequest): Promise<QuoteResponse> {
    return this.request("POST", "/internal/v1/quotes", request, { acceptStatus: [422] });
  }

  createBooking(request: BookingRequest): Promise<BookingResponse> {
    return this.request("POST", "/internal/v1/bookings", request, { acceptStatus: [422], retries: 2 });
  }

  async recordCall(payload: CallLogPayload): Promise<void> {
    await this.request("POST", "/internal/v1/call_logs", payload, { retries: 3 });
  }

  private async request<T>(
    method: "GET" | "POST",
    path: string,
    body?: unknown,
    options: { acceptStatus?: number[]; retries?: number } = {},
  ): Promise<T> {
    const retries = options.retries ?? 1;
    let lastError: unknown;

    for (let attempt = 0; attempt <= retries; attempt++) {
      try {
        const response = await fetch(this.baseUrl.replace(/\/$/, "") + path, {
          method,
          headers: {
            Authorization: `Bearer ${this.token}`,
            Accept: "application/json",
            ...(body ? { "Content-Type": "application/json" } : {}),
          },
          body: body ? JSON.stringify(body) : undefined,
          signal: AbortSignal.timeout(this.timeoutMs),
        });
        const json = (await response.json().catch(() => ({}))) as T;
        if (response.ok || options.acceptStatus?.includes(response.status)) return json;
        // 4xx other than the accepted ones will not get better with a retry.
        if (response.status < 500) throw new CoreApiError(`core ${method} ${path} -> ${response.status}`, response.status, json);
        lastError = new CoreApiError(`core ${method} ${path} -> ${response.status}`, response.status, json);
      } catch (error) {
        if (error instanceof CoreApiError && error.status < 500) throw error;
        lastError = error;
      }
      if (attempt < retries) await new Promise((r) => setTimeout(r, 300 * (attempt + 1)));
    }
    throw lastError;
  }
}
