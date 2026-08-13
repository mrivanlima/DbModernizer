# Diagnosing and Fixing a Slow Query, Step by Step

Companion code for the DbModernizer blog post ["Diagnosing and Fixing a Slow Query, Step by Step"](https://dataplatformadvisory.com/blog/2026/08/13/diagnosing-and-fixing-a-slow-query/).

This example reproduces a very common real-world pattern: a support dashboard
repeatedly queries a large `Orders` table for the small slice of rows in
`'Pending'` status, ordered by date. With no supporting index, SQL Server has
to scan the whole table to find a tiny fraction of matching rows.

## What this demonstrates

1. **The problem** — a full clustered index scan on a ~2 million row table to
   satisfy a query that only needs ~0.2% of the rows, verified with
   `SET STATISTICS IO/TIME` and the graphical execution plan.
2. **The expert fix** — a filtered, covering nonclustered index, plus a
   skeptical read of the missing-index DMVs (they're a lead, not a verdict)
   and a check for existing indexes before adding a new one.
3. **The AI-automation angle** — a scheduled, read-only watcher that scores
   missing-index candidates across the whole instance and logs them to a
   review queue. It never creates an index by itself; a human explicitly
   approves each candidate before it's applied.

## Prerequisites

- SQL Server 2019+ (Developer or Standard edition) or Azure SQL Database
- SQL Server Management Studio (SSMS) or `sqlcmd` to run the `.sql` files
- A scratch/test instance — **do not run this against production**; it
  creates a `SlowQueryDemo` database and seeds ~2 million rows
- Optional, for the scheduling wrapper: PowerShell with the `SqlServer`
  module (`Install-Module SqlServer`) if you want to run `run_watcher.ps1`
  under SQL Agent or Task Scheduler

## Files

| File | Purpose |
|---|---|
| `01_seed_schema.sql` | Creates `SlowQueryDemo`, the `Customers`/`Orders` tables, and seeds ~2M skewed rows (no index on the hot predicate) |
| `02_diagnose_and_fix.sql` | Reproduces the slow query, checks `STATISTICS IO/TIME`, reads the missing-index DMVs, applies the fix, and shows before/after evidence |
| `03_ai_missing_index_watcher.sql` | Read-only scheduled query that scores missing-index candidates instance-wide and logs them to `dbo.IndexCandidateLog` for human review |
| `run_watcher.ps1` | Optional PowerShell wrapper to run the watcher on a schedule (SQL Agent / Task Scheduler) and surface results to logging/alerting |

## Steps to reproduce

1. Open SSMS (or `sqlcmd`) and connect to a scratch SQL Server instance.
2. Run `01_seed_schema.sql`. This takes a few minutes — it's inserting ~2
   million rows.
3. Run `02_diagnose_and_fix.sql` top to bottom, one batch at a time. Read
   the `Messages` tab after each `STATISTICS IO/TIME` block, and turn on
   "Include Actual Execution Plan" (Ctrl+M) before running the first
   `SELECT` to see the Clustered Index Scan and missing-index hint.
4. Compare the `Messages` output and execution plan from before the
   `CREATE INDEX` step against after — logical reads should drop by roughly
   two orders of magnitude, and the plan operator should change from Scan
   to Seek.
5. Optionally, run `03_ai_missing_index_watcher.sql` to see the review-queue
   pattern. On a real instance with query history, this surfaces other
   missing-index candidates the same way — as a report, not an automatic
   action.
6. Clean up when done: `DROP DATABASE SlowQueryDemo;`

## Notes

- Row counts, logical reads, and timings will vary by hardware, SQL Server
  version, and buffer cache state — the pattern to look for (Scan → Seek,
  reads dropping by ~2 orders of magnitude) matters more than hitting an
  exact number.
- The filtered index in step 3 (`WHERE OrderStatus = 'Pending'`) only pays
  off if that predicate stays stable. If the dashboard later filters on
  multiple statuses, drop the filter and index `OrderStatus` normally.
