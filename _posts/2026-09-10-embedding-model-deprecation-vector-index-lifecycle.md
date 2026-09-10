---
title: "Your Embedding Model Has an Expiration Date. Do You Know It?"
description: "Vendors retire embedding models on fixed, published schedules, but most vector databases have no lifecycle plan for when the model behind them disappears."
date: 2026-09-10 03:40:00 -0400
categories: [ai-semantics]
tags: [vector-databases, embeddings, rag, vendor-lifecycle, future-outlook]
image: /assets/images/embedding-model-deprecation-vector-index-lifecycle-01.png
---

![Your Embedding Model Has an Expiration Date. Do You Know It?](/assets/images/embedding-model-deprecation-vector-index-lifecycle-01.png)

Every embedding model your vector database depends on is on a retirement clock, set by a vendor you don't control, and most teams don't find out the clock is running until they get a deprecation email with a shutdown date already on it. This isn't the accidental, silent version of embedding drift — it's a scheduled, announced, entirely predictable event that organizations routinely treat as a surprise anyway, because nobody owns embedding model lifecycle the way they'd own a database version upgrade.

## What's actually happening

Embedding providers retire models the same way they retire any other API-served model: with a deprecation notice, a shutdown date, and an expectation that customers migrate before the cutoff. Cohere has already shut down `embed-english-v2.0`, `embed-english-light-v2.0`, and `embed-multilingual-v2.0` on a scheduled retirement date of April 4, 2026, pushing customers toward its v3/v4 embedding line ([Cohere Deprecations](https://docs.cohere.com/docs/deprecations){:target="_blank" rel="noopener noreferrer"}). Google has moved its legacy `text-embedding-004` and `text-embedding-005` models into deprecation in favor of the newer `gemini-embedding-001` family. OpenAI publishes a standing policy of giving at least six months' notice before retiring a generally available model, notifying active users by email and listing every deprecation on a public page ([OpenAI Deprecations](https://developers.openai.com/api/docs/deprecations){:target="_blank" rel="noopener noreferrer"}).

The pattern across every major provider is the same: the model that produced every vector currently sitting in your index is not guaranteed to exist indefinitely. It has a lifecycle stage — generally available, deprecated, retired — and once it crosses into retired, the API endpoint that generated your embeddings in the first place stops answering calls. Deprecation policies typically move a model through named stages — generally available, then deprecated (still callable but flagged), then retired (the endpoint returns errors) — and the gap between "deprecated" and "retired" is exactly the window an organization has to migrate before the API simply stops working. That's a fundamentally different failure mode from the silent drift problem covered in [Semantic Rot: When Embedding Upgrades Break Vector Search](/blog/2026/08/17/silent-embedding-drift-vector-search/), where mismatched vectors quietly coexist in one index with no error thrown. A deprecation is loud, dated, and unavoidable — the failure isn't that nobody notices, it's that "we'll deal with it later" turns into "the model is gone and now we're re-embedding under a deadline with no plan."

The re-embedding math makes procrastination expensive. One recent breakdown of a production-scale migration put re-embedding roughly 50 million documents at approximately 25 billion tokens of processing — real compute-hours and real dollars, not a rounding error, and that's before accounting for the reindexing and validation work on the vector database side ([Migrating Vector Embeddings in Production Without Downtime](https://medium.com/google-cloud/migrating-vector-embeddings-in-production-without-downtime-8a0464af6f55){:target="_blank" rel="noopener noreferrer"}). Teams that don't budget for this in advance end up doing it anyway, just under a vendor-imposed deadline instead of on their own schedule.

## Who this hits

Data engineers and DBAs who own the vector store are the ones who receive the deprecation notice, if anyone reads it at all — provider emails go to whoever set up API billing, which is frequently not the same person maintaining the retrieval pipeline months or years later. Platform and ML engineering leads are accountable for retrieval quality and are the ones who have to explain a degraded or paused search feature if the migration gets rushed. Procurement and finance are affected in a way that's easy to miss: a "routine model upgrade" that's actually a forced full re-embed is a budget event, and if it isn't planned, it shows up as an unplanned compute spike instead of a line item anyone approved.

Organizations with the most exposure are the ones running vector search on a smaller or older embedding model chosen years ago for cost or simplicity — those models are disproportionately likely to be in a provider's deprecated tier already, since providers prioritize retiring their oldest, least-differentiated offerings first. Any team using an embeddings API without an internal record of which model version is in production, and when that vendor last updated its deprecation page, is flying blind on a date that's often already public. This is the same underlying gap covered in [Is Your Database AI-Ready?](/blog/2026/08/12/is-your-database-ai-ready/): AI-readiness isn't just about whether data is embedded, it's about whether the pipeline that embedded it is still standing.

## When this becomes a real risk

This is happening now, not in some distant future. Cohere's v2 embedding line retirement already passed its April 2026 shutdown date. OpenAI and Google both operate on rolling deprecation cycles measured in months, not years — OpenAI's stated minimum is six months' notice on generally available models, which sounds generous until you consider that a full re-embed-and-reindex project for a large corpus, done carefully with shadow validation, routinely takes weeks to months on its own. A six-month notice window leaves real but not enormous margin if the migration doesn't start until the notice arrives.

The deprecation cadence itself is accelerating as the embedding model market matures. New models topping retrieval benchmarks are now a near-quarterly occurrence, which pressures providers to consolidate their offerings and sunset older tiers faster to reduce the number of models they have to keep serving. That means the interval between "we picked this embedding model" and "this embedding model enters deprecation" is compressing, not lengthening — a model chosen 18-24 months ago is increasingly likely to already be on a retirement path today, and one chosen this year should be assumed to have a multi-year, not indefinite, shelf life.

## How it plays out in a real environment

A team picked an embedding model two or three years ago, built a vector index on top of it, and never touched the decision again — the pipeline works, retrieval quality is acceptable, and nobody revisits it because there's no recurring trigger to do so. The provider then announces deprecation of that exact model, with a shutdown date some months out. The notice goes to an engineer who set up the API key originally and may no longer be on the team, or it lands in a shared inbox nobody monitors for vendor announcements.

Months pass. Someone finally notices — often because a staging environment starts throwing errors on embedding calls, or because a routine dependency audit surfaces the provider's deprecation page — with the shutdown date now uncomfortably close. At that point, the organization is doing exactly the kind of full, live-corpus re-embedding project that should have been planned on its own timeline, except now it's compressed into whatever window remains before the API stops responding entirely. Under that time pressure, teams skip the safer migration patterns: shadow indexing, side-by-side recall validation, staged cutover. They do an in-place, rushed re-embed instead, which is exactly the condition that produces the mixed-space contamination and silent quality regression described in the drift post above. The scheduled, entirely foreseeable event ends up causing the unscheduled, silent failure mode because there was no lifecycle process sitting between them.

There's a second trap that makes this worse: providers often position the *replacement* model as a drop-in upgrade, sometimes even matching the old model's output dimensionality, which makes it tempting to treat the migration as a configuration change rather than a full re-embed. It isn't. A same-dimension replacement — Google's `gemini-embedding-001` succeeding `text-embedding-004`, for instance, or Cohere's v4 line succeeding v2 — still produces an incompatible vector space from the model it replaces. Swapping the API endpoint without re-embedding the existing corpus doesn't dodge the migration; it just recreates the mixed-space contamination problem on a deprecation-driven timeline instead of an intentional one.

## Actions to take now

1. **Inventory every embedding model currently in production today**, including the exact model version string, not just "we use OpenAI" or "we use Cohere" — deprecation notices are model-version-specific, and a vague inventory can't be checked against a specific deprecation date.
2. **Check each model against its provider's current deprecation page this week.** Cohere, OpenAI, Google, and other major providers all publish a deprecations or model-lifecycle page; treat checking it as a recurring task, not a one-time lookup, since new models get added to the list continuously.
3. **Assign an explicit owner for embedding model lifecycle**, the same way someone owns database version upgrades or TLS certificate renewals. Vendor deprecation emails should route to that owner, not to whoever happened to hold the API key when the account was created.
4. **Build a re-embedding runbook before you need one** — the shadow-index, dual-write, staged-cutover pattern described in the drift post above, made concrete for your own stack: which job re-embeds the corpus, how you validate recall before cutover, how long a full pass takes at your current corpus size and provider rate limits.
5. **Budget re-embedding as a recurring operating cost, not a one-time migration**, using a real estimate for your corpus size (25 billion tokens per 50 million documents is a useful order-of-magnitude anchor) so a forced migration is a planned expense, not a surprise spike.
6. **Prefer providers and model families with longer stated deprecation windows and clear versioning when choosing a new embedding model**, and document that choice's expected lifecycle alongside the decision, so the next team doesn't inherit an undated dependency.
7. **Set a recurring calendar review — quarterly is reasonable — to reconcile your embedding model inventory against every provider's current deprecation status**, so a shutdown date is something you planned around months in advance, not something you discover in an inbox with a deadline already attached.

## A few direct answers

**Does a deprecated embedding model stop working immediately?** No — "deprecated" means the model is flagged for future retirement but still callable; "retired" means the endpoint stops answering. The deprecated stage is the migration window, and it's usually measured in months, not years.

**Can I just switch to the replacement model without re-embedding everything?** No. Even a same-dimension replacement model produces a different, incompatible vector space, so switching the endpoint without re-embedding the existing corpus reintroduces mixed-space contamination rather than avoiding it.

**How much warning do vendors actually give?** It varies by provider, but OpenAI's published minimum is six months for generally available models, and Cohere and Google have both announced retirement dates for older embedding models well in advance on their public deprecation pages. The notice exists; the risk is that nobody inside the organization is watching for it.

## Key takeaways

- Embedding model retirement is scheduled and announced by vendors, not a surprise: Cohere's v2 embedding models were shut down on April 4, 2026, and OpenAI commits to at least six months' notice before retiring a generally available model.
- This is a distinct risk from silent embedding drift — deprecation is loud and dated, but organizations without a lifecycle owner end up handling it as a last-minute crisis anyway.
- Re-embedding a large corpus is a real cost, not a rounding error: roughly 25 billion tokens for 50 million documents in one recent production estimate.
- Rushed, deadline-driven re-embeds are exactly the conditions that produce the mixed-space contamination and silent retrieval-quality regressions that a calm, planned migration avoids.
- The fix is organizational as much as technical: inventory every embedding model version in production, assign an explicit owner, and check vendor deprecation pages on a recurring schedule rather than waiting for a notice email.

If you can't currently name the exact embedding model version behind your production vector index and when its provider last updated its deprecation policy, that's worth resolving before the next retirement notice arrives. [Get in touch](/about/#contact) or see how we approach [database and data platform modernization](/services/) if you want help building a lifecycle process around your AI data infrastructure.

---

*Ivan Lima is a data engineer specializing in database modernization for AI systems. [Get in touch](/about/#contact) if your database needs to be ready for what's next.*
