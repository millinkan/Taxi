# ADR 0004: Voice agent on Twilio ConversationRelay and Claude

**Status:** accepted · **Date:** 2026-10-19

## Context
The pilot firm's dispatcher drives, so calls go unanswered. We need an agent
that understands callers (often in Swiss German), quotes official prices and
books. Then it must hand off reliably.

## Decision
- **Twilio ConversationRelay** handles speech-to-text and text-to-speech; our
  service exchanges plain text over a websocket. That's far less code than raw
  media streams, and speech providers and voices can be switched by
  configuration.
- **Claude `claude-opus-5-5`** at effort `medium` with adaptive thinking, with
  server-side refusal fallback (`fallbacks: "default"`), streaming, and five
  narrow tools. Effort `low` was faster, but in pilot testing the model
  sometimes put its reasoning into the spoken reply, which the caller heard.
  Tool inputs are validated with zod before they reach the core.
- **Conversation history is append-only.** Barge-in is recorded as a new
  message, never by editing old ones. This keeps prompt caching and
  thinking-block replay valid.
- **Safety net before cleverness**: any error, refusal, timeout or the
  10-minute limit leads to one apology sentence and a transfer to the
  dispatcher. If the dispatcher doesn't answer, the core takes a voicemail and
  sends an SMS link.
- **Idempotent booking**: the tool-use ID is the booking's idempotency key, so
  a retried tool call can't double-book.

## Consequences
Per-minute telephony and model costs apply (see VOICE_AGENT.md). Swiss-German
recognition quality depends on the speech provider and must be checked with
real calls during the pilot.
