/*
    01_seed_schema.sql

    Creates FragDemo and seeds an Orders table the way a real OLTP table
    fragments in practice: a narrow clustered index on an ever-increasing
    OrderId (fine), plus a nonclustered index on OrderStatus that gets
    updated constantly as orders move through a small set of status values
    (Pending -> Shipped -> Delivered). Repeated UPDATEs on an indexed column
    cause page splits, which is what actually drives fragmentation --
    not the INSERTs.

    Do not run this against production. It creates a new database and
    seeds ~1.5 million rows; on typical hardware this takes a few minutes.
*/

SET NOCOUNT ON;
GO

IF DB_ID('FragDemo') IS NOT NULL
BEGIN
    ALTER DATABASE FragDemo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE FragDemo;
END
GO

CREATE DATABASE FragDemo;
GO

ALTER DATABASE FragDemo SET RECOVERY SIMPLE;
GO

USE FragDemo;
GO

CREATE TABLE dbo.Orders
(
    OrderId       INT IDENTITY(1,1) NOT NULL,
    CustomerId    INT NOT NULL,
    OrderStatus   VARCHAR(20) NOT NULL DEFAULT ('Pending'),
    OrderTotal    DECIMAL(10,2) NOT NULL,
    OrderDate     DATETIME2(0) NOT NULL DEFAULT (SYSUTCDATETIME()),
    LastUpdated   DATETIME2(0) NOT NULL DEFAULT (SYSUTCDATETIME()),
    Notes         VARCHAR(200) NOT NULL DEFAULT (REPLICATE('x', 150)),
    CONSTRAINT PK_Orders PRIMARY KEY CLUSTERED (OrderId)
);
GO

CREATE NONCLUSTERED INDEX IX_Orders_OrderStatus
    ON dbo.Orders (OrderStatus) INCLUDE (CustomerId, OrderTotal);
GO

-- Seed ~1.5M orders, all starting life as 'Pending'
DECLARE @i INT = 0;
DECLARE @BatchSize INT = 10000;

WHILE @i < 1500000
BEGIN
    ;WITH Numbers AS
    (
        SELECT TOP (@BatchSize) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects a CROSS JOIN sys.all_objects b
    )
    INSERT INTO dbo.Orders (CustomerId, OrderStatus, OrderTotal, OrderDate)
    SELECT
        (ABS(CHECKSUM(NEWID())) % 200000) + 1,
        'Pending',
        CAST((ABS(CHECKSUM(NEWID())) % 50000) AS DECIMAL(10,2)) / 100.0,
        DATEADD(SECOND, -(ABS(CHECKSUM(NEWID())) % 15552000), SYSUTCDATETIME())
    FROM Numbers;

    SET @i += @BatchSize;
END
GO

-- Simulate real order-status churn: every order moves through
-- Pending -> Shipped -> Delivered, each transition an UPDATE on the
-- indexed OrderStatus column. This is what actually fragments the
-- nonclustered index -- an in-place value change that no longer sorts
-- where the old value did forces a page split.
UPDATE TOP (1000000) dbo.Orders
SET OrderStatus = 'Shipped', LastUpdated = SYSUTCDATETIME()
WHERE OrderStatus = 'Pending';
GO

UPDATE TOP (800000) dbo.Orders
SET OrderStatus = 'Delivered', LastUpdated = SYSUTCDATETIME()
WHERE OrderStatus = 'Shipped';
GO

-- A second round of churn on a subset, to build up realistic fragmentation
-- rather than a single clean pass
UPDATE TOP (300000) dbo.Orders
SET OrderStatus = 'Delivered', LastUpdated = SYSUTCDATETIME()
WHERE OrderStatus = 'Shipped';
GO

UPDATE TOP (150000) dbo.Orders
SET OrderStatus = 'Cancelled', LastUpdated = SYSUTCDATETIME()
WHERE OrderStatus = 'Pending';
GO

PRINT 'Seed complete. Row count and fragmentation check:';

SELECT COUNT(*) AS TotalOrders FROM dbo.Orders;

SELECT
    OBJECT_NAME(ips.object_id)      AS TableName,
    i.name                          AS IndexName,
    ips.index_type_desc,
    ips.avg_fragmentation_in_percent,
    ips.avg_page_space_used_in_percent,
    ips.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('dbo.Orders'), NULL, NULL, 'SAMPLED') ips
JOIN sys.indexes i ON i.object_id = ips.object_id AND i.index_id = ips.index_id
ORDER BY ips.avg_fragmentation_in_percent DESC;
GO
