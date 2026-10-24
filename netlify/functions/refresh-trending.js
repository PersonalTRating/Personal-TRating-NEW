// Scheduled function — fires once daily at 03:00 UTC via netlify.toml.
//
// What it does (in order):
//   1. Calls refresh_all_trending() via Supabase service role to recalculate
//      is_trending and recent_review_count for every active trainer.
//      Badges on trainers whose reviews aged beyond 7 days are cleared.
//      Trainers who newly qualify are marked.
//   2. POSTs to NETLIFY_BUILD_HOOK_URL to trigger a site rebuild so the
//      updated is_trending values are reflected in the static HTML.
//
// Why a rebuild is needed:
//   The site is built with Astro SSG.  is_trending is read from Supabase at
//   build time and baked into static HTML.  Database changes are invisible to
//   visitors until the next Netlify build.  This function closes that loop
//   automatically — no manual redeploy needed.
//
// Required environment variables:
//   PUBLIC_SUPABASE_URL        — Supabase project URL
//   SUPABASE_SERVICE_ROLE_KEY  — service role key (bypasses RLS)
//   NETLIFY_BUILD_HOOK_URL     — Netlify build hook URL
//     Create: Netlify Dashboard → Site → Site configuration →
//     Build & deploy → Build hooks → Add build hook → name "Daily trending refresh"
//     Copy the URL and save it as NETLIFY_BUILD_HOOK_URL in env vars.
//
// Optional environment variable:
//   REFRESH_SECRET  — if set, any HTTP request must supply
//                     Authorization: Bearer {REFRESH_SECRET}
//                     Scheduled invocations (no Authorization header) always pass.
//
// Security model:
//   Netlify's `schedule` config is mutually exclusive with `path` — this
//   function has no public HTTP endpoint.  REFRESH_SECRET is defense-in-depth
//   for any accidental HTTP exposure.
// ─────────────────────────────────────────────────────────────────────────────

import { createClient }   from '@supabase/supabase-js';
import { timingSafeEqual } from 'crypto';

const SUPABASE_URL   = process.env.PUBLIC_SUPABASE_URL       ?? '';
const SUPABASE_SVC   = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';
const BUILD_HOOK_URL = process.env.NETLIFY_BUILD_HOOK_URL    ?? '';
const REFRESH_SECRET = process.env.REFRESH_SECRET            ?? '';

export const handler = async (event) => {
  // ── 1. Authorization ─────────────────────────────────────────────────────
  // Scheduled invocations carry no Authorization header — allow.
  // Manual/HTTP invocations must supply a valid Bearer token.
  const authHeader  = event.headers['authorization'] || event.headers['Authorization'] || '';
  const bearerToken = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;

  if (authHeader !== '') {
    if (bearerToken === null || !REFRESH_SECRET || !constantTimeEquals(bearerToken, REFRESH_SECRET)) {
      console.warn('[refresh-trending] Rejected — invalid authorization');
      return { statusCode: 401, body: 'Unauthorized' };
    }
  }

  // ── 2. Guard: required env vars ──────────────────────────────────────────
  if (!SUPABASE_URL || !SUPABASE_SVC) {
    console.error('[refresh-trending] Supabase env vars not set');
    return { statusCode: 500, body: 'server_misconfigured' };
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SVC, {
    auth: { persistSession: false },
  });

  // ── 3. Recalculate is_trending for all active trainers ───────────────────
  console.log('[refresh-trending] Starting trending refresh…');

  const { data: count, error: rpcErr } = await supabase.rpc('refresh_all_trending');

  if (rpcErr) {
    console.error('[refresh-trending] RPC error:', rpcErr.message);
    return { statusCode: 500, body: 'rpc_error' };
  }

  console.log(`[refresh-trending] Refreshed ${count} trainers`);

  // ── 4. Trigger Netlify rebuild ────────────────────────────────────────────
  if (!BUILD_HOOK_URL) {
    console.warn('[refresh-trending] NETLIFY_BUILD_HOOK_URL not set — skipping rebuild');
    return {
      statusCode: 200,
      body: JSON.stringify({ trainers_updated: count, rebuild: 'skipped_no_hook_url' }),
    };
  }

  let rebuildStatus;
  try {
    const res = await fetch(BUILD_HOOK_URL, { method: 'POST' });
    rebuildStatus = res.status;
    if (!res.ok) {
      const body = await res.text();
      console.error(`[refresh-trending] Build hook failed — status ${res.status}: ${body}`);
    } else {
      console.log(`[refresh-trending] Build hook triggered — status ${res.status}`);
    }
  } catch (err) {
    console.error('[refresh-trending] Build hook fetch threw:', err.message);
    rebuildStatus = 0;
  }

  return {
    statusCode: 200,
    body: JSON.stringify({ trainers_updated: count, rebuild_status: rebuildStatus }),
  };
};

function constantTimeEquals(a, b) {
  if (!a || !b) return false;
  try {
    const bufA = Buffer.from(a);
    const bufB = Buffer.from(b);
    if (bufA.length !== bufB.length) return false;
    return timingSafeEqual(bufA, bufB);
  } catch {
    return false;
  }
}
