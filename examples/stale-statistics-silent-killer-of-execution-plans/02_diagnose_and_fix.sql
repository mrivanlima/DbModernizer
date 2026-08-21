/*
    02_diagnose_and_fix.sql

    Diagnoses and fixes the stale-statistics problem seeded by
    01_seed_schema.sql: a query filtering on recent OrderDate values gets
    a bad cardinality estimate because those dates fall past the edge of
    the last full-scan histogram, and the optimizer assumes almost no
    rows match.
*/

USE StaleStatsDemo;
GO

-- Step 1: Confirm the histogram is stale relative to the actual data.
-- last_updated should be days/weeks behind the max OrderDate in the
-- table, and modification_counter will look small *relative to table
-- size* even though it's tens of thousands of real rows.
SELECT
    sp.last_updated,
    sp.rows                AS rows_at_last_stats_update,
    sp.modification_counter,
    (SELECT COUNT(*) FROM dbo.Orders)    AS current_row_count,
    (SELECT MAX(OrderDate) FROM dbo.Orders) AS current_max_orderdate
FROM sys.dm_db_stats_properties(OBJECT_ID('dbo.Orders'), 2) sp; -- stats_id 2 = IX_Orders_OrderDate
GO

-- Step 2: Reproduce the bad plan. Filtering on a date range entirely
-- past the histogram's last recorded step gets estimated at roughly 1
-- row (the "unknown region beyond the histogram" guess), even though
-- tens of thousands of rows actually match.
SET STATISTICS IO, TIME ON;

SELECT OrderId, CustomerId, OrderTotal
FROM dbo.Orders
WHERE OrderDate >= '2026-09-05'
  AND OrderDate <  '2026-09-06';

SET STATISTICS IO, TIME OFF;
GO
-- Check the actual execution plan (Ctrl+M in SSMS before running, or
-- pull the XML from sys.dm_exec_query_stats): the estimated number of
-- rows on the index seek will be ~1, actual will be ~20,000. That
-- mismatch drives the optimizer to a Key Lookup / Nested Loop plan sized
-- for a handful of rows -- fine at 1 row, expensive at 20,000, because
-- the Key Lookup runs once per row instead of the table just being
-- scanned or hash-joined once.

-- Step 3: Fix it -- update statistics on the specific index with a full
-- scan. On a table this size, a full scan is worth the one-time cost for
-- an ascending-key column that clearly needs it; a sampled update can
-- miss the same edge-of-histogram problem if the sample doesn't happen
-- to land on recent rows.
UPDATE STATISTICS dbo.Orders IX_Orders_OrderDate WITH FULLSCAN;
GO

-- Step 4: Re-run the same query and compare. Estimated rows on the seek
-- should now be close to the ~20,000 actual, and the plan should shift
-- to whatever access pattern actually fits that row count (frequently a
-- straight index seek + range scan rather than a per-row Key Lookup).
SET STATISTICS IO, TIME ON;

SELECT OrderId, CustomerId, OrderTotal
FROM dbo.Orders
WHERE OrderDate >= '2026-09-05'
  AND OrderDate <  '2026-09-06';

SET STATISTICS IO, TIME OFF;
GO

-- Step 5: Confirm the histogram now reflects current data.
SELECT
    sp.last_updated,
    sp.rows                AS rows_at_last_stats_update,
    sp.modification_counter
FROM sys.dm_db_stats_properties(OBJECT_ID('dbo.Orders'), 2) sp;
GO
