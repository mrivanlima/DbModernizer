---
title: "Performance Tuning for Hybrid Search: Vector vs. Keyword Resource Contention"
description: "Vector and keyword retrieval share CPU, buffer cache, and connection pools inside one database -- tune them separately or one starves the other's latency."
date: 2026-09-07 01:30:00 -0400
categories: [performance]
tags: [performance-engineering, vector-databases, hybrid-search, rag, indexing]
image: /assets/images/performance-tuning-for-hybrid-search-01.png
---

![Diagram showing HNSW vector search and BM25 keyword search competing for shared CPU, buffer cache, and connection pool resources before merging via reciprocal rank fusion](/assets/images/performance-tuning-for-hybrid-search-01.png)

Hybrid search runs vector similarity and keyword (BM25) retrieval as two separate queries against the same database, then merges the results -- and that's exactly where its performance problems start. Dense-only retrieval hits roughly 78% recall@10 and sparse-only BM25 lands around 65%, but hybrid search reaches 91% recall@10, which is why most production retrieval-augmented generation (RAG) systems have converged on it ([Digital Applied, "Hybrid Search: BM25, Vector & Reranking Reference 2026"](https://www.digitalapplied.com/blog/hybrid-search-bm25-vector-reranking-reference-2026){:target="_blank" rel="noopener noreferrer"}). What the accuracy numbers don't show is that both retrieval paths draw from the same CPU, buffer cache, and connection pool -- and a burst on one side degrades the other's latency in ways that are easy to miss in a benchmark and expensive to discover in production.

## Why hybrid search creates contention that single-mode search doesn't

A pure vector search or a pure keyword search has one resource profile to manage. Hybrid search has two, running concurrently, inside the same instance. The vector path -- typically an HNSW index -- traverses a multilayer graph that's ideally RAM-resident; once past 5-10 million vectors you're effectively sizing your Postgres instance around the index, and past 100 million vectors the working set stops fitting in memory and query latency climbs ([ParadeDB, "pgvector Limitations"](https://www.paradedb.com/learn/postgresql/pgvector-limitations){:target="_blank" rel="noopener noreferrer"}). The keyword path scans an inverted index (tsvector, or a dedicated BM25 extension like pg_search) and leans more on disk I/O and parallel workers.

Those are different access patterns competing for the same finite pool of shared_buffers, CPU cores, and connection slots. Vector workloads share CPU, memory, and I/O with the rest of your Postgres traffic, and a burst of vector queries can starve transactional or keyword queries of buffer cache and parallel workers -- the reverse is equally true. If you've tuned [HNSW and IVFFlat indexes](/2026/08/18/indexing-for-ai-workloads/) in isolation, this is the failure mode that only shows up once you put both retrieval paths in the same query path under real concurrent load.

## Key takeaways

- **Hybrid search's accuracy gain doesn't come free** -- 91% recall@10 versus 78-65% for single-mode retrieval requires running two resource-hungry queries per request, not one.
- **HNSW and BM25 have different resource profiles** -- vector search is memory- and CPU-bound on graph traversal; keyword search is I/O- and worker-bound on inverted index scans.
- **Contention shows up under concurrency, not in isolated benchmarks** -- test both retrievers running simultaneously at realistic QPS, not sequentially.
- **Reciprocal Rank Fusion (RRF) is cheap; the two retrievals feeding it aren't** -- RRF itself is just addition across a few hundred already-ranked candidates, so the latency budget is spent almost entirely upstream.
- **Connection pooling and parallel worker limits need separate tuning per retriever** -- a shared, untuned pool lets either retrieval path starve the other during a traffic spike.

## Where the latency budget actually goes

Reciprocal Rank Fusion, the standard way to merge vector and keyword result sets, is deliberately cheap: it ignores raw similarity or BM25 scores (which sit on incompatible scales) and ranks purely by each result's position in its own list. RRF is just addition across a few dozen or a few hundred already-retrieved candidates -- no model inference, no index lookups, nothing that scales with corpus size ([Redis, "Reciprocal Rank Fusion: How Hybrid Search Really Works"](https://redis.io/blog/reciprocal-rank-fusion/){:target="_blank" rel="noopener noreferrer"}). That means fusion is never your bottleneck. The two retrievals feeding it are, and the standard advice to run them in parallel so total latency tracks the slower retriever, not the sum of both, only helps if neither retriever is starving the other for the CPU and memory it needs to hit its own target.

This is also why isolated benchmarks mislead teams here. A vector index that returns in 8ms and a BM25 query that returns in 12ms look fine measured one at a time. Run 200 of each concurrently against the same instance, and both numbers move -- often nonlinearly -- because they're now fighting over shared_buffers, the same fixed set of CPU cores, and a connection pool that wasn't sized with two retrieval paths in mind.

## Practical tuning moves

Start by separating what you can. If your platform supports it, route vector and keyword queries through separate connection pool limits (PgBouncer pool sizing per query type, or equivalent) so a burst on one path can't fully starve the pool the other path needs. Cap parallel workers per query type explicitly rather than letting Postgres's planner allocate them dynamically under load -- unbounded parallel workers on either retriever is a common way one query type crowds out the other during a spike.

On the vector side, keep HNSW's `m` parameter at its default (16) unless recall@10 plateaus below what your queries need -- bumping it inflates index size, and therefore memory pressure, faster than it improves recall. If you're pushing past the point where the HNSW graph comfortably fits in shared_buffers, binary quantization or a tool like pgvectorscale reduces the memory footprint that's driving contention with the keyword path in the first place, the same mechanism covered in [pgvector vs. purpose-built vector databases](/2026/08/20/pgvector-vs-purpose-built-vector-databases/).

On the keyword side, make sure your inverted index actually fits the read pattern -- a stale text index behaves like the fragmented indexes covered in [our index bloat deep dive](/2026/08/19/index-bloat-and-fragmentation/), just for text instead of numeric columns. Finally, load-test both retrieval paths concurrently, at the QPS you actually expect, before trusting any single-path benchmark number your vendor published.

## What this means for teams evaluating RAG infrastructure

If your retrieval pipeline is still growing -- more documents, more concurrent users, more query volume -- the resource contention described here compounds. It's the kind of problem that's invisible in a proof-of-concept with a handful of test queries and very visible three months into production when both retrieval paths are under real load simultaneously. Planning for that concurrency now, rather than after a latency regression in production, is cheaper by an order of magnitude. If you're building out the retrieval layer for a [RAG system](/2026/09/03/rag-in-production-chunking-hybrid-retrieval/) and want a second set of eyes on where contention is likely to show up in your specific architecture, [get in touch](/about/#contact).

*Ivan Lima is a data engineer specializing in database modernization for AI systems. [Get in touch](/about/#contact) if your database needs to be ready for what's next.*
