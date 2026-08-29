---
title: "When Success Becomes the Outage: Inside Neon's IP Exhaustion Incident"
description: "A stale execution plan on Neon's own control-plane database triggered CPU saturation, a stuck suspend job, and a Kubernetes cluster that ran out of IP addresses."
date: 2026-08-29 01:35:00 -0400
categories: [case-studies]
tags: [incident-postmortem, resiliency, database-reliability, real-incidents, performance]
image: /assets/images/neon-ip-exhaustion-case-study-01.png
---

![Four-step diagram showing Neon's IP exhaustion incident: a Postgres execution-plan regression causes CPU saturation, which stalls the compute-suspend job, which exhausts VPC subnet IP addresses, which blocks new compute starts](/assets/images/neon-ip-exhaustion-case-study-01.png)

A single Postgres query on Neon's own control-plane database picked a bad execution plan, and that one plan change cascaded into two production outages that ran out of IP addresses. This is part of Data Platform Advisory's **Real Incidents** series: real, publicly disclosed outages, read for what they teach about database resiliency, not for blame. Note: this is a separate, earlier Neon incident (May 2025) from the "Delayed Start Compute Operations" cold-start postmortem covered elsewhere in this series — same company, two distinct failure modes.

## Severity scorecard

| | |
|---|---|
| **Company** | Neon (serverless Postgres, now part of Databricks) |
| **Date** | May 16 and May 19, 2025 (recurrence), AWS us-east-1 |
| **Duration** | Hours of degraded compute starts on May 16; a second multi-hour degradation on May 19 after a follow-up config change |
| **Scope** | Idle databases needing a cold start, and high-frequency programmatic database creation (agentic AI platforms hit hardest) |
| **Root cause** | A Postgres execution-plan regression on Neon's control-plane database caused CPU saturation, stalling the job that suspends idle compute VMs, which drove concurrent compute count high enough to exhaust VPC subnet IP addresses |
| **Data lost** | None reported |
| **Source** | [Neon's May/June stability recap](https://neon.com/blog/an-apology-and-a-recap-on-may-june-stability){:target="_blank" rel="noopener noreferrer"} and its linked postmortem series, published July 16, 2025 |

## What happened

Neon runs each customer database ("Compute") as its own pod in a Kubernetes cluster, with a scheduled control-plane job called the Activity Monitor responsible for suspending idle Computes to make scale-to-zero work. The chain of events, drawn from Neon's own postmortem series:

1. A Postgres query used by the Activity Monitor to find suspendable Computes changed its execution plan, shifting from an efficient index lookup to a broad scan across a `computes` table holding tens of millions of historical rows.
2. That plan change drove CPU saturation on the control plane's own backing Postgres database. Query times that normally ran a few hundred milliseconds stretched past 100 seconds.
3. With the control plane's queries starved for CPU, the Activity Monitor stopped suspending idle Computes. Running Compute count climbed from a typical 5,000-6,000 toward roughly 8,100 in the AWS us-east-1 region — still under the 10,000 ceiling Neon had load-tested, but enough to hit a limit nobody was watching.
4. That region's three VPC subnets were sized for 12,000 total IP addresses (half the allocation of Neon's other regions, a legacy sizing decision from before the region's growth). At ~8,100 active Computes, the subnets ran out of assignable IPs — not because all 12,000 were in use, but because AWS CNI's default IP-pooling behavior had left thousands of addresses allocated to nodes that no longer had CPU or memory headroom to actually use them.
5. With no assignable IPs, new compute pods couldn't start — meaning idle databases waking up for a connection, and agentic platforms creating databases programmatically, both began failing.

The timing wasn't incidental. Neon's own recap notes that agentic AI platforms drove a sustained 5x increase in database-creation rate and a 50x increase in branch-creation rate across May and June 2025 — load Neon had projected wouldn't arrive until the end of the year. The horizontally-scalable architecture designed to absorb it ("Cells") was already in flight but not yet shipped.

Attempts to fix the IP shortage made things worse before they got better. Engineers first tried lowering AWS CNI's `WARM_IP_TARGET` setting to free unused IPs, based on a misreading of the documentation's default behavior. That released IPs but introduced an unexpected side effect: the setting prevented new pods from starting for 30 seconds after any pod was deleted, throttling recovery exactly when it was needed most. A follow-up attempt on May 19 to revert the configuration change triggered a second, similar outage, because the "healthy" state from the prior weekend turned out to depend on Pod-churn conditions that reverting the setting alone didn't restore.

## Root cause: a query-plan regression escalating through three layers with no circuit breaker

**A single execution plan controlled fleet-wide capacity.** The Activity Monitor's query worked fine for a long time on the assumption that the planner would keep choosing the efficient index. Nothing enforced that assumption — when the planner picked a different plan (Neon's investigation found this varied by region, tied to the shape of each region's `computes` table), there was no fallback, timeout, or circuit breaker between "this control-plane query is now slow" and "the fleet stops suspending compute."

**A capacity ceiling that was tested but not monitored as a live signal.** Neon had load-tested up to 10,000 concurrent Computes and sized us-east-1's subnets for 12,000 IPs specifically because of that ceiling. But the incident happened at ~8,100 Computes — under both numbers — because IP *allocation* (what AWS CNI reserved per node) and IP *assignment* (what was actually usable) diverged under the specific pattern of rapid pod creation without corresponding deletion. The tested ceiling didn't account for that divergence.

**A remediation that changed a poorly-understood subsystem under active incident pressure.** AWS CNI's `WARM_IP_TARGET` and `WARM_ENI_TARGET` interact in ways Neon's own engineers found genuinely surprising even after the fact — IP addresses in a 30-second cooldown window still count toward the "warm" target, which can stall new pod starts entirely under high pod churn. Making a config change to unblock an active incident, without full certainty of its side effects, is a defensible call under pressure — but it's also exactly the situation that produced the May 19 recurrence.

## What Data Platform Advisory would add

Neon's own response — building a horizontally-scalable "Cells" architecture, enforcing stronger per-project and per-customer limits, rewriting queries to be more defensive against plan drift, and separating the hot-path suspend/resume logic from the rest of the control plane — is the right structural fix and Neon shipped it quickly. A few things worth adding from a database-modernization lens:

- **Control-plane databases deserve the same query-plan monitoring as customer-facing ones.** The query that triggered this incident wasn't a customer query — it was Neon's own internal fleet-management logic running against Neon's own Postgres instance. Infrastructure that manages infrastructure is still a database workload, and it needs the same execution-plan drift alerting, `ANALYZE` scheduling, and slow-query alerting any production OLTP system gets. See our [related piece on stale statistics silently degrading execution plans](/2026/08/21/stale-statistics-silent-killer-of-execution-plans/) for the mechanics of exactly this failure mode.
- **Capacity limits need a live headroom signal, not just a load-tested ceiling.** Load testing to 10,000 Computes told Neon what the system could handle in aggregate. It didn't surface that *allocated-but-unusable* IPs could make a subnet functionally exhausted well below that number. Any hard resource ceiling — IPs, connections, file descriptors, whatever — needs a metric tracking the gap between "provisioned" and "actually usable," not just total capacity against total demand.
- **Agentic AI traffic breaks assumptions baked into capacity models built for human usage patterns.** Neon's January 2025 forecast had this scaling need arriving by year-end; agentic platforms pulled it in by months. Any team whose capacity planning assumes historically human-driven growth curves should treat that assumption as expired — see our related post on [how AI agents broke a database model provisioned for humans](/2026/08/14/database-provisioned-for-humans-agents-broke-model/).

## Mapping to the 8 Pillars

This incident touches three of the 8 Pillars of the Modern Data Platform most directly:

- **Pillar 1 — Cloud-Scale Infrastructure**: the underlying failure was a capacity and elasticity gap — subnet sizing, Kubernetes node scheduling, and cloud networking limits that hadn't caught up to the actual growth curve.
- **Pillar 5 — Intelligent Resiliency**: a single query-plan regression on an internal database had no circuit breaker before it escalated into a fleet-wide capacity crisis — the definition of a resiliency gap between one slow query and total service impact.
- **Pillar 7 — Cost & Efficiency (FinOps)**: the underlying driver was a 5x surge in database creation and 50x surge in branch creation from agentic platforms — exactly the kind of AI-driven, difficult-to-forecast resource consumption this pillar exists to help enterprises plan and monitor for, discussed further in our post on [AI agent fan-out as the new thundering herd](/2026/08/26/ai-agent-fanout-thundering-herd-database-resiliency/).

## Key takeaways

- A single execution-plan regression on Neon's own internal control-plane database escalated into a two-incident, multi-day IP exhaustion crisis — infrastructure-managing-infrastructure queries need the same monitoring as customer-facing ones.
- Agentic AI platforms drove a 5x increase in database creation and a 50x increase in branch creation in a matter of weeks, arriving months ahead of Neon's own forecast.
- Allocated capacity and usable capacity are not the same number — Neon's subnets ran out of assignable IPs while thousands of addresses sat allocated to nodes with no room to use them.
- A well-intentioned remediation (adjusting AWS CNI's IP-pooling target) fixed the immediate problem and introduced a new failure mode, and a follow-up attempt to revert it caused a second outage three days later.

If your capacity planning still assumes human-paced growth, or your control-plane's own queries aren't watched for plan drift, that's worth a second look before AI-agent traffic finds the gap for you. [Get in touch](/about/#contact) if you want a second set of eyes on where that risk lives in your own stack.

*Ivan Lima is a data engineer specializing in database modernization for AI systems. [Get in touch](/about/#contact) if your database needs to be ready for what's next.*
