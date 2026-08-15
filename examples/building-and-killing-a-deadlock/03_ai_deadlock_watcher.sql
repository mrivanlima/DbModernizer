/*
    03_ai_deadlock_watcher.sql
    Companion code for "Building and Killing a Deadlock With Your Own Hands"

    A scheduled, read-only watcher that parses every deadlock graph out of
    the system_health Extended Events session, extracts which objects and
    statements were involved, and logs a pattern signature. When the same
    pair of objects deadlocks repeatedly, it's almost never a fluke -- it's
    a systemic access-order problem like the one in this post -- so the
    watcher raises that as a scored candidate for a human to fix in code.

    It never rewrites a stored procedure, never reorders anything, and
    never touches DEADLOCK_PRIORITY. It only reports.
*/

USE DeadlockDemo;
GO

IF OBJECT_ID('dbo.DeadlockLog') IS NULL
BEGIN
    CREATE TABLE dbo.DeadlockLog
    (
        DeadlockLogId   INT IDENTITY PRIMARY KEY,
        EventTime       DATETIME2      NOT NULL,
        VictimObjects   NVARCHAR(400)  NOT NULL,   -- objects touched by the losing session
        SurvivorObjects NVARCHAR(400)  NOT NULL,   -- objects touched by the winning session
        PatternKey      AS (CONVERT(VARCHAR(400),
                                CASE WHEN VictimObjects < SurvivorObjects
                                     THEN VictimObjects + '|' + SurvivorObjects
                                     ELSE SurvivorObjects + '|' + VictimObjects END)) PERSISTED,
        DeadlockGraph   XML            NOT NULL,
        ReviewStatus    VARCHAR(20)    NOT NULL DEFAULT 'pending_review',
        LoggedAt        DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
    );
    CREATE INDEX IX_DeadlockLog_PatternKey ON dbo.DeadlockLog (PatternKey, EventTime);
END
GO

;WITH RawEvents AS
(
    SELECT
        CAST(event_data.value('(event/@timestamp)[1]', 'varchar(50)') AS DATETIME2) AS EventTime,
        event_data.query('.') AS DeadlockGraph
    FROM
    (
        SELECT CAST(target_data AS XML) AS TargetData
        FROM sys.dm_xe_session_targets st
        JOIN sys.dm_xe_sessions s ON s.address = st.event_session_address
        WHERE s.name = 'system_health'
          AND st.target_name = 'ring_buffer'
    ) AS RingBuffer
    CROSS APPLY TargetData.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS XEventData(event_data)
),
Parsed AS
(
    SELECT
        r.EventTime,
        r.DeadlockGraph,
        -- Objects referenced by the process SQL Server picked as victim
        STUFF((
            SELECT DISTINCT ', ' + ol.value('@objectname', 'nvarchar(200)')
            FROM r.DeadlockGraph.nodes('//deadlock/process-list/process[@id=sql:column("VictimId")]/../process[@id=sql:column("VictimId")]//objectlock') AS o(ol)
            FOR XML PATH('')
        ), 1, 2, '') AS VictimObjects,
        STUFF((
            SELECT DISTINCT ', ' + ol.value('@objectname', 'nvarchar(200)')
            FROM r.DeadlockGraph.nodes('//deadlock/process-list/process[@id!=sql:column("VictimId")]//objectlock') AS o(ol)
            FOR XML PATH('')
        ), 1, 2, '') AS SurvivorObjects
    FROM RawEvents r
    CROSS APPLY (SELECT r.DeadlockGraph.value('(//deadlock/process-list/process[@status="aborted" or @victimStatus="1"]/@id)[1]', 'varchar(50)') AS VictimId) v(VictimId)
)
INSERT INTO dbo.DeadlockLog (EventTime, VictimObjects, SurvivorObjects, DeadlockGraph)
SELECT p.EventTime, ISNULL(p.VictimObjects, '(unresolved)'), ISNULL(p.SurvivorObjects, '(unresolved)'), p.DeadlockGraph
FROM Parsed p
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.DeadlockLog dl WHERE dl.EventTime = p.EventTime
);
GO

-- Score: how many times has this exact pair of objects deadlocked in the
-- last 7 days? Two or more is a pattern, not a coincidence -- flag it.
SELECT
    PatternKey,
    COUNT(*)              AS OccurrenceCount,
    MIN(EventTime)         AS FirstSeen,
    MAX(EventTime)         AS LastSeen,
    MAX(ReviewStatus)      AS ReviewStatus
FROM dbo.DeadlockLog
WHERE EventTime >= DATEADD(DAY, -7, SYSUTCDATETIME())
GROUP BY PatternKey
HAVING COUNT(*) >= 2
ORDER BY OccurrenceCount DESC;

-- A DBA reviews that list -- daily, or however often makes sense -- and
-- decides whether the fix is a consistent access order (as in this post),
-- a covering index that shrinks the lock footprint, or shortening the
-- transaction. The watcher's job ends at the report; nothing here ever
-- issues ALTER PROCEDURE or touches application code on its own.
GO
