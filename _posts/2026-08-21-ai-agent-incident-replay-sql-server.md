---
title: "The Credential Risk Was on Record Six Hours Before the Incident Started"
description: "The sixth and final piece for AI agent database access: reconstructing one chronological timeline across five independent audit trails, so an incident review doesn't mean cross-referencing five tables by hand under pressure."
categories: [case-studies]
tags: [ai-agents, agent-access, database-governance, open-source, real-incidents]
image: /assets/images/ai-agent-incident-replay-01.png
date: 2026-08-21 12:45:00 -0400
---

![Five separate audit sources for a Guardrail, Approval Queue, Row-Level Security, Credential Audit, and Cost Governor merging into one reconstructed incident timeline](/assets/images/ai-agent-incident-replay-01.png)

This is the sixth and final piece in a series on database-side controls for AI agents with direct SQL execute access. The [first](/blog/2026/08/17/ai-agent-database-firewall-sql-server/) refused badly-shaped statements. The [second](/blog/2026/08/18/schema-change-approval-queue-for-ai-agents/) queued schema changes for human review. The [third](/blog/2026/08/18/ai-agent-row-level-security-sql-server/) scoped access by identity. The [fourth](/blog/2026/08/19/ai-agent-credential-connection-auditor-sql-server/) audited whether that identity still deserved to be trusted. The [fifth](/blog/2026/08/20/ai-agent-query-cost-governor-sql-server/) refused expensive queries before they ran. All five run *during* an agent's action. This one runs *after* — and it's the piece the very first post in this series named, unbuilt, as a "where this goes next" idea, back before there were five audit trails yet worth reconstructing.

## The problem five separate audit tables create

Each of the five prior projects writes its own audit table, and that's the correct design in isolation — a record has to survive even when the statement it's auditing gets rolled back or refused, so each control needs to own its record independently rather than share one. But that correctness creates a real cost the moment something actually goes wrong with an agent: an incident responder doesn't want five separate tables. They want one timeline, and reconstructing that by hand — checking the guardrail's log, then the approval queue's, then RLS, then the credential registry, then the cost governor, in whatever order someone happens to think to check them — is slow at exactly the moment speed matters most.

## Key takeaways

- Five independent, correctly-isolated audit trails create a real cost during incident response: nobody has time to manually cross-reference five tables under pressure, in whatever order they happen to think of them
- Reconstructing one chronological timeline across all five, filterable by agent and time window, doesn't replace any of the five controls — it's the consolidated read path built for the moment someone needs to answer "what actually happened"
- Context that predates an incident matters as much as the incident itself — a credential-sharing risk on record hours before an incident started is easy to miss unless it's sitting in the same timeline as everything that happened after
- This is the second project in the series (after the credential auditor) to work correctly on the first real run — and that's not a coincidence worth glossing over; see below

## What was actually built

Five audit tables, shaped after what each sibling project in this series actually writes, merged into one timeline:

```python
def timeline(self, agent_id=None, start=None, end=None) -> list:
    """Returns every event across all five audit tables, in chronological
    order, optionally filtered to one agent and/or a time window."""
    queries = [
        ("Guardrail", "SELECT executed_at, agent_id, decision, ... FROM dbo.guardrail_audit"),
        ("Schema-Approval-Queue", "SELECT executed_at, agent_id, decision, ... FROM dbo.approval_audit"),
        ("Row-Level-Security", "SELECT executed_at, agent_id, decision, ... FROM dbo.rls_audit"),
        ("Credential-Auditor", "SELECT snapshot_at AS executed_at, agent_id, 'SNAPSHOT', ... FROM dbo.credential_snapshot"),
        ("Query-Cost-Governor", "SELECT executed_at, agent_id, decision, ... FROM dbo.cost_audit"),
    ]
    events = []
    for source, query in queries:
        # ... apply agent_id / time-window filters, run, tag each row with `source`
        events.extend(...)

    events.sort(key=lambda e: e.executed_at)
    return events
```

Nothing here is architecturally novel — it's five reads and a sort. That's deliberate, and it's the actual point: the value isn't clever code, it's having the query already written and ready before an incident, instead of improvising it while something's actively going wrong.

## Seeing what one query surfaces that five separate logs wouldn't have, easily

A simulated incident: an agent tries five different things over six minutes — an unscoped delete, a disguised schema change, an out-of-scope relabel, an expensive cartesian join — each caught by a different control from earlier in this series. One line in this timeline predates all of it:

```
=== FILTERED: migration-agent only, chronological across all five controls (7 events) ===
  [08:00:00] Credential-Auditor       decision=SNAPSHOT             login=svc_shared_agent_login scope=US-WEST shared_with=billing-agent, support-bot-east
  [14:00:00] Guardrail                decision=APPROVED             UPDATE: UPDATE dbo.demo_accounts SET balance = balance - 5 WHERE account_id = 4
  [14:00:45] Guardrail                decision=BLOCKED_NO_WHERE     DELETE: DELETE FROM dbo.demo_accounts
  [14:01:30] Schema-Approval-Queue    decision=QUEUED_FOR_APPROVAL  DROP TABLE dbo.demo_accounts
  [14:02:10] Row-Level-Security       decision=BLOCKED_RLS          scope=US-WEST: UPDATE dbo.demo_accounts SET region = 'EU-CENTRAL' WHERE account_id = ...
  [14:02:50] Query-Cost-Governor      decision=BLOCKED_COST         est_cost=2.2600: SELECT a.owner_name, o.amount FROM dbo.demo_accounts a CROSS JOIN dbo. ...
  [14:04:00] Schema-Approval-Queue    decision=REJECTED             DROP TABLE dbo.demo_accounts (resolved by dba-ivan)
```

The 08:00:00 entry — a credential-sharing risk exactly the kind the [fourth post in this series](/blog/2026/08/19/ai-agent-credential-connection-auditor-sql-server/) would flag — is six hours before anything else in this timeline. It's not a separate report someone has to remember to pull. It's the same query.

## The honest pattern across the last two posts in this series

This is the second project here (after the credential auditor) that worked correctly the first time I ran it against SQL Server, with no real bug story to tell. Worth naming the pattern directly rather than pretending otherwise for consistency with the earlier, harder-won posts: the two lowest-risk projects to get right in this entire series are the two that never touch SQL Server's transactional or query-planning machinery — audit and replay. No transaction boundaries to get subtly wrong, no predicate timing to misunderstand, no execution-plan parsing to miscalibrate. Just reads and a sort.

That's a genuinely useful piece of advice buried in what could read as a boring admission: the detective layer is cheap to build correctly, which makes it a reasonable place to start — even before the preventive controls it eventually sits on top of are fully built out. The hard part of this particular project wasn't the code. It was designing a seed scenario realistic enough that the consolidated timeline actually demonstrated its value instead of just proving a UNION query works.

## What this doesn't solve

This doesn't detect that an incident is happening — it answers "what happened" once someone already knows to ask. It also seeds its own demo data rather than connecting to five live sibling databases; a real deployment would query the actual guardrail, approval-queue, RLS, credential-auditor, and cost-governor audit tables directly, or a consolidated copy of them. Detecting that something's worth reviewing in the first place — anomaly scoring, alerting thresholds — is a different, unbuilt project.

## Where the series ends, for now

Six projects, six real SQL Server demos, six pieces of the same underlying argument: an AI agent with direct database access needs checks it can't talk its way around, at every layer — what it's allowed to run, what schema changes get a human's sign-off, what data its identity can reach, whether that identity still deserves trust, what a query will cost before it runs, and what actually happened when something goes wrong. No single layer covers what the others miss, and that was true on the first post and still true on this one. This is a deliberate stopping point for the series as originally scoped, not an implied cliffhanger — if a seventh piece makes sense later, it'll earn its place the way each of these six did: a real gap, a real incident, a real demo.

The full project — the five-table schema, the timeline and summary logic, and the seeded incident scenario runnable via Docker Compose against a real SQL Server 2025 instance — is open source: [github.com/mrivanlima/ai-agent-incident-replay](https://github.com/mrivanlima/ai-agent-incident-replay){:target="_blank" rel="noopener noreferrer"}. If your agents already have database access spread across multiple controls and you don't have one query that can answer "what did this agent actually do," that's worth building before you need it during an actual incident. [Get in touch](/about/#contact) if you want help wiring this series into your own environment.

*Ivan Lima is a data engineer specializing in database modernization for AI systems. [Get in touch](/about/#contact) if your database needs to be ready for what's next.*
