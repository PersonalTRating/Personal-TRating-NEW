/**
 * bmpDumbbell — premium dumbbell SVG with full progressive fill.
 *
 * Approach: two full-dumbbell layers sharing the same geometry.
 *   Layer 1 — dark base (full dumbbell, no clipping)
 *   Layer 2 — green lit version (full dumbbell, clipped left→right by fill%)
 *
 * The SVG clipPath rect width = (score/100) × viewBoxWidth.
 * This means the clip boundary cuts cleanly through the plates, handle,
 * or anywhere in between, so the fill truly covers the whole shape.
 *
 * ViewBox: 220 × 80
 *   Left plate centre:  cx=38,  right plate centre: cx=182
 *   Plate radius: 34  (spans x=4..72 and x=148..216)
 *   Handle: x=72..148, h=10, cy=40
 *
 * Score bands:
 *   0   → no fill, no glow
 *   1-39  → muted green fill, no glow
 *   40-69 → moderate fill, subtle glow
 *   70-94 → strong fill, visible glow
 *   95-100 → near-full fill, pronounced premium glow
 */

let _uid = 0;

export function bmpDumbbell(bmp: number, w = 52): string {
  const uid = ++_uid;
  const score = Math.max(0, Math.min(100, bmp || 0));

  const VW = 220, VH = 80;
  const h = Math.round(w * VH / VW);

  // Geometry
  const PL = 38, PRC = 182, CY = 40, R = 34;
  const HX = PL + R;               // handle start x = 72
  const HW = PRC - PL - R * 2;     // handle width  = 76
  const HH = 10, HY = CY - HH / 2; // handle y = 35

  // Progressive fill width
  const fillW = (score / 100) * VW;

  // Score band
  const band = score >= 95 ? 4 : score >= 70 ? 3 : score >= 40 ? 2 : score > 0 ? 1 : 0;

  // Unique SVG IDs per call — multiple dumbbells on the same page won't share defs
  const cid = `c${uid}`;   // clip path
  const gpid = `p${uid}`;  // green plate radial gradient
  const ghid = `h${uid}`;  // green handle gradient
  const afid = `f${uid}`;  // ambient glow filter

  // Gradient colours scale up with band
  const cols: [string, string, string, string][] = [
    ['', '', '', ''],
    ['#22c55e', '#16a34a', '#14532d', '#082110'],  // band 1 — muted
    ['#4ade80', '#22c55e', '#14532d', '#082110'],  // band 2 — moderate
    ['#86efac', '#4ade80', '#16a34a', '#082110'],  // band 3 — strong
    ['#bbf7d0', '#6ee7b7', '#22c55e', '#082110'],  // band 4 — premium
  ];
  const [g0, g1, g2, g3] = band > 0 ? cols[band] : cols[1];

  // Ambient glow (band 3+)
  const ambOp   = band >= 4 ? 0.32 : band >= 3 ? 0.16 : 0;
  const glowBlur = band >= 4 ? 5    : band >= 3 ? 3    : 0;

  // ── SVG helpers ──────────────────────────────────────────────────

  // Dark metallic plate — concentric rings with subtle highlights
  const darkPlate = (cx: number): string => [
    `<circle cx="${cx}" cy="${CY+1.5}" r="${R}" fill="rgba(0,0,0,0.4)"/>`,
    `<circle cx="${cx}" cy="${CY}" r="${R}" fill="#1e1e1e"/>`,
    `<circle cx="${cx}" cy="${CY}" r="${R}" fill="none" stroke="#3e3e3e" stroke-width="0.8"/>`,
    `<circle cx="${cx}" cy="${CY}" r="28.5" fill="#181818"/>`,
    `<circle cx="${cx}" cy="${CY}" r="28.5" fill="none" stroke="#303030" stroke-width="1.0"/>`,
    `<circle cx="${cx}" cy="${CY}" r="22" fill="#141414"/>`,
    `<circle cx="${cx}" cy="${CY}" r="22" fill="none" stroke="#2c2c2c" stroke-width="0.9"/>`,
    `<circle cx="${cx}" cy="${CY}" r="15" fill="#111"/>`,
    `<circle cx="${cx}" cy="${CY}" r="15" fill="none" stroke="#282828" stroke-width="0.8"/>`,
    `<circle cx="${cx}" cy="${CY}" r="8" fill="#0e0e0e"/>`,
    `<circle cx="${cx}" cy="${CY}" r="8" fill="none" stroke="#2a2a2a" stroke-width="0.6"/>`,
    `<circle cx="${cx}" cy="${CY}" r="3.5" fill="#1a1a1a"/>`,
    // Specular highlight — upper-left (light source)
    `<ellipse cx="${cx-10}" cy="${CY-13}" rx="9" ry="4.5" fill="white" opacity="0.055" transform="rotate(-22,${cx-10},${CY-13})"/>`,
    `<ellipse cx="${cx-7}" cy="${CY-15}" rx="4.5" ry="2.2" fill="white" opacity="0.08" transform="rotate(-25,${cx-7},${CY-15})"/>`,
  ].join('');

  // Green lit plate — same ring structure in green tones
  const greenPlate = (cx: number): string => [
    `<circle cx="${cx}" cy="${CY}" r="${R}" fill="url(#${gpid})"/>`,
    `<circle cx="${cx}" cy="${CY}" r="28.5" fill="none" stroke="rgba(10,80,20,0.60)" stroke-width="1.0"/>`,
    `<circle cx="${cx}" cy="${CY}" r="22" fill="none" stroke="rgba(5,60,15,0.50)" stroke-width="0.9"/>`,
    `<circle cx="${cx}" cy="${CY}" r="15" fill="none" stroke="rgba(0,50,12,0.42)" stroke-width="0.8"/>`,
    `<circle cx="${cx}" cy="${CY}" r="8" fill="#155c20"/>`,
    `<circle cx="${cx}" cy="${CY}" r="8" fill="none" stroke="rgba(0,40,10,0.35)" stroke-width="0.6"/>`,
    `<circle cx="${cx}" cy="${CY}" r="3.5" fill="#0e3d15"/>`,
    // Bright specular highlight
    `<ellipse cx="${cx-10}" cy="${CY-13}" rx="9" ry="4.5" fill="white" opacity="0.30" transform="rotate(-22,${cx-10},${CY-13})"/>`,
    `<ellipse cx="${cx-7}" cy="${CY-15}" rx="4.5" ry="2.2" fill="white" opacity="0.38" transform="rotate(-25,${cx-7},${CY-15})"/>`,
  ].join('');

  // ── Defs ─────────────────────────────────────────────────────────

  const defs = [
    // Clip path: rect from x=0 to fillW — drives the whole fill
    `<clipPath id="${cid}"><rect x="0" y="0" width="${fillW.toFixed(2)}" height="${VH}"/></clipPath>`,

    // Radial gradient for green plate (objectBoundingBox — upper-left highlight)
    `<radialGradient id="${gpid}" cx="35%" cy="30%" r="70%">`,
    `<stop offset="0%" stop-color="${g0}"/>`,
    `<stop offset="15%" stop-color="${g1}"/>`,
    `<stop offset="55%" stop-color="${g2}"/>`,
    `<stop offset="100%" stop-color="${g3}"/>`,
    `</radialGradient>`,

    // Linear gradient for green handle (top → bottom)
    `<linearGradient id="${ghid}" x1="0%" y1="0%" x2="0%" y2="100%">`,
    `<stop offset="0%" stop-color="${g1}"/>`,
    `<stop offset="30%" stop-color="${g2}"/>`,
    `<stop offset="100%" stop-color="${g3}"/>`,
    `</linearGradient>`,

    // Ambient glow blur filter (band 3+ only)
    glowBlur > 0
      ? `<filter id="${afid}" x="-50%" y="-100%" width="200%" height="300%"><feGaussianBlur stdDeviation="${glowBlur}"/></filter>`
      : '',
  ].join('');

  // Soft ambient bloom behind the green layer (band 3+)
  const ambient = ambOp > 0
    ? `<ellipse cx="${(fillW/2).toFixed(1)}" cy="${CY}" rx="${(fillW/2+15).toFixed(1)}" ry="36" ` +
      `fill="${g1}" opacity="${ambOp}" filter="url(#${afid})" clip-path="url(#${cid})"/>`
    : '';

  // ── Assemble SVG ─────────────────────────────────────────────────

  return [
    `<svg viewBox="0 0 ${VW} ${VH}" width="${w}" height="${h}" xmlns="http://www.w3.org/2000/svg"`,
    ` style="display:block;overflow:visible;max-width:100%;height:auto;" aria-hidden="true">`,
    `<defs>${defs}</defs>`,

    // Ambient bloom (behind dark layer so it glows outward from the green shapes)
    ambient,

    // ── DARK BASE LAYER (full dumbbell, unclipped) ──
    // Handle
    `<rect x="${HX}" y="${HY}" width="${HW}" height="${HH}" rx="5" fill="#1c1c1c" stroke="#333" stroke-width="0.5"/>`,
    `<rect x="${HX}" y="${HY}" width="${HW}" height="3" rx="5" fill="white" opacity="0.04"/>`,
    // Plates on top of handle ends
    darkPlate(PL),
    darkPlate(PRC),

    // ── GREEN LIT LAYER (full dumbbell, clipped to fill%) ──
    `<g clip-path="url(#${cid})">`,
    // Handle green
    `<rect x="${HX}" y="${HY-1}" width="${HW}" height="${HH+2}" rx="5" fill="url(#${ghid})"/>`,
    `<rect x="${HX}" y="${HY-1}" width="${HW}" height="3.5" rx="5" fill="white" opacity="0.28"/>`,
    `<rect x="${HX}" y="${HY+HH}" width="${HW}" height="2" fill="black" opacity="0.20"/>`,
    // Green plates on top of green handle ends
    greenPlate(PL),
    greenPlate(PRC),
    `</g>`,

    `</svg>`,
  ].join('');
}
