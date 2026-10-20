import { z } from "zod";

// Every environment variable the voice service reads, validated at boot so a
// misconfiguration fails loudly at deploy time instead of on a live call.
// Documented in docs/CONFIGURATION.md.
const schema = z.object({
  PORT: z.coerce.number().int().positive().default(8080),
  // Public https URL of this service, exactly as configured in Twilio. Used
  // to verify Twilio signatures and to build the wss:// relay URL.
  PUBLIC_BASE_URL: z.string().url(),
  // Rails core: internal API (server-to-server) and public URL (Twilio).
  CORE_API_URL: z.string().url(),
  CORE_PUBLIC_URL: z.string().url(),
  INTERNAL_API_TOKEN: z.string().min(16),
  TWILIO_AUTH_TOKEN: z.string().min(8),
  // Off only for local development with a tunnel that rewrites URLs.
  TWILIO_VALIDATE_SIGNATURE: z.enum(["true", "false"]).default("true"),
  ANTHROPIC_MODEL: z.string().default("claude-opus-5-5"),
  // "low" is faster but at "low" the model sometimes reasons in its spoken
  // reply instead of thinking first; "medium" keeps the caller's audio clean.
  ANTHROPIC_EFFORT: z.enum(["low", "medium", "high"]).default("medium"),
  // ConversationRelay speech settings. Only the ones set are sent to Twilio,
  // so Twilio's defaults apply otherwise. See docs/VOICE_AGENT.md.
  CR_LANGUAGE: z.string().default("de-DE"),
  CR_SECONDARY_LANGUAGE: z.string().default("en-US"),
  CR_TTS_PROVIDER: z.string().optional(),
  CR_VOICE: z.string().optional(),
  CR_TRANSCRIPTION_PROVIDER: z.string().optional(),
  CR_SPEECH_MODEL: z.string().optional(),
  MAX_CALL_SECONDS: z.coerce.number().int().positive().default(600),
  LOG_LEVEL: z.enum(["debug", "info", "warn", "error"]).default("info"),
});

export type Config = z.infer<typeof schema>;

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = schema.safeParse(env);
  if (!parsed.success) {
    const problems = parsed.error.issues.map((i) => `  ${i.path.join(".")}: ${i.message}`).join("\n");
    throw new Error(`Invalid voice service configuration:\n${problems}`);
  }
  return parsed.data;
}
