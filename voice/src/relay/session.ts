import Anthropic from "@anthropic-ai/sdk";
import type { CoreApi, TenantConfig } from "../core/client.js";
import { callContext, defaultGreeting, FALLBACK_LINES } from "../agent/prompt.js";
import type { LlmRunner, Message, MessageParam } from "../agent/llm.js";
import { runTool, type CallEffect } from "../agent/tools.js";
import { log, errorFields } from "../logger.js";
import type { HandoffData, InboundMessage, OutboundMessage, SetupMessage } from "./protocol.js";

type ToolResult = Anthropic.Beta.Messages.BetaToolResultBlockParam;
type Language = "de" | "en";

export interface SessionDeps {
  core: CoreApi;
  llm: LlmRunner;
  send: (message: OutboundMessage) => void;
  // Firm config for the dialled number (cached by the incoming-call handler).
  resolveTenant: (setup: SetupMessage) => Promise<TenantConfig | null>;
  languages: Record<Language, string>; // e.g. { de: "de-DE", en: "en-US" }
  maxCallSeconds: number;
  // Injectable for tests.
  wait?: (ms: number) => Promise<void>;
  now?: () => Date;
}

// Model calls allowed for a single caller utterance (tool loops included).
const MAX_STEPS_PER_TURN = 6;

// One phone call. The conversation history is append-only: we never edit or
// delete a message once it is in `messages`, which keeps prompt caching and
// thinking-block replay valid on current Claude models.
export class CallSession {
  private tenant: TenantConfig | null = null;
  private callSid = "";
  private callerNumber: string | null = null;
  private dialledNumber: string | null = null;
  private language: Language = "de";
  private greeting = "";
  private context = "";

  private readonly messages: MessageParam[] = [];
  private readonly transcript: { role: "caller" | "agent"; text: string }[] = [];
  private readonly bookedReferences: string[] = [];
  private handoff: HandoffData | null = null;
  private ended = false;
  private closed = false;
  private failed = false;

  private chain: Promise<void> = Promise.resolve();
  private currentAbort: AbortController | null = null;
  private interruptNote: string | null = null;
  private interruptedDuringTools = false;
  private lastSpoken = "";
  private maxDurationTimer: NodeJS.Timeout | null = null;
  private readonly startedAt: Date;
  private readonly wait: (ms: number) => Promise<void>;
  private readonly now: () => Date;

  constructor(private readonly deps: SessionDeps) {
    this.wait = deps.wait ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
    this.now = deps.now ?? (() => new Date());
    this.startedAt = this.now();
  }

  // Entry point for every websocket message. Work is serialised so turns
  // never overlap; interrupts act immediately.
  handle(message: InboundMessage): Promise<void> {
    switch (message.type) {
      case "setup":
        this.chain = this.chain.then(() => this.setup(message));
        break;
      case "prompt":
        if (message.last === false || !message.voicePrompt?.trim()) break;
        this.chain = this.chain.then(() => this.onCallerSpeech(message.voicePrompt.trim()));
        break;
      case "dtmf":
        this.chain = this.chain.then(() => this.onCallerSpeech(`[keypad: ${message.digit}]`));
        break;
      case "interrupt":
        this.onInterrupt(message.utteranceUntilInterrupt ?? "");
        break;
      case "error":
        log.warn("relay error from Twilio", { callSid: this.callSid, description: message.description });
        break;
    }
    return this.chain;
  }

  // Called when the websocket closes. Records the call in the core.
  async close(): Promise<void> {
    if (this.closed) return;
    this.closed = true;
    this.ended = true;
    this.currentAbort?.abort();
    if (this.maxDurationTimer) clearTimeout(this.maxDurationTimer);
    await this.chain.catch(() => undefined);
    if (!this.tenant) return;

    const endedAt = this.now();
    try {
      await this.deps.core.recordCall({
        tenant_id: this.tenant.id,
        call_sid: this.callSid,
        from_number: this.callerNumber ?? undefined,
        to_number: this.dialledNumber ?? undefined,
        started_at: this.startedAt.toISOString(),
        ended_at: endedAt.toISOString(),
        duration_s: Math.round((endedAt.getTime() - this.startedAt.getTime()) / 1000),
        outcome: this.outcome(),
        language: this.language,
        summary: this.summary(),
        handled_by: "ai",
        transcript: this.transcript,
      });
    } catch (error) {
      log.error("could not record call", { callSid: this.callSid, ...errorFields(error) });
    }
  }

  outcome(): string {
    if (this.bookedReferences.length > 0) return "booked";
    if (this.failed && !this.handoff?.dispatcherPhone) return "failed";
    if (this.handoff?.reason === "transfer" || this.handoff?.reason === "error") return "transferred";
    if (this.handoff?.reason === "completed") return "information";
    return "abandoned";
  }

  get history(): readonly MessageParam[] {
    return this.messages;
  }

  // ---------------------------------------------------------------------

  private async setup(setup: SetupMessage) {
    this.callSid = setup.callSid;
    this.callerNumber = setup.from && /^\+\d{6,15}$/.test(setup.from) ? setup.from : null;
    this.dialledNumber = setup.to ?? null;
    this.tenant = await this.deps.resolveTenant(setup);
    if (!this.tenant) {
      log.error("relay session for unknown firm", { callSid: this.callSid, to: setup.to });
      this.fail(new Error("unknown firm"));
      return;
    }
    this.language = this.tenant.default_locale === "en" ? "en" : "de";
    this.greeting = defaultGreeting(this.tenant);
    this.context = callContext(this.tenant, this.callerNumber, this.greeting);
    this.transcript.push({ role: "agent", text: this.greeting });
    this.maxDurationTimer = setTimeout(() => this.onMaxDuration(), this.deps.maxCallSeconds * 1000);
    this.maxDurationTimer.unref?.();
    log.info("call started", { callSid: this.callSid, tenant: this.tenant.slug });
  }

  private async onCallerSpeech(text: string) {
    if (this.ended || !this.tenant) return;
    this.transcript.push({ role: "caller", text });

    // Tell the model what the caller actually heard before cutting in.
    const content = this.interruptNote ? `${this.interruptNote}\n${text}` : text;
    this.interruptNote = null;
    this.messages.push({ role: "user", content });
    await this.runTurn();
  }

  private onInterrupt(heard: string) {
    if (this.currentAbort) {
      this.currentAbort.abort();
    } else if (this.lastSpoken) {
      // The full reply is already in history; the caller only heard part.
      this.interruptNote = heard
        ? `[The caller interrupted you; they only heard: "${heard}"]`
        : "[The caller interrupted you before hearing your last reply]";
      this.interruptedDuringTools = true;
    }
  }

  private async runTurn() {
    this.interruptedDuringTools = false;

    for (let step = 0; step < MAX_STEPS_PER_TURN; step++) {
      if (this.ended) return;
      const abort = new AbortController();
      this.currentAbort = abort;
      let spoken = "";
      let message: Message;

      try {
        message = await this.deps.llm.runTurn({
          context: this.context,
          messages: this.messages,
          signal: abort.signal,
          onText: (delta) => {
            if (abort.signal.aborted || this.ended) return;
            spoken += delta;
            this.deps.send({ type: "text", token: delta, last: false });
          },
        });
      } catch (error) {
        this.currentAbort = null;
        if (abort.signal.aborted) {
          // Barge-in: keep what was actually said so the model knows. This
          // is a new message appended to history, never an edit.
          if (spoken.trim()) {
            this.messages.push({ role: "assistant", content: [{ type: "text", text: `${spoken.trim()} …` }] });
            this.transcript.push({ role: "agent", text: `${spoken.trim()} …` });
          }
          return;
        }
        this.fail(error);
        return;
      }
      this.currentAbort = null;

      if (spoken.trim()) {
        this.transcript.push({ role: "agent", text: spoken.trim() });
        this.lastSpoken = spoken;
      }

      if (message.stop_reason === "refusal") {
        this.fail(new Error("model refused the turn"));
        return;
      }

      this.messages.push({ role: "assistant", content: message.content });
      const toolUses = message.content.filter(
        (block): block is Anthropic.Beta.Messages.BetaToolUseBlock => block.type === "tool_use",
      );

      if (toolUses.length === 0) {
        this.endOfUtterance();
        return;
      }
      if (message.stop_reason === "max_tokens") {
        // A tool input cut off at max_tokens may still parse; never run it.
        this.fail(new Error("tool input truncated at max_tokens"));
        return;
      }

      const results: ToolResult[] = [];
      const effects: CallEffect[] = [];
      for (const toolUse of toolUses) {
        try {
          const outcome = await runTool(toolUse.name, toolUse.input, toolUse.id, {
            core: this.deps.core,
            tenant: this.tenant as TenantConfig,
            callSid: this.callSid,
            callerNumber: this.callerNumber,
            language: () => this.language,
          });
          results.push({ type: "tool_result", tool_use_id: toolUse.id, content: outcome.content, is_error: outcome.isError });
          effects.push(outcome.effect);
        } catch (error) {
          log.warn("tool failed", { callSid: this.callSid, tool: toolUse.name, ...errorFields(error) });
          results.push({
            type: "tool_result",
            tool_use_id: toolUse.id,
            content: "SERVICE_UNAVAILABLE: the booking system did not answer. Offer to connect the caller to the dispatcher.",
            is_error: true,
          });
        }
      }
      // All results of one assistant turn go back in a single user message.
      this.messages.push({ role: "user", content: results });

      for (const effect of effects) this.apply(effect);
      if (this.handoff) {
        this.endOfUtterance();
        await this.finish();
        return;
      }
      if (this.interruptedDuringTools) {
        this.endOfUtterance();
        return;
      }
    }

    this.fail(new Error("too many model steps for one utterance"));
  }

  private apply(effect: CallEffect) {
    switch (effect.kind) {
      case "booked":
        this.bookedReferences.push(effect.reference);
        break;
      case "language":
        this.language = effect.language;
        this.deps.send({
          type: "language",
          ttsLanguage: this.deps.languages[effect.language],
          transcriptionLanguage: this.deps.languages[effect.language],
        });
        break;
      case "transfer":
        this.handoff = this.makeHandoff("transfer", effect.reason);
        break;
      case "end":
        this.handoff = this.makeHandoff("completed", effect.reason);
        break;
      case "none":
        break;
    }
  }

  private makeHandoff(reason: HandoffData["reason"], detail?: string): HandoffData {
    return { reason, detail, dispatcherPhone: this.tenant?.dispatcher_phone ?? null, language: this.language };
  }

  private endOfUtterance() {
    if (!this.ended) this.deps.send({ type: "text", token: "", last: true });
  }

  // Let the voice finish its last sentence, then end the relay session.
  private async finish() {
    if (this.ended) return;
    this.ended = true;
    await this.wait(Math.min(12_000, 800 + this.lastSpoken.length * 70));
    this.deps.send({ type: "end", handoffData: JSON.stringify(this.handoff) });
  }

  // Anything unexpected: apologise and hand over to a person. Never leave
  // the caller in silence.
  private fail(error: unknown) {
    if (this.ended) return;
    log.error("voice session failed, handing over", { callSid: this.callSid, ...errorFields(error) });
    this.failed = true;
    const line = FALLBACK_LINES[this.language];
    this.deps.send({ type: "text", token: line, last: true });
    this.lastSpoken = line;
    this.transcript.push({ role: "agent", text: line });
    this.handoff = this.makeHandoff("error", error instanceof Error ? error.message : String(error));
    void this.finish();
  }

  private onMaxDuration() {
    if (this.ended) return;
    this.currentAbort?.abort();
    this.fail(new Error("maximum call duration reached"));
  }

  private summary(): string {
    if (this.bookedReferences.length > 0) return `Booked ${this.bookedReferences.join(", ")}.`;
    if (this.handoff) return `${this.handoff.reason}: ${this.handoff.detail ?? ""}`.trim();
    const callerTurns = this.transcript.filter((t) => t.role === "caller").length;
    return `Caller hung up after ${callerTurns} utterance(s).`;
  }
}
