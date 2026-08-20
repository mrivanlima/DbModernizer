---
title: "pgvector vs. Purpose-Built Vector Databases: A 2026 Decision Framework"
description: "pgvector wins on cost and simplicity under roughly 10-50 million vectors if you're already on Postgres; past that, purpose-built databases pull ahead on throughput and ops."
date: 2026-08-20 01:15:00 -0400
categories: [vector-databases]
tags: [vector-databases, pgvector, cost-efficiency, rag, performance-engineering]
image: /assets/images/pgvector-vs-purpose-built-vector-databases-01.png
---

![Decision framework diagram comparing pgvector and purpose-built vector databases across vector count, query volume, and operational complexity](/assets/images/pgvector-vs-purpose-built-vector-databases-01.png)

Use pgvector if you're already running Postgres and your workload stays under roughly 10 to 50 million vectors with moderate query volume -- it's cheaper, it's one less system to operate, and 2026 benchmarks show it's no longer the performance compromise it used to be. Reach for a purpose-built vector database like Qdrant, Milvus, or Pinecone once you're past that range, need sub-10ms p95 latency at high query-per-second rates, or require advanced filtering and multi-tenant isolation that a general-purpose relational engine wasn't built for. The rest of this post is the reasoning behind that line, and where it actually sits for your workload.

## Why this decision keeps coming up

Every team adding retrieval-augmented generation, semantic search, or a recommendation feature to an existing product hits the same fork: bolt vector search onto the Postgres database that's already running production traffic, or stand up a dedicated vector database next to it. Two years ago the answer leaned heavily toward "dedicated" -- pgvector's HNSW implementation was new, slow to build, and fell over past a few million rows. That's no longer the full picture, and treating it as settled either way costs teams real money and real latency.

## What changed: pgvector closed the performance gap

The biggest shift is pgvectorscale, Timescale's extension that adds StreamingDiskANN indexing and statistical binary quantization on top of pgvector. In Timescale's own benchmark, Postgres with pgvectorscale hit 471 queries per second at 99% recall against 50 million vectors, versus 41.47 QPS for Qdrant on the same hardware -- an 11.4x throughput advantage, with 28x lower p95 latency than Pinecone's storage-optimized index at matching recall ([Tiger Data, "pgvector vs. Qdrant"](https://www.tigerdata.com/blog/pgvector-vs-qdrant){:target="_blank" rel="noopener noreferrer"}). That's a vendor-run benchmark -- Timescale built pgvectorscale and published the numbers -- so treat the magnitude with appropriate skepticism, but the direction is consistent with what other teams have independently reported: the raw performance gap that used to make "just use a real vector database" the safe default answer has mostly closed for mid-scale workloads.

Binary quantization is doing a lot of that work. AWS's own guidance for Aurora PostgreSQL shows the same pattern: quantizing vectors to binary representations cuts memory footprint dramatically and keeps HNSW's RAM ceiling from becoming the limiting factor as dataset size grows ([AWS Database Blog](https://aws.amazon.com/blogs/database/scale-pgvector-with-binary-quantization-on-amazon-aurora-postgresql/){:target="_blank" rel="noopener noreferrer"}). Without quantization, HNSW keeps the full graph in memory, and that's the mechanism behind most "pgvector fell over" stories from 2024.

## Where pgvector still runs out of road

None of that erases pgvector's real ceiling. Each `vector(1536)` value takes roughly 6KB on disk before row overhead and index cost, so 100 million rows of raw vector storage alone exceeds 600GB before you've built an index against it ([ParadeDB, "pgvector Limitations"](https://www.paradedb.com/learn/postgresql/pgvector-limitations){:target="_blank" rel="noopener noreferrer"}). pgvector also only supports HNSW and IVFFlat as index types -- IVFFlat builds fast but degrades as the dataset grows, and HNSW gives good recall but has long build times and high memory demand during construction. Single-table PostgreSQL limits (32TB per table, TOAST object size ceilings) mean billion-vector deployments need partitioning strategies that most teams aren't set up to maintain. And critically, none of pgvector's scaling techniques change the fact that it's still bound by Postgres's general-purpose query planner and storage engine -- it was never rebuilt from the ground up around approximate nearest-neighbor search the way Qdrant's Rust engine or Milvus's distributed architecture were.

If you're already tuning [HNSW and IVFFlat indexes](/2026/08/18/indexing-for-ai-workloads/) on a relational workload, you've likely felt this tension firsthand: the index type that gives you the best recall is also the one most likely to blow past your `maintenance_work_mem` budget during a rebuild.

## Key takeaways

- **Under ~10M vectors, on Postgres already:** pgvector wins on cost and operational simplicity -- no new system, no new failure mode to monitor.
- **10M-50M vectors, with pgvectorscale/quantization tuning:** pgvector is now genuinely competitive on throughput, not just "good enough."
- **Past 50M-100M vectors, or high sustained QPS:** purpose-built databases pull ahead, and self-hosting one becomes cost-justified once a managed option like Pinecone would otherwise run well past $5,000/month at that scale.
- **Advanced filtering, hybrid search, or strict multi-tenant isolation:** purpose-built engines like Qdrant were designed around these patterns; pgvector supports them but with more manual query engineering.
- **The index type matters as much as the database:** IVFFlat vs. HNSW vs. DiskANN changes build time, memory ceiling, and recall independently of which database holds them.

## What actually drives the cost line

The economics flip at a predictable point. A team already paying for Postgres gets pgvector close to free at low scale -- no new infrastructure bill, no new operational surface. But HNSW's memory requirements scale with vector count, and once a workload needs a large, RAM-heavy instance just to hold the index, the "database you already run" line item quietly turns into a dedicated, expensive machine anyway. At that point the comparison isn't "free vs. paid," it's "one expensive Postgres instance vs. one purpose-built system" -- and the purpose-built system usually wins on throughput per dollar once you're actually paying real infrastructure cost either way.

This is also where embedding hygiene starts to matter more, not less. A system carrying tens of millions of vectors across a partitioned, quantized index is much harder to audit for [drift when embedding models change underneath it](/2026/08/17/silent-embedding-drift-vector-search/) than a small, single-table pgvector setup -- scale amplifies the blast radius of a silent re-embedding mistake.

## The actual decision framework

Ask four questions, in this order: How many vectors, today and in 18 months? What's the sustained query volume, not the peak demo number? Does the workload need hybrid search, complex metadata filtering, or hard multi-tenant isolation? And is there already a team that owns Postgres operations, or would a vector database be the first new piece of infrastructure this team has run? Most teams answering honestly land on pgvector for anything under 10-20 million vectors with a Postgres-literate team already in place, and shift the calculus toward a purpose-built system only when the vector count, query volume, or filtering complexity genuinely outgrows what a well-tuned Postgres extension can carry.

If you're mid-migration and unsure which side of that line your workload actually sits on, [get in touch](/services/) -- this is exactly the kind of tradeoff that's cheap to model before committing infrastructure spend to it.

*Ivan Lima is a data engineer specializing in database modernization for AI systems. [Get in touch](/about/#contact) if your database needs to be ready for what's next.*
