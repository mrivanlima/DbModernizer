---
title: "Pydantic is Just Relational Data Modeling for Python"
description: "Pydantic's field constraints and validators aren't a new invention for AI agents — they're SQL CHECK constraints and NOT NULL, wearing a Python decorator."
date: 2026-08-21 05:44:00 -0400
categories: [data-engineering]
tags: [pydantic, structured-outputs, schema-design, tool-calling, you-already-know-this, grounded-architect]
image: /assets/images/pydantic-relational-data-modeling-python-01.png
---

![Side-by-side diagram comparing a Pydantic model class with typed fields and constraints against an equivalent SQL CREATE TABLE statement with matching column types and CHECK constraints](/assets/images/pydantic-relational-data-modeling-python-01.png)

Here's the direct answer, no warm-up needed: a Pydantic model is a table definition. `Field(gt=0)` is a `CHECK` constraint. `Optional[str] = None` is a nullable column. If you've ever written a `CREATE TABLE` statement, you already know how to write a Pydantic model — you've just never seen it written in Python syntax before.

This is the second post in "You Already Know This," the series making the case that DBAs already hold the core skill set agentic AI needs. Post one argued that multi-agent systems are state management and retrieval problems wearing new vocabulary. This post takes the single cleanest example of that pattern and holds it still long enough to actually look at.

## Why teams reach for Pydantic in the first place

An LLM asked to call a tool or return structured data does not return structured data. It returns text that looks like structured data, most of the time, unless the schema is ambiguous, the model is having a bad day, or the prompt drifted three turns ago. Teams building agents hit this immediately: the model calls `create_invoice` with `amount: "one hundred and fifty"` instead of `150.00`, or omits a required field, or invents a field that doesn't exist in the tool's contract.

The fix everyone reaches for is Pydantic. Define a model, pass it as the expected output shape, let the validation layer catch what the model got wrong, retry with the error fed back in. It works well enough that libraries built entirely around this loop — Instructor, Pydantic AI — have become default infrastructure for tool-calling agents. In production, that retry-on-validation-failure pattern is doing real work: unparseable response rates from LLM tool calls have been measured dropping from around 8% to 0.3% once Pydantic validation and automatic retries are in the loop, with wrong-type rates falling to zero ([MachineLearningMastery](https://machinelearningmastery.com/the-complete-guide-to-using-pydantic-for-validating-llm-outputs/){:target="_blank" rel="noopener noreferrer"}).

That's a genuinely good outcome. What it is not is a new idea.

## The part everyone skips: this is a data modeling problem, not a Python problem

Watch how a typical Pydantic model for an agent tool call gets described in a blog post: "define your schema," "add validation rules," "enforce types." Strip the Python syntax off that sentence and you're describing exactly what a DBA does before a table goes into production. Column types are type enforcement. `NOT NULL` is a required field. A `CHECK` constraint is a validator. A foreign key is referential integrity that Pydantic can only approximate with a nested model and a lookup you write yourself.

The reason this gets missed is that the discourse around structured outputs treats Pydantic as an LLM-adjacent invention — something that grew up alongside agent frameworks to solve an agent-shaped problem. It didn't. Pydantic is a decades-old idea (typed, constrained, validated records) wearing a decorator syntax that happens to be convenient for a function signature. The LLM didn't create the need for structured, constrained data. It just made the cost of *not* having it visible faster, because now a malformed record isn't a bug ticket next sprint — it's a tool call that silently corrupts an agent's next three steps.

## Side by side: same constraints, two syntaxes

Here's a Pydantic model an agent framework might use to validate a tool call for creating a support ticket:

```python
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
from enum import Enum

class Priority(str, Enum):
    low = "low"
    medium = "medium"
    high = "high"
    critical = "critical"

class SupportTicket(BaseModel):
    ticket_id: int = Field(gt=0)
    customer_email: str = Field(pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
    subject: str = Field(min_length=1, max_length=200)
    priority: Priority
    assigned_agent_id: Optional[int] = None
    created_at: datetime
    resolved: bool = False
```

And the equivalent, in the syntax this same logic has had for forty years:

```sql
CREATE TABLE support_ticket (
    ticket_id         INT PRIMARY KEY CHECK (ticket_id > 0),
    customer_email    VARCHAR(255) NOT NULL
                       CHECK (customer_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    subject           VARCHAR(200) NOT NULL CHECK (LENGTH(subject) >= 1),
    priority           VARCHAR(10) NOT NULL
                       CHECK (priority IN ('low','medium','high','critical')),
    assigned_agent_id INT REFERENCES agent(agent_id),
    created_at        TIMESTAMPTZ NOT NULL,
    resolved          BOOLEAN NOT NULL DEFAULT FALSE
);
```

Every constraint in the Pydantic model has a direct, one-to-one line in the DDL. `gt=0` is `CHECK (ticket_id > 0)`. The regex `pattern` is a `CHECK` with a regex operator. The `Enum` is a `CHECK ... IN (...)` — or, if you actually run this at scale, a proper lookup table with a foreign key, which is the constraint Pydantic *can't* express on its own because it has no concept of "ask another table if this value is currently valid." `Optional[int] = None` is a nullable foreign key. `bool = False` is `NOT NULL DEFAULT FALSE`.

The one asymmetry worth naming: Pydantic validates a value in isolation, at the moment a Python object is constructed. A `CHECK` constraint enforces the same rule at every write, from every process, for the life of the row — including the write nobody remembered to route through your Pydantic model six months from now. That's not an argument against Pydantic. It's the argument for keeping both layers, which the field increasingly agrees on: Pydantic for early, ergonomic validation at the boundary where the LLM's output enters your system, and the database's own constraints as the layer that can't be bypassed by a script somebody wrote at 11 PM ([hzionn, The GeekHub](https://medium.com/the-geekhub/pydantic-vs-database-validation-why-application-level-validation-matters-a174e0b79ea6){:target="_blank" rel="noopener noreferrer"}).

## The analogy, stated plainly

A Pydantic model without a backing database constraint is a `CHECK` constraint that only fires the first time. It validates the LLM's output on the way in, then hands you a plain Python object that's free to be mutated, serialized, re-deserialized, or written to storage with none of those original guarantees still attached. If that object's final destination is a table, and that table doesn't carry its own constraints, you've spent real engineering effort validating data on its way into a place where nothing is validated once it arrives.

DBAs have never had the luxury of validating once and trusting forever. Every schema you've designed assumes a write can come from anywhere — a migration script, a bulk load, a junior engineer's one-off query — and the constraint has to hold regardless of which path got there. That instinct is exactly what's missing from most agent tool-calling code today, and it's exactly what you already know how to add.

## Practical guidance

If you're the DBA on a team building agent tooling, three moves apply your existing skill set directly:

First, treat every Pydantic model an agent uses for tool calls as a draft schema, not a finished one. Ask what table it's ultimately writing to, and check whether that table's constraints actually match the model's `Field` definitions. They drift apart faster than anyone expects.

Second, push for `Enum` fields to become real lookup tables with foreign keys the moment the set of valid values is something the business, not the codebase, controls. A hardcoded Python `Enum` for `priority` is fine. A hardcoded `Enum` for `department` is a foreign key you're pretending doesn't need to exist.

Third, when an agent's retry loop fires because Pydantic rejected a malformed tool call, log that rejection the way you'd log a `CHECK` constraint violation — because that's what it is. A cluster of rejections on the same field is a schema signal, not just an LLM quality problem.

## Key takeaways

- A Pydantic model's `Field` constraints are functionally identical to SQL `CHECK`, `NOT NULL`, and type declarations — same rules, different syntax.
- Pydantic validates once, at construction time; a database constraint enforces the rule on every write, from every caller, indefinitely.
- `Enum` fields are `CHECK (... IN (...))` in disguise, and should graduate to a real lookup table once the valid set is business-controlled rather than code-controlled.
- Structured-output validation measurably improves agent reliability — but only for the write path it actually covers, not the ones that bypass it.
- The DBA instinct to assume a write can come from anywhere is the missing piece in most agent tool-calling code today.

If your agent's tool-calling layer has a Pydantic model but no matching constraint on the table it writes to, that's a gap worth closing before it closes itself at 3 AM. [Get in touch](/about/#contact) if your database needs to be ready for what's next.

*Ivan Lima is a data engineer specializing in database modernization for AI systems. [Get in touch](/about/#contact) if your database needs to be ready for what's next.*
