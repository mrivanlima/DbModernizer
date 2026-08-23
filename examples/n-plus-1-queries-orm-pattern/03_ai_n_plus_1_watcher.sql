/*
    03_ai_n_plus_1_watcher.sql
    Read-only, scheduled watcher that scans the plan cache for the N+1
    fingerprint: near-identical parameterized query text executed an
    unusually high number of times relative to how cheap each execution is.

    This never rewrites application code or touches the ORM's mapping. It
    only produces a scored report in dbo.NPlus1CandidateLog for a human
    (the app developer, not just the DBA) to review and decide whether to
    add eager loading for that specific relationship.
*/

USE NPlus1Demo;
GO

IF OBJECT_ID('dbo.NPlus1CandidateLog') IS NULL
BEGIN
    CREATE TABLE dbo.NPlus1CandidateLog
    (
        LogId               INT IDENTITY(1,1) PRIMARY KEY,
        CapturedAt          DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
        QueryTemplate       NVARCHAR(500) NOT NULL,
        ExecutionCount      BIGINT NOT NULL,
        AvgLogicalReads     BIGINT NOT NULL,
        TotalElapsedMs      DECIMAL(18,2) NOT NULL,
        SuspicionScore      DECIMAL(10,2) NOT NULL,
        ReviewStatus        NVARCHAR(20) NOT NULL DEFAULT 'pending', -- pending | approved | dismissed
        ReviewedBy          NVARCHAR(100) NULL,
        ReviewedAt          DATETIME2 NULL
    );
END
GO

-- Heuristic: flag statements that (a) run against a single table with a
-- simple equality predicate on what looks like a foreign key, (b) have a
-- high execution_count, and (c) are cheap per-call (low avg logical reads) —
-- the combination that makes N+1 invisible to "slow query" alerting, since
-- no single execution ever crosses a slow-query threshold.
INSERT INTO dbo.NPlus1CandidateLog
    (QueryTemplate, ExecutionCount, AvgLogicalReads, TotalElapsedMs, SuspicionScore)
SELECT
    LEFT(st.text, 500) AS QueryTemplate,
    qs.execution_count,
    qs.total_logical_reads / NULLIF(qs.execution_count, 0) AS AvgLogicalReads,
    qs.total_elapsed_time / 1000.0 AS TotalElapsedMs,
    -- Score rewards high execution_count combined with low per-call cost
    -- and a WHERE clause that looks like a single-row FK lookup — that
    -- combination is what a human reviewer should look at first.
    CAST(
        (qs.execution_count * 1.0)
        / NULLIF(qs.total_logical_reads / NULLIF(qs.execution_count, 0), 0)
    AS DECIMAL(10,2)) AS SuspicionScore
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE qs.execution_count > 100                         -- ran way more than a normal page load should issue
  AND st.text LIKE 'SELECT%WHERE%=%'                    -- simple single-predicate shape
  AND st.text NOT LIKE '%JOIN%'                          -- not already a joined/eager query
  AND (qs.total_logical_reads / NULLIF(qs.execution_count, 0)) < 50 -- cheap per call — the N+1 tell
  AND NOT EXISTS (
        SELECT 1 FROM dbo.NPlus1CandidateLog existing
        WHERE existing.QueryTemplate = LEFT(st.text, 500)
          AND existing.CapturedAt > DATEADD(HOUR, -24, SYSDATETIME())
      );
GO

SELECT * FROM dbo.NPlus1CandidateLog
WHERE ReviewStatus = 'pending'
ORDER BY SuspicionScore DESC;
GO

-- Human-in-the-loop gate: nothing in this script ever runs DDL, changes
-- an ORM mapping, or auto-adds eager loading. A developer reviews the
-- pending rows and, if they confirm the pattern by checking the
-- application code path, marks the row reviewed like this:
--
-- UPDATE dbo.NPlus1CandidateLog
-- SET ReviewStatus = 'approved', ReviewedBy = 'ivan', ReviewedAt = SYSDATETIME()
-- WHERE LogId = @id;
--
-- Only after that human step does the actual fix (adding .Include() /
-- joinedload() / JOIN FETCH in the app code) happen, in a normal code
-- review — this watcher's job is purely to surface the candidate early,
-- before it shows up as a vague "the dashboard feels slow" complaint.
