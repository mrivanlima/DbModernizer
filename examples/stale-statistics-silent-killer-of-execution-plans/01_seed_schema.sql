/*
    01_seed_schema.sql

    Reproduces a realistic "ascending key" stale-statistics problem: an
    Orders table with a growing OrderDate column, seeded with history,
    then given three weeks of nightly-sized batches that land past the
    edge of the existing statistics histogram -- without triggering an
    auto-update, because each batch is nowhere near the dynamic
    modification-counter threshold on an 8-million-row table.

    Run this once against a scratch/test database. Takes a few minutes
    on typical hardware because of the row volume.
*/

USE master;
GO

IF DB_ID('StaleStatsDemo') IS NULL
    CREATE DATABASE StaleStatsDemo;
GO

USE StaleStatsDemo;
GO

IF OBJECT_ID('dbo.Orders') IS NOT NULL
    DROP TABLE dbo.Orders;
GO

CREATE TABLE dbo.Orders
(
    OrderId       BIGINT IDENTITY(1,1) PRIMARY KEY,
    CustomerId    INT NOT NULL,
    OrderDate     DATETIME2(0) NOT NULL,
    OrderStatus   VARCHAR(20) NOT NULL,
    OrderTotal    DECIMAL(10,2) NOT NULL
);
GO

CREATE NONCLUSTERED INDEX IX_Orders_OrderDate
    ON dbo.Orders (OrderDate) INCLUDE (CustomerId, OrderTotal);
GO

-- Seed ~8,000,000 rows of "history" spread over the last 3 years.
SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#Numbers') IS NOT NULL DROP TABLE #Numbers;
CREATE TABLE #Numbers (n INT PRIMARY KEY);

;WITH L0 AS (SELECT 1 AS c UNION ALL SELECT 1),
      L1 AS (SELECT 1 AS c FROM L0 a CROSS JOIN L0 b),
      L2 AS (SELECT 1 AS c FROM L1 a CROSS JOIN L1 b),
      L3 AS (SELECT 1 AS c FROM L2 a CROSS JOIN L2 b),
      L4 AS (SELECT 1 AS c FROM L3 a CROSS JOIN L3 b),
      Nums AS (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM L4)
INSERT INTO #Numbers (n)
SELECT TOP (1000000) n FROM Nums;

DECLARE @batch INT = 0;
WHILE @batch < 8
BEGIN
    INSERT INTO dbo.Orders (CustomerId, OrderDate, OrderStatus, OrderTotal)
    SELECT
        (ABS(CHECKSUM(NEWID())) % 500000) + 1,
        DATEADD(SECOND, -(ABS(CHECKSUM(NEWID())) % (3 * 365 * 86400)), '2026-08-21'),
        'Delivered',
        CAST((ABS(CHECKSUM(NEWID())) % 50000) / 100.0 AS DECIMAL(10,2))
    FROM #Numbers;

    SET @batch += 1;
END

-- Full-scan stats now, capturing history up through '2026-08-21' as the
-- effective histogram boundary. This mirrors a database that had healthy
-- statistics at some point in the past.
UPDATE STATISTICS dbo.Orders IX_Orders_OrderDate WITH FULLSCAN;
GO

-- Simulate three weeks of nightly ETL: ~20,000 new orders/night, dated
-- into the days *after* the histogram boundary above. On an 8M-row
-- table, 20,000 rows is ~0.25% -- nowhere near the ~5-10% dynamic
-- threshold SQL Server uses under trace flag 2371 (default behavior in
-- compat level 130+), so auto-update statistics never fires.
DECLARE @day INT = 1;
WHILE @day <= 21
BEGIN
    INSERT INTO dbo.Orders (CustomerId, OrderDate, OrderStatus, OrderTotal)
    SELECT TOP (20000)
        (ABS(CHECKSUM(NEWID())) % 500000) + 1,
        DATEADD(SECOND, ABS(CHECKSUM(NEWID())) % 86400, DATEADD(DAY, @day, '2026-08-21')),
        'Delivered',
        CAST((ABS(CHECKSUM(NEWID())) % 50000) / 100.0 AS DECIMAL(10,2))
    FROM #Numbers;

    SET @day += 1;
END
GO

DROP TABLE #Numbers;
GO

PRINT 'Seed complete. dbo.Orders row count: ' + CAST((SELECT COUNT(*) FROM dbo.Orders) AS VARCHAR(20));
GO
