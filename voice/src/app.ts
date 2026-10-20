import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import { WebSocketServer, type WebSocket } from "ws";
import type { Config } from "./config.js";
import type { CoreApi, TenantConfig } from "./core/client.js";
import type { LlmRunner } from "./agent/llm.js";
import { defaultGreeting } from "./agent/prompt.js";
import { CallSession } from "./relay/session.js";
import { parseInbound, type HandoffData } from "./relay/protocol.js";
import { isValidSignature } from "./twilio/signature.js";
import * as twiml from "./twilio/twiml.js";
import { log, errorFields } from "./logger.js";

export const RELAY_PATH = "/twilio/relay";

// HTTP routes:
//   GET  /healthz                     liveness for the load balancer
//   POST /twilio/voice/incoming       Twilio voice webhook for each firm number
//   POST /twilio/voice/relay-ended    <Connect action>: handoff after the AI
//   WS   /twilio/relay                ConversationRelay text stream
export function createApp(config: Config, deps: { core: CoreApi; llm: LlmRunner }): Server {
  const coreFallbackUrl = `${config.CORE_PUBLIC_URL.replace(/\/$/, "")}/twilio/voice/fallback`;
  const coreDialStatusUrl = `${config.CORE_PUBLIC_URL.replace(/\/$/, "")}/twilio/voice/dial_status`;
  const publicBase = config.PUBLIC_BASE_URL.replace(/\/$/, "");
  const activeSessions = new Set<CallSession>();

  const server = createServer(async (req, res) => {
    try {
      const path = (req.url ?? "/").split("?")[0];
      if (req.method === "GET" && path === "/healthz") {
        return send(res, 200, "application/json", JSON.stringify({ ok: true, activeCalls: activeSessions.size }));
      }
      if (req.method !== "POST") return send(res, 404, "text/plain", "not found");

      const params = await readForm(req);
      if (!verify(req, params)) return send(res, 403, "text/plain", "invalid signature");

      if (path === "/twilio/voice/incoming") return send(res, 200, "text/xml", await incomingCall(params));
      if (path === "/twilio/voice/relay-ended") return send(res, 200, "text/xml", relayEnded(params));
      return send(res, 404, "text/plain", "not found");
    } catch (error) {
      log.error("http handler failed", errorFields(error));
      // Let Twilio fall back to the core's safety net for this number.
      return send(res, 200, "text/xml", twiml.redirect(coreFallbackUrl));
    }
  });

  function verify(req: IncomingMessage, params: Record<string, string>): boolean {
    if (config.TWILIO_VALIDATE_SIGNATURE === "false") return true;
    const url = publicBase + (req.url ?? "");
    return isValidSignature(config.TWILIO_AUTH_TOKEN, url, params, header(req, "x-twilio-signature"));
  }

  async function incomingCall(params: Record<string, string>): Promise<string> {
    const to = params.To ?? params.Called ?? "";
    let tenant: TenantConfig | null = null;
    try {
      tenant = await deps.core.tenantForNumber(to);
    } catch (error) {
      log.error("firm lookup failed, using core fallback", { to, ...errorFields(error) });
    }
    if (!tenant || !tenant.voice_agent_enabled) return twiml.redirect(coreFallbackUrl);

    log.info("incoming call", { callSid: params.CallSid, tenant: tenant.slug });
    return twiml.conversationRelay({
      relayUrl: publicBase.replace(/^http/, "ws") + RELAY_PATH,
      actionUrl: `${publicBase}/twilio/voice/relay-ended`,
      welcomeGreeting: defaultGreeting(tenant),
      language: tenant.default_locale === "en" ? config.CR_SECONDARY_LANGUAGE : config.CR_LANGUAGE,
      secondaryLanguage: tenant.default_locale === "en" ? config.CR_LANGUAGE : config.CR_SECONDARY_LANGUAGE,
      ttsProvider: config.CR_TTS_PROVIDER,
      voice: config.CR_VOICE,
      transcriptionProvider: config.CR_TRANSCRIPTION_PROVIDER,
      speechModel: config.CR_SPEECH_MODEL,
      // Place names help speech recognition with local names (Schaan, Altenrhein...).
      hints: tenant.places.map((p) => p.name).slice(0, 50),
      parameters: { tenantId: String(tenant.id) },
    });
  }

  function relayEnded(params: Record<string, string>): string {
    let handoff: HandoffData | null = null;
    try {
      handoff = params.HandoffData ? (JSON.parse(params.HandoffData) as HandoffData) : null;
    } catch {
      handoff = null;
    }
    if (!handoff || handoff.reason === "completed") return twiml.hangup();

    // Transfer (asked for, or after an error): ring the dispatcher; the core
    // handles no-answer with voicemail and an SMS booking link.
    if (handoff.dispatcherPhone) return twiml.dial(handoff.dispatcherPhone, coreDialStatusUrl);
    return twiml.redirect(coreFallbackUrl);
  }

  // --- websocket: one CallSession per call ------------------------------
  const wss = new WebSocketServer({ noServer: true });
  server.on("upgrade", (req, socket, head) => {
    const path = (req.url ?? "").split("?")[0];
    if (path !== RELAY_PATH) {
      socket.destroy();
      return;
    }
    wss.handleUpgrade(req, socket, head, (ws) => attachSession(ws));
  });

  function attachSession(ws: WebSocket) {
    const session = new CallSession({
      core: deps.core,
      llm: deps.llm,
      send: (message) => {
        if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(message));
      },
      // The setup message carries the dialled number; the firm config is
      // cached by the core client from the incoming-call lookup.
      resolveTenant: (setup) => deps.core.tenantForNumber(setup.to ?? ""),
      languages: { de: config.CR_LANGUAGE, en: config.CR_SECONDARY_LANGUAGE },
      maxCallSeconds: config.MAX_CALL_SECONDS,
    });
    activeSessions.add(session);

    ws.on("message", (data) => {
      const message = parseInbound(data.toString());
      if (!message) return;
      session.handle(message).catch((error) => log.error("session handler failed", errorFields(error)));
    });
    ws.on("close", () => {
      activeSessions.delete(session);
      void session.close();
    });
    ws.on("error", (error) => log.warn("relay socket error", errorFields(error)));
  }

  // Graceful shutdown: finish recording calls in progress.
  server.on("close", () => {
    for (const session of activeSessions) void session.close();
    wss.close();
  });

  return server;
}

function header(req: IncomingMessage, name: string): string | undefined {
  const value = req.headers[name];
  return Array.isArray(value) ? value[0] : value;
}

async function readForm(req: IncomingMessage): Promise<Record<string, string>> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req) {
    size += (chunk as Buffer).length;
    if (size > 64 * 1024) throw new Error("request body too large");
    chunks.push(chunk as Buffer);
  }
  return Object.fromEntries(new URLSearchParams(Buffer.concat(chunks).toString("utf8")));
}

function send(res: ServerResponse, status: number, contentType: string, body: string) {
  res.writeHead(status, { "Content-Type": contentType, "Cache-Control": "no-store" });
  res.end(body);
}
