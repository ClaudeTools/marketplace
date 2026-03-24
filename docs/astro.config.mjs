import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://claudetools.github.io',
  base: '/marketplace',
  integrations: [
    starlight({
      title: 'claudetools',
      customCss: ['./src/styles/custom.css'],
      social: [
        { icon: 'github', label: 'GitHub', href: 'https://github.com/ClaudeTools/marketplace' },
      ],
      sidebar: [
        { label: 'Getting Started', autogenerate: { directory: 'getting-started' } },
        {
          label: 'Guides',
          items: [
            { label: 'Which Tool Should I Use?', slug: 'guides/which-tool' },
            { slug: 'guides/debug-a-bug' },
            { slug: 'guides/build-a-feature' },
            { slug: 'guides/review-code' },
            { slug: 'guides/explore-a-codebase' },
            { slug: 'guides/run-security-audit' },
            { slug: 'guides/design-a-ui' },
            { slug: 'guides/manage-tasks' },
            { slug: 'guides/coordinate-agents' },
            { slug: 'guides/improve-prompts' },
            { slug: 'guides/setup-new-project' },
          ],
        },
        { label: 'Skills', autogenerate: { directory: 'reference/skills' } },
        { label: 'Slash Commands', autogenerate: { directory: 'reference/commands' } },
        { label: 'Agents', autogenerate: { directory: 'reference/agents' } },
        { label: 'Hooks', autogenerate: { directory: 'reference/hooks' } },
        { label: 'Codebase Pilot', autogenerate: { directory: 'reference/codebase-pilot' } },
        { label: 'More Reference', autogenerate: { directory: 'reference', collapsed: true } },
        { label: 'Advanced', autogenerate: { directory: 'advanced', collapsed: true } },
      ],
    }),
  ],
});
