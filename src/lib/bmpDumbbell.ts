export function bmpDumbbell(bmp: number, w = 52): string {
  const score = Math.max(0, Math.min(100, bmp || 0));
  const h = Math.round(w * 0.42);
  // Bar spans x=28..72 (44 units) in viewBox "0 0 100 42"
  const fw = ((score / 100) * 44).toFixed(2);
  const fwNum = (score / 100) * 44;
  const hasScore = score > 0;
  const showGlow = score >= 60;

  const plate = (cx: number): string =>
    `<circle cx="${cx}" cy="22.5" r="13.5" fill="rgba(0,0,0,0.4)"/>` +
    `<circle cx="${cx}" cy="21" r="13.5" fill="#0c0c0c"/>` +
    `<circle cx="${cx}" cy="21" r="13" fill="none" stroke="#252525" stroke-width="0.7"/>` +
    `<circle cx="${cx}" cy="21" r="11.8" fill="#181818"/>` +
    `<circle cx="${cx}" cy="21" r="9" fill="#0f0f0f"/>` +
    `<circle cx="${cx}" cy="21" r="8.5" fill="none" stroke="#272727" stroke-width="0.5"/>` +
    `<circle cx="${cx}" cy="21" r="4.8" fill="#131313"/>` +
    `<circle cx="${cx}" cy="21" r="4.3" fill="none" stroke="#2c2c2c" stroke-width="0.5"/>` +
    `<circle cx="${cx}" cy="21" r="2.2" fill="#0a0a0a"/>` +
    `<ellipse cx="${cx - 3}" cy="14" rx="3.2" ry="1.8" fill="white" opacity="0.07" transform="rotate(-22,${cx - 3},14)"/>`;

  return (
    `<svg viewBox="0 0 100 42" width="${w}" height="${h}" xmlns="http://www.w3.org/2000/svg" ` +
    `style="display:block;" aria-hidden="true">` +
    `<defs>` +
    (hasScore
      ? `<linearGradient id="bmpgf" x1="0%" y1="0%" x2="100%" y2="0%">` +
        `<stop offset="0%" stop-color="#1b9430"/>` +
        `<stop offset="65%" stop-color="#3ab54a"/>` +
        `<stop offset="100%" stop-color="#54d167"/>` +
        `</linearGradient>` +
        (showGlow
          ? `<filter id="bmpglow" x="-20%" y="-50%" width="140%" height="200%">` +
            `<feGaussianBlur stdDeviation="1.5" result="b"/>` +
            `<feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>` +
            `</filter>`
          : '')
      : '') +
    `</defs>` +
    (score >= 50
      ? `<ellipse cx="${(28 + fwNum / 2).toFixed(1)}" cy="21" rx="${(fwNum / 2 + 4).toFixed(1)}" ry="5.5" fill="#3ab54a" opacity="${(score / 100 * 0.12).toFixed(3)}"/>`
      : '') +
    `<rect x="28" y="17.5" width="44" height="7" rx="3" fill="#1a1a1a"/>` +
    `<rect x="28" y="17.5" width="44" height="2.2" rx="1.2" fill="white" opacity="0.03"/>` +
    (hasScore
      ? `<rect x="28" y="17.5" width="${fw}" height="7" rx="3" fill="url(#bmpgf)"${showGlow ? ' filter="url(#bmpglow)"' : ''}/>` +
        `<rect x="28" y="17.5" width="${fw}" height="2.2" rx="1.2" fill="white" opacity="0.18"/>` +
        `<rect x="28" y="22.3" width="${fw}" height="2.2" fill="black" opacity="0.12"/>`
      : '') +
    plate(14) + plate(86) +
    `</svg>`
  );
}
