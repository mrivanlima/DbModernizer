/*
    02_reproduce_and_fix.sql
    Companion code for "Building and Killing a Deadlock With Your Own Hands"

    Run 01_seed_schema.sql first. This file has three parts:

      PART A - reproduce the deadlock (needs TWO SSMS query windows)
      PART B - read the deadlock graph SQL Server already captured for you
      PART C - the fix: a consistent-access-order wrapper, applied and re-tested

    Run each part's batches in the order shown. Part A requires opening a
    second SSMS window (or a second sqlcmd session) -- see the README.
*/

USE DeadlockDemo;
GO

/* =========================================================================
   PART A - Reproduce the deadlock
   =========================================================================

   In SESSION 1, run this batch first:

       EXEC dbo.TransferFunds
           @FromAccountId = 1, @ToAccountId = 3, @Amount = 100.00,
           @DelayBetweenUpdates = '00:00:08';

   While it's paused on the WAITFOR (you have ~8 seconds), switch to
   SESSION 2 and run the mirror-image transfer -- same two accounts,
   opposite direction:

       EXEC dbo.TransferFunds
           @FromAccountId = 3, @ToAccountId = 1, @Amount = 50.00,
           @DelayBetweenUpdates = '00:00:00';

   What happens:
     - Session 1 takes an exclusive (X) lock on AccountId 1, then waits.
     - Session 2 immediately takes an X lock on AccountId 3, then tries to
       update AccountId 1 -- blocked, waiting on Session 1's lock.
     - When Session 1's WAITFOR ends, it tries to update AccountId 3 --
       blocked, waiting on Session 2's lock.
     - Neither can proceed. SQL Server's lock monitor detects the cycle
       (it runs this deadlock-search check roughly every 5 seconds, or
       faster once contention is detected in a bank of sessions) and picks
       a victim, killing that session's transaction with:

       Msg 1205, Level 13, State 51, Line ...
       Transaction (Process ID nn) was deadlocked on lock resources with
       another process and has been chosen as the deadlock victim. Rerun
       the transaction.

   The victim is normally whichever transaction is cheaper to roll back
   (SQL Server estimates this), not simply "whoever asked for the lock
   second" -- you can also assign priority explicitly with
   SET DEADLOCK_PRIORITY if you have a session that should never lose.
*/


/* =========================================================================
   PART B - Read the deadlock graph SQL Server already captured
   =========================================================================
   The system_health Extended Events session runs by default on every
   SQL Server instance and always captures deadlock graphs -- you don't
   need a custom trace running beforehand. This pulls the most recent one
   out of the ring buffer and back into readable XML.
*/

;WITH DeadlockEvents AS
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
)
SELECT TOP 5
    EventTime,
    DeadlockGraph
FROM DeadlockEvents
ORDER BY EventTime DESC;

-- Click a result cell in the DeadlockGraph column: SSMS renders it as XML
-- you can save as .xdl and reopen to get the graphical deadlock diagram
-- (two process nodes, the lock resources between them, and the victim
-- marked with an X). Look for:
--   <deadlock-list><deadlock>
--     <resource-list>          -- which locks were being fought over (KEY locks
--                                  on the Accounts clustered index, in this case)
--     <process-list>           -- the two sessions, their T-SQL, and which one
--                                  is victim="1"
GO


/* =========================================================================
   PART C - The fix: consistent access order
   =========================================================================
   Both sessions were locking the same two rows in opposite order. Force
   every caller through a wrapper that always locks the lower AccountId
   first, regardless of transfer direction, and the cycle becomes
   impossible -- both sessions now queue for the same first lock instead
   of crossing each other.
*/

CREATE OR ALTER PROCEDURE dbo.TransferFundsSafe
    @FromAccountId INT,
    @ToAccountId   INT,
    @Amount        DECIMAL(12,2),
    @DelayBetweenUpdates CHAR(8) = '00:00:00'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FirstLockId  INT = IIF(@FromAccountId < @ToAccountId, @FromAccountId, @ToAccountId);
    DECLARE @SecondLockId INT = IIF(@FromAccountId < @ToAccountId, @ToAccountId, @FromAccountId);

    BEGIN TRANSACTION;

    -- Touch the lower AccountId first no matter which direction the money
    -- is moving. A harmless "no-op" UPDATE (SET Balance = Balance) is
    -- enough to take the X lock in the right order before doing real work.
    UPDATE dbo.Accounts SET Balance = Balance WHERE AccountId = @FirstLockId;

    IF @DelayBetweenUpdates <> '00:00:00'
        WAITFOR DELAY @DelayBetweenUpdates;

    UPDATE dbo.Accounts SET Balance = Balance WHERE AccountId = @SecondLockId;

    UPDATE dbo.Accounts SET Balance = Balance - @Amount WHERE AccountId = @FromAccountId;
    UPDATE dbo.Accounts SET Balance = Balance + @Amount WHERE AccountId = @ToAccountId;

    COMMIT TRANSACTION;
END
GO

-- Re-run Part A's two sessions again, but call TransferFundsSafe instead
-- of TransferFunds. Session 2 now simply waits behind Session 1 for the
-- lock on AccountId 1 -- no cycle, no victim, both transfers commit.
-- Confirm with:
SELECT * FROM dbo.Accounts ORDER BY AccountId;
GO
