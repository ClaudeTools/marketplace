#!/bin/bash
# Generate a design brief using Claude CLI
# Usage: generate-design-brief.sh "<goal>" ["<context>"]
# Example: generate-design-brief.sh "Landing page for a cooking app" "warm, inviting, recipe-focused"

set -euo pipefail

GOAL="${1:-}"
CONTEXT="${2:-}"

if [ -z "$GOAL" ]; then
  echo "Usage: generate-design-brief.sh \"<goal>\" [\"<context>\"]"
  echo "Example: generate-design-brief.sh \"Dashboard for a fitness tracker\" \"dark theme, data-dense\""
  exit 1
fi

# Check if claude CLI is available
if ! command -v claude &>/dev/null; then
  echo "# Design Brief (template — claude CLI not available)"
  echo ""
  echo "## Goal: $GOAL"
  [ -n "$CONTEXT" ] && echo "## Context: $CONTEXT"
  echo ""
  echo "## Color Palette (3-5 colors)"
  echo "| Role | Hex | Reasoning |"
  echo "|------|-----|-----------|"
  echo "| Brand | #_____ | |"
  echo "| Background | #_____ | |"
  echo "| Foreground | #_____ | |"
  echo "| Accent | #_____ | |"
  echo ""
  echo "## Typography"
  echo "- Heading: [font] — [why]"
  echo "- Body: [font] — [why]"
  echo ""
  echo "## Layout Approach"
  echo "- [describe]"
  echo ""
  echo "## Signature Element"
  echo "- [one element unique to this product]"
  echo ""
  echo "## Depth Strategy"
  echo "- [borders-only | subtle-shadows | layered | surface-shifts]"
  echo ""
  echo "## Spacing Scale"
  echo "- Base: [4px | 8px]"
  exit 0
fi

PROMPT="You are a design director creating a detailed design brief. Your goal is to produce a specific, opinionated design direction — NOT generic 'clean and modern' suggestions.

<goal>${GOAL}</goal>
<context>${CONTEXT:-No additional context provided}</context>

<process>
1. DOMAIN EXPLORATION: Spend time in this product's world. What physical space does it evoke? What materials, textures, colors exist naturally there? List 5+ domain concepts.

2. COLOR WORLD: What colors exist in this product's domain? Not 'warm' or 'cool' — go to the actual world. List 5+ specific colors with hex values and where they come from.

3. SIGNATURE: Name ONE element — visual, structural, or interaction — that could ONLY exist for THIS product.

4. DEFAULTS TO REJECT: Name 3 obvious/generic choices for this type of interface and what replaces each.
</process>

<output_format>
Respond with EXACTLY this markdown structure:

# Design Brief: [product name]

## Domain Exploration
[5+ concepts from the product's world]

## Color Palette
| Role | Hex | From the domain |
|------|-----|----------------|
| Brand | #hex | [why this color, where it comes from] |
| Background | #hex | [why] |
| Foreground | #hex | [why] |
| Accent 1 | #hex | [why] |
| Accent 2 | #hex | [why] |

## Typography
- **Heading:** [specific Google Font name] — [why it fits this product's world]
- **Body:** [specific Google Font name] — [why it fits]

## Layout Approach
[specific layout description — not 'clean grid']

## Signature Element
[one unique element with description of how it manifests]

## Defaults Rejected
| Default | Replacement | Why |
|---------|-------------|-----|
| [generic choice 1] | [specific alternative] | [reasoning] |
| [generic choice 2] | [specific alternative] | [reasoning] |
| [generic choice 3] | [specific alternative] | [reasoning] |

## Depth Strategy
[borders-only | subtle-shadows | layered | surface-shifts] — [why]

## Spacing
- Base unit: [4px or 8px]
- Scale: [list of values]
</output_format>

Produce the brief now. Be specific and opinionated. Every choice must come from the product's world, not from generic design patterns."

RESULT=$(echo "$PROMPT" | timeout 30 claude -p --no-input --model sonnet 2>/dev/null || echo "TIMEOUT")

case "$RESULT" in
  TIMEOUT|"")
    echo "# Design Brief Generation Failed"
    echo "Claude CLI timed out or returned empty. Try again or write the brief manually."
    exit 0
    ;;
  *)
    echo "$RESULT"
    ;;
esac
