// Tiny TwiML builders. Hand-written XML keeps us independent of SDK version
// drift; every interpolated value goes through escapeXml.

export function escapeXml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

function attrs(values: Record<string, string | undefined>): string {
  return Object.entries(values)
    .filter(([, v]) => v !== undefined && v !== "")
    .map(([k, v]) => ` ${k}="${escapeXml(v as string)}"`)
    .join("");
}

export function response(inner: string): string {
  return `<?xml version="1.0" encoding="UTF-8"?><Response>${inner}</Response>`;
}

export interface RelayOptions {
  relayUrl: string;
  actionUrl: string;
  welcomeGreeting: string;
  language: string;
  secondaryLanguage?: string;
  ttsProvider?: string;
  voice?: string;
  transcriptionProvider?: string;
  speechModel?: string;
  hints?: string[];
  parameters: Record<string, string>;
}

// <Connect><ConversationRelay>: Twilio does speech-to-text and text-to-speech
// and exchanges plain text with our websocket.
export function conversationRelay(o: RelayOptions): string {
  const relayAttrs = attrs({
    url: o.relayUrl,
    welcomeGreeting: o.welcomeGreeting,
    welcomeGreetingInterruptible: "any",
    language: o.language,
    ttsProvider: o.ttsProvider,
    voice: o.voice,
    transcriptionProvider: o.transcriptionProvider,
    speechModel: o.speechModel,
    interruptible: "any",
    dtmfDetection: "true",
    hints: o.hints && o.hints.length > 0 ? o.hints.join(",") : undefined,
  });
  const secondary = o.secondaryLanguage ? `<Language${attrs({ code: o.secondaryLanguage })}/>` : "";
  const params = Object.entries(o.parameters)
    .map(([name, value]) => `<Parameter${attrs({ name, value })}/>`)
    .join("");
  return response(
    `<Connect${attrs({ action: o.actionUrl })}><ConversationRelay${relayAttrs}>${secondary}${params}</ConversationRelay></Connect>`,
  );
}

export function dial(number: string, actionUrl: string, sayFirst?: { text: string; language: string }): string {
  const say = sayFirst ? `<Say${attrs({ language: sayFirst.language })}>${escapeXml(sayFirst.text)}</Say>` : "";
  return response(`${say}<Dial${attrs({ timeout: "25", action: actionUrl })}><Number>${escapeXml(number)}</Number></Dial>`);
}

export function redirect(url: string): string {
  return response(`<Redirect method="POST">${escapeXml(url)}</Redirect>`);
}

export function hangup(): string {
  return response("<Hangup/>");
}
