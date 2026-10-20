import Anthropic from "@anthropic-ai/sdk";
import { TOOLS } from "./tools.js";
import { STATIC_INSTRUCTIONS } from "./prompt.js";

export type MessageParam = Anthropic.Beta.Messages.BetaMessageParam;
export type Message = Anthropic.Beta.Messages.BetaMessage;

export interface TurnRequest {
  context: string;
  messages: MessageParam[];
  signal: AbortSignal;
  onText: (delta: string) => void;
}

// One model call: streams text as it is generated, resolves with the full
// message (including tool_use blocks). Behind an interface so the call logic
// can be tested without the network.
export interface LlmRunner {
  runTurn(request: TurnRequest): Promise<Message>;
}

export class AnthropicRunner implements LlmRunner {
  private readonly client: Anthropic;

  constructor(
    private readonly model: string,
    private readonly effort: "low" | "medium" | "high",
    client?: Anthropic,
  ) {
    // Short timeout and few retries: a caller is waiting on the line. On
    // failure the session hands the caller to a human instead.
    this.client = client ?? new Anthropic({ timeout: 20_000, maxRetries: 1 });
  }

  async runTurn({ context, messages, signal, onText }: TurnRequest): Promise<Message> {
    const stream = this.client.beta.messages.stream(
      {
        model: this.model,
        max_tokens: 4096,
        // Reasoning goes into thinking blocks, which are never streamed to
        // the caller; without it the model sometimes reasons in spoken text.
        thinking: { type: "adaptive", display: "omitted" },
        // Server-side fallback: if the model declines a turn for policy
        // reasons, the API retries on Anthropic's recommended fallback model
        // inside the same call instead of leaving the caller in silence.
        betas: ["server-side-fallback-2026-07-01"],
        fallbacks: "default",
        output_config: { effort: this.effort },
        system: [
          // Identical for every call and firm: cached across calls.
          { type: "text", text: STATIC_INSTRUCTIONS, cache_control: { type: "ephemeral" } },
          { type: "text", text: context },
        ],
        tools: TOOLS,
        messages,
      },
      { signal },
    );
    stream.on("text", (delta) => onText(delta));
    return stream.finalMessage();
  }
}
