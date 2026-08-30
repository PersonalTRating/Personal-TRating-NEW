import type { APIRoute } from 'astro';
import { supabase } from '../lib/supabase';

const SITE = 'https://coachcards.com';

const staticPages = [
  { url: '/',               priority: '1.0' },
  { url: '/find-a-trainer', priority: '0.9' },
  { url: '/for-trainers',   priority: '0.8' },
  { url: '/contact',        priority: '0.7' },
  { url: '/signup',         priority: '0.5' },
  { url: '/login',          priority: '0.5' },
  { url: '/terms',          priority: '0.3' },
  { url: '/privacy',        priority: '0.3' },
];

export const GET: APIRoute = async () => {
  const { data: trainers } = await supabase
    .from('trainers')
    .select('id')
    .order('bmp_score', { ascending: false });

  const trainerUrls = (trainers ?? []).map(t => ({
    url: `/trainers/${t.id}`,
    priority: '0.8',
  }));

  const allPages = [...staticPages, ...trainerUrls];

  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${allPages.map(p => `  <url><loc>${SITE}${p.url}</loc><priority>${p.priority}</priority></url>`).join('\n')}
</urlset>`;

  return new Response(xml, {
    headers: { 'Content-Type': 'application/xml; charset=utf-8' },
  });
};
