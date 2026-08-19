# Index Bloat and Fragmentation: When to Rebuild, When to Ignore It

Companion code for the DbModernizer blog post ["Index Bloat and Fragmentation: When to Rebuild, When to Ignore It"](https://dataplatformadvisory.com/blog/2026/08/19/index-bloat-and-fragmentation/).

This example reproduces realistic index fragmentation the way it actually
happens in production -- not from inserts, but from repeated UPDATEs on an
indexed status column as orders move through a small set of states
(`Pending` -> `Shipped` -> `Delivered`). It then shows how to read
fragmentation correctly (two DMV columns, not one), decide REBUILD vs.
REORGANIZE with storage-appropriate thresholds, and apply the fix online.

## What this demonstrates

1. **The problem** -- an `Orders` table whose nonclustered status index
   fragments from status-value churn, verified with two different
   `sys.dm_db_index_physical_stats` columns (`avg_fragmentation_in_percent`
   for logical fragmentation, `avg_page_space_used_in_percent` for page
   density) rather than the one column most maintenance scripts check.
2. **The expert fix** -- an online `ALTER INDEX ... REBUILD` with a
   deliberate fill factor, using storage-aware thresholds instead of the
   stale 5%/30% defaults, plus before/after evidence from
   `STATISTICS IO/TIME`.
3. **The AI-automation angle** -- a scheduled, read-only watcher that scores
   every index on the instance against both fragmentation signals and logs
   candidates to a review table. It never issues `ALTER INDEX` itself; a
   human reviews the daily report and decides what to run.

## Prerequisites

- SQL Server 2019+ (Developer, Standard, or Enterprise edition) or Azure SQL
  Database. `ONLINE = ON` index rebuilds require Enterprise Edition or
  Azure SQL Database -- on Standard Edition, drop that option (the rebuild
  will briefly block, which is fine on a scratch instance).
- SQL Server Management Studio (SSMS) or `sqlcmd` to run the `.sql` files
- A scratch/test instance -- **do not run this against production**; it
  creates a `FragDemo` database and seeds ~1.5 million rows, then churns
  updates across it
- Optional, for the scheduling wrapper: PowerShell with the `SqlServer`
  module (`Install-Module SqlServer`) if you want to run `run_watcher.ps1`
  under SQL Agent or Task Scheduler

## Files

| File | Purpose |
|---|---|
| `01_seed_schema.sql` | Creates `FragDemo`, the `Orders` table, and simulates realistic status churn (UPDATEs, not inserts) to build up fragmentation |
| `02_diagnose_and_fix.sql` | Reads fragmentation correctly (both DMV columns), reproduces the read-cost with `STATISTICS IO/TIME`, rebuilds the index online with a sane fill factor, and confirms it helped |
| `03_ai_fragmentation_watcher.sql` | Read-only scheduled query that scores every index on the instance using storage-aware thresholds and logs candidates to `dbo.IndexFragmentationLog` for human review |
| `run_watcher.ps1` | Optional PowerShell wrapper to run the watcher on a schedule (SQL Agent / Task Scheduler) and surface flagged indexes to logging/alerting |

## Steps to reproduce

1. Open SSMS (or `sqlcmd`) and connect to a scratch SQL Server instance.
2. Run `01_seed_schema.sql`. This takes a few minutes -- it's inserting
   ~1.5 million rows and then running several large UPDATE batches to churn
   the status column.
3. Note the fragmentation numbers the seed script prints at the end --
   `IX_Orders_OrderStatus` should show meaningfully higher
   `avg_fragmentation_in_percent` and lower `avg_page_space_used_in_percent`
   than the clustered index on `OrderId`, which barely fragments because it
   only ever grows at the end.
4. Run `02_diagnose_and_fix.sql` top to bottom, one batch at a time. Read
   the `Messages` tab after each `STATISTICS IO/TIME` block.
5. Compare the fragmentation and logical-reads numbers from before the
   `ALTER INDEX ... REBUILD` against after -- logical fragmentation should
   drop close to 0, page density should land near the fill factor (90%),
   and logical reads for the sample query should drop.
6. Optionally, run `03_ai_fragmentation_watcher.sql` to see the review-queue
   pattern. On a real instance it surfaces every index above the size and
   fragmentation thresholds instance-wide, as a report -- not an automatic
   action.
7. Clean up when done: `DROP DATABASE FragDemo;`

## Notes

- Fragmentation percentages and page counts will vary by hardware, SQL
  Server version, and how the `WHILE` loop batches happen to land -- the
  pattern (churn creates fragmentation, both DMV columns move, rebuild
  fixes both) matters more than hitting an exact number.
- The 30%/60% REORGANIZE/REBUILD thresholds in this example assume
  SSD/NVMe-backed storage, which is most cloud-managed SQL Server today.
  If the target instance is still on spinning disks, use the older,
  lower 5%/30% split instead -- the physical cost of out-of-order pages on
  HDD is real in a way it mostly isn't on flash.
- `avg_page_space_used_in_percent` requires `'SAMPLED'` or `'DETAILED'`
  mode (used throughout this example), not `'LIMITED'` -- the default mode
  in many maintenance scripts, which only returns
  `avg_fragmentation_in_percent`. That's a large part of why so many
  environments only ever look at logical fragmentation: it's the free
  column, and the one that costs more to compute is the one that actually
  matters.
