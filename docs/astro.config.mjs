import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import starlightLlmsTxt from 'starlight-llms-txt';

export default defineConfig({
  site: 'https://claudetools.github.io',
  base: '/marketplace',
  integrations: [
    starlight({
      title: 'claudetools',
      plugins: [starlightLlmsTxt({
        projectName: 'claudetools',
        description: 'claudetools is a Claude Code plugin that adds zero-config guardrails (hooks), structured workflow skills, autonomous agent pipelines, and semantic code navigation (codebase-pilot) to Claude Code sessions. One install command, no configuration needed.',
        details: `Key concepts:
- **Hooks** fire on Claude Code lifecycle events (PreToolUse, PostToolUse, UserPromptSubmit) to catch mistakes before they happen
- **Skills** are structured workflows invoked via slash commands (e.g. /code-review, /investigating-bugs, /managing-tasks)
- **Agents** are autonomous pipelines for complex tasks (bugfix-pipeline, feature-pipeline, security-pipeline, refactor-pipeline)
- **Codebase Pilot** indexes your repo with tree-sitter for instant symbol search, import tracing, and architecture mapping across 14 languages
- **Agent Mesh** coordinates multiple Claude Code sessions working in the same repo with file locks, messaging, and shared decisions`,
        promote: ['index*', 'getting-started/**', 'guides/which-tool'],
        demote: ['advanced/**', 'reference/whats-new'],
        exclude: ['reference/whats-new'],
        customSets: [
          {
            label: 'Getting Started',
            paths: ['getting-started/**'],
            description: 'installation, quick tour, core concepts, and FAQ for new users',
          },
          {
            label: 'Workflow Guides',
            paths: ['guides/**'],
            description: 'step-by-step guides for common workflows like debugging, building features, and code review',
          },
          {
            label: 'Reference',
            paths: ['reference/**'],
            description: 'complete reference for all skills, agents, hooks, commands, and codebase-pilot CLI',
          },
        ],
      })],
      customCss: ['./src/styles/custom.css'],
      editLink: {
        baseUrl: 'https://github.com/ClaudeTools/marketplace-dev/edit/main/docs/',
      },
      social: [
        { icon: 'github', label: 'GitHub', href: 'https://github.com/ClaudeTools/marketplace' },
      ],
      sidebar: [
        { label: 'Getting Started', autogenerate: { directory: 'getting-started' } },
        {
          label: 'Guides',
          items: [
            { label: 'Which Tool Should I Use?', slug: 'guides/which-tool' },
            { slug: 'guides/setup-new-project' },
            { slug: 'guides/explore-a-codebase' },
            { label: 'Tutorial: Your First Bug Fix', slug: 'guides/tutorial-first-bug-fix' },
            { label: 'Tutorial: Explore a New Codebase', slug: 'guides/tutorial-explore-new-codebase' },
            { label: 'Tutorial: Safe Refactor', slug: 'guides/tutorial-safe-refactor' },
            { slug: 'guides/debug-a-bug' },
            { slug: 'guides/build-a-feature' },
            { slug: 'guides/review-code' },
            { slug: 'guides/improve-prompts' },
            { slug: 'guides/manage-tasks' },
            { slug: 'guides/design-a-ui' },
            { slug: 'guides/run-security-audit' },
            { slug: 'guides/coordinate-agents' },
            { label: 'Common Recipes', slug: 'guides/recipes' },
          ],
        },
        { label: 'Skills', autogenerate: { directory: 'reference/skills' } },
        { label: 'Slash Commands', autogenerate: { directory: 'reference/commands' } },
        { label: 'Agents', autogenerate: { directory: 'reference/agents' } },
        { label: 'Hooks', autogenerate: { directory: 'reference/hooks' } },
        { label: 'Codebase Pilot', autogenerate: { directory: 'reference/codebase-pilot' } },
        { label: 'Cheat Sheet', slug: 'reference/cheat-sheet' },
        { label: 'More Reference', autogenerate: { directory: 'reference', collapsed: true } },
        { label: 'Advanced', autogenerate: { directory: 'advanced', collapsed: true } },
      ],
    }),
  ],
});
