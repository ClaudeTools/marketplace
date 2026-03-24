import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://claudetools.github.io',
  base: '/marketplace',
  integrations: [
    starlight({
      title: 'claudetools',
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
