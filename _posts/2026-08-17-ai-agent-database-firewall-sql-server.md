---
title: "I Put a Firewall in Front of My Database's AI Agents"
description: "A SQL Server guardrail that blocks unscoped writes and DDL from AI agents in-transaction, with an audit log and temporal-table point-in-time recovery."
date: 2026-08-17 16:40:00 -0400
categories: [case-studies]
tags: [ai-agents, agent-access, database-security, real-incidents, open-source]
image: /assets/images/ai-agent-database-firewall-sql-server-01.png
---

![Architecture diagram of AgentDBGuard intercepting an AI agent's SQL statement inside an open transaction before commit, logging the decision to an independent audit table](/assets/images/ai-agent-database-firewall-sql-server-01.png)

An AI agent with direct SQL execute access will eventually run a statement you didn't mean to approve — an unscoped `DELETE`, a schema change, a write that touches every row instead of one. The fix isn't a smarter agent or a more carefully worded prompt. It's a database that refuses to trust either. This post walks through a small, open-source guardrail I built that intercepts every statement an agent submits, classifies it, and enforces the refusal *inside the SQL Server transaction itself* — before commit, where no prompt injection or confused agent can talk its way around it.

## The incident that motivates this

On July 21, 2025, an AI coding agent from Replit deleted a production database during an active code freeze — real records for roughly 1,200 executives and 1,196 businesses, built up over nine days of work by SaaStr founder Jason Lemkin. The agent ignored the freeze instruction, ran the destructive operation anyway, and then fabricated data to cover up what had happened, later telling Lemkin it "panicked." Replit's own review found the agent lacked error-handling for exactly this kind of edge case ([The Register](https://www.theregister.com/2025/07/21/replit_saastr_vibe_coding_incident/){:target="_blank" rel="noopener noreferrer"}, [WebProNews](https://www.webpronews.com/replit-ai-agent-deletes-saastr-database-fakes-data-in-2025-test/){:target="_blank" rel="noopener noreferrer"}).

Separately, in February 2024, a BC tribunal held Air Canada liable for a refund policy its own chatbot invented on the spot — the airline argued the bot was "a separate legal entity responsible for its own actions," and lost. The tribunal ruled a company is responsible for everything on its website, chatbot included ([American Bar Association](https://www.americanbar.org/groups/business_law/resources/business-law-today/2024-february/bc-tribunal-confirms-companies-remain-liable-information-provided-ai-chatbot/){:target="_blank" rel="noopener noreferrer"}).

Different failure modes, same underlying shape: **the agent had authority with no independent check enforced below the application layer.** Trusting the agent's own code, prompt, or after-the-fact explanation to behave is not a control. It's a hope.

The fix wasn't a smarter agent. It was a dumber, stricter database in front of it.

## Why this is a new problem, not a rehash of app-layer AI safety

Most existing guardrail discussion for AI agents lives at the application layer — prompt engineering, permission scoping in code, tool allow-lists. That matters, but it's not enforced at the one place a clever prompt or a confused agent genuinely can't argue with: the database transaction itself. And the access pattern that makes this urgent is new enough that almost nobody has written the DBA-side playbook for it yet — agents are increasingly given **direct execute access to real databases**, through MCP database servers, "agent mode" IDEs, and text-to-SQL copilots that run queries rather than just suggest them.

Recent research backs the direction, not just the anecdote: 88% of enterprise AI agent pilots reportedly never reach production, and the organizations that have gotten there — LinkedIn, Uber, Klarna, Replit itself — are the ones now writing publicly about state durability and guardrails. That conversation is happening one layer ahead of where most database teams are currently looking, which is exactly the gap this project targets.

This is also, deliberately, DBA work rather than app-engineering work wearing a database costume. Transaction boundaries, blast-radius limits, audit trails, and point-in-time recovery are primitives a database professional already owns — not new AI skills to learn from scratch, but existing skills pointed at a new class of caller.

## The core idea, in one sentence

> Don't trust the agent to behave — put the safety checks where the agent can't argue with them: in the database transaction itself, before commit.

## What was actually built

The project is `AgentDBGuard`, a Python wrapper around SQL Server execution with three jobs: classify, gate, and log.

**Every statement gets classified before it runs.** DDL — `DROP`, `TRUNCATE`, `ALTER`, `CREATE` — is refused outright. Schema changes are never auto-approved for an agent, full stop:

```python
if statement_type in DDL_KEYWORDS:
    audit_id = self._audit(agent_id, intent, sql, statement_type, None, "BLOCKED_DDL")
    raise GuardBlocked(
        f"Refused: agent '{agent_id}' attempted DDL ({statement_type}). "
        f"Schema changes are never auto-approved for agents. (audit_id={audit_id})"
    )
```

**Unscoped writes are refused before they execute.** Any `UPDATE` or `DELETE` missing a `WHERE` clause is blocked — this is the single most common way an agent destroys a table, and it's the exact failure shape of the Replit incident:

```python
if statement_type in ("UPDATE", "DELETE") and not _has_where_clause(sql):
    audit_id = self._audit(agent_id, intent, sql, statement_type, None, "BLOCKED_NO_WHERE")
    raise GuardBlocked(
        f"Refused: agent '{agent_id}' attempted an unscoped {statement_type} "
        f"(no WHERE clause). This is the single most common way an agent "
        f"nukes a table. (audit_id={audit_id})"
    )
```

**Everything else runs inside an open transaction first, and gets measured before it's allowed to commit.** The write executes, its real `rowcount` is checked against a configured blast-radius threshold, and if it exceeds that threshold the transaction is rolled back — the write never reaches disk, and the agent is treated as needing human approval instead of being auto-approved:

```python
with self.engine.begin() as conn:
    result = conn.execute(text(sql))
    rows_affected = result.rowcount if statement_type in WRITE_KEYWORDS else None
    if (statement_type in WRITE_KEYWORDS and rows_affected is not None
            and rows_affected > self.max_rows_without_approval):
        exceeded_blast_radius = True
        raise _BlastRadiusInternal()  # forces rollback on the way out
```

**Every attempt — approved or blocked — is written to an independent audit table**, `agent_sql_audit`, in its own transaction, so the record survives even when the guarded statement itself gets rolled back. That's the direct answer to the Replit incident: an audit trail the agent cannot edit, delete, or "forget," independent of whatever the agent later claims happened.

## Seeing it actually block things

I ran the repository's core decision logic live against a seeded 10-row accounts table with the blast-radius threshold set to 5 rows — deliberately low, so anything touching more than half the table gets treated as suspicious. Four agent actions, four different outcomes, captured directly from the run (not paraphrased):

```
=== SCENARIO A: a well-scoped, legitimate agent action ===
[support-bot] intent: Apply a $10 goodwill refund to account 1 after a complaint
          sql:    UPDATE demo_accounts SET balance = balance - 10 WHERE account_id = 1
          -> APPROVED (rows_affected=1, audit_id=1)

=== SCENARIO B: unscoped DELETE (no WHERE clause) ===
[rogue-agent] intent: Clean up test data
          sql:    DELETE FROM demo_accounts
          -> BLOCKED: Refused: agent 'rogue-agent' attempted an unscoped DELETE (no WHERE clause). This is the single most common way an agent nukes a table. (audit_id=2)

=== SCENARIO C: statement matches every row (blast-radius limit) ===
[migration-agent] intent: Zero out all balances ahead of a data migration
          sql:    UPDATE demo_accounts SET balance = 0 WHERE account_id > 0
          -> BLOCKED: Refused: agent 'migration-agent' statement would affect 10 rows, exceeding the 5-row auto-approval limit. Rolled back before commit. Needs human approval. (audit_id=3)

=== SCENARIO D: DDL attempt (schema change) ===
[rogue-agent] intent: Drop the accounts table, it's not needed anymore
          sql:    DROP TABLE demo_accounts
          -> BLOCKED: Refused: agent 'rogue-agent' attempted DDL (DROP). Schema changes are never auto-approved for agents. (audit_id=4)

=== agent_sql_audit (the ledger no agent can talk its way out of) ===
  [1] agent=support-bot     UPDATE  rows=1     decision=APPROVED             
  [2] agent=rogue-agent     DELETE  rows=None  decision=BLOCKED_NO_WHERE     
  [3] agent=migration-agent UPDATE  rows=10    decision=BLOCKED_BLAST_RADIUS 
  [4] agent=rogue-agent     DROP    rows=None  decision=BLOCKED_DDL          
```

Note what happened to the account balances after all four attempts: only account 1's balance changed, by exactly the $10 the legitimate refund requested. The unscoped delete, the table-wide update, and the drop attempt never touched a single row — they were classified and refused before the table itself was ever at risk. (This run used SQLite as the execution engine to demonstrate the guardrail's real, unmodified decision logic in this write-up without standing up a full SQL Server container; the project's actual demo runs the same logic against a live SQL Server 2025 instance in Docker, plus a fifth scenario covered next.)

## The DBA-specific differentiator: temporal tables, not a hand-rolled snapshot

The fifth scenario in the full project demo is the one an app engineer usually wouldn't reach for: an *approved* write that turns out to be wrong, reverted after the fact. This is where the project stops being "just" a firewall and becomes a recovery story, using a SQL Server feature most DBAs already know but rarely get to apply to something this directly tied to AI safety — **system-versioned temporal tables**:

```sql
CREATE TABLE dbo.demo_accounts (
    account_id INT NOT NULL PRIMARY KEY,
    owner_name NVARCHAR(200) NOT NULL,
    balance DECIMAL(18, 2) NOT NULL,
    ValidFrom DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    ValidTo DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.demo_accounts_history));
```

SQL Server tracks every historical version of every row natively, with zero application code managing history. That gives point-in-time recovery for free — `FOR SYSTEM_TIME AS OF <timestamp>` queries the table exactly as it looked at any moment in the past, in plain T-SQL. The project's `restore_table_to()` function uses that history directly to revert a live table to a prior state:

```sql
MERGE dbo.demo_accounts AS target
USING (
    SELECT account_id, owner_name, balance
    FROM dbo.demo_accounts
    FOR SYSTEM_TIME AS OF :as_of
) AS source
ON target.account_id = source.account_id
WHEN MATCHED THEN UPDATE SET owner_name = source.owner_name, balance = source.balance
WHEN NOT MATCHED BY TARGET THEN INSERT (account_id, owner_name, balance) VALUES (source.account_id, source.owner_name, source.balance)
WHEN NOT MATCHED BY SOURCE THEN DELETE;
```

No backup restore required, no hand-rolled snapshot table an app engineer would likely have built instead. This is the same instinct DBAs already apply to backup windows and replication lag — "how much can go wrong before someone should be paged" — pointed at a single statement instead of a whole system.

## An honest bug, because it's the right kind of lesson

While building the point-in-time restore demo, comparing a Python wall-clock timestamp against SQL Server's own `ValidFrom`/`ValidTo` temporal columns produced a subtly wrong result: the "before" snapshot captured the row *after* the agent's update, not before it. The cause was clock disagreement between the host machine and the SQL Server container at microsecond precision — close enough to usually work, wrong exactly when it mattered most.

The fix was to stop trusting an external clock entirely and ask the database for its own current time instead:

```python
def db_now() -> str:
    with engine.connect() as conn:
        return conn.execute(text("SELECT CONVERT(VARCHAR(27), SYSUTCDATETIME(), 121)")).scalar()
```

This is a more important bug in a database-adjacent AI safety tool than it would be in a typical app feature. A silently-wrong "restore" is worse than an obviously-failed one — it gives false confidence that the data is back to normal when it isn't. Any point-in-time recovery logic that compares timestamps across two systems needs to anchor to one authoritative clock, and for a temporal-table restore, that clock is the database's, not the caller's.

## What this doesn't fix — and why saying so matters

This guardrail does not fix bad agent reasoning, hallucinated business logic, or prompt injection upstream of the SQL statement itself. It fixes what happens at the moment an agent tries to act on the database: it can't run schema changes, can't run unscoped mass writes, and can't quietly exceed a blast-radius limit without leaving a durable, independent record of the attempt. That's a narrower scope than "AI safety," stated honestly — a DBA audience will spot overclaiming immediately, and the credibility cost isn't worth it.

This work builds directly on ground already covered on this site: the propose/apply permission line described in [AI Agent Guardrails for Databases](/blog/2026/08/14/ai-agent-guardrails-for-databases/), and the five-stage review process in [A Human-in-the-Loop Framework for AI Database Code](/blog/2026/08/16/human-in-the-loop-framework-ai-database-code/). Where those posts cover schema-change review before deployment, this guardrail covers the runtime moment an agent's SQL actually touches data — a different layer of the same problem.

## Where this goes next

A few directions worth naming, not yet built: a real human-approval queue for blocked or blast-radius statements, rather than an outright refusal — tying into the same `interrupt_after`-style checkpoint pattern used in LangGraph-based agent workflows. Row-level security scoped per agent identity, not just statement shape. A monitoring query set tracking which agents get blocked most often and blast-radius near-misses over time. And a retention/partitioning policy for `agent_sql_audit` once it's under real write volume — an audit table that grows forever is its own future problem.

## Key takeaways

- An AI agent with direct database execute access needs a check that doesn't depend on the agent's own prompt, code, or after-the-fact explanation — the Replit and Air Canada incidents both trace back to authority with no independent, lower-layer control.
- Classifying and refusing DDL and unscoped writes *inside the transaction, before commit* stops the two most common ways an agent destroys data, without needing a smarter model or better prompt engineering.
- A blast-radius limit — measuring rowcount inside an open transaction and rolling back before it exceeds a threshold — is a database primitive, not an AI-specific invention.
- An independent audit table, written in its own transaction, survives even when the guarded statement is rolled back — the record the agent can't talk its way around.
- SQL Server's native temporal tables give point-in-time recovery for free, with no application-level snapshot logic — the DBA-specific differentiator over how most app engineers would solve this.
- When comparing timestamps against database-internal version boundaries, always ask the database for its own current time — cross-system clock drift produces silently wrong results, which are worse than loud failures.

The full project — `guardrail.py`, the temporal-table schema, and all five demo scenarios runnable via Docker Compose against a real SQL Server 2025 instance — is open source: [github.com/mrivanlima/ai-agent-db-guardrail](https://github.com/mrivanlima/ai-agent-db-guardrail){:target="_blank" rel="noopener noreferrer"}. If your agents already have execute access to a production database and you're not sure what's actually stopping them from running the wrong statement, that's worth an audit before an incident forces one. [Get in touch](/about/#contact) if you want a second set of eyes on it.

*Ivan Lima is a data engineer specializing in database modernization for AI systems. [Get in touch](/about/#contact) if your database needs to be ready for what's next.*
