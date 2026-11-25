"""Seek the HTML film frame by frame in headless Chromium and screenshot each frame.
usage: capture.py frames            -> all 516 frames to build/frames
       capture.py stills 0.5,1.5,..  -> named stills to review/stills"""
import os, sys, pathlib
from playwright.sync_api import sync_playwright

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HTML = pathlib.Path(ROOT, 'out', 'CoachCards-Motion-Film.html').as_uri() + '?capture=1'
FPS, DUR = 30, 17.2
mode = sys.argv[1]
with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={'width': 1920, 'height': 1080}, device_scale_factor=1)
    pg.goto(HTML); pg.evaluate('window.ready'); pg.wait_for_timeout(300)
    errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
    if mode == 'frames':
        out = os.path.join(ROOT, 'build', 'frames'); os.makedirs(out, exist_ok=True)
        n = round(FPS * DUR)
        for f in range(n):
            pg.evaluate(f'window.seek({f / FPS})')
            pg.screenshot(path=os.path.join(out, f'f{f:04d}.png'))
        print('frames', n)
    else:
        out = os.path.join(ROOT, 'review', 'stills'); os.makedirs(out, exist_ok=True)
        for s in sys.argv[2].split(','):
            pg.evaluate(f'window.seek({float(s)})')
            pg.screenshot(path=os.path.join(out, f's{float(s):06.2f}.png'))
        print('stills', sys.argv[2])
    if errs: print('PAGE ERRORS:', errs)
    b.close()
