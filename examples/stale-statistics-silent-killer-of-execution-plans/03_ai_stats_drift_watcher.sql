/*
    03_ai_stats_drift_watcher.sql

    A scheduled, read-only query that flags statistics likely to have
    the ascending-key drift problem from this post: the modification
    counter alone is a bad signal on a large table (a 20,000-row nightly
    ETL batch never crosses the dynamic threshold on an 8M-row table),
    so this checks a second, more direct signal instead -- how long it's
    actually been since each statistic was refreshed, weighted by how
    write-heavy the underlying table is.

    It never runs UPDATE STATISTICS itself. It logs candidates to a
    review table; a human (or a separate, explicitly-approved job) picks
    what to run and when, same pattern as the index-fragmentation watcher
    in this repo's other examples folder.
*/

USE StaleStatsDemo;
GO

IF OBJECT_ID('dbo.StatsDriftLog') IS NULL
BEGIN
    CREATE TABLE dbo.StatsDriftLog
    (
        LogId               INT IDENTITY(1,1) PRIMARY KEY,
        CheckedAt           DATETIME2(0) NOT NULL DEFAULT (SYSUTCDATETIME()),
        SchemaName          SYSNAME NOT NULL,
        TableName           SYSNAME NOT NULL,
        StatsName           SYSNAME NOT NULL,
        LastUpdated         DATETIME2(3) NULL,
        DaysSinceUpdate     INT NULL,
        RowsAtLastUpdate    BIGINT NULL,
        ModificationCounter BIGINT NULL,
        PctModifiedOfLast   DECIMAL(9,4) NULL,
        RecommendedAction   VARCHAR(20) NOT NULL,
        ReviewedByHuman     BIT NOT NULL DEFAULT (0),
        ActionTaken         VARCHAR(20) NULL,
        ActionTakenAt       DATETIME2(0) NULL
    );
END
GO

-- Flag anything either (a) not updated in over 14 days AND has taken any
-- writes at all, or (b) has had modifications exceeding 10% of the row
-- count at last update -- catching both the "quiet ascending key" case
-- and the more classic "big enough change but nobody rebuilt stats"
-- case in one pass.
DECLARE @StaleDays INT = 14;
DECLARE @PctThreshold DECIMAL(5,2) = 10.0;

INSERT INTO dbo.StatsDriftLog
    (SchemaName, TableName, StatsName, LastUpdated, DaysSinceUpdate,
     RowsAtLastUpdate, ModificationCounter, PctModifiedOfLast, RecommendedAction)
SELECT
    s.name  AS SchemaName,
    t.name  AS TableName,
    st.name AS StatsName,
    sp.last_updated,
    DATEDIFF(DAY, sp.last_updated, SYSUTCDATETIME()) AS DaysSinceUpdate,
    sp.rows,
    sp.modification_counter,
    CASE WHEN sp.rows > 0
         THEN CAST(sp.modification_counter AS DECIMAL(18,4)) / sp.rows * 100
         ELSE NULL END AS PctModifiedOfLast,
    CASE
        WHEN sp.rows > 0
             AND CAST(sp.modification_counter AS DECIMAL(18,4)) / sp.rows * 100 >= @PctThreshold
            THEN 'UPDATE_NOW'
        WHEN sp.modification_counter > 0
             AND DATEDIFF(DAY, sp.last_updated, SYSUTCDATETIME()) >= @StaleDays
            THEN 'REVIEW'
        ELSE 'OK'
    END AS RecommendedAction
FROM sys.stats st
JOIN sys.tables t ON t.object_id = st.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
CROSS APPLY sys.dm_db_stats_properties(st.object_id, st.stats_id) sp
WHERE t.is_ms_shipped = 0
  AND sp.modification_counter > 0;

-- Surface only what needs a look -- this is the report a human reviews
-- before deciding what to run and when (an off-hours window, most
-- likely, for a FULLSCAN on anything large).
SELECT *
FROM dbo.StatsDriftLog
WHERE CheckedAt = (SELECT MAX(CheckedAt) FROM dbo.StatsDriftLog)
  AND RecommendedAction <> 'OK'
ORDER BY PctModifiedOfLast DESC;
GO
