"""Capture the live UK leaderboard (mobile 390 px, 3x), its first three coach cards and Tracy Gibson's profile header."""
import json, os
from playwright.sync_api import sync_playwright

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets'); os.makedirs(OUT, exist_ok=True)
J = r'els => els.filter(e=>e.offsetHeight).map(e => {const r=e.getBoundingClientRect(); return {x:r.left, y:r.top+scrollY, w:r.width, h:r.height, text:e.innerText.replace(/\s+/g," "), href:e.getAttribute("href")}})'
STATIC = 'nav,.fat-filters{position:static!important} .fat-mob-filter-panel,.fat-mob-filter-backdrop,#pt-lightbox{display:none!important} *{transition:none!important;animation:none!important;scroll-behavior:auto!important} ::-webkit-scrollbar{display:none}'
info = {}
with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_context(viewport={'width': 390, 'height': 844}, device_scale_factor=3, is_mobile=True).new_page()
    pg.goto('https://www.coachcards.co.uk/find-a-trainer/', wait_until='networkidle'); pg.wait_for_timeout(1500)
    pg.add_style_tag(content=STATIC); pg.wait_for_timeout(500)
    info['cards'] = pg.eval_on_selector_all('a.trc', J)[:3]
    hb = pg.locator('text=United Kingdom Rankings').first.bounding_box(); sy = pg.evaluate('scrollY')
    info['heading'] = {'y': hb['y'] + sy, 'h': hb['height']}
    info['sub'] = pg.inner_text('#fat-lb-sub')
    for c in info['cards']:
        name = c['text'].split(' ', 1)[1].split(' ')[0:2]; key = '_'.join(name).lower()
        c['key'] = key
        pg.screenshot(path=os.path.join(OUT, f'card_{key}.png'), clip={'x': c['x'] - 14, 'y': c['y'] - 14, 'width': c['w'] + 28, 'height': c['h'] + 28}, full_page=True)
    h = info['heading']
    pg.screenshot(path=os.path.join(OUT, 'uk_heading.png'), clip={'x': 0, 'y': h['y'] - 30, 'width': 390, 'height': info['cards'][0]['y'] - h['y'] + 16}, full_page=True)
    tracy = info['cards'][0]['href']; info['tracy_href'] = tracy
    pg.goto('https://www.coachcards.co.uk' + tracy, wait_until='networkidle'); pg.wait_for_timeout(1500)
    pg.add_style_tag(content=STATIC); pg.wait_for_timeout(400)
    info['profile_hero'] = pg.evaluate("document.querySelector('section').innerText.replace(/\\s+/g,' ').slice(0,300)")
    nb = pg.locator('h1').first.bounding_box(); info['name_box'] = nb
    info['handle_box'] = pg.locator('text=@peachcamp').first.bounding_box()
    pg.screenshot(path=os.path.join(OUT, 'tracy_profile_top.png'))
    json.dump(info, open(os.path.join(OUT, 'live_info.json'), 'w'), indent=1)
    b.close()
print(json.dumps(info, indent=1))
