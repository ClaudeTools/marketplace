# Critique Protocol

Your first build ships structure. Now evaluate it like a design lead — not "does this work?" but "would I put my name on this?"

---

## The Gap

Correct means the layout holds, the grid aligns, the colors don't clash. Crafted means someone cared about every decision. You can feel the difference — a hand-thrown mug vs injection-molded. Both hold coffee. One has presence.

---

## 1. See the Composition

**Rhythm:** Does the layout breathe unevenly? Dense tooling gives way to open content, heavy elements balance light ones. Default layouts are monotone — same card size, same gaps, same density everywhere. Flatness is the sound of no one deciding.

**Proportions:** A 280px sidebar says "navigation serves content." A 360px sidebar says "these are peers." If you can't articulate what your proportions declare, they're not declaring anything.

**Focal Point:** Every screen has ONE thing the user came here to do. That thing dominates — through size, position, contrast, or surrounding space. When everything competes equally, the interface feels like a parking lot.

---

## 2. See the Craft

**Spacing Grid:** Every value a multiple of the baseline (4px), no exceptions. But correctness alone isn't craft. A tool panel at 16px padding feels workbench-tight. The same card at 24px feels like a brochure. Density is a design decision.

**Typography:** If size is the ONLY thing separating headline from body from label, the hierarchy is too weak. Weight, tracking, and opacity create layers that size alone cannot.

**Surfaces:** Remove every border from your CSS mentally. Can you still perceive structure through surface color alone? If not, your surfaces aren't working hard enough.

**Interactive States:** Every button, link, and clickable region responds to hover and press. Missing states make an interface feel like a photograph of software.

---

## 3. See the Content

Read every visible string as a user would. Not checking typos — checking truth.

Does this screen tell one coherent story? Could a real person see exactly this data? Or does the page title belong to one product, the body to another, and the sidebar metrics to a third?

Content incoherence breaks the illusion faster than any visual flaw.

---

## 4. See the Structure

Open the CSS and find the lies — places held together with tape.

- Negative margins undoing parent padding → use flex column with section padding
- calc() values as workarounds → simplify the layout
- Absolute positioning to escape flow → use proper grid/flex
- !important declarations → fix specificity instead

The correct answer is always simpler than the hack.

---

## 5. The Loop

After critiquing:
1. Identify every place you defaulted instead of decided
2. Rebuild those parts from the decision, not from a patch
3. Do not narrate the critique — do the work, show the result
4. Ask: "If they said this lacks craft, what would they point to?"
5. That thing you just thought of — fix it. Then ask again.

The first build was the draft. The critique is the design.
