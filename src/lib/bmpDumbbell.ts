export function bmpDumbbell(bmp: number, w = 52): string {
  const score = Math.max(0, Math.min(100, bmp || 0));
  const h = Math.round(w * 0.42);
  const fw = ((score / 100) * 42).toFixed(2);
  const hi = score >= 90;
  const hiRing = (cx: number): string =>
    hi ? `<circle cx="${cx}" cy="21" r="14.2" fill="none" stroke="#39e858" stroke-width="1.3" opacity="0.55"/>` : '';
  const plate = (cx: number): string =>
    `<circle cx="${cx}" cy="21" r="15" fill="#0a0a0a"/>` +
    `<circle cx="${cx}" cy="21" r="13.5" fill="#1e1e1e"/>` +
    `<circle cx="${cx}" cy="21" r="10.5" fill="#131313"/>` +
    `<circle cx="${cx}" cy="21" r="4.5" fill="#0a0a0a"/>` +
    `<ellipse cx="${cx - 5}" cy="13" rx="5" ry="3" fill="white" opacity="0.06" transform="rotate(-20,${cx - 5},13)"/>` +
    hiRing(cx);
  const fill =
    score > 0
      ? `<rect x="29" y="16" width="${fw}" height="10" fill="#39e858"/>` +
        `<rect x="29" y="16" width="${fw}" height="3.5" fill="white" opacity="0.15"/>` +
        `<rect x="29" y="22" width="${fw}" height="4" fill="black" opacity="0.15"/>`
      : '';
  const glow = score >= 95 ? ';filter:drop-shadow(0 0 8px rgba(57,232,88,0.65))' : '';
  return (
    `<svg viewBox="0 0 100 42" width="${w}" height="${h}" ` +
    `style="display:inline-block;vertical-align:middle${glow};" aria-hidden="true">` +
    `<rect x="10" y="15" width="80" height="12" rx="4" fill="#151515"/>` +
    `<rect x="10" y="15" width="80" height="4" rx="2" fill="white" opacity="0.03"/>` +
    fill + plate(15) + plate(85) +
    `</svg>`
  );
}
