/*
    02_reproduce_and_fix.sql
    Reproduces the classic N+1 pattern (1 query for authors + N queries
    for each author's posts), shows the query count/read cost, then fixes
    it with a single set-based JOIN query, with before/after evidence.

    Run against NPlus1Demo (created by 01_seed_schema.sql).
*/

USE NPlus1Demo;
GO

-- =========================================================================
-- STEP 1: The problem, reproduced at the SQL level.
--
-- An ORM's "lazy loading" of a to-many relationship (e.g. author.Posts in
-- Entity Framework, or a naive loop calling repo.GetPostsByAuthor(id) per
-- row) generates exactly this shape: one query to fetch the "one" side,
-- then one additional round trip per row to fetch the "many" side.
--
-- Simulating the ORM's actual round trips: first the "get all authors"
-- query, then a separate query per author for their posts. This block
-- issues 501 total statements against a 500-row driving table.
-- =========================================================================

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- Query 1: "SELECT * FROM Authors" — this is what an ORM issues first.
SELECT AuthorId, AuthorName, Email FROM dbo.Authors;

-- Queries 2..501: one per author, exactly what lazy-loading a
-- navigation property generates. In application code this is a loop:
--   foreach (var author in authors) { var posts = author.Posts; }
-- Here we simulate a handful to show the shape and per-call cost;
-- in the real app this runs once per every one of the 500 authors.
SELECT PostId, Title, PublishedAt FROM dbo.Posts WHERE AuthorId = 1;
SELECT PostId, Title, PublishedAt FROM dbo.Posts WHERE AuthorId = 2;
SELECT PostId, Title, PublishedAt FROM dbo.Posts WHERE AuthorId = 3;
SELECT PostId, Title, PublishedAt FROM dbo.Posts WHERE AuthorId = 4;
SELECT PostId, Title, PublishedAt FROM dbo.Posts WHERE AuthorId = 5;

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- Each of the per-author SELECTs above is cheap in isolation (a handful of
-- logical reads via the IX_Posts_AuthorId seek) — that's exactly what makes
-- this pattern easy to miss in code review. The cost isn't in any one query,
-- it's in issuing 500 of them: 500 round trips, 500x network latency, 500x
-- query-compilation/plan-cache lookups, and 500x whatever connection-pool
-- and TDS-protocol overhead your driver adds per call. On a network with
-- even 2ms round-trip latency, that's a full second of pure waiting before
-- a single row of application logic runs — and it gets worse under load
-- because every one of those 500 statements competes for a pooled connection.

-- =========================================================================
-- STEP 2: Confirm it from the DMVs — this is what makes the diagnosis
-- objective rather than a guess. Look for a very high execution_count on
-- near-identical query text, which is the fingerprint of N+1 (as opposed
-- to a single query that's slow for its own reasons).
-- =========================================================================

SELECT TOP 20
    qs.execution_count,
    qs.total_logical_reads,
    qs.total_elapsed_time / 1000.0 AS total_elapsed_ms,
    SUBSTRING(st.text, (qs.statement_start_offset/2) + 1,
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE qs.statement_end_offset END
            - qs.statement_start_offset)/2) + 1) AS query_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE st.text LIKE '%FROM dbo.Posts WHERE AuthorId%'
ORDER BY qs.execution_count DESC;
GO
-- A high execution_count (hundreds, matching your driving-table row count)
-- on a parameterized single-row lookup is the N+1 fingerprint. Compare that
-- against total_elapsed_time: the per-call cost looks trivial, but summed
-- across execution_count it's often the single largest time sink tied to a
-- page load, dwarfing every other query on that request.

-- =========================================================================
-- STEP 3: The expert fix — collapse N+1 round trips into one set-based
-- query. This is what the ORM should be told to do explicitly (eager
-- loading: .Include() in EF Core, joinedload() in SQLAlchemy, JOIN FETCH
-- in JPA/Hibernate) instead of touching the navigation property lazily
-- inside a loop.
-- =========================================================================

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT
    a.AuthorId,
    a.AuthorName,
    a.Email,
    p.PostId,
    p.Title,
    p.PublishedAt
FROM dbo.Authors a
LEFT JOIN dbo.Posts p ON p.AuthorId = a.AuthorId
ORDER BY a.AuthorId;

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- Before/after evidence to look for:
--   Before: 501 separate statements, 501 round trips, 501 plan-cache
--           lookups, cumulative elapsed time dominated by network latency.
--   After:  1 statement, 1 round trip, 1 execution plan (typically a
--           Clustered Index Scan on Authors + Index Seek on
--           IX_Posts_AuthorId in a Nested Loops or Hash Match join),
--           logical reads roughly equal to the sum of what the 501
--           queries did individually, but paid once instead of 501 times.
-- The row count returned is larger (one row per post, authors with no
-- posts appear once via the LEFT JOIN with NULL post columns) — that's
-- expected and is why application code groups the flat result back into
-- author -> [posts] shape client-side, which is exactly what ORMs do
-- internally when you use eager loading instead of lazy loading.
