import { defineConfig } from 'astro/config';
import tailwind from '@astrojs/tailwind';
import sitemap from '@astrojs/sitemap';

export default defineConfig({
  site: 'https://personaltrating.com',
  integrations: [
    tailwind(),
    sitemap({
      filter: (page) => !page.includes('/trainers/') && !page.includes('/review/'),
    }),
  ],
  output: 'static',
});
