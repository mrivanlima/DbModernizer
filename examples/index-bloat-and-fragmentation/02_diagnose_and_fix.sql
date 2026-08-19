/*
    02_diagnose_and_fix.sql

    Run this against FragDemo after 01_seed_schema.sql. Walks through:
      1. Reading fragmentation the right way (both logical fragmentation
         AND page density -- not just avg_fragmentation_in_percent alone).
      2. Deciding REORGANIZE vs REBUILD using storage-appropriate thresholds,
         not the stale 5%/30% defaults everyone copy-pastes.
      3. Applying the fix online, with a sane fill factor.
      4. Confirming it actually helped with before/after evidence.
*/

USE FragDemo;
GO

-- ===========================================================================
-- STEP 1: Read fragmentation correctly.
--
-- avg_fragmentation_in_percent measures LOGICAL fragmentation -- how out of
-- order pages are relative to their ideal sequence. On spinning disks this
-- mattered a lot because it turned sequential reads into random ones. On
-- SSD/NVMe storage, random and sequential I/O cost is nearly identical, so
-- this number alone is a weak signal.
--
-- avg_page_space_used_in_percent measures PAGE DENSITY -- how full each page
-- actually is. Low density is the number that costs you: more pages means
-- more buffer pool memory to hold the same data, more pages to read off
-- disk, and larger backups. This is the one worth acting on.
-- ===========================================================================
SELECT
    OBJECT_NAME(ips.object_id)          AS TableName,
    i.name                              AS IndexName,
    ips.avg_fragmentation_in_percent    AS LogicalFragPct,
    ips.avg_page_space_used_in_percent  AS PageDensityPct,
    ips.page_count,
    ips.page_count * 8.0 / 1024         AS SizeMB
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('dbo.Orders'), NULL, NULL, 'SAMPLED') ips
JOIN sys.indexes i ON i.object_id = ips.object_id AND i.index_id = ips.index_id
WHERE ips.index_level = 0   -- leaf level only; upper levels are tiny and noisy
ORDER BY ips.avg_fragmentation_in_percent DESC;

-- Expect IX_Orders_OrderStatus to show high logical fragmentation (the
-- repeated status UPDATEs cause page splits) AND meaningfully reduced page
-- density -- this is the index actually worth rebuilding. The clustered
-- index on OrderId, by contrast, only ever grows at the end (an
-- ever-increasing key), so it should show low fragmentation even without
-- maintenance -- a useful contrast to confirm you're reading the DMV right.

-- ===========================================================================
-- STEP 2: Confirm the cost in practice, not just in the DMV.
-- A scan that has to read more pages than necessary is the actual
-- symptom -- reproduce it before deciding to act.
-- ===========================================================================
SET STATISTICS IO, TIME ON;

SELECT OrderId, CustomerId, OrderTotal
FROM dbo.Orders
WHERE OrderStatus = 'Delivered';

SET STATISTICS IO, TIME OFF;

-- Note the "logical reads" figure for IX_Orders_OrderStatus in the Messages
-- tab -- that's what should drop after the rebuild below.

-- ===========================================================================
-- STEP 3: Apply the fix.
--
-- Thresholds here use the storage-aware guidance many practitioners have
-- converged on for modern SSD/NVMe-backed instances, rather than the
-- Microsoft-documented 5%/30% defaults everyone's maintenance script still
-- ships with: REORGANIZE at 10-30% logical fragmentation, REBUILD above
-- 30%, and always cross-check against page density before bothering.
-- If you're still on spinning disks, use the older 5%/30% split instead --
-- the physical cost of out-of-order pages is real there.
--
-- ONLINE = ON (Enterprise/Azure SQL) avoids blocking readers/writers during
-- the rebuild -- essential for a table this size on a live system.
-- FILLFACTOR = 90 leaves 10% free space per page on purpose, so the next
-- round of status-value UPDATEs has room to land without triggering an
-- immediate page split -- fixing today's fragmentation without guaranteeing
-- tomorrow's.
-- ===========================================================================
ALTER INDEX IX_Orders_OrderStatus ON dbo.Orders
REBUILD WITH (ONLINE = ON, FILLFACTOR = 90, MAXDOP = 0);
GO

-- ===========================================================================
-- STEP 4: Confirm it actually helped.
-- ===========================================================================
SELECT
    OBJECT_NAME(ips.object_id)          AS TableName,
    i.name                              AS IndexName,
    ips.avg_fragmentation_in_percent    AS LogicalFragPct,
    ips.avg_page_space_used_in_percent  AS PageDensityPct,
    ips.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('dbo.Orders'), NULL, NULL, 'SAMPLED') ips
JOIN sys.indexes i ON i.object_id = ips.object_id AND i.index_id = ips.index_id
WHERE i.name = 'IX_Orders_OrderStatus' AND ips.index_level = 0;

SET STATISTICS IO, TIME ON;

SELECT OrderId, CustomerId, OrderTotal
FROM dbo.Orders
WHERE OrderStatus = 'Delivered';

SET STATISTICS IO, TIME OFF;

-- Expect: LogicalFragPct near 0, PageDensityPct near 90 (matching the fill
-- factor), page_count reduced, and logical reads for the same query lower
-- than the STEP 2 baseline -- fewer, fuller pages to scan.

-- ===========================================================================
-- For comparison: REORGANIZE instead of REBUILD.
-- Reorganize is always online, doesn't update statistics (do that
-- separately), and works incrementally in place -- appropriate for the
-- 10-30% band, or when you can't take the (usually brief) extra resource
-- cost of a rebuild during business hours even with ONLINE = ON.
-- ===========================================================================
-- ALTER INDEX IX_Orders_OrderStatus ON dbo.Orders REORGANIZE;
-- UPDATE STATISTICS dbo.Orders IX_Orders_OrderStatus;
GO
