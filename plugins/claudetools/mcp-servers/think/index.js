#!/usr/bin/env node
// think/index.js — Lean thinking MCP server for structured problem-solving
//
// Inspired by Anthropic's "think tool" research (https://www.anthropic.com/engineering/claude-think-tool)
// which showed +54% on tau-bench with a minimal scratchpad tool.
//
// This version adds step tracking + auto-summarization on top of the scratchpad pattern:
//   - 95% smaller tool description (~20 tokens vs ~400)
//   - 4 params vs 9 (dropped totalThoughts, needsMoreThoughts, nextThoughtNeeded → done)
//   - Auto-summarization after configurable threshold to prevent context bloat
//   - No chalk dependency

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const server = new McpServer({
  name: "think",
  version: "1.0.0",
});

const history = [];
const SUMMARIZE_AFTER = parseInt(process.env.THINK_SUMMARIZE_AFTER || "8", 10);

server.tool(
  "think",
  "Scratch pad for reasoning. No side effects. Use for multi-step analysis, planning, or debugging before acting.",
  {
    thought: z.string().describe("Your current reasoning step"),
    done: z.boolean().describe("True when reasoning is complete").default(false),
    branch: z.string().optional().describe("Branch label if exploring an alternative"),
    revises: z.number().int().min(1).optional().describe("Step number this replaces"),
  },
  async ({ thought, done, branch, revises }) => {
    // Handle revision — truncate history from the revised step
    if (revises !== undefined && revises > 0 && revises <= history.length) {
      history.splice(revises - 1);
    }

    const step = history.length + 1;
    history.push({ step, thought, branch, done });

    // Build compact response
    const response = { step, done, total: history.length };

    // Auto-summarize older thoughts to prevent context bloat
    if (history.length > SUMMARIZE_AFTER) {
      const recent = history.slice(-3);
      const older = history.slice(0, -3);
      response.summary = older
        .map((h) => `${h.step}: ${h.thought.slice(0, 60)}${h.thought.length > 60 ? "..." : ""}`)
        .join(" | ");
      response.recentSteps = recent.map((h) => h.step);
    }

    return {
      content: [{ type: "text", text: JSON.stringify(response) }],
    };
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
