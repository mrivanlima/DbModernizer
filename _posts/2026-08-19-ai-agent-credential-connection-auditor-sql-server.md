---
title: "The Permissions Were Never Checked Again After They Were Granted"
description: "A fourth layer for AI agent database access: auditing the identity layer itself -- shared credentials, stale rotation, and scope creep -- that my SQL Server firewall, approval queue, and row-level security all quietly assume is trustworthy."
categories: [case-studies]
tags: [ai-agents, agent-access, database-governance, open-source, real-incidents]
image: /assets/images/ai-agent-credential-auditor-01.png
date: 2026-08-19 07:50:00 -0400
---

![Three flagged findings from an AI agent credential audit: a shared credential used by three agents, a credential 270 days overdue for rotation, and 67% of a granted access scope never actually used](/assets/images/ai-agent-credential-auditor-01.png)

This is the fourth piece in a series on database-side controls for AI agents with direct SQL execute access. The [first post](/blog/2026/08/17/ai-agent-database-firewall-sql-server/) refused badly-shaped statements outright. The [second](/blog/2026/08/18/schema-change-approval-queue-for-ai-agents/) queued schema changes for human review instead of refusing them outright. The [third](/blog/2026/08/18/ai-agent-row-level-security-sql-server/) scoped what an agent could see and touch based on its declared identity — and closed with an honest caveat I want to pick up here: Row-Level Security enforces scope given an *honestly declared* identity. It doesn't authenticate that identity, and it doesn't check whether the identity's grant is still appropriate. This post is what closes that gap.

## The incident underneath the incident

The Mexican government breach that motivated the row-level-security post — nine agencies, 195 million taxpayer records, 220 million civil records, December 2025 through February 2026 — had a root cause underneath its root cause. The excessive, shared permissions that made the breach possible didn't appear the day it happened. They existed for a long time before that, unaudited, because nobody was checking whether a grant made sense against how it was actually being used.

That's not a hypothetical pattern. A [2026 least-privilege research report](https://www.kiteworks.com/cybersecurity-risk-management/ai-agent-security-incidents-2026/){:target="_blank" rel="noopener noreferrer"} analyzing over 3 billion permissions found that on average only about 4% had been used in the trailing 90 days, while nearly one in three could modify or delete sensitive data. And per IBM's Cost of a Data Breach Report 2025, 97% of AI-related breaches involved organizations lacking proper AI access controls — not lacking access controls generically, lacking ones scoped and audited for AI and agent identities specifically. Nobody had to break in cleverly the first time either. The permissions were just never checked again after they were granted.

## Key takeaways

- Row-level security and statement-shape guardrails both assume the calling identity is trustworthy — none of the controls earlier in this series verify that assumption or check whether a grant is still appropriate
- Treat agent credentials the way DBAs already treat human access reviews: register what was granted, log what's actually used, and periodically audit the gap between the two
- Three checks catch three distinct failure modes: agents sharing one underlying credential (a single compromise takes out every agent using it), credentials nobody has rotated, and broad grants an agent's actual activity never exercises
- This is the first project in the series that isn't a runtime gate — it's a detective control, a periodic review, not a preventive one blocking anything in real time

## What was actually built

A registry of declared agent identities, an activity log of what they actually do, and three audit checks run against the gap between them:

```python
def audit_shared_credentials(self) -> list:
    """Flags any credential_login used by more than one declared agent identity."""
    with self.engine.connect() as conn:
        rows = conn.execute(text(
            "SELECT credential_login, agent_id FROM dbo.agent_registry "
            "ORDER BY credential_login, agent_id"
        )).fetchall()

    by_login = {}
    for r in rows:
        by_login.setdefault(r.credential_login, []).append(r.agent_id)

    return [
        SharedCredentialFinding(credential_login=login, agent_ids=agents)
        for login, agents in by_login.items() if len(agents) > 1
    ]
```

The scope-creep check is the one I'd point to as the most directly useful in practice: for every agent granted the broadest scope, it compares that grant against the regions its activity log actually shows it touching, and reports what percentage of the grant has simply never been exercised — the same 4%-utilization finding from the research above, computed against this project's own data instead of cited as an external statistic.

## Seeing it flag real patterns

Five registered agents — three deliberately sharing one credential, one with a credential nobody's rotated in 270 days, two granted the broadest scope — after three weeks of simulated activity:

```
--- Shared-credential findings ---
  RISK: credential 'svc_shared_agent_login' is shared by 3 declared agents:
        billing-agent, migration-agent-west, support-bot-east
        A single compromised or leaked credential here compromises all 3
        agent identities at once.

--- Stale-credential findings (>180 days since rotation) ---
  RISK: agent 'ops-admin-agent' credential 'svc_ops_admin_login' last
        rotated 270 days ago.

--- Scope-creep findings (granted 'ALL', actual usage narrower) ---
  RISK: agent 'ops-admin-agent' declared scope=ALL, but activity history
        only ever touches: US-EAST, US-WEST
        33% of the granted region scope has never actually been used.
  RISK: agent 'reporting-agent' declared scope=ALL, but activity history
        only ever touches: US-EAST
        67% of the granted region scope has never actually been used.
```

Worth being precise about the shared-credential check's mechanics, because a technically sharp reader will ask: it audits the registry's *declared* credential label, not the raw SQL login SQL Server itself observes via `SUSER_SNAME()`. In this demo — and in most real deployments routing agents through one shared MCP gateway connection — every agent's observed SQL login is identical by construction, which is itself the exact anti-pattern being flagged. A deployment provisioning real, distinct SQL logins per agent would get the same signal directly from `SUSER_SNAME()` instead of the registry.

## The honest, slightly anticlimactic lesson

Every other project in this series had a real bug story: a clock-drift issue in the point-in-time restore, a future-dated post silently dropped, a wrong assumption about how a block predicate fails. This one worked correctly the first time I ran it against SQL Server. That's worth naming rather than manufacturing drama for consistency — the reason is structural. This project never touches SQL Server's transactional or predicate machinery; it's plain table reads and threshold comparisons in Python. That category of code is inherently easier to get right than anything involving transaction boundaries or predicate timing, which is exactly what the earlier three projects kept tripping on.

That's part of the actual pitch for building this one, not an afterthought: detective controls are cheaper to get right than preventive ones, and this is the control that tells you whether the other three are even pointed at the right identities in the first place. If you're deciding where to start hardening AI agent database access and can only build one thing first, an audit of what's already been granted is a reasonable place to begin — before the guardrail, the queue, or the row-level policy, because all three of those inherit whatever the credential layer already got wrong.

## What this doesn't solve

This finds the gap; it doesn't close it. Narrowing an over-broad grant or rotating a stale credential is still a human decision this project deliberately doesn't automate, the same way the schema-approval project surfaces DDL requests rather than resolving them unilaterally. And the shared-credential check specifically depends on the registry being maintained honestly — if nobody updates it when a new agent starts reusing an old credential, the audit won't catch what it was never told about.

Across all four projects now: the firewall refuses what should never run. The approval queue routes what might be legitimate to a human. Row-level security scopes what an agent can reach by identity. This audits whether that identity — and its grant — still deserves to be trusted at all. An AI agent with real database access needs checks at every one of those layers, because none of them alone covers what the others miss.

The full project — the registry, activity log, and all three audit checks runnable via Docker Compose against a real SQL Server 2025 instance — is open source: [github.com/mrivanlima/ai-agent-credential-auditor](https://github.com/mrivanlima/ai-agent-credential-auditor){:target="_blank" rel="noopener noreferrer"}. If you can't currently answer "which of our agents' grants have actually been used in the last 90 days," that's worth finding out before an audit happens under worse circumstances. [Get in touch](/about/#contact) if you want help running this against your own environment.

*Ivan Lima is a data engineer specializing in database modernization for AI systems. [Get in touch](/about/#contact) if your database needs to be ready for what's next.*
