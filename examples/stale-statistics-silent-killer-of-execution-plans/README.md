# Stale Statistics: The Silent Killer of Good Execution Plans

Companion code for the DbModernizer blog post ["Stale Statistics: The Silent Killer of Good Execution Plans"](https://dataplatformadvisory.com/blog/2026/08/21/stale-statistics-silent-killer-of-execution-plans/).

This example reproduces the "ascending key" flavor of stale statistics --
the one that doesn't show up as a fragmentation alarm or a maintenance-job
failure, because nothing is broken. A steadily-growing `OrderDate` column
gets nightly inserts that never come close to the row-modification
threshold SQL Server uses to trigger an automatic statistics update on a
large table, so the histogram quietly stops reflecting reality. A query
filtering on recent dates gets a cardinality estimate of about 1 row when
the real answer is 20,000, and the optimizer picks a plan sized for the
wrong number.

## What this demonstrates

1. **The problem** -- an 8-million-row `Orders` table where three weeks
   of realistic nightly ETL batches land past the edge of the last
   full-scan statistics update, without ever triggering an automatic
   refresh, verified with `sys.dm_db_stats_properties` and a query whose
   estimated-vs-actual row counts are off by four orders of magnitude.
2. **The expert fix** -- a targeted `UPDATE STATISTICS ... WITH FULLSCAN`
   on the affected index, with before/after evidence from
   `sys.dm_db_stats_properties` and `SET STATISTICS IO, TIME`.
3. **The AI-automation angle** -- a scheduled, read-only watcher that
   scores every statistic on the instance by both staleness (days since
   last update) and drift (modifications as a percentage of the row
   count at last update), logging candidates to a review table. It never
   runs `UPDATE STATISTICS` itself; a human reviews the report and
   decides what to run and when.

## Prerequisites

- SQL Server 2019+ (Developer, Standard, or Enterprise edition) or Azure
  SQL Database
- A scratch/test instance -- this script creates its own `StaleStatsDemo`
  database and drops/recreates `dbo.Orders` if it already exists
- A few minutes of runtime and roughly 1-2 GB of free space for the seed
  data (~8 million base rows plus ~420,000 "nightly ETL" rows)

## How to run

1. **Seed the problem**

   ```
   sqlcmd -S <your-instance> -i 01_seed_schema.sql
   ```

   This creates `StaleStatsDemo`, builds `dbo.Orders` with a nonclustered
   index on `OrderDate`, loads ~8,000,000 rows of history dated over the
   prior 3 years, runs a `FULLSCAN` statistics update to establish a
   realistic "healthy" histogram baseline, then loads 21 more batches of
   20,000 rows each dated into the days immediately after that baseline
   -- simulating three weeks of nightly ETL that never trigger an
   auto-update on a table this size.

2. **Reproduce and fix the problem**

   ```
   sqlcmd -S <your-instance> -i 02_diagnose_and_fix.sql
   ```

   Run this in SSMS with "Include Actual Execution Plan" on (Ctrl+M) to
   see the estimated-vs-actual row count mismatch directly. The script
   checks `sys.dm_db_stats_properties`, runs the affected query once
   against the stale histogram, updates statistics with `FULLSCAN`, then
   re-runs the same query so you can compare plans and I/O directly.

3. **Run the AI-automation watcher**

   ```
   sqlcmd -S <your-instance> -i 03_ai_stats_drift_watcher.sql
   ```

   Creates `dbo.StatsDriftLog` if it doesn't exist, scores every
   statistic in the database, and returns only the rows worth a look
   (`UPDATE_NOW` or `REVIEW`). Schedule this daily (see
   `run_watcher.ps1`) against each database that matters -- it only
   reads and logs, it never modifies statistics on its own.

## Files

- `01_seed_schema.sql` -- builds the demo database and reproduces the
  ascending-key drift scenario
- `02_diagnose_and_fix.sql` -- diagnoses the bad cardinality estimate and
  applies the fix, with before/after evidence
- `03_ai_stats_drift_watcher.sql` -- the read-only scheduled watcher and
  its log table
- `run_watcher.ps1` -- a minimal wrapper for running the watcher on a
  schedule (Windows Task Scheduler or SQL Agent CmdExec step)
