---
title: "A CTO's Guide to Evaluating RAG Systems Before You Ship"
description: "Most RAG pilots stall on data readiness, not model quality. Here's the checklist CTOs should run before shipping a retrieval-augmented generation system."
date: 2026-09-05 00:15:00 -0400
categories: [ai-semantics]
tags: [ai-semantics, rag, vector-databases, semantic-search, governance]
image: /assets/images/ctos-guide-to-evaluating-rag-systems-01.png
---

![Diagram of four RAG evaluation checkpoints: retrieval quality, faithfulness, hallucination detection, and production drift](/assets/images/ctos-guide-to-evaluating-rag-systems-01.png)

A retrieval-augmented generation (RAG) system is ready to ship when it passes four separate evaluations, not one: retrieval quality (does it find the right documents), faithfulness (does the answer stick to what it found), hallucination rate (does it invent anything), and drift resilience (does quality hold up after launch day). Most teams evaluate only the last mile -- does the final answer sound right -- and miss the first three, which is exactly where RAG systems actually fail in production.

That gap has real consequences at the executive level. Gartner reported in January 2026 that at least half of generative AI projects were abandoned after proof-of-concept, and pointed directly at RAG as a repeat offender: "poor quality data produces unreliable outputs, failed retrieval augmented generation (RAG) implementations, and models that can't be fine-tuned effectively" ([Gartner, "Why 50% of GenAI Projects Fail — And How to Beat the Odds"](https://www.gartner.com/en/articles/genai-project-failure){:target="_blank" rel="noopener noreferrer"}). MIT Media Lab's Project NANDA found something similar from the other direction: 95% of organizations saw no measurable P&L return on generative AI investment despite tens of billions in enterprise spend, with data readiness and workflow integration -- not the underlying model -- cited as the deciding factor ([MIT NANDA, "The GenAI Divide: State of AI in Business 2025," via Forbes](https://www.forbes.com/sites/jasonsnyder/2025/08/26/mit-finds-95-of-genai-pilots-fail-because-companies-avoid-friction/){:target="_blank" rel="noopener noreferrer"}).

If you're a CTO deciding whether to greenlight a RAG system for production, or a technical lead trying to explain to leadership why "it works in the demo" isn't the same as "it's ready," this is the checklist to run first.

## Key takeaways

- Evaluate retrieval and generation separately -- a wrong answer is usually a retrieval failure wearing a generation costume.
- Track recall@k, precision@k, and NDCG on a held-out set of real queries before you ever look at the generated text.
- Faithfulness and hallucination are distinct failure modes and need distinct tests: one asks "is this supported," the other asks "did it make something up."
- Production RAG quality degrades quietly -- embedding drift, index staleness, and query-distribution shift erode accuracy weeks after launch with no error in your logs.
- Build the evaluation harness before you build the demo. Retrofitting evaluation onto a system already in front of stakeholders is where most of this gets skipped.

## Why "it sounds right" isn't an evaluation

Most RAG demos get judged by a human reading a handful of generated answers and nodding. That's a spot-check, not an evaluation, and it systematically misses the two most common failure patterns: retrieval that quietly returns near-miss documents, and generation that sounds confident regardless of what it was given. A large-language model is a very good writer -- it will produce fluent, well-structured prose whether the underlying retrieval was correct or not. That's precisely why sounding right is the least informative signal you have.

The fix is to stop treating "does the RAG system work" as one question. It's four.

## What changes when you evaluate retrieval on its own?

Before any text is generated, ask only: for a representative set of real user queries, did the system retrieve the passages that actually contain the answer? This is a classic information-retrieval evaluation, and it doesn't require an LLM at all -- you need a labeled set of query/relevant-document pairs, which you can build from support tickets, internal FAQs, or a sample of real usage.

The standard metrics:

- **Recall@k** -- of all the relevant documents that exist, what fraction showed up in the top k results?
- **Precision@k** -- of the top k results returned, what fraction were actually relevant?
- **MRR (Mean Reciprocal Rank)** -- how high up the list was the first relevant result, on average?
- **NDCG (Normalized Discounted Cumulative Gain)** -- a ranking-quality score that rewards relevant documents appearing earlier and penalizes them appearing late.

If retrieval recall is low, no amount of prompt engineering downstream will fix the answers -- the model is working with an incomplete or wrong set of source documents and has no way to know that. This is also where chunking strategy and hybrid search (combining keyword and vector search) tend to have outsized impact; see our companion post on [chunking, hybrid retrieval, and what actually moves the needle](/2026/09/03/rag-in-production-chunking-hybrid-retrieval/) for the mechanics.

## What does "faithfulness" actually test?

Faithfulness (sometimes called groundedness) asks a narrower question than "is the answer correct": is every claim in the generated answer traceable back to something in the retrieved context? A faithful answer can still be incomplete or unhelpful -- but it won't be fabricated.

The common technique is LLM-as-judge: a separate model (often a stronger or differently-tuned one) is given the generated answer alongside the retrieved passages and asked to score whether each claim is supported. This isn't a hand-wavy idea -- it's now a formally benchmarked research area. A May 2025 paper introduced FaithJudge, an LLM-as-judge framework trained on a pool of human-annotated hallucination examples, and used it to power a public, continuously updated leaderboard for RAG faithfulness across summarization, question-answering, and data-to-text tasks ([Benchmarking LLM Faithfulness in RAG with Evolving Leaderboards, EMNLP 2025 Industry Track](https://aclanthology.org/2025.emnlp-industry.54/){:target="_blank" rel="noopener noreferrer"}). If a research community is building competitive leaderboards around measuring this, it's not something a CTO should treat as a nice-to-have.

## Where does hallucination detection fit separately?

Hallucination detection is faithfulness's stricter cousin: it's specifically looking for claims that are not just unsupported by the retrieved context, but actively invented -- a statistic, a name, a policy detail that appears nowhere in your source documents. In regulated or customer-facing settings, this is the failure mode that turns into a support incident or a compliance problem, not just an unhelpful answer. Open-source and commercial evaluation frameworks (RAGAS, TruLens, DeepEval, Arize) all ship dedicated hallucination-detection metrics for exactly this reason -- treat "faithfulness score" and "hallucination rate" as two separate dashboard numbers, not one.

## Why does a RAG system that passed evaluation still degrade in production?

This is the checkpoint teams skip most often, because it doesn't show up until weeks after launch. A few concrete mechanisms:

- **Embedding drift** -- if you swap or fine-tune your embedding model without re-indexing every document, new queries and old documents are no longer in a comparable vector space. We've covered this specific failure mode, including how to catch it before it silently degrades results, in [silent embedding drift in vector search](/2026/08/17/silent-embedding-drift-vector-search/).
- **Index staleness** -- source documents change, but the vector index doesn't get refreshed on the same cadence, so retrieval starts returning outdated answers with full confidence.
- **Query-distribution shift** -- real user queries after launch rarely match the query patterns you tested against. A retrieval system tuned against internal test queries can quietly underperform against how customers actually phrase things.
- **Corpus poisoning** -- for systems that ingest external or user-supplied content into the retrieval corpus, an unvetted or adversarial document can get retrieved and treated as ground truth; see our post on [knowledge base poisoning in vector-store RAG](/2026/08/25/knowledge-base-poisoning-vector-store-rag-database/).

None of these throw an error. They show up as a slow decline in answer quality that's easy to miss unless you're running the same retrieval and faithfulness evaluations on a schedule, not just once before launch.

## The pre-ship checklist

Before a RAG system goes to production, a CTO should be able to answer yes to each of the following, with a number attached, not a vibe:

1. Do we have recall@k and NDCG scores on a labeled set of real queries, and do they meet a defined threshold?
2. Do we have a faithfulness score from an LLM-as-judge or equivalent process, run against a representative sample of generated answers?
3. Do we track hallucination rate as a distinct metric from faithfulness?
4. Is there a recurring (not one-time) evaluation job that re-runs these checks on a schedule, so drift is caught automatically rather than reported by an unhappy user?
5. Is the underlying data -- the documents being retrieved from -- governed with the same rigor as the model? An ungoverned corpus makes every other number on this list unstable.

That last point is really the throughline. RAG evaluation isn't a model-quality problem you can solve with prompt tuning; it's a data-platform problem. The retrieval half of the system is only as good as the metadata, freshness, and access controls on the underlying data it searches -- which is why this maps directly to the Semantic Readiness pillar of a modern data platform, not the AI/ML pillar most teams assume it belongs to. If your team needs help getting the data foundation itself ready for AI workloads, that's exactly where our [services](/services/) start.

*Ivan Lima is a data engineer specializing in database modernization for AI systems. [Get in touch](/about/#contact) if your database needs to be ready for what's next.*
