/*
  01_seed_schema.sql
  Minimal reproducible schema + seed data for the "slow query" scenario
  covered in "Diagnosing and Fixing a Slow Query, Step by Step."

  Target: SQL Server 2019+ (also works on Azure SQL Database).
  Run this first, in a scratch/test database -- do not run against production.
*/

IF DB_ID('SlowQueryDemo') IS NULL
BEGIN
    CREATE DATABASE SlowQueryDemo;
END
GO

USE SlowQueryDemo;
GO

DROP TABLE IF EXISTS dbo.Orders;
DROP TABLE IF EXISTS dbo.Customers;
GO

CREATE TABLE dbo.Customers
(
    CustomerId   INT IDENTITY(1,1) PRIMARY KEY,
    CustomerName VARCHAR(100) NOT NULL,
    Region       VARCHAR(50)  NOT NULL,
    CreatedAt    DATETIME2    NOT NULL DEFAULT SYSDATETIME()
);
GO

CREATE TABLE dbo.Orders
(
    OrderId      INT IDENTITY(1,1) PRIMARY KEY,
    CustomerId   INT NOT NULL,
    OrderStatus  VARCHAR(20) NOT NULL,   -- 'Pending','Shipped','Cancelled','Delivered'
    OrderDate    DATETIME2   NOT NULL,
    OrderTotal   DECIMAL(10,2) NOT NULL
    -- Intentionally NO index on CustomerId or OrderStatus yet -- that's the point.
);
GO

-- Seed 5,000 customers
;WITH n AS (
    SELECT TOP (5000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.Customers (CustomerName, Region)
SELECT
    'Customer ' + CAST(rn AS VARCHAR(10)),
    CASE rn % 4 WHEN 0 THEN 'West' WHEN 1 THEN 'East' WHEN 2 THEN 'North' ELSE 'South' END
FROM n;
GO

-- Seed ~2,000,000 orders, skewed so most rows are NOT 'Pending'
-- (mirrors a real support-queue table: a small, hot slice of a big table)
;WITH n AS (
    SELECT TOP (2000000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
    FROM sys.all_objects a CROSS JOIN sys.all_objects b CROSS JOIN sys.all_objects c
)
INSERT INTO dbo.Orders (CustomerId, OrderStatus, OrderDate, OrderTotal)
SELECT
    1 + ABS(CHECKSUM(NEWID())) % 5000,
    CASE
        WHEN rn % 500 = 0 THEN 'Pending'      -- ~0.2% of rows: the hot, narrow slice
        WHEN rn % 7 = 0   THEN 'Cancelled'
        WHEN rn % 3 = 0   THEN 'Delivered'
        ELSE 'Shipped'
    END,
    DATEADD(DAY, -1 * (ABS(CHECKSUM(NEWID())) % 730), SYSDATETIME()),
    CAST(10 + (ABS(CHECKSUM(NEWID())) % 49000) AS DECIMAL(10,2)) / 100.0
FROM n;
GO

UPDATE STATISTICS dbo.Orders;
UPDATE STATISTICS dbo.Customers;
GO

PRINT 'Seed complete: ' + CAST((SELECT COUNT(*) FROM dbo.Orders) AS VARCHAR(20)) + ' orders, '
    + CAST((SELECT COUNT(*) FROM dbo.Customers) AS VARCHAR(20)) + ' customers.';
GO
