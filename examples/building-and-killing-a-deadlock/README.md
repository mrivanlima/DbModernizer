# Building and Killing a Deadlock With Your Own Hands

Companion code for the DbModernizer blog post ["Building and Killing a Deadlock With Your Own Hands"](https://dataplatformadvisory.com/blog/2026/08/15/building-and-killing-a-deadlock/).

This example reproduces a textbook write-write deadlock: two concurrent
fund transfers between the same two accounts, moving money in opposite
directions. Each session locks one account, then blocks waiting for the
other -- a lock cycle SQL Server has no choice but to break by killing one
of them.

## What this demonstrates

1. **The problem** -- two sessions calling `dbo.TransferFunds` with the
   same two accounts but opposite `@FromAccountId`/`@ToAccountId`, deadlocking
   on the `Accounts` clustered index and producing error 1205.
2. **The expert fix** -- reading the deadlock graph SQL Server already
   captured via the `system_health` Extended Events session, then a
   consistent-access-order wrapper (`dbo.TransferFundsSafe`) that always
   locks the lower `AccountId` first regardless of transfer direction,
   which makes the cycle structurally impossible.
3. **The AI-automation angle** -- a scheduled, read-only watcher that
   parses deadlock graphs out of `system_health`, logs which object pairs
   were involved, and flags object pairs that deadlock repeatedly as a
   scored candidate for a human to fix in code. It never edits a stored
   procedure or reorders anything itself.

## Prerequisites

- SQL Server 2019+ (Developer or Standard edition) or Azure SQL Database
- SQL Server Management Studio (SSMS), with **two** query windows (or two
  `sqlcmd` sessions) open against the same instance, to reproduce Part A
- A scratch/test instance -- **do not run this against production**; it
  creates a `DeadlockDemo` database
- Optional, for the scheduling wrapper: PowerShell with the `SqlServer`
  module (`Install-Module SqlServer`) if you want to run `run_watcher.ps1`
  under SQL Agent or Task Scheduler

## Files

| File | Purpose |
|---|---|
| `01_seed_schema.sql` | Creates `DeadlockDemo`, the `Accounts` table, and the deliberately naive `dbo.TransferFunds` procedure |
| `02_reproduce_and_fix.sql` | Part A: two-session repro script that triggers the deadlock. Part B: query to pull the deadlock graph out of `system_health`. Part C: the `dbo.TransferFundsSafe` fix and a re-test |
| `03_ai_deadlock_watcher.sql` | Read-only scheduled query that parses deadlock graphs, logs object pairs to `dbo.DeadlockLog`, and scores recurring patterns for human review |
| `run_watcher.ps1` | Optional PowerShell wrapper to run the watcher on a schedule and surface flagged patterns to alerting |

## Steps to reproduce

1. Open SSMS and connect to a scratch SQL Server instance.
2. Run `01_seed_schema.sql`. This is fast -- four rows.
3. Open **two** query windows against `DeadlockDemo` (Session 1 and
   Session 2 in the comments of `02_reproduce_and_fix.sql`).
4. Follow Part A's comments exactly: run the Session 1 `EXEC` first (it
   has an 8-second `WAITFOR`), then within that window switch to Session
   2 and run its `EXEC`. One of the two windows will return error 1205
   within a few seconds; the other will complete normally.
5. Run Part B's query (same or a third window) to pull the deadlock graph
   that `system_health` already captured. Click the XML result to view it;
   save as `.xdl` and reopen in SSMS for the graphical version.
6. Run Part C to create `dbo.TransferFundsSafe`, then repeat step 4 but
   call `TransferFundsSafe` instead of `TransferFunds` in both sessions.
   Session 2 now simply waits for Session 1 instead of deadlocking --
   both transfers commit, confirmed by the final `SELECT` against
   `dbo.Accounts`.
7. Optionally, run `03_ai_deadlock_watcher.sql` to see the pattern-logging
   watcher. On a real instance with deadlock history, this surfaces
   recurring object pairs the same way -- as a scored report, not an
   automatic code change.
8. Clean up when done: `DROP DATABASE DeadlockDemo;`

## Notes

- The deadlock monitor's exact timing (default check interval, backing off
  under contention) can shift which session ends up as victim from run to
  run -- the point of the exercise is the *pattern* (a lock cycle across
  two sessions), not which specific session loses.
- `dbo.TransferFundsSafe`'s "touch the lower AccountId first" pattern
  generalizes to any multi-row write: sort the rows you're about to touch
  by a stable key before you start writing, in every code path that
  writes to that table.
- The deadlock priority of a session can also be set explicitly with
  `SET DEADLOCK_PRIORITY` if one transaction should never be the victim --
  useful as a stopgap, but it doesn't remove the underlying cycle the way
  consistent ordering does.
