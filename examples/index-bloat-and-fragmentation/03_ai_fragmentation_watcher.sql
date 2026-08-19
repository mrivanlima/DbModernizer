/*
    03_ai_fragmentation_watcher.sql

    A scheduled, read-only query that scores every index on the instance
    for fragmentation using BOTH signals (logical fragmentation and page
    density) and storage-aware thresholds, then logs candidates to a
    review queue -- it never rebuilds or reorganizes anything itself.

    Run this daily (see run_watcher.ps1) against each database that
    matters. It's intentionally scoped to indexes above a minimum size --
    tiny indexes aren't worth measuring or maintaining.
*/

USE FragDemo;
GO

IF OBJECT_ID('dbo.IndexFragmentationLog') IS NULL
BEGIN
    CREATE TABLE dbo.IndexFragmentationLog
    (
        LogId                 INT IDENTITY(1,1) PRIMARY KEY,
        CheckedAt             DATETIME2(0) NOT NULL DEFAULT (SYSUTCDATETIME()),
        DatabaseName          SYSNAME NOT NULL,
        SchemaName             SYSNAME NOT NULL,
        TableName             SYSNAME NOT NULL,
        IndexName             SYSNAME NOT NULL,
        LogicalFragPct        DECIMAL(5,2) NOT NULL,
        PageDensityPct        DECIMAL(5,2) NOT NULL,
        PageCount             BIGINT NOT NULL,
        RecommendedAction     VARCHAR(20) NOT NULL,
        ReviewedByHuman       BIT NOT NULL DEFAULT (0),
        ActionTaken           VARCHAR(20) NULL,
        ActionTakenAt         DATETIME2(0) NULL
    );
END
GO

-- Storage-aware thresholds. Adjust @StorageType based on the actual
-- underlying disk for the instance being checked -- SSD/NVMe backends
-- (most cloud-managed SQL today) can tolerate higher logical fragmentation
-- before it's worth the CPU/IO cost of a rebuild; spinning disks can't.
DECLARE @StorageType VARCHAR(10) = 'SSD';   -- 'SSD' or 'HDD'
DECLARE @ReorgThreshold DECIMAL(5,2) = CASE WHEN @StorageType = 'SSD' THEN 30.0 ELSE 5.0 END;
DECLARE @RebuildThreshold DECIMAL(5,2) = CASE WHEN @StorageType = 'SSD' THEN 60.0 ELSE 30.0 END;
DECLARE @MinPageCount INT = 1000;            -- ~8MB; skip anything smaller
DECLARE @MinPageDensity DECIMAL(5,2) = 75.0; -- flag low-density pages even if logical frag looks tame

INSERT INTO dbo.IndexFragmentationLog
    (DatabaseName, SchemaName, TableName, IndexName, LogicalFragPct, PageDensityPct, PageCount, RecommendedAction)
SELECT
    DB_NAME(),
    s.name,
    t.name,
    i.name,
    ips.avg_fragmentation_in_percent,
    ips.avg_page_space_used_in_percent,
    ips.page_count,
    CASE
        WHEN ips.avg_fragmentation_in_percent >= @RebuildThreshold
             OR ips.avg_page_space_used_in_percent < @MinPageDensity THEN 'REBUILD'
        WHEN ips.avg_fragmentation_in_percent >= @ReorgThreshold THEN 'REORGANIZE'
        ELSE 'MONITOR'
    END
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'SAMPLED') ips
JOIN sys.indexes i ON i.object_id = ips.object_id AND i.index_id = ips.index_id
JOIN sys.tables t ON t.object_id = ips.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE ips.index_level = 0
  AND ips.page_count >= @MinPageCount
  AND i.name IS NOT NULL
  AND (
        ips.avg_fragmentation_in_percent >= @ReorgThreshold
        OR ips.avg_page_space_used_in_percent < @MinPageDensity
      );

-- The report a human reviews: today's candidates, worst first. Someone
-- decides per index whether REBUILD/REORGANIZE is worth the resource cost
-- right now, whether ONLINE = ON is available (Enterprise/Azure SQL vs.
-- Standard), and what fill factor fits that index's write pattern. This
-- watcher's job stops at the report -- it never issues ALTER INDEX itself.
SELECT
    DatabaseName, SchemaName, TableName, IndexName,
    LogicalFragPct, PageDensityPct, PageCount, RecommendedAction, CheckedAt
FROM dbo.IndexFragmentationLog
WHERE CheckedAt >= CAST(SYSUTCDATETIME() AS DATE)
ORDER BY
    CASE RecommendedAction WHEN 'REBUILD' THEN 1 WHEN 'REORGANIZE' THEN 2 ELSE 3 END,
    LogicalFragPct DESC;
GO
