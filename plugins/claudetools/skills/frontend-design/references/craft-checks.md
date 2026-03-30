# Craft Checks

Apply these in **Build Mode only**. In Maintain Mode, use the consistency checks from the Mode Detection section instead.

---

## Before Writing Each Component

**Mandatory checkpoint.** Every time you write UI code, state:

```
Intent: [who is this human, what must they do, how should it feel]
Palette: [colors from exploration — and WHY they fit this product's world]
Depth: [borders / shadows / layered — and WHY this fits the intent]
Surfaces: [elevation scale — and WHY this color temperature]
Typography: [typeface — and WHY it fits the intent]
Spacing: [base unit]
```

If you cannot explain WHY for each choice, you are defaulting. Stop and think.

**WRONG:** `Palette: Blue primary, gray neutrals / Typography: Inter / Depth: Subtle shadows` — no reasoning, identical to what any AI would produce.

**CORRECT:** `Palette: Deep teal (#0D4F4F) from brewery copper patina, warm cream (#F5F0E8) from unbleached paper — WHY: craft brewery inventory tool, colors from the physical space of brewing. Typography: DM Sans — WHY: geometric but slightly warm, matches precision-meets-craft feel.`

---

## Gotchas

These are concrete mistakes you WILL make without this section. Not general advice — specific corrections.

- **Blue + gray default.** You will reach for `blue-600` primary and `gray-*` neutrals because training data is saturated with this palette. The domain exploration step exists to prevent this. If your palette could belong to any SaaS app, you defaulted.
- **Dashboard clone layout.** Sidebar + card grid + icon-left-number-big-label-small metric boxes. Every AI produces this. The signature element requirement forces differentiation.
- **Populated-only components.** You will skip loading, empty, and error states because they add complexity. Users see these states more than you think — an empty dashboard with no guidance feels broken.
- **Raw Tailwind values.** `bg-white text-gray-800` instead of `bg-background text-foreground`. validate-design.sh catches these, but you should never write them. Raw values break when themes change.
- **Purple/violet accent.** The most overused AI-generated color choice. Avoid unless the user explicitly requests it.

---

## Craft Tests (run before presenting)

**Swap test:** If you swapped your typeface, layout, or palette for the most common alternatives and nothing felt different — you defaulted. Iterate.

**Squint test:** Blur your eyes at the interface. Can you still perceive hierarchy? Nothing jumping out harshly? Craft whispers.

**Signature test:** Can you point to 5 specific elements where your signature appears? Not "the overall feel" — actual components, actual decisions. A signature you cannot locate does not exist.

**Token test:** Read your CSS variables out loud. Do they sound like THIS product's world? `--ink` and `--parchment` evoke a world. `--gray-700` and `--surface-2` evoke a template.

---

## Self-Critique (Correct → Crafted)

After building, before presenting:

**Composition:** Layout has rhythm? Proportions declaring what matters? Clear focal point?

**Craft:** Spacing on grid? Typography layers beyond size? Surfaces whisper hierarchy? All hover/press states?

**Content:** Coherent story? Real person could see this data? Incoherence breaks illusion faster than visual flaws.

If any critique reveals defaults — fix before presenting. For the full critique protocol: `Read ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/references/critique-protocol.md`
