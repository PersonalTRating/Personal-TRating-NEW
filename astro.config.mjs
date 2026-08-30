import { defineConfig } from 'astro/config';
import tailwind from '@astrojs/tailwind';

export default defineConfig({
  site: 'https://coachcards.co.uk',
  integrations: [tailwind()],
  output: 'static',
});
