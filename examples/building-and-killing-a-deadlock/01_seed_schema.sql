/*
    01_seed_schema.sql
    Companion code for "Building and Killing a Deadlock With Your Own Hands"
    https://dataplatformadvisory.com/blog/2026/08/15/building-and-killing-a-deadlock/

    Creates a small DeadlockDemo database with an Accounts table and a
    TransferFunds procedure, seeded with just enough data to reproduce a
    classic write-write deadlock between two concurrent transfers.

    Run this against a SCRATCH / TEST instance only.
*/

SET NOCOUNT ON;
GO

IF DB_ID('DeadlockDemo') IS NOT NULL
BEGIN
    ALTER DATABASE DeadlockDemo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE DeadlockDemo;
END
GO

CREATE DATABASE DeadlockDemo;
GO

ALTER DATABASE DeadlockDemo SET READ_COMMITTED_SNAPSHOT OFF;
GO

USE DeadlockDemo;
GO

CREATE TABLE dbo.Accounts
(
    AccountId   INT           NOT NULL PRIMARY KEY CLUSTERED,
    AccountName VARCHAR(50)   NOT NULL,
    Balance     DECIMAL(12,2) NOT NULL
);
GO

INSERT INTO dbo.Accounts (AccountId, AccountName, Balance)
VALUES
    (1, 'Checking - Alice', 5000.00),
    (2, 'Savings  - Alice',10000.00),
    (3, 'Checking - Bob',    2500.00),
    (4, 'Savings  - Bob',    7500.00);
GO

-- Deliberately naive: updates the "from" account first, then the "to"
-- account, in whatever order the caller passes the account IDs. This is
-- the root cause of the deadlock in this example -- see the blog post.
CREATE OR ALTER PROCEDURE dbo.TransferFunds
    @FromAccountId INT,
    @ToAccountId   INT,
    @Amount        DECIMAL(12,2),
    @DelayBetweenUpdates CHAR(8) = '00:00:00'  -- lets us widen the race window on demand
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;

    UPDATE dbo.Accounts
        SET Balance = Balance - @Amount
        WHERE AccountId = @FromAccountId;

    IF @DelayBetweenUpdates <> '00:00:00'
        WAITFOR DELAY @DelayBetweenUpdates;

    UPDATE dbo.Accounts
        SET Balance = Balance + @Amount
        WHERE AccountId = @ToAccountId;

    COMMIT TRANSACTION;
END
GO

PRINT 'DeadlockDemo database ready.';
