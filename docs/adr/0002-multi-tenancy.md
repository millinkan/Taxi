# ADR 0002: Shared-schema multi-tenancy

**Status:** accepted · **Date:** 2026-10-19

## Context
The business only works if adding a firm is cheap. There will be tens of
firms, each with modest data.

## Decision
One database and one schema, with a `tenant_id` column on every firm-owned
table. Rules:
1. Controllers reach firm data only through `Current.tenant.<association>`.
2. Forms that reference other records (places in fixed routes, vehicles,
   drivers) look those IDs up through the tenant, so a forged ID from another
   firm resolves to nothing.
3. Public pages resolve the firm from its custom domain or `/:tenant_slug`.
   Unknown or paused firms return 404.
4. Integration tests assert cross-tenant access is impossible.

## Alternatives considered
- Database per tenant: strong isolation, but heavy operations for small firms.
- PostgreSQL row-level security: a good extra layer once we move to
  PostgreSQL ([0003](0003-sqlite-first.md)), and worth adding then.

## Consequences
Onboarding is one transaction (`TenantOnboarding`). Isolation depends on
following rule 1, which code review and the isolation tests enforce.
