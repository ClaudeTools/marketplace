# The Intelligence Spectrum

> Match the level of intelligence to the level of ambiguity. Use code where code works. Use AI where reasoning is required. NEVER use one where the other belongs.

---

## Core Principle

Every request MUST be handled at the lowest-cost tier capable of producing a correct result. There are three tiers. Evaluate from Tier 1 downward — only escalate when the current tier cannot produce the correct answer.

---

## Tier 1: Deterministic Processing

**What it is:** Code. Pattern matching. Regex. Lookup tables. Rule engines. Date arithmetic. Database queries.

**When to use it:** The answer can be computed without judgement.

**Cost:** Zero tokens. Sub-millisecond.

**Coverage:** 40-60% of queries in a well-scoped domain.

<example>
Input: "Show my invoices from last month"
<reasoning>"Last month" is a computable date range. "Show invoices" maps to a known API call. No ambiguity exists. This is Tier 1.</reasoning>
Action: Resolve date range deterministically. Execute API call directly. Return templated response.
</example>

<example>
Input: "What's my GST liability for Q4?"
<reasoning>"Q4" is October 1 to December 31 — deterministic. "GST liability" maps to a known report. No reasoning needed.</reasoning>
Action: Resolve date range. Run report query. Return formatted result.
</example>

NEVER route these through an LLM: date/time parsing, keyword-to-tool mapping, entity ID lookups, known format conversions, template-based responses for structured data.

---

## Tier 2: Semantic Processing

**What it is:** Lightweight classification. Embeddings. Small models (1-3B parameters). Fuzzy matching. Vector similarity.

**When to use it:** Intent is recognisable but not exact-match. Multiple tools could apply and a classifier can disambiguate. Entity mentions need fuzzy matching.

**Cost:** ~$0.0001 per classification. ~100x cheaper than full LLM. Under 50ms.

**Coverage:** 20-30% of queries.

<example>
Input: "How much did we spend on office stuff?"
<reasoning>"Office stuff" does not match a known category exactly, but embeddings can match it to "Office Supplies" in the chart of accounts. The intent ("how much did we spend") maps to an expense report. Classification + fuzzy match resolves this without full LLM reasoning.</reasoning>
Action: Classify intent as expense_query. Fuzzy-match "office stuff" to account category. Execute query. Return templated response.
</example>

---

## Tier 3: AI Inference

**What it is:** Full LLM reasoning. Multi-step planning. Novel question answering. Contextual synthesis. Explanation and insight generation.

**When to use it:** The query genuinely requires reasoning. The answer is not knowable in advance. Multi-turn context synthesis is needed.

**Cost:** Full token pricing. 1-30+ seconds.

**Coverage:** 10-30% of queries — the ones that actually need it.

<example>
Input: "Why is my GST liability higher than expected this quarter?"
<reasoning>This requires comparing current figures to expectations, identifying contributing factors, and explaining causation. The answer depends on context the user has not fully specified. This is genuine reasoning.</reasoning>
Action: Route to full LLM with pre-resolved figures, narrowed tool set, and structured context from Tiers 1-2.
</example>

---

## Architecture

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

IMPORTANT: Each tier pre-processes for the next. Even when a query reaches Tier 3, the LLM receives pre-resolved dates, matched entities, a narrowed tool set (5 instead of 30), and structured context. Tier 3 performs better BECAUSE Tiers 1 and 2 exist.

---

## Why This Works

1. **Deterministic operations produce deterministic errors when handled by AI.** Date parsing is the #1 source of LLM tool-calling errors. A deterministic parser eliminates the most common failure mode outright.

2. **Less choice produces better choice.** 30 tools in a prompt consumes 2,000-5,000 tokens and creates a choice paradox. Narrowing to 2-5 relevant tools improves selection accuracy and reduces token cost by 40-60%.

3. **Templates eliminate variance.** For structured outputs (tables, summaries, reports), templates produce 100% consistent formatting at zero token cost. LLM generation quality varies; templates do not.

4. **Less AI produces smarter AI.** When the LLM only handles genuinely complex queries, it starts from a better position: smaller prompts, pre-resolved parameters, relevant tools only, structured context. Fewer compounding errors. Higher quality reasoning on the problems that actually need it.

---

## Decision Routing

When evaluating which tier handles a request, apply this checklist top-to-bottom. STOP on first match:

1. Can the answer be computed from known inputs without judgement? → **Tier 1.** STOP.
2. Can intent be classified and entities resolved with lightweight matching? → **Tier 2.** STOP.
3. Does the query require reasoning, synthesis, or multi-step planning? → **Tier 3.**

NEVER skip this evaluation. NEVER default to Tier 3 because it is easier to implement. The cost of routing a Tier 1 query through Tier 3 is not just tokens — it is accuracy loss, latency, and variance in output quality.

---

## Implementation Priority

When building a tiered system, implement in this order. Each step compounds on the previous:

1. **Deterministic date/time parser** — eliminates the #1 error category immediately
2. **Response templates** for the top 10 query types — removes 30-50% of generation tokens
3. **Prompt caching** — enable platform-level caching for system prompts (up to 90% discount)
4. **Intent pattern registry** — 30-50 regex patterns for common queries, bypassing the LLM entirely
5. **Dynamic tool selection** — inject only relevant tools based on classified intent

By step 5, the LLM handles only queries that genuinely need it, with better context, fewer tools, and pre-resolved parameters.

---

## Related

- `docs/five-step-algorithm.md` — The engineering process for applying these principles: question, delete, simplify, accelerate, automate.
