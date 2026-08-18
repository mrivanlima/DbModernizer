---
title: "A Perfectly Scoped Query From the Wrong Agent Is Still a Breach"
description: "A third layer for AI agent database access, alongside my SQL Server firewall and approval queue: native Row-Level Security that enforces what an agent can see and touch based on its identity, not its SQL's shape."
categories: [case-studies]
tags: [ai-agents, agent-access, database-security, open-source, real-incidents]
image: /assets/images/ai-agent-row-level-security-01.png
date: 2026-08-18 09:20:00 -0400
---

![Diagram contrasting an AI agent's in-scope region, where SQL Server Row-Level Security allows reads and writes, against an out-of-scope region, where rows are hidden from SELECT and writes are blocked](/assets/images/ai-agent-row-level-security-01.png)

This is the third piece in a series on database-side controls for AI agents with direct SQL execute access. The [first post](/blog/2026/08/17/ai-agent-database-firewall-sql-server/) covered a firewall that refuses badly-shaped statements outright — unscoped writes, schema changes. The [second](/blog/2026/08/18/schema-change-approval-queue-for-ai-agents/) covered a human-approval queue for the schema changes that firewall refuses, so a legitimate change doesn't just get re-run by hand later. Both of those check the *shape* of an agent's SQL. This one checks something neither of them can: given a statement that's perfectly well-formed and perfectly scoped-looking, does the agent issuing it actually have any business touching those rows at all?

## The incident that motivates this one

Between December 2025 and February 2026, a single attacker used Claude Code and GPT-4.1 to breach nine Mexican government agencies — the federal tax authority, Mexico City's civil registry, the electoral institute — exposing 195 million taxpayer records and 220 million civil records, plus more than 150GB of additional data.

The root cause wasn't a novel exploit technique. It was excessive, shared permissions never enforced at the data layer itself. Whatever had execute access could see and touch far more than its actual job required, because nothing below the application layer was checking. A [2026 least-privilege research report](https://www.kiteworks.com/cybersecurity-risk-management/ai-agent-security-incidents-2026/){:target="_blank" rel="noopener noreferrer"} analyzing over 3 billion permissions found that on average only about 4% had been used in the trailing 90 days — and nearly one in three could modify or delete sensitive data. Nobody had to break in cleverly. The door was already open wider than anyone was using it.

## Key takeaways

- A statement-shape guardrail can't catch this failure mode: `WHERE region = 'US-EAST'` is a perfectly scoped clause, and still exactly the wrong thing for an agent with no business in `US-EAST` to run
- SQL Server's native Row-Level Security enforces what an agent can see and touch based on its declared identity, independent of how its SQL is written — a `SELECT` with zero WHERE clause, or a deliberately broad `WHERE 1=1`, still only returns rows inside that agent's scope
- RLS has two distinct enforcement mechanisms that fail differently, and conflating them will make your own testing look broken when it isn't: a **filter** predicate silently hides out-of-scope rows before they can even be matched, while a **block** predicate throws an explicit error when a write's *result* would violate the predicate on a row that was visible to begin with
- This complements, not replaces, statement-shape guardrails — an agent correctly scoped to its own data can still submit an unscoped DELETE within that scope, which is a different problem this project doesn't solve

## What was actually built

The core of it is a SQL Server security policy backed by a schema-bound predicate function:

```sql
CREATE OR ALTER FUNCTION dbo.fn_agent_region_predicate(@region NVARCHAR(20))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE @region = CAST(SESSION_CONTEXT(N'agent_region') AS NVARCHAR(20))
   OR CAST(SESSION_CONTEXT(N'agent_region') AS NVARCHAR(20)) = 'ALL';

CREATE SECURITY POLICY dbo.AgentRegionPolicy
    ADD FILTER PREDICATE dbo.fn_agent_region_predicate(region) ON dbo.demo_accounts,
    ADD BLOCK PREDICATE dbo.fn_agent_region_predicate(region) ON dbo.demo_accounts AFTER INSERT,
    ADD BLOCK PREDICATE dbo.fn_agent_region_predicate(region) ON dbo.demo_accounts AFTER UPDATE,
    ADD BLOCK PREDICATE dbo.fn_agent_region_predicate(region) ON dbo.demo_accounts BEFORE UPDATE,
    ADD BLOCK PREDICATE dbo.fn_agent_region_predicate(region) ON dbo.demo_accounts BEFORE DELETE
    WITH (STATE = ON);
```

Agent identity is carried via `SESSION_CONTEXT`, set once per connection before any of that agent's SQL runs — mirroring how a real MCP database server or agent gateway typically authenticates a caller against a shared connection, rather than provisioning a distinct SQL login per agent (the same predicate pattern works against `SUSER_SNAME()` instead, if your environment does provision real per-agent logins). A thin Python wrapper, `AgentIdentityGuard`, establishes that identity and writes to an audit table — but the actual enforcement is entirely SQL Server's, not application code the agent could reason its way around.

## Seeing it hold up, including the part that surprised me

Against a real SQL Server 2025 instance, with an agent scoped to `US-WEST` trying two different ways to reach outside its region:

```
=== SCENARIO C: a well-scoped-looking write reaching OUTSIDE the agent's identity ===
    (This has a WHERE clause -- a shape-based guardrail would approve it.
     This agent is scoped to US-WEST; the target rows are US-EAST.)
  -> APPROVED, rows_affected=0 -- the filter predicate hid the US-EAST rows
     before the WHERE clause could ever match them. No error, no rows
     touched: the agent's own SQL was syntactically fine, it just had
     nothing it was allowed to see.

=== SCENARIO D: the same agent tries to relabel a row IT CAN see out of its own scope ===
    (Exfiltration by relabeling: not reaching for another region's data,
     but trying to move its own row into a region it isn't scoped to.)
  -> BLOCKED: Refused: agent 'migration-agent-west' (scope=US-WEST)
     attempted a UPDATE that Row-Level Security's block predicate rejected
     -- the target row(s) are outside this agent's identity scope. The
     write never reached the table.
```

My first draft of this demo only had scenario C, and I assumed it would throw the same error as an out-of-scope INSERT. It didn't — it silently affected zero rows. It took a moment to click: the filter predicate hides out-of-scope rows from ever being matched by a WHERE clause, so the UPDATE never reaches the point where a block predicate would need to fire — there's nothing left to violate it. The block predicate only fires on a *result* violation: a row that was visible ending up with a post-operation value that breaks the rule, which is a genuinely different scenario. I had to write scenario D — an agent trying to relabel its own row into a scope it doesn't hold — to actually exercise that path.

Worth stating plainly rather than glossing over: RLS's "fail silently" behavior on reads and matches, and its "fail loudly" behavior on result-violating writes, are two different mechanisms doing two different jobs. A demo (or a test suite) that expects one where the other actually applies will look broken even though the security property held the entire time.

## What this doesn't solve

Row-Level Security enforces scope given an *honestly declared* identity — it doesn't itself authenticate that identity. If the gateway setting `SESSION_CONTEXT` can be tricked into declaring the wrong agent or the wrong scope, this control doesn't catch that; it assumes the layer establishing identity is trustworthy, same as any authentication system has to assume somewhere. And it doesn't replace the first two posts in this series — an agent correctly scoped to exactly the data it should touch can still submit an unscoped DELETE or a DROP TABLE within that scope. That's still the firewall's job, not this one's.

Between the three projects now: the firewall refuses what should never run regardless of who's asking. The approval queue routes what might be legitimate to a human instead of deciding alone. Row-level security scopes what an agent can reach in the first place, before either of the other two questions is even relevant. Different layer, same underlying problem — an AI agent with real database access needs checks it can't talk its way around, and no single layer covers all of them.

The full project — the predicate function, the security policy, and all six scenarios runnable via Docker Compose against a real SQL Server 2025 instance — is open source: [github.com/mrivanlima/ai-agent-row-level-security](https://github.com/mrivanlima/ai-agent-row-level-security){:target="_blank" rel="noopener noreferrer"}. If your agents have database access scoped by convention rather than enforced by the engine, that's worth closing before it's the reason nine agencies' worth of records end up on someone else's list. [Get in touch](/about/#contact) if you want help wiring this into your own environment.

*Ivan Lima is a data engineer specializing in database modernization for AI systems. [Get in touch](/about/#contact) if your database needs to be ready for what's next.*
