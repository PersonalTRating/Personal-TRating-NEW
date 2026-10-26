/**
 * bmpDumbbell — two-asset progressive-fill component.
 *
 * Layers two images at the same position:
 *   Layer 1  /assets/dumbbell-dark.webp  — 2000×727 px, dark metallic base
 *   Layer 2  /assets/dumbbell-green.svg  — same canvas, transparent bg, green-lit
 *
 * CSS clip-path:inset(0 X% 0 0) on the green layer reveals it left→right
 * proportional to the BMP score.
 *
 * mix-blend-mode:multiply on the dark WebP makes its white background
 * transparent against the dark dashboard card surface.
 */

const ASSET_W = 2000;
const ASSET_H = 727;

export function bmpDumbbell(bmp: number, w = 52): string {
  const score = Math.max(0, Math.min(100, bmp || 0));
  // Soft feathered right edge: 5% gradient transition instead of hard clip
  const feather = 5;
  const fadeStart = Math.max(0, score - feather).toFixed(2);
  const maskStyle = score <= 0
    ? 'opacity:0;'
    : `mask-image:linear-gradient(to right,black 0%,black ${fadeStart}%,transparent ${score.toFixed(2)}%);` +
      `-webkit-mask-image:linear-gradient(to right,black 0%,black ${fadeStart}%,transparent ${score.toFixed(2)}%);`;

  return (
    `<div style="position:relative;display:inline-block;width:${w}px;max-width:100%;aspect-ratio:${ASSET_W}/${ASSET_H};">` +
    // Dark base: multiply blend dissolves white bg against dark surface
    `<img src="/assets/dumbbell-dark.webp" width="${ASSET_W}" height="${ASSET_H}"` +
    ` style="display:block;position:absolute;inset:0;width:100%;height:100%;object-fit:fill;mix-blend-mode:multiply;" alt="">` +
    // Green overlay: transparent SVG, revealed left→right with feathered right edge
    `<img src="/assets/dumbbell-green.svg" width="${ASSET_W}" height="${ASSET_H}"` +
    ` style="position:absolute;inset:0;width:100%;height:100%;object-fit:fill;${maskStyle}" alt="">` +
    `</div>`
  );
}
