# Parameter Sniffing: Why It's Fast for One User and Slow for Everyone Else

Companion code for the DbModernizer blog post ["Parameter Sniffing: Why It's Fast for One User and Slow for Everyone Else"](https://dataplatformadvisory.com/blog/2026/08/17/parameter-sniffing-fast-for-one-slow-for-everyone/).

This example reproduces a textbook parameter-sniffing bug: a stored
procedure filters a heavily skewed column (`OrderStatus`, ~96% one value),
gets its first cached plan compiled for a rare parameter value, and then
serves every other caller a plan shaped for the wrong row count.

## What this demonstrates

1. **The problem** -- `dbo.GetOrdersByStatus` compiles a seek-plus-lookup
   plan optimized for the rare `'Pending'` status, then reuses that same
   cached plan for `'Completed'` (96% of the table), turning a plan that
   should scan into one that performs a key lookup per row.
2. **The expert fix** -- diagnosing it via `sys.dm_exec_procedure_stats`,
   the cached plan's estimated-vs-actual row counts, and confirming
   statistics aren't stale before blaming sniffing. Then three fix options
   in order of preference: `OPTIMIZE FOR` a representative value,
   `OPTION (RECOMPILE)`, or splitting the rare/critical value into its own
   branch.
3. **The AI-automation angle** -- a scheduled, read-only Query Store
   watcher that scores procedures by how much their duration varies across
   executions of the same cached plan, and produces a ranked report for a
   human to act on. It never applies a hint, forces a plan, or edits a
   procedure itself.

## Prerequisites

- SQL Server 2016+ (Developer or Standard edition) or Azure SQL Database
- SQL Server Management Studio (SSMS) or `sqlcmd`
- A scratch/test instance -- **do not run this against production**; it
  creates a `ParamSniffDemo` database and seeds ~500,000 rows
- Query Store enabled for Part 3 (on by default for new databases in
  compatibility level 130+; the seed script sets compatibility level 150)
- Optional, for the scheduling wrapper: PowerShell with the `SqlServer`
  module (`Install-Module SqlServer`) if you want to run
  `run_plan_variance_watcher.ps1` under SQL Agent or Task Scheduler

## Files

| File | Purpose |
|---|---|
| `01_seed_schema.sql` | Creates `ParamSniffDemo`, the skewed `Orders` table, and the naive `dbo.GetOrdersByStatus` procedure |
| `02_reproduce_and_fix.sql` | Part A: reproduces the sniffed plan. Part B: diagnoses it with the plan cache and actual-vs-estimated rows. Part C: three fix options, cheapest/safest first |
| `03_ai_plan_variance_watcher.sql` | Read-only Query Store query that scores procedures by execution-duration variance and logs candidates to `dbo.PlanVarianceLog` |
| `run_plan_variance_watcher.ps1` | Optional PowerShell wrapper to run the watcher on a schedule and surface flagged procedures |

## Steps to reproduce

1. Open SSMS (or `sqlcmd`) and connect to a scratch SQL Server instance.
2. Run `01_seed_schema.sql`. Seeding 500,000 rows in batches takes a
   couple of minutes.
3. Run Part A of `02_reproduce_and_fix.sql`: it frees the plan cache for a
   clean repro, calls the procedure with `'Pending'` first, then calls it
   with `'Completed'`. Watch the `STATISTICS IO` output on the second
   call -- expect a very high logical read count relative to the table's
   actual page count.
4. Run Part B to pull the cached plan's stats from
   `sys.dm_exec_procedure_stats`, then re-run with **Include Actual
   Execution Plan** on in SSMS and compare Estimated vs. Actual rows on
   the Index Seek / Key Lookup operators. A gap of two-plus orders of
   magnitude is the signature of sniffing, not a missing index.
5. Run Part C to apply Option 1 (`OPTIMIZE FOR`), test, then try Option 2
   (`OPTION (RECOMPILE)`) and Option 3 (branch on the skewed value) the
   same way -- each `ALTER PROCEDURE` overwrites the previous version so
   you can compare all three independently.
6. Re-run the free-cache-then-call-both-statuses sequence at the bottom of
   Part C and confirm `'Completed'` now gets a plan shaped for its own row
   count.
7. Optionally, run `03_ai_plan_variance_watcher.sql` (after generating
   some mixed traffic against the procedure so Query Store has runtime
   stats to score) to see the variance-scoring watcher produce its ranked
   report.
8. Clean up when done: `DROP DATABASE ParamSniffDemo;`

## Notes

- The exact variance ratio and read counts will shift run to run depending
  on hardware and buffer pool state -- the point is the *pattern* (huge
  swing in cost for the same cached plan), not a specific number.
- `OPTIMIZE FOR` and branching both require knowing your data's skew in
  advance; `OPTION (RECOMPILE)` needs no such knowledge but costs CPU on
  every call, so it's the right trade for low-frequency procs and the
  wrong one for something called thousands of times a second.
- Query Store's `sp_query_store_force_plan` is another lever worth knowing
  about once you've identified a specific known-good plan_id, but it's a
  more surgical, harder-to-maintain fix than any of the three in this repo
  and is best reserved for cases where the other three don't fit.
