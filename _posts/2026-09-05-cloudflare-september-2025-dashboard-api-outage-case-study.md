---
title: "Anatomy of an API Outage: What Broke When Cloudflare's Dashboard Went Down"
description: "A React bug and an overloaded auth service took down Cloudflare's dashboard and APIs for an hour. Here's the chain of failure and what it teaches about control-plane isolation."
date: 2026-09-05 01:15:00 -0400
categories: [case-studies]
tags: [incident-postmortem, resiliency, database-reliability, real-incidents, governance]
image: /assets/images/cloudflare-september-2025-dashboard-api-outage-case-study-01.png
---

![Five-step timeline diagram of Cloudflare's September 12, 2025 dashboard and API outage, from a buggy dashboard release through Tenant Service overload to full recovery](/assets/images/cloudflare-september-2025-dashboard-api-outage-case-study-01.png)

A frontend bug in Cloudflare's dashboard combined with an under-provisioned authorization service to take the Cloudflare Dashboard and a set of related APIs offline for roughly an hour on September 12, 2025. This is part of Data Platform Advisory's **Real Incidents** series: real, publicly disclosed outages, read for what they teach about database and platform resiliency, not for blame.

## Severity scorecard

| | |
|---|---|
| **Company** | Cloudflare |
| **Date** | September 12, 2025 |
| **Duration** | ~1 hour 15 minutes core impact (17:57–19:12 UTC) |
| **Scope** | Cloudflare Dashboard and a broad set of related APIs; CDN edge/data plane was unaffected |
| **Root cause** | A React `useEffect` dependency bug triggered excessive retries against a Tenant Service API, overwhelming the service that handles API request authorization |
| **Data lost** | None reported |
| **Source** | [Cloudflare's own postmortem](https://blog.cloudflare.com/deep-dive-into-cloudflares-sept-12-dashboard-and-api-outage/){:target="_blank" rel="noopener noreferrer"}, published September 13, 2025 |

## What happened

Cloudflare's own account, published the day after the incident, traces a chain that starts in the frontend and ends in the authorization layer:

1. At 16:32 UTC, a new version of the Cloudflare Dashboard shipped containing a bug: a React `useEffect` hook had a problematic object in its dependency array. Because that object was recreated on every state or prop change, React treated it as "always new" and re-ran the effect far more often than intended — triggering many more calls to the `/organizations` endpoint per dashboard render than expected, including retries on failure.
2. At 17:50 UTC, a new version of the Tenant API Service — the backend service responsible for evaluating API request authorization — was deployed, coinciding with the climbing call volume from the dashboard bug.
3. At 17:57 UTC, the Tenant Service became overwhelmed. Because Tenant Service sits inside Cloudflare's API authorization path, its overload meant authorization could no longer be evaluated for many requests — and those requests returned HTTP 5xx errors. Dashboard availability began dropping. **Impact start.**
4. At 18:17 UTC, the team added resources to the Tenant Service and the Cloudflare API climbed back to 98% availability — but the dashboard itself did not recover.
5. At 18:58 UTC, in an attempt to fully restore the dashboard, the team removed some erroring code paths and shipped a new Tenant Service version. This change was itself bad and caused a second spike in impact.
6. At 19:12 UTC, the problematic Tenant Service change was reverted, and dashboard availability returned to 100%. **Impact end.**

Because the failure was contained to Cloudflare's control plane — the systems that manage configuration and authorization — the data plane serving cached content and other edge security features kept working throughout. The outage affected users only if they were making configuration changes or using the dashboard.

## Root cause: a frontend bug meets a backend capacity limit

**A dependency array that never should have triggered a re-fetch.** The dashboard's `useEffect` hook depended on an object that was reconstructed on every render — a common and easy-to-miss React mistake. Instead of running once, the effect ran repeatedly, and each run made a call to an API used for organization data, with retries stacked on top when calls failed.

**A shared authorization service without enough headroom.** Tenant Service wasn't just another backend dependency — it sits directly in the request-authorization path for Cloudflare's APIs. When it couldn't keep up with the inflated call volume, every API request depending on it failed closed, returning 5xx rather than serving a degraded but functional response. Cloudflare's own writeup notes plainly that the service "was not allocated sufficient capacity to handle spikes in load like this."

**A remediation attempt that made things worse.** The first response — adding resources to Tenant Service — helped the API recover but didn't fix the dashboard. The follow-up attempt, which removed erroring code paths and shipped a new Tenant Service version, triggered a second impact spike before being reverted. Cloudflare attributes part of this to a "thundering herd" effect: once the service came back, every dashboard session simultaneously tried to re-authenticate, overwhelming it again.

## What Data Platform Advisory would add

Cloudflare's postmortem is candid about the immediate fixes: migrating Tenant Service to Argo Rollouts (which auto-detects and rolls back a bad deploy), adding capacity headroom, and improving observability to distinguish retry traffic from genuine new requests. Two things worth adding from a data-platform governance lens:

**Authorization services deserve the same load-shedding discipline as a primary database.** Tenant Service functioning as a hard dependency for all API authorization is architecturally similar to a database being a single point of failure for an application tier. The same patterns that protect a primary database under load — circuit breakers, graceful degradation, rate limiting at the client before requests ever reach the shared dependency — apply just as directly to an internal authorization service. Cloudflare's response (a temporary rate limit, added capacity) is exactly the reactive version of what a proactive capacity and backpressure policy would have done automatically.

**Client-side retry storms are a governance gap, not just a bug.** The `useEffect` defect was a code review miss, but the fact that a single buggy frontend deploy could generate enough retry traffic to take down a shared backend service reflects an absence of retry budgets or backoff policies enforced at the client level. Any system where a frontend can freely retry against a shared, stateful backend needs rate limiting and exponential backoff treated as a required contract, not an implementation detail left to individual teams.

## How this maps to the 8 Pillars

This incident sits primarily under **Intelligent Resiliency** (pillar 5) — the failure and recovery pattern of an overloaded internal service — with a secondary tie to **Automated Operations & CI/CD** (pillar 2), since a canary or automated-rollback process on the Tenant Service (the Argo Rollouts migration Cloudflare has now prioritized) would have limited the second impact spike before a human had to intervene.

For teams building or relying on any authorization or metadata service that sits in a critical path — including database access-control layers — the lesson holds regardless of company size: the service that evaluates "is this request allowed" needs more headroom and more automated protection than the services it protects, because when it fails, everything behind it fails closed with it.

*Ivan Lima is a data engineer specializing in database modernization for AI systems. [Get in touch](/about/#contact) if your database needs to be ready for what's next.*
