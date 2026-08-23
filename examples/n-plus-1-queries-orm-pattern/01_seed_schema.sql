/*
    01_seed_schema.sql
    Creates NPlus1Demo and seeds a Blog/Post/Author schema sized so the
    N+1 pattern is obvious: 500 authors, 5,000 posts (10 posts/author avg).

    Run against a scratch/test SQL Server instance. Do NOT run in production.
*/

IF DB_ID('NPlus1Demo') IS NOT NULL
BEGIN
    ALTER DATABASE NPlus1Demo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE NPlus1Demo;
END
GO

CREATE DATABASE NPlus1Demo;
GO

USE NPlus1Demo;
GO

CREATE TABLE dbo.Authors
(
    AuthorId    INT IDENTITY(1,1) PRIMARY KEY,
    AuthorName  NVARCHAR(100) NOT NULL,
    Email       NVARCHAR(200) NOT NULL
);
GO

CREATE TABLE dbo.Posts
(
    PostId      INT IDENTITY(1,1) PRIMARY KEY,
    AuthorId    INT NOT NULL REFERENCES dbo.Authors(AuthorId),
    Title       NVARCHAR(200) NOT NULL,
    PublishedAt DATETIME2 NOT NULL,
    Body        NVARCHAR(MAX) NOT NULL
);
GO

CREATE INDEX IX_Posts_AuthorId ON dbo.Posts(AuthorId);
GO

-- Seed 500 authors
;WITH n AS (
    SELECT TOP (500) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.Authors (AuthorName, Email)
SELECT 'Author ' + CAST(rn AS VARCHAR(10)),
       'author' + CAST(rn AS VARCHAR(10)) + '@example.com'
FROM n;
GO

-- Seed ~5,000 posts, spread across authors (5-15 posts each)
;WITH n AS (
    SELECT TOP (5000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.Posts (AuthorId, Title, PublishedAt, Body)
SELECT (rn % 500) + 1,
       'Post title ' + CAST(rn AS VARCHAR(10)),
       DATEADD(DAY, -(rn % 365), SYSDATETIME()),
       REPLICATE('Sample post body content. ', 20)
FROM n;
GO

PRINT 'Seed complete: ' + CAST((SELECT COUNT(*) FROM dbo.Authors) AS VARCHAR(10)) + ' authors, ' +
      CAST((SELECT COUNT(*) FROM dbo.Posts) AS VARCHAR(10)) + ' posts.';
GO
