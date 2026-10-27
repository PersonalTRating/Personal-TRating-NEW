/**
 * bmpConfig — single source of truth for all BMP bracket definitions,
 * formula constants, and UI labels used across the site.
 *
 * Import from here instead of hard-coding thresholds in individual pages.
 */

// ── Formula constants ─────────────────────────────────────────────────────────
export const BMP_PRIOR_COUNT    = 8;    // phantom reviews for Bayesian smoothing
export const BMP_PRIOR_RATING   = 4.0;  // phantom star rating
export const BMP_QUALITY_MAX    = 70;   // max pts from quality component
export const BMP_CONFIDENCE_MAX = 20;   // max pts from confidence component
export const BMP_ACTIVITY_MAX   = 10;   // max pts from activity component
export const BMP_TRENDING_BONUS = 2;    // pts added when trainer is trending
export const BMP_FRESH_FACE_MAX = 2;    // distinct reviewers threshold for Fresh Face badge

// ── Types ──────────────────────────────────────────────────────────────────────
export interface BmpBracket {
  name:  string;
  color: string;
  bg:    string;
  desc:  string;
}

// ── Dashboard bracket (full detail, null = no score yet → "Building Reputation") ──
export function getDashboardBracket(score: number | null | undefined): BmpBracket | null {
  if (!score) return null;
  if (score < 70) return { name:'Developing',  color:'#7c3aed', bg:'#ede9fe', desc:'Your reputation is growing. Each verified review builds your BMP score.' };
  if (score < 80) return { name:'Established', color:'#0369a1', bg:'#e0f2fe', desc:'A dependable review base and good client ratings put you in the established tier.' };
  if (score < 90) return { name:'Strong',      color:'#2a9438', bg:'#eaf7ec', desc:'Strong review quality and consistent activity mark you as a trusted PT.' };
  if (score < 95) return { name:'Advanced',    color:'#0f766e', bg:'#ccfbf1', desc:'Advanced scores reflect outstanding review quality and sustained engagement from clients.' };
  return               { name:'Elite',        color:'#92400e', bg:'#fef3c7', desc:"Elite on CoachCards — exceptional quality, consistency and momentum." };
}

// ── Public rank badge (trainer profile, find-a-trainer cards) ─────────────────
export function getPublicRankBadge(score: number | null | undefined): { label: string; color: string; bg: string } {
  if (!score || score < 70) return { label:'Developing',  color:'#7c3aed', bg:'#ede9fe' };
  if (score < 80)           return { label:'Established', color:'#0369a1', bg:'#e0f2fe' };
  if (score < 90)           return { label:'Strong',      color:'#2a9438', bg:'#eaf7ec' };
  if (score < 95)           return { label:'Advanced',    color:'#0f766e', bg:'#ccfbf1' };
  return                           { label:'Elite',       color:'#92400e', bg:'#fef3c7' };
}

// ── Five-tier bracket list for public explainer sections ──────────────────────
export const BMP_BRACKET_TIERS = [
  { range:'95–100', label:'Elite',        color:'#92400e', bg:'#fef3c7', desc:'Pinnacle of verified reputation'              },
  { range:'90–94',  label:'Advanced',     color:'#0f766e', bg:'#ccfbf1', desc:'Outstanding quality & sustained engagement'    },
  { range:'80–89',  label:'Strong',       color:'#2a9438', bg:'#eaf7ec', desc:'Trusted, consistent, well-reviewed'            },
  { range:'70–79',  label:'Established',  color:'#0369a1', bg:'#e0f2fe', desc:'Solid review base, reliable rating'            },
  { range:'0–69',   label:'Developing',   color:'#7c3aed', bg:'#ede9fe', desc:'Growing history — every review counts'         },
] as const;

// ── Tooltip strings (shared across pages) ─────────────────────────────────────
export const BMP_TOOLTIP_SHORT = 'Quality 70 pts · Confidence 20 pts · Activity 10 pts';
export const BMP_TOOLTIP_LONG  = 'BMP scores PTs 0–100: Quality (up to 70 pts) + Confidence (up to 20 pts) + Activity (up to 10 pts). Trending trainers may receive a small additional boost. Only verified reviews count.';
