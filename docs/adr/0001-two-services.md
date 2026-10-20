# ADR 0001: Rails core plus a separate Node voice service

**Status:** accepted · **Date:** 2026-10-19

## Context
The product has two very different workloads. The first is CRUD with forms,
dashboards, SMS and background jobs. The second is live phone calls: long-lived
websockets that stream text both ways with tight latency budgets.

## Decision
- **core/** (Rails 8.1) owns all data and business rules: prices, bookings,
  firms, notifications.
- **voice/** (Node 22, TypeScript) runs only the call: the Twilio
  ConversationRelay websocket and the Claude agent. It's stateless and
  reaches all data through the core's internal API.

## Consequences
- A bug or outage in voice can't corrupt bookings. The core's Twilio fallback
  still forwards calls to the dispatcher.
- Prices and booking rules exist once (in the core), so the agent can never
  invent its own.
- Two deployables instead of one. Both deploy with Kamal to the same server.
