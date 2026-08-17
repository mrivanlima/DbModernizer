/*
    01_seed_schema.sql
    Companion code for "Parameter Sniffing: Why It's Fast for One User
    and Slow for Everyone Else" (Data Platform Advisory blog).

    Creates a scratch database with an Orders table whose OrderStatus
    column is deliberately skewed: ~96% 'Completed', ~4% everything else.
    That skew is what makes parameter sniffing bite here -- run this on
    a scratch/test instance only.
*/

IF DB_ID('ParamSniffDemo') IS NOT NULL
BEGIN
    ALTER DATABASE ParamSniffDemo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ParamSniffDemo;
END
GO

CREATE DATABASE ParamSniffDemo;
GO

ALTER DATABASE ParamSniffDemo SET COMPATIBILITY_LEVEL = 150;
GO

USE ParamSniffDemo;
GO

CREATE TABLE dbo.Orders
(
    OrderId       INT IDENTITY(1,1) PRIMARY KEY,
    CustomerId    INT NOT NULL,
    OrderStatus   VARCHAR(20) NOT NULL,
    OrderTotal    DECIMAL(12,2) NOT NULL,
    OrderDate     DATETIME2 NOT NULL
);
GO

CREATE INDEX IX_Orders_OrderStatus ON dbo.Orders (OrderStatus) INCLUDE (CustomerId, OrderTotal, OrderDate);
GO

-- Seed ~500,000 rows: 96% Completed, 3% Shipped, ~0.9% Cancelled, ~0.1% Pending.
-- Pending is the rare status -- a handful of rows out of half a million.
SET NOCOUNT ON;

DECLARE @i INT = 0;
DECLARE @BatchSize INT = 10000;

WHILE @i < 500000
BEGIN
    ;WITH Numbers AS
    (
        SELECT TOP (@BatchSize) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects a CROSS JOIN sys.all_objects b
    )
    INSERT INTO dbo.Orders (CustomerId, OrderStatus, OrderTotal, OrderDate)
    SELECT
        ABS(CHECKSUM(NEWID())) % 50000 + 1,
        CASE
            WHEN r <= 0.96 THEN 'Completed'
            WHEN r <= 0.99 THEN 'Shipped'
            WHEN r <= 0.999 THEN 'Cancelled'
            ELSE 'Pending'
        END,
        CAST(ABS(CHECKSUM(NEWID())) % 50000 AS DECIMAL(12,2)) / 100.0,
        DATEADD(MINUTE, -ABS(CHECKSUM(NEWID())) % 525600, SYSDATETIME())
    FROM
    (
        SELECT n, CAST(ABS(CHECKSUM(NEWID())) % 1000 AS DECIMAL(5,3)) / 1000 AS r
        FROM Numbers
    ) AS Seed;

    SET @i += @BatchSize;
END
GO

UPDATE STATISTICS dbo.Orders WITH FULLSCAN;
GO

CREATE PROCEDURE dbo.GetOrdersByStatus
    @Status VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT OrderId, CustomerId, OrderTotal, OrderDate
    FROM dbo.Orders
    WHERE OrderStatus = @Status
    ORDER BY OrderDate DESC;
END
GO

-- Sanity check on the skew:
-- SELECT OrderStatus, COUNT(*) AS Cnt FROM dbo.Orders GROUP BY OrderStatus ORDER BY Cnt DESC;
