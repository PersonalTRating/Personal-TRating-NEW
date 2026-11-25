"""Capture the live London local leaderboard, its coach cards and Paul Davies's profile (mobile, 390 px, 3x)."""
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
    pg.goto('https://www.coachcards.co.uk/find-a-trainer/', wait_until='networkidle'); pg.wait_for_timeout(1200)
    pg.click('#geo-tab-local'); pg.wait_for_timeout(600)
    pg.type('#geo-local-unified', 'London', delay=40); pg.wait_for_timeout(1800)
    opts = pg.query_selector_all('[role=option], [class*=sugg] li, [class*=sugg] button, [class*=dropdown] li')
    [o for o in opts if o.inner_text().startswith('London')][0].click(); pg.wait_for_timeout(2500)
    pg.add_style_tag(content=STATIC); pg.wait_for_timeout(500)
    info['cards'] = pg.eval_on_selector_all('a.trc', J)
    info['heading'] = pg.eval_on_selector_all('h2', J)
    info['sub'] = pg.inner_text('#fat-lb-sub')
    info['rank_marks'] = pg.eval_on_selector_all('a.trc .trc-rank, a.trc [class*=rank]', J)
    pg.screenshot(path=os.path.join(OUT, 'london_full.png'), full_page=True)
    for c in info['cards']:
        name = c['text'].split(' London')[0].strip().lower().replace(' ', '_')
        pg.screenshot(path=os.path.join(OUT, f'card_{name}.png'), clip={'x': c['x'] - 14, 'y': c['y'] - 14, 'width': c['w'] + 28, 'height': c['h'] + 28}, full_page=True)
    hb = pg.locator('text=London Rankings').first.bounding_box(); sy = pg.evaluate('scrollY')
    h = {'y': hb['y'] + sy, 'h': hb['height']}; info['heading'] = h
    pg.screenshot(path=os.path.join(OUT, 'london_heading.png'), clip={'x': 0, 'y': h['y'] - 30, 'width': 390, 'height': info['cards'][0]['y'] - h['y'] + 16}, full_page=True)
    # phone-screen view for the match-cut: heading + first cards, as the phone would show it
    pg.evaluate(f"window.scrollTo(0, {h['y'] - 90})"); pg.wait_for_timeout(500)
    pg.screenshot(path=os.path.join(OUT, 'london_phone_view.png'))
    # Paul Davies profile
    paul = [c for c in info['cards'] if c['text'].startswith('Paul Davies')][0]['href']
    info['paul_href'] = paul
    pg.goto('https://www.coachcards.co.uk' + paul, wait_until='networkidle'); pg.wait_for_timeout(1500)
    pg.add_style_tag(content=STATIC); pg.wait_for_timeout(400)
    info['profile_title'] = pg.title()
    info['profile_hero_fields'] = pg.evaluate("document.querySelector('section').innerText.replace(/\\s+/g,' ').slice(0,400)")
    info['profile_gate_visible'] = pg.evaluate("[...document.querySelectorAll('*')].some(e=>e.children.length<3 && /Create a free account to view/.test(e.textContent) && e.offsetHeight>0)")
    info['reviews'] = pg.eval_on_selector_all('.tp-rev-card', J)
    names = pg.eval_on_selector_all('h1, .tp-hero-name', J); info['name_el'] = names[:2]
    pg.screenshot(path=os.path.join(OUT, 'paul_profile_top.png'))
    json.dump(info, open(os.path.join(OUT, 'live_info.json'), 'w'), indent=1)
    b.close()
print(json.dumps({k: v for k, v in info.items() if k != 'reviews'}, indent=1)[:2500])
print('REVIEWS:'); [print('-', r['text'][:220]) for r in info['reviews']]
