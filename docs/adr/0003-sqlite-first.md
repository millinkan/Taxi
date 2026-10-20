# ADR 0003: SQLite first, PostgreSQL when needed

**Status:** accepted · **Date:** 2026-10-19

## Context
The pilot is one firm with 4 cars, growing to a few dozen firms in the region.
That's well under 10 writes per second. Rails 8 runs SQLite in production with
Solid Queue, Cache and Cable, so there's no Redis or database server to run.

## Decision
Use SQLite on a persistent volume for the pilot and early growth. Write only
database-agnostic Active Record code.

## Consequences
- One container, one volume, backups by copying files (see OPERATIONS.md).
- Migration trigger: more than one app server, sustained write contention, or
  the wish for row-level security. Then set `DATABASE_URL` to PostgreSQL, add
  the `pg` gem, and copy the data over with a one-off script.
