/*
    03_ai_plan_variance_watcher.sql
    Read-only, scheduled watcher for the AI-automation angle.

    Parameter sniffing doesn't show up as an error -- it shows up as a
    procedure whose average logical reads or CPU swing wildly call to
    call, because the same cached plan is serving very different
    parameter shapes. This watcher scores that variance from data SQL
    Server is already collecting (Query Store), and produces a report --
    it never touches OPTION(RECOMPILE), a plan guide, or the proc itself.
*/

USE ParamSniffDemo;
GO

-- Requires Query Store to be on (default ON for new databases in
-- compatibility level 130+; enable explicitly if needed):
-- ALTER DATABASE ParamSniffDemo SET QUERY_STORE = ON;

IF OBJECT_ID('dbo.PlanVarianceLog') IS NULL
BEGIN
    CREATE TABLE dbo.PlanVarianceLog
    (
        LogId            INT IDENTITY(1,1) PRIMARY KEY,
        CheckedAt        DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        ProcName         NVARCHAR(260) NOT NULL,
        QueryId          BIGINT NOT NULL,
        PlanId           BIGINT NOT NULL,
        MinDurationMs     DECIMAL(18,2) NOT NULL,
        MaxDurationMs     DECIMAL(18,2) NOT NULL,
        AvgDurationMs     DECIMAL(18,2) NOT NULL,
        VarianceRatio     DECIMAL(18,2) NOT NULL,   -- Max / NULLIF(Min, 0)
        ExecutionCount   BIGINT NOT NULL
    );
END
GO

-- Score every query in Query Store by how much its duration swings across
-- executions of the SAME plan. A single cached plan whose slowest run is
-- 20x+ its fastest run, over a meaningful number of executions, is a
-- strong candidate for parameter sniffing rather than "the server was busy."
INSERT INTO dbo.PlanVarianceLog
    (ProcName, QueryId, PlanId, MinDurationMs, MaxDurationMs, AvgDurationMs, VarianceRatio, ExecutionCount)
SELECT
    OBJECT_NAME(q.object_id)                              AS ProcName,
    q.query_id,
    p.plan_id,
    MIN(rs.min_duration) / 1000.0                          AS MinDurationMs,
    MAX(rs.max_duration) / 1000.0                          AS MaxDurationMs,
    AVG(rs.avg_duration) / 1000.0                           AS AvgDurationMs,
    CAST(MAX(rs.max_duration) AS DECIMAL(18,2))
        / NULLIF(MIN(NULLIF(rs.min_duration, 0)), 0)        AS VarianceRatio,
    SUM(rs.count_executions)                                AS ExecutionCount
FROM sys.query_store_query q
JOIN sys.query_store_plan p ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats rs ON rs.plan_id = p.plan_id
WHERE q.object_id <> 0
  AND rs.last_execution_time >= DATEADD(DAY, -1, SYSUTCDATETIME())
GROUP BY q.object_id, q.query_id, p.plan_id
HAVING SUM(rs.count_executions) >= 20
   AND CAST(MAX(rs.max_duration) AS DECIMAL(18,2)) / NULLIF(MIN(NULLIF(rs.min_duration, 0)), 0) >= 10;

-- Daily report: which procs are the worst offenders this week, ranked.
SELECT
    ProcName,
    COUNT(*)              AS TimesFlagged,
    MAX(VarianceRatio)    AS WorstVarianceRatio,
    MAX(CheckedAt)         AS LastFlagged
FROM dbo.PlanVarianceLog
WHERE CheckedAt >= DATEADD(DAY, -7, SYSUTCDATETIME())
GROUP BY ProcName
ORDER BY WorstVarianceRatio DESC;

-- A human reviews that ranked list and decides, per proc, whether the fix
-- is OPTIMIZE FOR a representative value, OPTION (RECOMPILE), splitting
-- the skewed path out, or forcing a specific known-good plan via
-- sp_query_store_force_plan -- this script never calls any of those itself.
