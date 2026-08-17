/*
    02_reproduce_and_fix.sql
    Part A: reproduce the sniffed-plan problem.
    Part B: diagnose it with the plan cache and actual-vs-estimated rows.
    Part C: three fix options, in the order to reach for them.

    Run against ParamSniffDemo (01_seed_schema.sql) on a scratch instance.
*/

USE ParamSniffDemo;
GO

-- ============================================================
-- PART A: Reproduce it
-- ============================================================

-- Clear the plan cache for this proc so the next call compiles fresh.
-- (Never do this on production -- it's only to make the repro deterministic.)
DBCC FREEPROCCACHE;
GO

-- First caller of the day asks for the RARE status. SQL Server compiles
-- a plan optimized for ~500 rows: an index seek + key lookup. Cheap, fast,
-- gets cached under this exact proc/statement.
EXEC dbo.GetOrdersByStatus @Status = 'Pending';
GO

-- Now the next 200 callers ask for the COMMON status. SQL Server does NOT
-- recompile -- it reuses the seek-plus-lookup plan it already has, because
-- the plan is cached per statement, not per parameter value.
SET STATISTICS IO, TIME ON;
EXEC dbo.GetOrdersByStatus @Status = 'Completed';
SET STATISTICS IO, TIME OFF;
GO
-- Expect: hundreds of thousands of key lookups (one RID/key lookup per
-- matching row) instead of a scan, and a runtime that's an order of
-- magnitude worse than a plan compiled fresh for 'Completed' would be.

-- ============================================================
-- PART B: Diagnose it
-- ============================================================

-- Look at the plan actually sitting in cache for this proc, and what
-- parameter it was compiled for.
SELECT
    p.name AS ProcName,
    qs.execution_count,
    qs.total_logical_reads / qs.execution_count AS AvgLogicalReads,
    cp.plan_handle,
    st.text AS SqlText
FROM sys.dm_exec_procedure_stats qs
JOIN sys.procedures p ON p.object_id = qs.object_id
JOIN sys.dm_exec_cached_plans cp ON cp.plan_handle = qs.plan_handle
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE p.name = 'GetOrdersByStatus';

-- Pull the actual execution plan (SSMS: Include Actual Execution Plan, ON)
-- and compare the Estimated vs. Actual number of rows on the Index Seek
-- operator. A huge gap -- estimate ~500, actual ~480,000 -- is the
-- fingerprint of a sniffed plan, not a missing index or stale statistics.
EXEC dbo.GetOrdersByStatus @Status = 'Completed';

-- Confirm it's not stale statistics before blaming sniffing:
DBCC SHOW_STATISTICS ('dbo.Orders', 'IX_Orders_OrderStatus') WITH HISTOGRAM;

-- ============================================================
-- PART C: Fix options, cheapest/safest first
-- ============================================================

-- Option 1: OPTIMIZE FOR a representative "typical" value.
-- Good when one value dominates traffic and you're fine always compiling
-- for that shape. Here 'Completed' is what ~96% of callers actually pass.
ALTER PROCEDURE dbo.GetOrdersByStatus
    @Status VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT OrderId, CustomerId, OrderTotal, OrderDate
    FROM dbo.Orders
    WHERE OrderStatus = @Status
    ORDER BY OrderDate DESC
    OPTION (OPTIMIZE FOR (@Status = 'Completed'));
END
GO

-- Option 2: OPTION (RECOMPILE). Compiles a fresh, parameter-specific plan
-- on every execution -- correct every time, at the cost of CPU on every
-- call. Reach for this when the proc is called infrequently enough that
-- per-call compile cost is cheaper than an occasionally-terrible plan.
ALTER PROCEDURE dbo.GetOrdersByStatus
    @Status VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT OrderId, CustomerId, OrderTotal, OrderDate
    FROM dbo.Orders
    WHERE OrderStatus = @Status
    ORDER BY OrderDate DESC
    OPTION (RECOMPILE);
END
GO

-- Option 3: split the skewed value into its own path. Best when one value
-- is both rare AND performance-critical (e.g. 'Pending' needs to stay fast
-- because it drives an operational queue), so it shouldn't share a cached
-- plan with the high-volume path at all.
ALTER PROCEDURE dbo.GetOrdersByStatus
    @Status VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    IF @Status = 'Pending'
    BEGIN
        SELECT OrderId, CustomerId, OrderTotal, OrderDate
        FROM dbo.Orders
        WHERE OrderStatus = 'Pending'
        ORDER BY OrderDate DESC
        OPTION (OPTIMIZE FOR (@Status = 'Pending'));
    END
    ELSE
    BEGIN
        SELECT OrderId, CustomerId, OrderTotal, OrderDate
        FROM dbo.Orders
        WHERE OrderStatus = @Status
        ORDER BY OrderDate DESC
        OPTION (OPTIMIZE FOR (@Status UNKNOWN));
    END
END
GO

-- Re-test: free the cache, run 'Pending' then 'Completed' again, confirm
-- both now get a plan shaped for their own row count.
DBCC FREEPROCCACHE;
EXEC dbo.GetOrdersByStatus @Status = 'Pending';
SET STATISTICS IO ON;
EXEC dbo.GetOrdersByStatus @Status = 'Completed';
SET STATISTICS IO OFF;
GO
-- Expect: 'Completed' now shows a scan-shaped plan with logical reads in
-- the low thousands (matching the table's page count), not one lookup per row.
