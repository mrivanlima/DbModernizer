---
title: "How a Routine Database Permission Change Took Down Half the Internet: The Cloudflare Outage"
description: "Cloudflare's worst outage since 2019 traced back to a ClickHouse permissions change that doubled a config file's size. Here's what happened and what it teaches."
date: 2026-08-22 01:50:00 -0400
categories: [case-studies]
tags: [incident-postmortem, resiliency, database-reliability, real-incidents, ci-cd]
image: /assets/images/cloudflare-november-2025-outage-case-study-01.png
---

![Five-step diagram of Cloudflare's November 18, 2025 outage, from a ClickHouse permissions change to a doubled feature file, a hardcoded limit, and a core proxy crash](/assets/images/cloudflare-november-2025-outage-case-study-01.png)

A permissions change to a ClickHouse database cluster caused Cloudflare's worst outage since 2019 — roughly four hours where a large share of the Internet's traffic, including sites like X, ChatGPT, and Spotify, returned HTTP 5xx errors. This is part of Data Platform Advisory's **Real Incidents** series: real, publicly disclosed outages, read for what they teach about database resiliency, not for blame.

## Severity scorecard

| | |
|---|---|
| **Company** | Cloudflare |
| **Date** | November 18, 2025 |
| **Duration** | ~4 hours core impact (11:20–14:30 UTC), full resolution at 17:06 UTC |
| **Scope** | Core CDN/proxy traffic, Workers KV, Cloudflare Access, Turnstile, and the Cloudflare Dashboard |
| **Root cause** | A ClickHouse permissions change caused a metadata query to return duplicate columns, doubling a machine-learning "feature file" past a hardcoded size limit and crashing the core proxy |
| **Data lost** | None reported |
| **Source** | [Cloudflare's own postmortem](https://blog.cloudflare.com/18-november-2025-outage/){:target="_blank" rel="noopener noreferrer"}, published November 18, 2025 |

## What happened

Cloudflare's own account, published the same day by CEO Matthew Prince, lays out a precise chain of cause and effect:

1. At 11:05 UTC, Cloudflare deployed a change to database access permissions on a ClickHouse cluster — part of ongoing work to make distributed queries run under individual user accounts instead of a shared system account, for better security and reliability.
2. That change had a side effect nobody anticipated: a metadata query used to generate Cloudflare's Bot Management "feature file" started returning duplicate rows. The query selected columns from `system.columns` without filtering by database name, and the new permissions exposed metadata for underlying shard tables (`r0`) in addition to the distributed tables (`default`) it had only ever seen before.
3. The feature file — refreshed every five minutes and propagated to every machine on Cloudflare's network — more than doubled in size as a result.
4. Cloudflare's proxy software (FL2) had a hardcoded limit of 200 machine-learning features, well above the ~60 actually in use, as a memory-preallocation safeguard. The oversized file blew past that limit, and the code handling the check called `.unwrap()` on an error value rather than handling it gracefully — causing the process to panic and return HTTP 5xx errors.
5. Because the bad file was regenerated every five minutes from a cluster that was only partially rolled out to the new permissions, the system intermittently recovered and failed again depending on which ClickHouse node produced that cycle's file — a fluctuating pattern that initially led the team to suspect a large-scale DDoS attack rather than an internal database change.

Cloudflare stopped the automatic generation and propagation of new feature files, manually restored a last-known-good version, and restarted the core proxy — restoring most traffic by 14:30 UTC, with full recovery of all downstream systems (including a login backlog on the Dashboard) by 17:06 UTC.

## Root cause: three compounding failures, not one

**A metadata query with an implicit assumption baked in.** The query that generated the feature file never explicitly filtered by database name — it worked only because, historically, the permissions in place meant it could only ever see one database's worth of columns. That assumption was never encoded or tested; it just happened to be true until a permissions change made it false.

**A hardcoded limit with no graceful failure path.** The 200-feature ceiling existed for good reason — a real performance safeguard against unbounded memory use. But the code path that hit that ceiling called `.unwrap()` on a `Result`, which panics on an unexpected value instead of falling back, logging, or degrading gracefully. A legitimate safety limit became the actual crash point.

**Insufficient isolation between a permissions change and its blast radius.** The permissions change was rolled out gradually across the ClickHouse cluster — reasonable practice for a risky change — but the systems consuming that cluster's output had no way to detect that the shape of the data itself had silently changed, and no kill switch to stop propagating a malformed file once one was produced.

## What Data Platform Advisory would add

Cloudflare's own remediation plan (hardening ingestion of internally generated config files the same way they'd treat user input, adding more global kill switches, and reviewing failure modes across core proxy modules) is the right response and worth taking at face value. A few things worth adding from a database-modernization lens:

- **Internally generated data needs the same validation as external input.** The industry habit of trusting "our own" pipeline output more than user input is exactly what let an oversized, malformed file propagate unchecked to the entire network. Any file or config generated by a database query and consumed downstream should be schema-validated before it's trusted, not just before it's accepted from outside.
- **Permission changes to shared infrastructure deserve their own blast-radius review**, separate from the review the change itself gets. The ClickHouse permissions change was almost certainly reviewed as a security and access-control improvement — which it was. What it didn't get was a review of every downstream consumer whose query behavior implicitly depended on the old permission boundary.
- **A safety limit without a graceful degradation path isn't actually a safety limit.** The 200-feature cap did exactly what it was designed to do — catch an anomalous condition — and the software still crashed, because catching the condition and handling it are two different engineering problems. Anywhere a system enforces a hard limit on ingested data, the failure mode for exceeding it should be tested, not assumed.

## Mapping to the 8 Pillars

This incident touches three of the 8 Pillars of the Modern Data Platform most directly:

- **Pillar 3 — Intelligent Pipelines & Governance**: a governance/access-control change to a shared database cluster had an unreviewed downstream effect on data shape — exactly the kind of lineage and impact-analysis gap this pillar exists to close.
- **Pillar 5 — Intelligent Resiliency**: the actual crash was a resiliency failure — a caught error condition with no graceful degradation, escalating a data anomaly into a total proxy outage instead of a contained one.
- **Pillar 2 — Automated Operations & CI/CD**: the fix that ultimately worked — stopping propagation and rolling back to a last-known-good file — is the same discipline database CI/CD applies to schema changes: validate before you promote, and always have a fast, tested rollback path.

## Key takeaways

- A database permissions change with no functional intent of its own triggered Cloudflare's worst outage since 2019 — infrastructure changes that look purely administrative can still alter what queries return.
- Internally generated configuration and data files deserve validation before propagation, not just external user input.
- A hardcoded safety limit is only as good as what happens when it's hit — Cloudflare's 200-feature cap worked exactly as designed and the system still crashed.
- Fluctuating, hard-to-diagnose failures (recovering, then failing again) can look exactly like an attack when the real cause is a partially-rolled-out internal change — a detail worth remembering before assuming the worst-case explanation first.

If a permissions or infrastructure change to your data platform could silently alter what a downstream system receives, that's worth pressure-testing before it happens in production. [Get in touch](/about/#contact) if you want a second set of eyes on where that risk lives in your own stack.

*Ivan Lima is a data engineer specializing in database modernization for AI systems. [Get in touch](/about/#contact) if your database needs to be ready for what's next.*
