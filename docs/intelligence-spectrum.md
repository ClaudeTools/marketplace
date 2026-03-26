# The Intelligence Spectrum

> Match the level of intelligence to the level of ambiguity. Use code where code works. Use AI where reasoning is required. Never use one where the other belongs.

---

## The Problem

Most AI agent systems route every interaction through a large language model. The LLM interprets intent, selects tools, resolves parameters, executes actions, and generates a response. It works - but it's like hiring a surgeon to apply band-aids.

The reality: a significant portion of interactions in any domain-specific system follow predictable patterns. When a user asks "show my invoices", there is nothing to reason about. The intent is clear, the tool is obvious, the parameters are deterministic. Sending this through a $0.01+ LLM call is waste.

The counterintuitive finding from production systems: **reducing AI involvement often improves accuracy**. When an LLM doesn't have to parse dates, resolve entity names, or select from 30 tools, it makes fewer mistakes on the tasks it *does* handle. Less noise in, better signal out.

---

## The Principle

There are three fundamentally different types of processing, and each request should be handled at the lowest-cost tier capable of producing a correct result.

### 1. Deterministic Processing

**What it is:** Code. Pattern matching. Regex. Lookup tables. Rule engines. Date arithmetic. Database queries.

**When to use it:** The answer can be computed without judgement. "Last month" is always a date range. "Show my orders" always maps to the same API call. An entity name always resolves to the same database ID.

**Cost:** Effectively zero. Sub-millisecond. No tokens consumed.

**Coverage:** Typically 40-60% of queries in a well-scoped domain application.

### 2. Semantic Processing

**What it is:** Lightweight classification. Embeddings. Small language models (1-3B parameters). Fuzzy matching. Vector similarity search.

**When to use it:** The intent is recognisable but not exact. The user said something that *means* "show my invoices" but didn't use those words. Or multiple tools could apply and a fast classifier can disambiguate. Or an entity mention needs fuzzy matching against a database.

**Cost:** Approximately $0.0001 per classification - roughly 100x cheaper than a full LLM call. Under 50ms.

**Coverage:** Another 20-30% of queries, catching what deterministic rules miss.

### 3. AI Inference

**What it is:** Full LLM reasoning. Multi-step planning. Novel question answering. Contextual synthesis. Error recovery. Explanation and insight generation.

**When to use it:** The query genuinely requires reasoning. "Why is my GST liability higher than expected?" "Review my finances and suggest where I can cut costs." Multi-turn conversations requiring context synthesis. Anything where the *answer isn't knowable in advance*.

**Cost:** Full token pricing. 1-30+ seconds depending on complexity.

**Coverage:** The remaining 10-30% of queries - the ones that actually need it.

---

## The Architecture

```
               User Request
                    |
          +---------v----------+
          |  TIER 1: RULES     |  Deterministic. <1ms. Zero tokens.
          |  Pattern match     |
          |  Keyword maps      |
          |  Date resolution   |
          +---+----------+-----+
         match|          |no match
              |          |
    +---------v--+  +----v-----------------+
    | Direct     |  |  TIER 2: CLASSIFIER  |  Lightweight. <50ms.
    | execution  |  |  Small model /       |
    | + template |  |  embeddings          |
    | response   |  |  Intent + entity     |
    |            |  |  resolution          |
    | Cost: ~$0  |  +---+-----------+------+
    +------------+ classified       |ambiguous
                       |            |
         +-------------v-+  +------v-----------------+
         | Tool execution |  |  TIER 3: FULL LLM      |
         | with resolved  |  |  Complex reasoning      |
         | parameters +   |  |  Multi-step planning    |
         | template       |  |  Novel questions         |
         |                |  |  Explanation + insight   |
         | Cost: minimal  |  |  Cost: full              |
         +----------------+  +-------------------------+
```

The key architectural insight: **each tier pre-processes for the next**. Even when a query reaches Tier 3, the LLM receives pre-resolved dates, matched entities, a narrowed tool set (5 instead of 30), and structured context rather than raw conversation history. This means Tier 3 performs better *because* Tiers 1 and 2 exist.

---

## Why This Works

### 1. Deterministic operations have deterministic answers

"Last month" is a date range. "Q4 2025" is October 1 to December 31. "YTD" is January 1 to today. These are the #1 source of LLM tool-calling errors, and they're entirely computable without AI. A deterministic date parser eliminates the most common failure mode in agent systems outright.

### 2. Less choice = better choice

Injecting 30 tools into every prompt consumes 2,000-5,000 tokens and creates a "choice paradox" for the model. After Tier 1/2 classification narrows to the relevant 2-5 tools, the LLM selects more accurately from a smaller, relevant set. Measured impact: 40-60% token reduction in prompts, plus improved tool selection accuracy.

### 3. Predictable responses for predictable queries

For data tables, financial summaries, and status reports, templates produce 100% consistent formatting at zero token cost. The LLM's generation quality varies - sometimes it dumps raw JSON, sometimes it formats beautifully. Templates remove that variance entirely for structured outputs.

### 4. The paradox: less AI = smarter AI

When the LLM only handles genuinely complex queries, it starts from a better position: smaller prompts, pre-resolved parameters, relevant tools only, structured context. It's not wasting capacity on trivial pattern matching. The result is fewer compounding errors and higher quality reasoning on the problems that actually need it.

---

## The Evidence

This isn't theoretical. It's the dominant production pattern in 2025-26.

**Stripe** coined the "minion architecture" - deterministic code handles the predictable, LLMs tackle the ambiguous. Their blueprints are directed graphs where nodes are explicitly typed as either deterministic (code) or agentic (LLM). In production, only 14% of their nodes remain fully agentic.

**Intercom's Fin** uses a custom BERT model for 90% of routing decisions with >98% accuracy, escalating only 10% to a full LLM. The same pattern appears across Zendesk, customer support platforms, and enterprise AI deployments.

**Cost evidence** from production systems consistently shows 60-80% reduction through tiered routing, with prompt caching adding another 50-90% discount on the system prompt tokens that survive to Tier 3.

The academic literature converges on the same conclusion. Research on production-grade agentic workflows explicitly separates deterministic orchestration from agentic reasoning, arguing that mixing these concerns leads to "LLM drift" - where the model gradually deviates from intended behaviour because it's handling tasks that code could do better.

---

## The Mental Model

Think of it as a funnel, not a pipeline:

- **Most requests** are routine and can be handled instantly by code
- **Some requests** need a quick classification step before deterministic execution
- **Few requests** genuinely require the full reasoning capability of a large model

The goal isn't to replace AI. It's to give AI a better starting position by handling everything below its pay grade with the right tool for the job.

Or more bluntly: **AI should reason, not route.**

---

## Practical Starting Points

The highest-ROI, lowest-effort sequence for any AI agent system:

1. **Deterministic date/time parser** - eliminates the #1 error category immediately
2. **Response templates** for the top 10 query types - removes 30-50% of generation tokens
3. **Prompt caching** - enable platform-level caching for system prompts (up to 90% discount)
4. **Intent pattern registry** - 30-50 regex patterns for common queries, bypassing the LLM entirely
5. **Dynamic tool selection** - inject only relevant tools based on classified intent

Each step compounds. By step 5, your LLM is handling only the queries that genuinely need it, with better context, fewer tools, and pre-resolved parameters.

---

*The right question isn't "how do I make my AI smarter?" It's "how do I make sure my AI only handles the problems worth being smart about?"*
