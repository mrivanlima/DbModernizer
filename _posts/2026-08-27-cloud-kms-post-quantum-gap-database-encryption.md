---
title: "The Post-Quantum Gap Hiding Inside Your Cloud Database KMS"
description: "AWS, Azure, and GCP are rolling out post-quantum KMS support on different timelines. TLS being quantum-safe doesn't mean your database's encryption keys are."
date: 2026-08-27 03:45:00 -0400
categories: [quantum]
tags: [quantum, post-quantum-cryptography, cloud-infrastructure, key-management, database-security, future-outlook]
image: /assets/images/cloud-kms-post-quantum-gap-database-encryption-01.png
---

![Diagram showing a database's TLS connection already protected by hybrid post-quantum key exchange, while the transparent data encryption key underneath it still depends on the cloud provider's classical KMS key-wrapping timeline](/assets/images/cloud-kms-post-quantum-gap-database-encryption-01.png)

Most database teams that have started post-quantum planning are tracking the wrong milestone. They've confirmed their database connections use TLS with hybrid post-quantum key exchange and treated that as the quantum-safe box checked. It isn't. The keys that actually encrypt data at rest — the transparent data encryption (TDE) keys, the column-level encryption keys, the ones wrapped and managed by your cloud provider's key management service — are on a completely separate migration timeline, and that timeline isn't yours to set. It belongs to AWS, Azure, or Google Cloud, and the three are moving at meaningfully different speeds.

## What's actually happening

Post-quantum cryptography (PQC) touches a database environment in at least two places that get conflated but move independently. The first is the network layer: TLS connections between application and database, protected by hybrid key exchange combining a classical algorithm with NIST's ML-KEM (the standardized post-quantum key encapsulation mechanism, finalized as FIPS 203 in August 2024). The second is the key management layer underneath encryption at rest: the KMS or HSM that generates, wraps, and rotates the actual encryption keys protecting your TDE, your backups, your column-level "always encrypted" fields.

Cloud providers have prioritized the first layer, because TLS is the easier, more standardized migration and it's visible to every customer running a network scan. AWS added opt-in ML-KEM support for TLS connections to KMS, ACM, and Secrets Manager endpoints starting in 2025, available in non-FIPS endpoints across all regions ([AWS Security Blog](https://aws.amazon.com/blogs/security/ml-kem-post-quantum-tls-now-supported-in-aws-kms-acm-and-secrets-manager){:target="_blank" rel="noopener noreferrer"}). Google Cloud KMS added ML-KEM and ML-DSA as preview key algorithms in August 2025, with full infrastructure-level post-quantum protection for connections targeted for 2026 ([Google Cloud Blog](https://cloud.google.com/blog/products/identity-security/announcing-quantum-safe-key-encapsulation-mechanisms-in-cloud-kms){:target="_blank" rel="noopener noreferrer"}). Azure's story is more fragmented: as of April 2026, ML-KEM and ML-DSA are available through SymCrypt, but support depends on which Key Vault tier and region you're using, and native support in the Managed HSM algorithm set remains a visible gap ([Quantum Sequrity](https://quantumsequrity.com/blog/azure-key-vault-post-quantum){:target="_blank" rel="noopener noreferrer"}).

The second layer — PQ-backed KMS keys that actually wrap your data-at-rest encryption keys with post-quantum algorithms, not just protect the connection to the key store — is earlier and slower. AWS describes this as an ongoing 2026-2027 phase, not a shipped capability ([AWS Security Blog](https://aws.amazon.com/blogs/security/ml-kem-post-quantum-tls-now-supported-in-aws-kms-acm-and-secrets-manager){:target="_blank" rel="noopener noreferrer"}). That gap matters enormously, because it's the second layer, not the first, that determines whether a stolen backup or an exfiltrated snapshot can eventually be decrypted by a future quantum computer. A perfectly hybrid-PQC TLS session does nothing to protect data that's already sitting at rest under a classically-wrapped key.

## Who this affects

**Database and platform engineers** are the ones most likely to mistake "our connections use hybrid PQC TLS" for "we're covered," because that's the metric most PQC scanning tools and network compliance checks report on first. It's the visible, easy-to-verify layer, so it becomes the one people check off.

**Cloud architects and infrastructure leads** own the harder question: for each managed database service in use — RDS, Aurora, Azure SQL, Cloud SQL, Cosmos DB, self-managed engines on cloud VMs — what algorithm actually wraps the encryption key protecting data at rest today, and what is the provider's committed (not aspirational) date for post-quantum key wrapping at that layer? That answer differs by provider, by service, and sometimes by region within the same provider.

**Procurement and vendor-risk teams** need to treat cloud KMS post-quantum readiness as a contractual and SLA question, not an assumed capability. An organization's actual crypto-agility is bounded by its least agile cloud dependency — if your database runs on a managed service and the provider hasn't shipped PQ-backed key wrapping, no amount of internal readiness closes that gap. It's not created and not fixed at your layer.

**CISOs and compliance leads** answering to the December 2030 federal PQC deadline (set by the June 2026 executive order) need to know that a "we use TLS 1.3 with PQC" answer in a vendor questionnaire doesn't establish that stored data is protected against harvest-now-decrypt-later collection. The distinction between transport-layer and at-rest key-wrapping PQC needs to show up explicitly in any audit or attestation, or it will get glossed over by both sides.

## When this becomes real

**Already happening**: the transport-layer rollout is live today, unevenly, across all three major providers — which is exactly why it's easy to mistake for complete coverage. Harvest-now-decrypt-later collection of encrypted backups and snapshots is also already happening, by the same logic as always: an adversary doesn't need today's key-wrapping algorithm to be broken, only for it to still be classical when a cryptographically relevant quantum computer eventually arrives.

**Near-term, 2026-2027**: this is the window AWS has explicitly named for PQ-backed KMS keys, and where Google Cloud has targeted full infrastructure-level post-quantum protection. Expect the three major providers to reach meaningfully different points in this window — treat any specific provider date as provisional until it appears in that provider's own release notes, not a third-party roundup.

**2028-2030**: this is when the gap between "our TLS is quantum-safe" and "our data-at-rest keys are quantum-safe" needs to have closed, if the federal December 2030 key-establishment deadline and its downstream contractor requirements are going to be met by organizations depending on managed database KMS. Providers that are still finishing at-rest key-wrapping migration this late leave their customers with no self-service way to accelerate — the fix isn't in the customer's control.

## How this actually plays out in a database environment

The practical failure mode is a false sense of completion. A team runs a TLS/cipher scan against their database connections, sees ML-KEM or another post-quantum key exchange in the negotiated handshake, and marks post-quantum readiness as done for that system. Nobody separately checks what algorithm the underlying KMS used to generate and wrap the TDE key that's actually protecting the data files, the backups, and the replication snapshots sitting at rest — because that information isn't visible from a network scan. It requires going into the KMS console or API for each database and each region and checking key metadata directly, which almost nobody does as a matter of routine.

This is compounded by inconsistency across a multi-cloud or multi-service estate. A team running Aurora PostgreSQL in one region, Azure SQL in another, and a self-managed engine on a third provider's VMs doesn't have one PQC timeline to track — it has three, plus whatever a self-managed engine's own crypto library supports, which is a fourth variable entirely and often the least mature of the four. Crypto-agility research is explicit on this point: an organization's real agility is bounded by its least agile vendor dependency, and cloud KMS is frequently that dependency, because customers can't independently upgrade a managed service's underlying key-wrapping algorithm the way they could patch a library they control directly ([The Quantum Insider](https://thequantuminsider.com/2026/07/31/why-crypto-agility-matters-for-post-quantum-cryptography-migration/){:target="_blank" rel="noopener noreferrer"}).

There's a second, subtler failure mode: assuming provider commitments are uniform when they're tiered. Azure's ML-KEM and ML-DSA availability through SymCrypt depends on Key Vault tier and region as of April 2026, meaning two teams at the same company, using the same cloud provider, can have genuinely different post-quantum coverage depending on which Key Vault SKU and region their database happens to use ([Quantum Sequrity](https://quantumsequrity.com/blog/azure-key-vault-post-quantum){:target="_blank" rel="noopener noreferrer"}). A single "are we PQC-ready" answer at the company level is not meaningful without that granularity.

## Actions to take now

1. **Separate the two questions explicitly in any internal audit or vendor questionnaire**: "Is our TLS to the database using hybrid post-quantum key exchange?" and "Is the KMS key wrapping our data-at-rest encryption key itself post-quantum?" Track them as two different line items, not one.

2. **Pull the actual key metadata for every managed database's KMS key**, per service and per region — not a network scan, the KMS console/API directly — to establish current algorithm state. Do this before assuming coverage from a provider's general PQC announcement, since announcements are often preview or partial-region rollouts.

3. **Get committed dates in writing from each cloud provider for PQ-backed key wrapping on the specific services and regions you use**, not the provider's general roadmap page. A vendor's aggregate PQC announcement doesn't bind them to your specific Aurora instance in your specific region.

4. **Inventory which databases are self-managed versus provider-managed**, because self-managed engines depend on your own crypto library choices (which you can control and accelerate) while managed services depend entirely on provider timelines (which you can't). Prioritize risk assessment accordingly — the self-managed systems are actually the ones where you have agency to move faster if the risk warrants it.

5. **Flag any data with a confidentiality requirement extending past 2030** — health records, financial data, anything under long-retention regulatory mandates — that currently sits in a managed database whose provider hasn't committed to at-rest PQ key wrapping before that date. This is the concrete exposure list, not an abstract one.

6. **Build the internal audit habit now, not at deadline time**: revisit each provider's committed dates quarterly, because this is a fast-moving and uneven landscape — a provider's timeline that looked adequate in early 2026 may slip, and a provider that looked behind may leapfrog another.

7. **For new database deployments, treat cloud KMS post-quantum maturity as a selection criterion**, not an afterthought discovered after the system is already in production and migration becomes a heavier lift.

## Key takeaways

- Post-quantum TLS for database connections and post-quantum key wrapping for data at rest are two different migrations on two different timelines — don't let confirmation of one stand in for the other.
- AWS, Azure, and Google Cloud are all mid-rollout on post-quantum KMS support in 2026, but at different maturity levels and with provider-specific gaps, especially at the at-rest key-wrapping layer.
- Azure's post-quantum Key Vault support varies by tier and region as of April 2026 — a single company-wide "PQC ready" answer can be wrong for specific databases.
- An organization's real crypto-agility is bounded by its least agile cloud dependency, and for most teams that's a managed database's KMS, not anything under direct control.
- The concrete first step is pulling actual KMS key metadata per database and region — not trusting a TLS scan or a provider's general announcement.

Getting a database's post-quantum posture right means knowing exactly which layer you're actually protected at, and which layer is still waiting on someone else's roadmap. [Get in touch](/about/#contact) if you need help mapping that exposure across your database environment before it becomes a deadline problem.

---

*Ivan Lima is a data engineer specializing in database modernization for AI systems. [Get in touch](/about/#contact) if your database needs to be ready for what's next.*
