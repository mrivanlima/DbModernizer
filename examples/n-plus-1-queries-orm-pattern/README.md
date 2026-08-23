# N+1 Queries: Catching the ORM Pattern That's Quietly Killing Your Database

Companion code for the DbModernizer blog post ["N+1 Queries: Catching the ORM Pattern That's Quietly Killing Your Database"](https://dataplatformadvisory.com/blog/2026/08/23/n-plus-1-queries-orm-pattern/).

This example reproduces the classic N+1 query pattern that ORM lazy loading
generates: one query to fetch a list of parent rows (authors), then one
additional query per row to fetch each parent's children (posts) — 501
statements instead of 1 for a 500-row list.

## What this demonstrates

1. **The problem** — a simulated ORM lazy-load loop issuing one cheap query
   per author, confirmed objectively via `sys.dm_exec_query_stats` (a very
   high `execution_count` on near-identical, cheap, parameterized query
   text — the N+1 fingerprint that "slow query" alerting misses entirely).
2. **The expert fix** — a single set-based `JOIN` query that collapses 501
   round trips into 1, with before/after evidence (statement count, logical
   reads, elapsed time) and a note on what eager-loading APIs to reach for
   in real ORMs (`.Include()` in EF Core, `joinedload()` in SQLAlchemy,
   `JOIN FETCH` in JPA/Hibernate).
3. **The AI-automation angle** — a scheduled, read-only watcher that scans
   the plan cache for the N+1 fingerprint and logs scored candidates to a
   review queue. It never rewrites application code or ORM mappings; a
   developer explicitly reviews and approves each candidate before anyone
   touches the eager-loading configuration.

## Prerequisites

- SQL Server 2019+ (Developer or Standard edition) or Azure SQL Database
- SQL Server Management Studio (SSMS) or `sqlcmd` to run the `.sql` files
- A scratch/test instance — **do not run this against production**; it
  creates an `NPlus1Demo` database and seeds sample data
- Optional, for the scheduling wrapper: PowerShell with the `SqlServer`
  module (`Install-Module SqlServer`) if you want to run `run_watcher.ps1`
  under SQL Agent or Task Scheduler

## Files

| File | Purpose |
|---|---|
| `01_seed_schema.sql` | Creates `NPlus1Demo`, the `Authors`/`Posts` tables, and seeds 500 authors with ~5,000 posts |
| `02_reproduce_and_fix.sql` | Simulates the ORM's N+1 round trips, confirms the fingerprint via `sys.dm_exec_query_stats`, then fixes it with a single `JOIN` query and shows before/after evidence |
| `03_ai_n_plus_1_watcher.sql` | Read-only scheduled query that scores N+1 candidates from the plan cache and logs them to `dbo.NPlus1CandidateLog` for human review |
| `run_watcher.ps1` | Optional PowerShell wrapper to run the watcher on a schedule (SQL Agent / Task Scheduler) and surface results to a log file |

## Steps to reproduce

1. Open SSMS (or `sqlcmd`) and connect to a scratch SQL Server instance.
2. Run `01_seed_schema.sql` to create and seed `NPlus1Demo`.
3. Run `02_reproduce_and_fix.sql` top to bottom, one batch at a time. Read
   the `Messages` tab after each `STATISTICS IO/TIME` block to see the
   round-trip cost of the per-author queries versus the single joined query.
4. Run the `sys.dm_exec_query_stats` query in step 2 of that same file to
   see the N+1 fingerprint: a high `execution_count` on cheap, near-identical
   statement text.
5. Optionally, run `03_ai_n_plus_1_watcher.sql` to see the review-queue
   pattern in action against the plan cache entries left behind by step 3.
6. Clean up when done: `DROP DATABASE NPlus1Demo;`

## Notes

- Execution counts, logical reads, and timings will vary by hardware, SQL
  Server version, and buffer cache state — the pattern to look for (many
  cheap, near-identical statements collapsing into one set-based query)
  matters more than hitting an exact number.
- The watcher's heuristic (`execution_count > 100`, no `JOIN`, low average
  logical reads per call) is a starting point, not a universal threshold —
  tune it to your workload's normal call volume before relying on it.
- This pattern isn't SQL Server- or ORM-specific: the same fix (batch the
  "many" side into one query, keyed off the "one" side's IDs) applies
  whether the driver is Entity Framework, Hibernate, SQLAlchemy, or hand-
  rolled data access code.
