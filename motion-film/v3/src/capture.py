"""Seek the HTML segment frame by frame (24 fps, matching the opener) in headless Chromium.
capture.py frames | capture.py stills <comma list of segment seconds> [outdir]"""
import os, sys, pathlib
from playwright.sync_api import sync_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
URL = pathlib.Path(ROOT, 'out', 'CoachCards-Features-15s.html').as_uri() + '?capture=1'
FPS, NF = 24, 360
with sync_playwright() as p:
    b = p.chromium.launch(); pg = b.new_page(viewport={'width': 1920, 'height': 1080})
    errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
    pg.goto(URL); pg.evaluate('window.ready'); pg.wait_for_timeout(300)
    if sys.argv[1] == 'frames':
        out = os.path.join(ROOT, 'build', 'frames'); os.makedirs(out, exist_ok=True)
        for f in range(NF):
            pg.evaluate(f'window.seek({f / FPS})'); pg.screenshot(path=os.path.join(out, f'f{f:04d}.png'))
        print('frames', NF)
    else:
        out = os.path.join(ROOT, 'review', sys.argv[3] if len(sys.argv) > 3 else 'stills'); os.makedirs(out, exist_ok=True)
        for s in sys.argv[2].split(','):
            pg.evaluate(f'window.seek({float(s)})'); pg.screenshot(path=os.path.join(out, f's{float(s):06.2f}.png'))
        print('stills ->', out)
    if errs: print('PAGE ERRORS', errs)
    b.close()
