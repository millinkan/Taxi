// Twilio ConversationRelay websocket messages (Twilio -> us and us -> Twilio).
// Reference: Twilio docs, "ConversationRelay websocket messages".

export interface SetupMessage {
  type: "setup";
  sessionId: string;
  callSid: string;
  from?: string;
  to?: string;
  forwardedFrom?: string;
  customParameters?: Record<string, string>;
}

export interface PromptMessage {
  type: "prompt";
  voicePrompt: string;
  lang?: string;
  last?: boolean;
}

export interface InterruptMessage {
  type: "interrupt";
  utteranceUntilInterrupt?: string;
  durationUntilInterruptMs?: number | string;
}

export interface DtmfMessage {
  type: "dtmf";
  digit: string;
}

export interface ErrorMessage {
  type: "error";
  description?: string;
}

export type InboundMessage = SetupMessage | PromptMessage | InterruptMessage | DtmfMessage | ErrorMessage;

export type OutboundMessage =
  | { type: "text"; token: string; last: boolean; lang?: string }
  | { type: "language"; ttsLanguage: string; transcriptionLanguage: string }
  | { type: "end"; handoffData: string };

export function parseInbound(raw: string): InboundMessage | null {
  try {
    const message = JSON.parse(raw) as { type?: unknown };
    if (typeof message?.type !== "string") return null;
    return message as InboundMessage;
  } catch {
    return null;
  }
}

// What we hand back to Twilio when the relay session ends; Twilio posts it to
// the <Connect action> URL as HandoffData.
export interface HandoffData {
  reason: "transfer" | "completed" | "error";
  detail?: string;
  dispatcherPhone?: string | null;
  language: "de" | "en";
}
