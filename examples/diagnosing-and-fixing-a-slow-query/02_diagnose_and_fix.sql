/*
  02_diagnose_and_fix.sql
  Companion script to "Diagnosing and Fixing a Slow Query, Step by Step."

  Walks through: reproduce the slow query -> read the execution plan signal ->
  check the missing-index DMVs (with a skeptical eye) -> apply a targeted fix ->
  prove it worked with before/after evidence.

  Run 01_seed_schema.sql first.
*/

USE SlowQueryDemo;
GO

-- =====================================================================
-- STEP 1: Reproduce the problem
-- This is the query a support dashboard runs every few seconds:
-- "show me all pending orders, newest first."
-- =====================================================================
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

SELECT
    o.OrderId,
    o.CustomerId,
    c.CustomerName,
    o.OrderTotal,
    o.OrderDate
FROM dbo.Orders o
JOIN dbo.Customers c ON c.CustomerId = o.CustomerId
WHERE o.OrderStatus = 'Pending'
ORDER BY o.OrderDate DESC;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/*
  What you'll see in STATISTICS IO on an ungoverned ~2M row Orders table:

    Table 'Orders'. Scan count 1, logical reads ~9,000+ (a full clustered
    index scan -- every page of the table, to find the ~0.2% of rows that
    match).
    Table 'Worktable'. Scan count 1, logical reads in the thousands
    (the sort for ORDER BY OrderDate DESC has no supporting index either).

  In the graphical execution plan (Ctrl+M in SSMS before running), the two
  signals to look for:
    1. A "Clustered Index Scan" on Orders with a high "Actual Number of
       Rows Read" relative to "Actual Number of Rows" -- SQL Server is
       reading millions of rows to return a few thousand.
    2. A yellow bang / missing index hint at the top of the plan window.
       Right-click it -> "Missing Index Details" to get the suggested
       CREATE INDEX statement.
*/


-- =====================================================================
-- STEP 2: Check the missing-index DMVs -- with a skeptical eye
-- Don't blindly apply what these suggest. They report an *estimated*
-- cost reduction percentage, and that number does not map 1:1 to real
-- execution time saved. Use them as a lead, not a verdict, and always
-- check for existing/near-duplicate indexes first.
-- =====================================================================
SELECT
    mid.statement                                  AS table_name,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns,
    migs.avg_total_user_cost,
    migs.avg_user_impact,          -- estimated % cost reduction; treat as a lead, not a verdict
    migs.user_seeks + migs.user_scans AS times_this_shape_was_needed
FROM sys.dm_db_missing_index_details mid
JOIN sys.dm_db_missing_index_groups mig  ON mig.index_handle = mid.index_handle
JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
WHERE mid.statement LIKE '%Orders%'
ORDER BY migs.avg_user_impact DESC;
GO

-- Also check what already exists, so you don't create a near-duplicate index:
SELECT
    i.name AS index_name,
    i.type_desc,
    STUFF((SELECT ',' + c.name
           FROM sys.index_columns ic
           JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
           WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0
           ORDER BY ic.key_ordinal
           FOR XML PATH('')), 1, 1, '') AS key_columns
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID('dbo.Orders') AND i.type > 0;
GO


-- =====================================================================
-- STEP 3: Apply the targeted fix
-- A filtered, covering nonclustered index: narrow on the predicate
-- (OrderStatus = 'Pending'), sorted the way the dashboard needs
-- (OrderDate DESC), and covering the columns the query actually selects
-- so there's no key lookup back to the clustered index.
--
-- Filtered index note: this only helps if the predicate literal
-- ('Pending') stays stable. If the dashboard later filters on other
-- statuses too, drop the filter and index OrderStatus normally instead.
-- =====================================================================
CREATE NONCLUSTERED INDEX IX_Orders_Pending_ByDate
ON dbo.Orders (OrderStatus, OrderDate DESC)
INCLUDE (CustomerId, OrderTotal)
WHERE OrderStatus = 'Pending';
GO


-- =====================================================================
-- STEP 4: Prove it worked -- before/after evidence
-- =====================================================================
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

SELECT
    o.OrderId,
    o.CustomerId,
    c.CustomerName,
    o.OrderTotal,
    o.OrderDate
FROM dbo.Orders o
JOIN dbo.Customers c ON c.CustomerId = o.CustomerId
WHERE o.OrderStatus = 'Pending'
ORDER BY o.OrderDate DESC;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/*
  Expected shift after the index:
    Table 'Orders'. Scan count 1, logical reads typically drop from
    ~9,000+ to well under 50 -- an Index Seek on IX_Orders_Pending_ByDate
    instead of a Clustered Index Scan, and no separate sort operator
    because OrderDate DESC is already the index order.

  Exact numbers vary by hardware/SQL Server version/buffer cache state --
  what to look for is the operator changing from Scan to Seek and logical
  reads dropping by roughly two orders of magnitude, not a specific
  millisecond target.
*/
GO
