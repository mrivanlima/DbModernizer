---
title: "Inside a Real Cascading Failure: A Redocly Case Study"
description: "How a missing retry cap on one background job took down Redocly's API for hours — and the architecture choices that could have contained it."
date: 2026-08-15 21:39:04 -0400
categories: [case-studies]
tags: [incident-postmortem, resiliency, database-reliability, real-incidents]
image: /assets/images/redocly-cascading-failure-case-study-01.png
---

![Six-step diagram of Redocly's January 2026 cascading failure, from a failed background job to database saturation, secrets-engine exhaustion, and a deadlocked API](/assets/images/redocly-cascading-failure-case-study-01.png)

A single background job with no retry limit took down Redocly's API for roughly an hour of customer-facing downtime on January 14, 2026 — and the failure mode is one almost every team running a database-backed job queue is exposed to today. This is the first post in Data Platform Advisory's **Real Incidents** series: real, publicly disclosed outages, read for what they teach about database resiliency, not for blame.

## Severity scorecard

| | |
|---|---|
| **Company** | Redocly (API documentation/developer tools platform) |
| **Date** | January 14, 2026 |
| **Duration** | ~3.5 hours total incident time, ~1 hour customer-facing |
| **Scope** | Redocly's core API, authentication, and all authenticated customer projects |
| **Root cause** | A background job entered an infinite retry loop with no backoff, saturating the database and exhausting the secrets engine's credential pool |
| **Data lost** | None reported |
| **Source** | [Redocly's own incident postmortem](https://redocly.com/blog/jan-2026-outage-postmortem){:target="_blank" rel="noopener noreferrer"}, published January 27, 2026 |

## What happened

Redocly's own account (part of a wider postmortem covering three separate incidents that month) lays out a clean six-step chain:

1. A cleanup job running against RabbitMQ failed, and because of missing error-handling logic, it entered an **infinite redelivery loop** — retrying every 20 seconds with no backoff and no cap.
2. Each retry hammered a large database table, and the sustained load pushed the API into an out-of-memory crash.
3. Every time the API tried to restart, it requested fresh dynamic database credentials from Redocly's secrets engine — standard practice for short-lived, scoped credentials.
4. Because old credential roles weren't being revoked fast enough, the roles piled up — Redocly reports **roughly 1,900 active roles accumulated**, hitting a hard ceiling on the secrets engine.
5. Once that ceiling was hit, the secrets engine started rejecting new credential requests outright.
6. With no valid credentials available, the orchestration layer couldn't schedule new API instances. The API was stuck in a flapping, unrecoverable state — and because authentication was embedded inside that same core API rather than run as a separate service, every authenticated customer project went down with it.

Redocly reports no data loss from the incident.

## Root cause: three compounding failures, not one

What makes this incident worth studying isn't the individual failure — job queues fail constantly — it's how three ordinary weaknesses stacked into an outage:

**No backoff or retry limit on the consumer.** A single failed job retrying forever, at a fixed 20-second interval, turned a transient error into sustained, self-inflicted load. Most queue frameworks support exponential backoff and dead-letter queues out of the box; this consumer apparently had neither configured.

**A credential-issuance system with no fast, automatic reclaim.** Dynamic, short-lived database credentials are a genuinely good security practice — far better than static shared credentials. But the security benefit only holds if expired or orphaned roles get revoked promptly. Here, revocation lagged badly enough that a burst of restarts alone could exhaust the pool.

**Authentication as a single point of failure inside the core API.** Redocly's own postmortem calls this out directly: because auth wasn't a separately deployed, isolated service, an API outage became an authentication outage became a total outage for every logged-in customer, rather than a contained degradation.

## What Data Platform Advisory would add

Redocly's corrective actions (4x infrastructure capacity, off-hours maintenance windows, exponential backoff, and — critically — decoupling auth into its own service) are the right fixes and worth taking at face value. A few things worth adding from a database-architecture lens:

- **A dead-letter queue isn't optional for anything touching production data.** Any consumer that can retry against a database table needs a hard retry cap and a place for permanently-failing messages to land for manual inspection — not an infinite loop that gets to keep hammering the primary database.
- **Credential-pool ceilings need their own alerting, separate from general resource monitoring.** ~1,900 roles sounds like a lot until you realize a crash-restart loop can generate that in hours. If the secrets engine has a hard cap, the metric to watch is "roles issued but not yet revoked," not just CPU or memory.
- **Blast-radius containment matters more than average-case reliability.** Redocly's infrastructure wasn't badly built — it was well-built for the common case and had one structural coupling (auth living inside the core API) that turned a database incident into a full outage. The database-modernization question worth asking of any system: which single service, if it goes down, takes everything else with it? That's usually not a performance problem to fix — it's an architecture decision to revisit.

## Mapping to the 8 Pillars

This incident touches three of the 8 Pillars of the Modern Data Platform most directly:

- **Pillar 5 — Intelligent Resiliency**: the core failure — no circuit breaker, no backoff, no isolation between a queue problem and the API's ability to serve any traffic at all.
- **Pillar 2 — Automated Operations & CI/CD**: a background job with unbounded retries is exactly the kind of automation gap that safe deployment and operational tooling is meant to catch before it reaches production.
- **Pillar 8 — AI Agent Identity & Access**: the credential-exhaustion mechanism here is a preview of a problem that gets worse as more of the "restart storm" traffic against a secrets engine comes from automated agents rather than humans — issuance and revocation speed matters even more when the requester isn't a person waiting on a dashboard.

## Key takeaways

- An infinite retry loop with no backoff or cap is one of the most common — and most preventable — causes of a self-inflicted outage.
- Dynamic, short-lived credentials are good security practice, but only as good as how fast expired roles get revoked.
- A single embedded dependency (here, auth living inside the core API) can turn a contained incident into a total outage — ask what your system's equivalent coupling is before it gets tested in production.
- Redocly's own transparent postmortem is a genuinely useful model for how to disclose an incident: clear timeline, honest root cause, concrete corrective actions with status (completed / in progress).

If your database or job infrastructure has never been pressure-tested against a scenario like this one, that's a conversation worth having before an incident forces it. [Get in touch](/about/#contact) if you want a second set of eyes on where your own blast radius is wider than it should be.

*Ivan Lima is a data engineer specializing in database modernization for AI systems. [Get in touch](/about/#contact) if your database needs to be ready for what's next.*
