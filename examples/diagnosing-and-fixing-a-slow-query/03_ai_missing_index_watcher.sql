/*
  03_ai_missing_index_watcher.sql
  The AI-automation angle for "Diagnosing and Fixing a Slow Query, Step by Step."

  Goal: catch this *class* of problem (a hot, unindexed predicate on a big
  table) before it becomes a support ticket, without letting an automated
  process create indexes on its own. This produces a scored, human-readable
  report. A person still approves before anything gets created.

  Run this on a schedule (SQL Agent job, or the PowerShell wrapper below via
  Windows Task Scheduler / cron on a jump box). It is READ-ONLY -- it never
  issues CREATE INDEX itself.
*/

USE SlowQueryDemo;
GO

IF OBJECT_ID('dbo.IndexCandidateLog') IS NULL
BEGIN
    CREATE TABLE dbo.IndexCandidateLog
    (
        LogId            INT IDENTITY(1,1) PRIMARY KEY,
        CapturedAt        DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
        TableName         NVARCHAR(256) NOT NULL,
        EqualityColumns   NVARCHAR(4000) NULL,
        InequalityColumns NVARCHAR(4000) NULL,
        IncludedColumns   NVARCHAR(4000) NULL,
        AvgUserImpact     FLOAT NOT NULL,
        TimesNeeded       BIGINT NOT NULL,
        Score             FLOAT NOT NULL,          -- our own weighting, not just SQL Server's estimate
        SuggestedDDL      NVARCHAR(MAX) NOT NULL,
        ReviewStatus      VARCHAR(20) NOT NULL DEFAULT 'pending_review',  -- pending_review | approved | rejected | applied
        ReviewedBy        NVARCHAR(128) NULL,
        ReviewedAt        DATETIME2 NULL
    );
END
GO

-- Score = estimated impact weighted by how often SQL Server actually
-- wanted this index shape, discounting one-off ad hoc queries.
-- This is deliberately conservative: it flags candidates for a human,
-- it never acts on them.
INSERT INTO dbo.IndexCandidateLog
    (TableName, EqualityColumns, InequalityColumns, IncludedColumns,
     AvgUserImpact, TimesNeeded, Score, SuggestedDDL)
SELECT
    mid.statement,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns,
    migs.avg_user_impact,
    migs.user_seeks + migs.user_scans,
    migs.avg_user_impact * LOG(1.0 + migs.user_seeks + migs.user_scans) AS score,
    N'CREATE NONCLUSTERED INDEX IX_AutoCandidate_' + CAST(mig.index_group_handle AS NVARCHAR(10))
        + N' ON ' + mid.statement
        + N' (' + ISNULL(mid.equality_columns, '') +
              CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL THEN ',' ELSE '' END
            + ISNULL(mid.inequality_columns, '') + N')'
        + CASE WHEN mid.included_columns IS NOT NULL
               THEN N' INCLUDE (' + mid.included_columns + N')'
               ELSE N'' END
        + N';  -- REVIEW: verify against existing indexes and real query patterns before running'
FROM sys.dm_db_missing_index_details mid
JOIN sys.dm_db_missing_index_groups mig  ON mig.index_handle = mid.index_handle
JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
WHERE migs.avg_user_impact >= 50.0            -- threshold: only worth a human's time above this
  AND (migs.user_seeks + migs.user_scans) >= 10  -- filter out one-off ad hoc queries
  AND NOT EXISTS (
        -- don't re-log something already sitting in the queue
        SELECT 1 FROM dbo.IndexCandidateLog existing
        WHERE existing.TableName = mid.statement
          AND ISNULL(existing.EqualityColumns,'') = ISNULL(mid.equality_columns,'')
          AND ISNULL(existing.InequalityColumns,'') = ISNULL(mid.inequality_columns,'')
          AND existing.ReviewStatus = 'pending_review'
      );
GO

-- The report a human reviews (e.g. emailed daily via SQL Agent + Database Mail,
-- or pulled into a Teams/Slack digest). Approval is a manual UPDATE to
-- ReviewStatus -- intentionally not automated.
SELECT
    LogId, CapturedAt, TableName, EqualityColumns, InequalityColumns,
    AvgUserImpact, TimesNeeded, Score, SuggestedDDL, ReviewStatus
FROM dbo.IndexCandidateLog
WHERE ReviewStatus = 'pending_review'
ORDER BY Score DESC;
GO

/*
  Human-in-the-loop gate, by design:

    -- A DBA reviews the report above, then explicitly approves:
    UPDATE dbo.IndexCandidateLog
    SET ReviewStatus = 'approved', ReviewedBy = SUSER_SNAME(), ReviewedAt = SYSDATETIME()
    WHERE LogId = 42;

    -- Only THEN does a separate, human-triggered step run the SuggestedDDL
    -- (copy/paste, or a small runner script that only executes rows marked
    -- 'approved' -- never 'pending_review').

  This mirrors how I'd wire this for a client: the watcher runs unattended
  on a schedule and does the tedious pattern-matching AI is good at; a
  person still makes the judgment call on which candidate to apply, and
  when the table is one of those "if the index build locks it, we lose
  money" tables, that gate matters more than the automation does.
*/
