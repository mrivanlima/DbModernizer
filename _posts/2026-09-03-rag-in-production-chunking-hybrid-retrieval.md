---
title: "RAG in Production: Chunking, Hybrid Retrieval, and What Actually Moves the Needle"
description: "In production RAG, retrieval causes 73% of failures, not generation. Here's what actually improves accuracy: chunking strategy, hybrid search, and reranking."
date: 2026-09-03 01:30:00 -0400
categories: [ai-semantics]
tags: [vector-databases, rag, ai-semantics, semantic-search, performance-engineering]
image: /assets/images/rag-in-production-chunking-hybrid-retrieval-01.png
---

![Diagram of a production RAG pipeline showing chunking, hybrid retrieval combining BM25 and vector search, and reranking before the LLM](/assets/images/rag-in-production-chunking-hybrid-retrieval-01.png)

When a retrieval-augmented generation system gives a wrong or incomplete answer, the instinct is to blame the model. The data says otherwise: industry analysis of production RAG failures in 2026 consistently finds that retrieval is the point of failure roughly 73% of the time, not generation ([Firecrawl, "Best Chunking Strategies for RAG (and LLMs) in 2026"](https://www.firecrawl.dev/blog/best-chunking-strategies-rag){:target="_blank" rel="noopener noreferrer"}). The model answered correctly given what it was handed -- it just wasn't handed the right passages. If you're troubleshooting a RAG system's accuracy, the highest-leverage place to look first is almost never the prompt or the LLM choice. It's chunking, retrieval, and reranking.

That reframing matters because most teams still spend their tuning budget on the wrong end of the pipeline. This post covers the three levers that actually move production RAG accuracy, in the order they compound: how you chunk, how you retrieve, and whether you rerank before generation.

## Key takeaways

- Retrieval, not generation, causes the majority of RAG failures in production -- fix chunking and retrieval before touching the prompt or the model.
- Recursive chunking at 300-500 tokens with 10-20% overlap is a strong, cheap baseline; semantic chunking earns its extra cost mainly on long or structurally loose documents.
- Hybrid retrieval (BM25 keyword search plus dense vector search) reliably beats either method alone -- a tuned hybrid setup posted a 7.4% NDCG lift over pure vector or pure keyword search on a public benchmark.
- Reranking is still worth the extra hop: independent and vendor-reported gains range from high single digits to +28% NDCG@10 depending on the reranker and dataset.
- A baseline RAG system without these techniques answers roughly 44% of factual questions correctly; well-tuned systems reach into the low-to-mid 60s -- there's real headroom left in most production deployments.

## Why "just add more context" doesn't fix it

A common response to bad RAG answers is to widen the retrieval window -- pull more chunks, use a bigger context window, let the model sort it out. This has a ceiling. A January 2026 systematic analysis identified what researchers are calling a "context cliff": response quality drops sharply once retrieved context passes roughly 2,500 tokens, regardless of how much more relevant material is technically available in that window ([Firecrawl, 2026](https://www.firecrawl.dev/blog/best-chunking-strategies-rag){:target="_blank" rel="noopener noreferrer"}). More context isn't free -- it's a tradeoff against the model's ability to actually use what it's given. That's what makes chunking and retrieval quality the real bottleneck instead of context budget: the goal isn't retrieving more, it's retrieving the right handful of passages.

## What chunking strategy actually works?

Start with recursive character splitting at 300-500 tokens with 10-20% overlap. That baseline is unglamorous, cheap to compute, and, per the same 2026 analysis, sentence-level chunking matched more expensive semantic chunking approaches up to roughly 5,000 tokens of source material at a fraction of the compute cost. Semantic chunking -- splitting on embedding-detected topic boundaries rather than fixed token counts -- does earn its keep on specific document types: long-form technical documentation, legal contracts, or anything with loose paragraph structure where fixed-size splitting routinely cuts a claim away from its qualifying clause. One published comparison found semantic chunking lifting retrieval accuracy to roughly 71% versus a fixed-size baseline on the same dataset -- a meaningful gain, but one worth validating against your own corpus before paying the extra indexing cost everywhere.

The practical rule: default to recursive chunking, and reserve semantic chunking for document types where you can show it earns its cost on your own eval set, not because it's the newer technique.

## Why hybrid retrieval beats vector search alone

Pure vector search misses exact-match signal that keyword search catches for free -- product SKUs, error codes, proper nouns, acronyms -- because semantic similarity can rank a paraphrase above an exact term match. Pure keyword search misses the paraphrases and synonyms that vector search is built for. Hybrid retrieval, which combines BM25 keyword scoring with dense vector similarity and merges the results, is now the default architecture for production RAG for exactly this reason.

The gains are measurable, not just theoretical. On the WANDS e-commerce search benchmark, a tuned hybrid configuration reached 0.7497 NDCG, a 7.4% improvement over BM25 alone (0.6983) and pure vector search alone (0.6953) ([Denser.ai, "Hybrid Search for RAG," 2026](https://denser.ai/blog/hybrid-search-for-rag/){:target="_blank" rel="noopener noreferrer"}). In more demanding domains -- financial documents mixing narrative text and tables -- a two-stage hybrid-plus-neural-reranking pipeline reached Recall@5 of 0.816, a level neither method alone gets close to on its own. If your retrieval layer is still vector-only, hybrid search is very likely the single highest-return architectural change available before you touch anything downstream.

## Does reranking still earn its latency cost?

Reranking adds a hop: retrieve a wider candidate set cheaply (via hybrid search), then re-score that shortlist with a more expensive, more accurate model before it reaches the LLM. The question worth asking honestly is whether that extra latency is worth it in 2026, given how much retrieval quality has already improved. The evidence says yes, with real spread between rerankers. ZeroEntropy reports its zerank-1 model delivering up to +28% NDCG@10 over baseline retrievers, correlating with measurably lower downstream hallucination rates ([ZeroEntropy, "Ultimate Guide to Choosing the Best Reranking Model," 2026](https://zeroentropy.dev/articles/ultimate-guide-to-choosing-the-best-reranking-model-in-2025/){:target="_blank" rel="noopener noreferrer"}). Voyage AI reports roughly +7.94% accuracy over Cohere's Rerank v3.5 across 93 evaluation datasets -- a vendor-stated figure worth validating independently rather than taking at face value, but directionally consistent with the pattern that reranking materially improves what actually reaches generation.

The newest capability worth watching is instruction-following reranking: Voyage's rerank-2.5, released in August 2025, lets you prepend a natural-language instruction to steer what "relevant" means for a given query type, rather than relying purely on learned similarity ([ZeroEntropy, 2026](https://zeroentropy.dev/articles/ultimate-guide-to-choosing-the-best-reranking-model-in-2025/){:target="_blank" rel="noopener noreferrer"}). For domains where relevance is context-dependent -- support tickets versus product documentation versus legal text -- that's a meaningfully different tool than a fixed similarity score.

## The measurable gap between naive and tuned RAG

It's worth putting a number on what all of this is worth. Benchmark literature on hybrid retrieval pipelines finds that straightforward retrieval without chunking, hybrid search, or reranking answers only about 44% of factual questions correctly, while well-tuned production RAG systems reach roughly 63% ([arXiv:2604.01733, "From BM25 to Corrective RAG: Benchmarking Retrieval," 2026](https://arxiv.org/pdf/2604.01733){:target="_blank" rel="noopener noreferrer"}). That's not a marginal tuning gain -- it's the difference between a system users trust and one they route around. This same gap shows up in the semantic readiness data covered in [Is Your Database AI-Ready?](/blog/2026/08/12/is-your-database-ai-ready/), where only a small fraction of enterprises report data that's genuinely prepared for AI workloads: retrieval tuning is one of the concrete, high-leverage places to close that gap once the underlying data platform is sound.

None of this matters, of course, if the index underneath it is quietly corrupted. If you're tuning chunking and retrieval on top of a vector store that's mixing vectors from two different embedding model versions, you're optimizing against noise -- see [Semantic Rot: When Embedding Upgrades Break Vector Search](/blog/2026/08/17/silent-embedding-drift-vector-search/) for how that happens silently. And if you're deciding where to run the index in the first place, [pgvector vs. Purpose-Built Vector Databases](/blog/2026/08/20/pgvector-vs-purpose-built-vector-databases/) covers the tradeoffs at different scales.

## A practical production checklist

1. **Baseline first.** Start with recursive chunking at 300-500 tokens, 10-20% overlap. Don't reach for semantic chunking until you've measured that it beats the baseline on your own corpus.
2. **Add hybrid retrieval before anything else.** BM25 plus vector search, merged, is the single change most likely to produce a measurable accuracy gain for the least engineering effort.
3. **Rerank the shortlist, not the whole corpus.** Retrieve wide and cheap with hybrid search, then rerank the top 20-50 candidates with a dedicated reranker before they reach the LLM.
4. **Watch the context cliff.** More retrieved context isn't automatically better once you're past roughly 2,500 tokens -- tighten retrieval precision instead of widening the window.
5. **Build a labeled eval set and measure every change against it.** Every stat in this post came from someone running exactly this kind of controlled comparison -- without one, you're tuning by intuition.
6. **Confirm the index itself is trustworthy before optimizing on top of it.** Mixed embedding model versions, poisoned entries, or stale content will undermine every retrieval technique above.

## Where this leaves you

Chunking, hybrid retrieval, and reranking aren't exotic techniques anymore -- they're the baseline for a production RAG system in 2026, and skipping any of them is very likely costing you retrieval accuracy you could get back with a few weeks of focused work. If you're evaluating whether your data platform is ready to support this kind of system reliably at scale, that's the kind of assessment we do. [Get in touch](/about/#contact) or see how we approach [database and data platform modernization](/services/) for AI workloads.

---

*Ivan Lima is a data engineer specializing in database modernization for AI systems. [Get in touch](/about/#contact) if your database needs to be ready for what's next.*
