/** @type {import('tailwindcss').Config} */
export default {
  content: ['./src/**/*.{astro,html,js,jsx,md,mdx,svelte,ts,tsx,vue}'],
  theme: {
    extend: {
      colors: {
        'brand-green':       '#3ab54a',
        'brand-green-dark':  '#2a9438',
        'brand-green-light': '#eaf7ec',
        'brand-border':      '#e0e8e1',
        'brand-text':        '#111311',
        'brand-muted':       '#8a8f8a',
        'brand-gold':        '#b8860b',
        'brand-off-white':   '#f7f8f7',
      },
      fontFamily: {
        sans:    ['Manrope', 'ui-sans-serif', 'system-ui', 'sans-serif'],
        display: ['"Playfair Display"', 'Georgia', 'serif'],
      },
    },
  },
  plugins: [],
};
