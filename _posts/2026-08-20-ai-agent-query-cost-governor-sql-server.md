---
title: "The Refusal Took 11 Milliseconds. The Query Would Have Taken 1,584."
description: "A fifth layer for AI agent database access: refusing expensive queries before they run at all, using SQL Server's own estimated execution plan -- because a correctly authorized, properly scoped query can still be the one that costs the most."
categories: [case-studies]
tags: [ai-agents, agent-access, database-performance, open-source, real-incidents]
image: /assets/images/ai-agent-query-cost-governor-01.png
date: 2026-08-20 07:45:00 -0400
---

![A refused query showing an 11.4ms estimated-cost-only check next to the 1,584ms and 400,000 rows it would have taken to actually run](/assets/images/ai-agent-query-cost-governor-01.png)

This is the fifth piece in a series on database-side controls for AI agents with direct SQL execute access. The [first](/blog/2026/08/17/ai-agent-database-firewall-sql-server/) refused badly-shaped statements. The [second](/blog/2026/08/18/schema-change-approval-queue-for-ai-agents/) queued schema changes for human review. The [third](/blog/2026/08/18/ai-agent-row-level-security-sql-server/) scoped access by identity. The [fourth](/blog/2026/08/19/ai-agent-credential-connection-auditor-sql-server/) audited whether that identity still deserved to be trusted. None of them ask the question this one does: even if a query is well-formed, authorized, correctly scoped, and issued by a trustworthy identity — is it *expensive*?

## The incident that motivates it

A three-person agency ate a $14,000 AWS bill in a single day after attackers extracted static access keys and burned Claude invocations on Bedrock. Different layer than what this post covers — infrastructure billing, not database compute — but the same underlying failure shape as everything else in this series: nothing was checking cost before it was incurred, and at agent speed, that gap turns a small mistake into a large one before a human notices.

The same failure exists one layer down, at the query level, every time an agent runs something expensive before anyone checks what it will cost. A join missing its condition, a WHERE clause that defeats every available index — a human writing SQL by hand rarely produces these by accident more than once. An agent generating queries at machine speed produces them constantly, and by the time the query is running, the cost is already being paid.

## Key takeaways

- A query can pass every check built earlier in this series — correct shape, authorized, correctly scoped, trustworthy identity — and still be the single most expensive thing that ran that day
- SQL Server can estimate a query's cost *before* running it, via `SET SHOWPLAN_XML` — refuse anything over a threshold using that estimate alone, and the refusal itself costs milliseconds regardless of how expensive the query would have been
- Intuition about what's expensive and what a cost-based optimizer actually finds expensive can point in different directions — my own assumption about which demo query would be the worst offender was wrong, and the real data is more useful than the guess would have been
- The right cost threshold isn't a number to copy from someone else's project — SQL Server's cost units are relative to the optimizer's internal accounting, not wall-clock time or dollars, and have to be calibrated against real data volume

## What was actually built

The core of it: get the estimated plan without running the query, read its cost, decide.

```python
def _estimate_cost(self, sql: str) -> float:
    with self.engine.connect() as conn:
        conn.execute(text("SET SHOWPLAN_XML ON"))
        try:
            result = conn.execute(text(sql))
            plan_xml = result.scalar()
        finally:
            conn.execute(text("SET SHOWPLAN_XML OFF"))
    return _parse_estimated_cost(plan_xml)

def run(self, sql: str, agent_id: str, intent: str) -> GovernedQueryResult:
    estimated_cost = self._estimate_cost(sql)

    if estimated_cost > self.max_estimated_cost:
        self._audit(agent_id, intent, sql, estimated_cost, None, None, "BLOCKED_COST")
        raise CostGovernorBlocked(
            f"Refused: estimated cost {estimated_cost:.2f} exceeds "
            f"{self.max_estimated_cost:.2f}. The query was never executed."
        )

    # only reached if the estimate was within budget
    start = time.perf_counter()
    with self.engine.connect() as conn:
        result = conn.execute(text(sql))
        rows = result.fetchall()
    elapsed_ms = (time.perf_counter() - start) * 1000
    ...
```

`SET SHOWPLAN_XML ON` is the mechanism worth calling out specifically: subsequent statements on that connection return their estimated execution plan instead of executing. A blocked query here never touches a single row — a meaningfully different guarantee than the guardrail project earlier in this series, which runs a write inside a transaction and rolls back after measuring the actual row count. That approach already pays the execution cost for anything it later decides to refuse. This one never spends it.

## Seeing the actual numbers, including the one I got wrong

Four scenarios against a 100,000-row orders table: a cheap indexed lookup, a query whose WHERE clause defeats the only relevant index, a cross join missing its join condition entirely, and a legitimate full-table aggregate.

```
=== SCENARIO C: a join missing its condition -- a cartesian product ===
[analytics-agent] intent: Join accounts to their orders for a summary
          sql:    SELECT a.owner_name, o.amount FROM dbo.demo_accounts a CROSS JOIN dbo.demo_orders o
          -> BLOCKED: Refused: agent 'analytics-agent' submitted a query with estimated
             cost 2.26, exceeding the 1.50 threshold. The query was never executed --
             only its estimated plan was.
          (checked and refused in 11.4ms -- the query itself never ran)
```

That query, run in an earlier uncalibrated pass before I fixed the threshold, actually took 1,584 milliseconds and returned 400,000 rows. The governor refused it in 11.4 milliseconds. That comparison is most of the pitch by itself.

Here's the part I got wrong going in: I built this demo expecting the non-sargable `WHERE YEAR(order_date) = 2026` query — the one deliberately designed to defeat the only index on that column — to be the standout expensive scenario. It wasn't. At 100,000 rows, a full table scan on narrow columns costs almost exactly the same, by SQL Server's own accounting, as an index seek returning a similar row count (0.52 vs. 0.51 estimated cost). The actual outlier was the missing join condition, by a wide margin. My first threshold guess of 5.0 was wrong for a related reason — every single scenario passed under it, including the 400,000-row cartesian join, because SQL Server's cost units are much smaller in absolute terms at this data volume than I'd assumed. I recalibrated to 1.5 based on the real observed numbers, not a second guess.

Worth stating plainly: don't assume which query pattern is "the expensive one" without measuring it against real data. That's the actual argument for building a cost governor around the optimizer's own estimate instead of a simpler rule like "flag any WHERE clause without a matching index" — the cost-based optimizer's model of what's expensive is a better judge of that than intuition is, mine included.

## What this doesn't solve

SQL Server's estimated cost is relative, not literal — it's not wall-clock time or dollars, and the right threshold is specific to your schema, data volume, and hardware. Copying the `1.5` used in this demo directly into a production deployment without calibrating against real traffic would be a mistake of exactly the kind I made on the first attempt here. This also only measures magnitude, not intent — it can't distinguish a legitimately expensive month-end report from a malicious one, and it doesn't estimate cost for DDL statements at all (those are still the sibling guardrail and approval-queue projects' job).

Across all five projects now: the firewall refuses what should never run. The approval queue routes schema changes to a human. Row-level security scopes what an agent can reach by identity. The credential auditor checks whether that identity still deserves trust. This refuses what would cost too much, regardless of whether every other check already passed. An AI agent with real database access needs checks at all five layers, because a query can clear four of them and still be the one that matters.

The full project — the `SHOWPLAN_XML`-based estimator, the calibration numbers, and all four scenarios runnable via Docker Compose against a real SQL Server 2025 instance — is open source: [github.com/mrivanlima/ai-agent-query-cost-governor](https://github.com/mrivanlima/ai-agent-query-cost-governor){:target="_blank" rel="noopener noreferrer"}. If your agents can already run arbitrary queries and nothing is checking their cost before they run, that's worth measuring before the bill does it for you. [Get in touch](/about/#contact) if you want help calibrating this against your own environment.

*Ivan Lima is a data engineer specializing in database modernization for AI systems. [Get in touch](/about/#contact) if your database needs to be ready for what's next.*
