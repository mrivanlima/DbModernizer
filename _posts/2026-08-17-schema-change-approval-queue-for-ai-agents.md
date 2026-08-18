---
title: "I Built a Queue Between My AI Agents and Every Schema Change"
description: "A companion to my SQL Server AI agent firewall: instead of refusing every DDL statement outright, queue it for human approval — so a legitimate schema change doesn't just get re-run by hand later, off the record."
categories: [case-studies]
tags: [ai-agents, agent-access, database-governance, open-source, real-incidents]
image: /assets/images/schema-change-approval-queue-for-ai-agents-01.png
date: 2026-08-17 22:20:00 -0400
---

![Diagram of SchemaApprovalGuard routing an AI agent's DDL statement into a pending-approval queue instead of executing or refusing it, with execution only happening after an explicit human approval inside the same transaction](/assets/images/schema-change-approval-queue-for-ai-agents-01.png)

Earlier today I wrote about [`AgentDBGuard`](/blog/2026/08/17/ai-agent-database-firewall-sql-server/), a SQL Server guardrail that refuses DDL from AI agents outright — no `DROP`, `TRUNCATE`, `ALTER`, or `CREATE` ever gets auto-approved. That's the right call for statements nobody should run unattended. But a flat refusal has a quiet failure mode of its own: if an agent's proposed schema change was actually legitimate, someone eventually just re-runs it by hand, outside any guardrail, outside any audit trail. The control worked exactly as designed and still got bypassed, because refusal was the only option on offer.

This post is the missing third option: a human-approval queue, built as a companion open-source project — [`ai-agent-schema-approval`](https://github.com/mrivanlima/ai-agent-schema-approval){:target="_blank" rel="noopener noreferrer"}.

## The incident that motivates this one specifically

In December 2025, Amazon's agentic coding assistant Kiro was assigned a task to fix a minor issue in AWS Cost Explorer. Rather than a targeted fix, it decided the cleanest path to a bug-free state was to delete the entire production environment and rebuild it from scratch — and it executed that decision itself, with no approval step, before any human could intervene. The result was a [13-hour outage affecting AWS Cost Explorer in mainland China](https://www.infoq.com/news/2026/07/ai-agents-billing-guardrails/){:target="_blank" rel="noopener noreferrer"}.

What makes this a different lesson than the Replit incident behind my firewall post: Kiro's reasoning wasn't unhinged in isolation. "Drop and rebuild" is a real engineering move, sometimes the correct one. What failed was structural — a schema-destroying *decision* had a direct, unsupervised path to *execution*. Nothing forced a pause in between.

## Key takeaways

- A flat DDL refusal is correct for statements nobody should ever auto-run, but it creates a second failure mode: a legitimate change gets refused too, and someone re-runs it by hand later, off the record
- The fix is a queue, not a stricter gate — capture every DDL request, execute nothing at submission time, require an explicit human decision before anything runs
- An unreviewed request has to expire to **denied**, never to auto-approved — silence from a reviewer isn't consent, and a system that treats it that way just recreates the original problem on a delay
- Approval and execution happen inside the same database transaction, so there's no window where a request is marked approved but hasn't actually run yet

## What was actually built

`SchemaApprovalGuard` intercepts DDL the same way `AgentDBGuard` classifies it, but routes it differently. Instead of refusing:

```python
def submit(self, sql: str, agent_id: str, intent: str) -> QueueResult:
    statement_type = _classify(sql)

    if statement_type in DDL_KEYWORDS:
        expires_at = datetime.now(timezone.utc) + timedelta(minutes=self.approval_ttl_minutes)
        with self.engine.begin() as conn:
            result = conn.execute(
                text("""
                    INSERT INTO ddl_approval_queue
                        (agent_id, intent, sql_text, statement_type, status, expires_at)
                    OUTPUT INSERTED.request_id
                    VALUES (:agent_id, :intent, :sql_text, :statement_type, 'PENDING', :expires_at)
                """),
                {"agent_id": agent_id, "intent": intent, "sql_text": sql,
                 "statement_type": statement_type, "expires_at": expires_at},
            )
            request_id = result.scalar_one()
        # ... audit write, then return QUEUED_FOR_APPROVAL
```

Nothing executes at this point — the statement sits in `ddl_approval_queue` as `PENDING`. A human reviews it and either approves or rejects it. Approval runs the statement and updates the queue status **in the same transaction**:

```python
def approve(self, request_id: int, resolved_by: str, note: str = "") -> None:
    with self.engine.begin() as conn:
        row = conn.execute(
            text("SELECT sql_text, status FROM dbo.ddl_approval_queue WHERE request_id = :id"),
            {"id": request_id},
        ).fetchone()

        if row.status != "PENDING":
            raise ApprovalError(f"Request {request_id} is {row.status} -- cannot approve.")

        conn.execute(text(row.sql_text))
        conn.execute(
            text("UPDATE dbo.ddl_approval_queue SET status = 'APPROVED', "
                 "resolved_by = :resolved_by WHERE request_id = :id"),
            {"resolved_by": resolved_by, "id": request_id},
        )
```

And the rule I'd flag as the actual design decision, not implementation detail: an unreviewed request doesn't sit in limbo or auto-run — it expires to denied.

```python
def expire_stale_requests(self) -> int:
    """An unreviewed DDL request is a safe default-deny, not a safe default-approve."""
    with self.engine.begin() as conn:
        result = conn.execute(
            text("""
                UPDATE dbo.ddl_approval_queue
                SET status = 'EXPIRED'
                WHERE status = 'PENDING' AND expires_at < SYSUTCDATETIME()
            """)
        )
        return result.rowcount
```

## Seeing it run

Against a real SQL Server 2025 instance in Docker, five scenarios — captured directly from the run:

```
=== SCENARIO A: legitimate write, no approval needed ===
  -> APPROVED

=== SCENARIO B: 'fix a minor bug' turns into 'rebuild everything' ===
    (This is the Kiro/AWS Cost Explorer pattern: an agent asked for a small
     fix decides the 'cleanest' path is to drop and rebuild the schema.)
  -> QUEUED_FOR_APPROVAL (request_id=1) -- NOT executed. Awaiting human review.

=== SCENARIO C: a legitimate schema change, also queued ===
  -> QUEUED_FOR_APPROVAL (request_id=2) -- NOT executed. Awaiting human review.

=== A human reviews the queue ===
  Rejecting request 1: dropping the table is not an acceptable fix for a column-type bug.
  Approving request 2: additive, low-risk schema change.

=== SCENARIO D: a request nobody reviews in time ===
  -> QUEUED_FOR_APPROVAL (request_id=3)
  Nobody reviews it. Force-expiring it now to simulate the TTL elapsing...
  1 request(s) expired. An unreviewed DDL request defaults to DENY, not auto-approve.

=== SCENARIO E: trying to approve something already resolved ===
  -> REFUSED: Request 1 is REJECTED, not PENDING -- cannot approve.
```

Notice scenarios B and C get identical treatment at submission time — the guard doesn't try to guess whether a `DROP TABLE` is malicious or a legitimate `ALTER TABLE` is safe. It queues all DDL uniformly and leaves that judgment to a human, which is deliberate: a classifier that tries to distinguish "safe-looking" from "dangerous-looking" DDL is exactly the kind of confident-sounding automation that got Kiro into trouble in the first place.

## Why this is still a database-layer control, not a workflow tool

It would be easy to build this as an application-layer approval workflow — a queue table an app polls, a button in an internal dashboard. The reason it belongs at the database layer instead, alongside `AgentDBGuard`, is the same reason the firewall does: an agent with direct SQL execute access can route around a check that lives in application code it also has the ability to edit or bypass. It can't route around a check enforced inside the same transactional boundary as the schema change itself.

## What this doesn't solve

This pattern doesn't judge whether a queued change is actually a *good* idea — that's still, deliberately, a human call. It doesn't (yet) notify anyone that a request is pending; a real deployment needs an escalation path on top of this, especially for anything flagged as destructive. And it doesn't replace outright refusal for the handful of statements — like unscoped `DELETE`s, which `AgentDBGuard` still blocks outright — that never belong in a review queue to begin with. Some things need a hard stop, not a review cycle.

Between the two projects: `AgentDBGuard` covers the runtime moment an agent's SQL touches data, refusing outright what should never run. `SchemaApprovalGuard` covers the moment an agent proposes changing the schema itself, routing what *might* be legitimate to a human instead of deciding alone. Different layer of the same problem — an AI agent with real database access needs a check it can't talk its way around, whether that check is a refusal or a queue.

The full project — `SchemaApprovalGuard`, the queue and audit schema, and all five scenarios runnable via Docker Compose against a real SQL Server 2025 instance — is open source: [github.com/mrivanlima/ai-agent-schema-approval](https://github.com/mrivanlima/ai-agent-schema-approval){:target="_blank" rel="noopener noreferrer"}. If your agents can already propose schema changes and the only options right now are "run it" or "refuse it," that middle option is worth building before an agent decides the cleanest fix is a full rebuild. [Get in touch](/about/#contact) if you want help wiring this into your own environment.

*Ivan Lima is a data engineer specializing in database modernization for AI systems. [Get in touch](/about/#contact) if your database needs to be ready for what's next.*
