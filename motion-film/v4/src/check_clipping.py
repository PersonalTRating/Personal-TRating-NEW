"""Automated clipping checks on the HTML film, at every frame of each beat's settled hold and sampled entrance frames.
  - every fully-revealed headline word sits wholly inside its reveal mask
  - the rankings list image and its first card fit inside the panel
  - BMP panel, review card, trending card and end-card link sit wholly inside the 1920x1080 stage (and the card inside its board)"""
import os, pathlib, sys
from playwright.sync_api import sync_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
URL = pathlib.Path(ROOT, 'out', 'CoachCards-Overview-15s.html').as_uri() + '?capture=1'
JS = r"""() => {
  const R = e => e.getBoundingClientRect(), vis = e => { const s = getComputedStyle(e); return s.display !== 'none' && +s.opacity > 0.02 && e.offsetParent !== null; };
  const inside = (a, b, tol = 0.6) => a.left >= b.left - tol && a.right <= b.right + tol && a.top >= b.top - tol && a.bottom <= b.bottom + tol;
  const out = [];
  document.querySelectorAll('.mask').forEach(m => { const w = m.firstChild; if (!vis(m.closest('.disp, .abs'))) return;
    const tf = getComputedStyle(w).transform; if (tf !== 'none' && Math.abs(new DOMMatrix(tf).f) > 0.5) return;       // only fully settled words
    if (!inside(R(w), R(m))) out.push('word clipped: ' + w.textContent); });
  const stage = R(document.getElementById('stage'));
  document.querySelectorAll('img').forEach(i => { if (!vis(i) || i.naturalWidth < 300) return; const p = i.parentElement, pr = R(p), r = R(i);
    if (getComputedStyle(p).overflow === 'hidden' && !inside(r, pr)) out.push('image clipped by container: ' + i.src.slice(22, 40) + ' ' + JSON.stringify([Math.round(r.bottom), Math.round(pr.bottom)]));
    if (!inside(r, stage)) out.push('image outside stage: ' + i.src.slice(22, 40)); });
  return out;
}"""
CHECK = [(1.6, 1.85), (2.5, 2.75), (3.45, 3.8), (4.4, 4.95), (6.4, 7.9), (10.0, 11.9), (13.5, 15.0)]     # settled holds (segment seconds)
ENTRY = [0.8, 1.0, 2.0, 2.9, 3.95, 4.1, 5.35, 5.8, 8.4, 9.0, 9.4, 12.9, 13.1]
with sync_playwright() as p:
    b = p.chromium.launch(); pg = b.new_page(viewport={'width': 1920, 'height': 1080})
    pg.goto(URL); pg.evaluate('window.ready'); pg.wait_for_timeout(300)
    bad = 0; n = 0
    times = [round(a + k / 24, 4) for a, z in CHECK for k in range(int((z - a) * 24) + 1)]
    for t in times:
        pg.evaluate(f'window.seek({t})'); r = pg.evaluate(JS); n += 1
        if r: bad += 1; print(f'settled {t:.2f}s:', r[:4])
    for t in ENTRY:
        pg.evaluate(f'window.seek({t})'); r = [x for x in pg.evaluate(JS) if not x.startswith('image outside stage')]   # entrances may slide in from off-stage
        n += 1
        if r: bad += 1; print(f'entrance {t:.2f}s:', r[:4])
    print(f'checked {n} frames; frames with problems: {bad}')
    b.close(); sys.exit(1 if bad else 0)
