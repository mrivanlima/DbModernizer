---
title: "Stop LLMs From Hallucinating SQL: Self-Correcting Agents"
description: "Hallucinated joins aren't an LLM defect. They're what happens when an agent queries a schema it's never actually seen at the DDL or catalog level, unguided."
date: 2026-08-20 05:40:00 -0400
categories: [ai-semantics]
tags: [text-to-sql, schema-linking, agent-access, database-first-architect, grounded-architect]
image: /assets/images/stop-llms-hallucinate-sql-self-correcting-agents-01.png
---

![Diagram showing a self-correcting text-to-SQL agent loop: draft query, execute against a sandboxed connection, catch the error, read information_schema, rewrite, and retry, with state persisted to the Agent State Ledger](/assets/images/stop-llms-hallucinate-sql-self-correcting-agents-01.png)

Hallucinated joins aren't a sign the LLM is dumb. They're what happens every time an agent gets asked to write SQL against a schema it has never actually seen — no catalog, no DDL, no foreign key map, just a table name typed into the prompt and a guess. Single-shot text-to-SQL fails on real enterprise schemas for the same reason a new hire fails when you hand them a business question and no data dictionary: not because they can't reason, but because they're reasoning over a schema that exists only in your head.

## Why one-shot prompting can't survive a real schema

The demo version of text-to-SQL looks convincing because demo schemas are small. Five tables, obvious column names, one sensible join path. Production schemas aren't like that. They're forty tables deep, with `customer_id` meaning three different things across three different systems, nullable foreign keys, and join paths that only make sense if you know which table got deprecated in 2019 but never dropped.

Ask a model to write SQL against that with nothing but a natural-language description of the schema, and it will do exactly what it's built to do: produce the most statistically plausible query, whether or not that query matches the actual constraints in the catalog. It invents a `customers.region` column because regions feel like something a customer table would have. It joins on `order_id` instead of `order_uuid` because that's the more common convention it's seen in training data. None of that is a reasoning failure. It's a grounding failure — the model was never given the one artifact that would have prevented it: the actual schema, queried at generation time, not summarized in a prompt.

## Why "better prompting" doesn't fix it either

The usual fix is to stuff more schema description into the prompt — table names, a few sample rows, a paragraph explaining the business logic. That helps, marginally, and it doesn't scale. Every enterprise schema changes: columns get renamed, tables get partitioned, a nullable column becomes required after a migration. A static schema description in a prompt goes stale the first time someone runs `ALTER TABLE`, and nobody updates the prompt when that happens. You end up maintaining a second, shadow copy of your schema in English, by hand, forever — which is precisely the kind of manual synchronization problem database engineers have spent decades building tools to eliminate.

The actual fix isn't better wording. It's giving the agent the same thing you'd give a new engineer on day one: read access to the catalog itself, plus a way to find out when it's wrong.

## The database-first fix: execute, catch, diagnose, rewrite

This is a multi-step loop, not a single inference call, and every step maps to something a database engineer already does instinctively when a query fails:

1. The agent drafts a candidate query based on the user's question and whatever schema context it has.
2. It executes that query against a sandboxed, read-only connection — never production, never with write privileges.
3. If execution fails, it catches the actual database error: `column "region" does not exist`, a constraint violation, a type mismatch.
4. It reads `information_schema` (or the engine's equivalent catalog views) to resolve the real column names, types, and foreign keys for the tables in question.
5. It rewrites the query against what the schema actually says, and retries — with a hard cap on retry count so a genuinely bad question doesn't loop forever.

```python
MAX_ATTEMPTS = 4

def run_text_to_sql(question: str, session_id: str, agent_id: str) -> QueryResult:
    attempt = 0
    context = {}  # accumulates real schema facts as errors surface

    while attempt < MAX_ATTEMPTS:
        sql = draft_sql(question, context)
        try:
            result = execute_readonly(sql)
            persist_ledger_state(session_id, agent_id, {
                "final_sql": sql, "attempts": attempt + 1, "status": "success"
            })
            return result
        except DatabaseError as err:
            attempt += 1
            missing = resolve_from_information_schema(err, sql)
            context.update(missing)  # real column names, types, FK targets
            persist_ledger_state(session_id, agent_id, {
                "last_error": str(err), "attempts": attempt, "status": "retrying"
            })

    raise UnresolvableQueryError(question, context)
```

That `persist_ledger_state` call isn't decorative. This retry loop has state that matters across attempts — how many tries have been spent, what schema facts have already been resolved, what the last error was — and that state belongs in the same place I described in [the first post in this series](/blog/2026/08/18/why-your-ai-agents-keep-crashing-database-architect/): the Agent State Ledger. A retry loop that keeps its progress in a local variable loses everything on a restart mid-loop and starts back at attempt one with no memory of what it already ruled out. A retry loop that writes its progress to durable state resumes exactly where it left off. Same failure mode as agent memory generally, just at a smaller scale.

Recent research backs the shape of this loop, not just the intuition behind it. MAC-SQL's Refiner agent executes a candidate query, observes the actual error or an empty result set, and rewrites accordingly, rather than trying to reason its way to a correct query in a single pass ([arXiv:2312.11242](https://arxiv.org/abs/2312.11242){:target="_blank" rel="noopener noreferrer"}). CHESS goes further for large, enterprise-scale schemas, pairing a Schema Selector that prunes an oversized catalog down to the relevant sub-schema with a Unit Tester that validates candidate queries before they're trusted ([arXiv:2405.16755](https://arxiv.org/abs/2405.16755){:target="_blank" rel="noopener noreferrer"}). Across this line of work, using the database's own execution feedback — a real error message, not a model second-guessing itself — is consistently what makes the correction loop actually converge instead of drifting into a different wrong answer.

## The analogy

A self-correcting SQL agent reading its own execution traceback and retrying is functionally what a query optimizer does when a plan fails: it doesn't sit and philosophize about why the plan might be suboptimal, it captures what actually happened, diagnoses the specific cause, and recompiles a new plan against ground truth. Nobody would trust an optimizer that picked a plan once and refused to ever look at execution statistics again. We shouldn't trust a text-to-SQL agent that works the same way.

## Practical guidance

- Never let the agent execute against production or with write privileges during query drafting. A sandboxed, read-only connection is non-negotiable — this loop will generate plenty of invalid SQL on the way to valid SQL.
- Query `information_schema` (or your engine's catalog views) live, at generation time. Don't hand the model a static schema summary and hope it stays current.
- Cap retries explicitly. A question the agent can't resolve in four attempts against the real catalog usually means the question itself is ambiguous, not that attempt five will succeed.
- Persist retry state — attempt count, resolved schema facts, last error — to durable storage, not a local variable, so a mid-loop restart doesn't erase progress.
- Log every failed attempt and its real database error. That log is what tells you whether your schema is genuinely hard to query or whether your agent's prompt context is stale.

## Key takeaways

- Hallucinated SQL isn't an LLM defect — it's what happens when an agent generates queries against a schema it's never actually seen at the DDL/catalog level.
- Static schema descriptions in prompts go stale the moment the real schema changes; querying `information_schema` live doesn't.
- The fix is a bounded loop: draft, execute against a sandboxed connection, catch the real error, resolve against the catalog, rewrite, retry.
- This loop needs durable state across attempts — the same Agent State Ledger pattern from post one, not a variable that disappears on restart.
- This is post two of three in [Database-First Agent Architecture](/blog/2026/08/18/why-your-ai-agents-keep-crashing-database-architect/). Post three covers the governance boundary this loop depends on: exactly what an autonomous agent is allowed to execute once it's confident in a query, building on the access-control ground covered in [AI Agent Guardrails for Databases](/blog/2026/08/14/ai-agent-guardrails-for-databases/).

If your agents are guessing at your schema instead of reading it, that's a fixable architecture problem, not a prompting problem. [Get in touch](/about/#contact) or see how we approach it on [our services page](/services/).

*Ivan Lima is a data engineer specializing in database modernization for AI systems. [Get in touch](/about/#contact) if your database needs to be ready for what's next.*
