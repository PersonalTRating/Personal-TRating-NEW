"""Live captures for v4: search states (UK / Country / Local), map view, Tracy's BMP panel, homepage BMP tiers."""
import json, os
from playwright.sync_api import sync_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets'); os.makedirs(OUT, exist_ok=True)
STATIC = 'nav,.fat-filters{position:static!important} .fat-mob-filter-panel,.fat-mob-filter-backdrop,#pt-lightbox{display:none!important} *{transition:none!important;animation:none!important;scroll-behavior:auto!important} ::-webkit-scrollbar{display:none}'
J = r'els => els.filter(e=>e.offsetHeight).map(e => e.innerText.replace(/\s+/g," ").slice(0,90))'
info = {}
def box(pg, sel):
    b = pg.locator(sel).first.bounding_box(); sy = pg.evaluate('scrollY'); return {'x': b['x'], 'y': b['y'] + sy, 'w': b['width'], 'h': b['height']}
with sync_playwright() as p:
    br = p.chromium.launch()
    pg = br.new_context(viewport={'width': 390, 'height': 844}, device_scale_factor=3, is_mobile=True).new_page()
    pg.goto('https://www.coachcards.co.uk/find-a-trainer/', wait_until='networkidle'); pg.wait_for_timeout(1500)
    pg.add_style_tag(content=STATIC); pg.wait_for_timeout(400)
    def shot(name):   # from the search bar to just past the second card
        s = box(pg, '.fat-search-wrap'); cards = pg.eval_on_selector_all('a.trc', 'els => els.filter(e=>e.offsetHeight).map(e=>{const r=e.getBoundingClientRect(); return r.bottom+scrollY})')
        bottom = cards[min(1, len(cards) - 1)] + 24 if cards else s['y'] + 760
        pg.screenshot(path=os.path.join(OUT, name), clip={'x': 0, 'y': s['y'] - 24, 'width': 390, 'height': bottom - s['y'] + 24}, full_page=True)
        info[name] = {'cards': pg.eval_on_selector_all('a.trc', J), 'sub': pg.inner_text('#fat-lb-sub'), 'tabs_y': box(pg, '#geo-tab-uk')['y'] - (s['y'] - 24)}
    shot('search_uk.png')
    pg.click('#geo-tab-country'); pg.wait_for_timeout(800); pg.select_option('#geo-country-sel', 'Scotland'); pg.wait_for_timeout(1800); shot('search_country.png')
    pg.click('#geo-tab-local'); pg.wait_for_timeout(600); pg.type('#geo-local-unified', 'London', delay=40); pg.wait_for_timeout(1800)
    [o for o in pg.query_selector_all('[role=option], [class*=sugg] li, [class*=sugg] button, [class*=dropdown] li') if o.inner_text().startswith('London')][0].click()
    pg.wait_for_timeout(2500); shot('search_local.png')
    # map view (UK)
    pg.goto('https://www.coachcards.co.uk/find-a-trainer/', wait_until='networkidle'); pg.wait_for_timeout(1200)
    pg.add_style_tag(content=STATIC)
    pg.locator('button', has_text='Map').first.click(); pg.wait_for_timeout(4000)
    m = pg.evaluate("(() => { const e = document.querySelector('.leaflet-container'); if (!e) return null; const r = e.getBoundingClientRect(); return {x:r.left, y:r.top+scrollY, w:r.width, h:r.height}; })()")
    info['map'] = m
    if m: pg.screenshot(path=os.path.join(OUT, 'map.png'), clip={'x': m['x'], 'y': m['y'], 'width': m['w'], 'height': m['h']}, full_page=True)
    # Tracy Gibson BMP panel (public part of her profile)
    pg.goto('https://www.coachcards.co.uk/trainers/ed71661a-2515-4df0-b0fe-0f486968d104/', wait_until='networkidle'); pg.wait_for_timeout(1500)
    pg.add_style_tag(content=STATIC); pg.wait_for_timeout(400)
    bb = pg.evaluate("(() => { const e = [...document.querySelectorAll('section, div')].find(d => /BMP SCORE/.test(d.innerText) && /out of 100/.test(d.innerText) && d.offsetHeight < 420 && d.offsetHeight > 150); const r = e.getBoundingClientRect(); return {x:r.left, y:r.top+scrollY, w:r.width, h:r.height, text:e.innerText.replace(/\\s+/g,' ')}; })()")
    info['bmp_panel'] = bb
    pg.screenshot(path=os.path.join(OUT, 'bmp_panel.png'), clip={'x': bb['x'], 'y': bb['y'], 'width': bb['w'], 'height': bb['h']}, full_page=True)
    # homepage BMP tiers (desktop row, as in the reference)
    d = br.new_page(viewport={'width': 1440, 'height': 900}, device_scale_factor=2)
    d.goto('https://www.coachcards.co.uk/', wait_until='networkidle'); d.wait_for_timeout(1500)
    tb = d.evaluate("(() => { const cs = [...document.querySelectorAll('.bmp-tier-card')]; cs[0].scrollIntoView({block:'center'}); const rs = cs.map(c => c.getBoundingClientRect()); const x0 = Math.min(...rs.map(r=>r.left)), y0 = Math.min(...rs.map(r=>r.top)), x1 = Math.max(...rs.map(r=>r.right)), y1 = Math.max(...rs.map(r=>r.bottom)); return {x:x0, y:y0+scrollY, w:x1-x0, h:y1-y0, tiers: cs.map(c=>c.innerText.replace(/\\s+/g,' ')), each: rs.map(r=>({x:r.left-x0, w:r.width}))}; })()")
    d.wait_for_timeout(1500); info['tiers'] = tb
    d.screenshot(path=os.path.join(OUT, 'tiers.png'), clip={'x': tb['x'] - 12, 'y': tb['y'] - 12, 'width': tb['w'] + 24, 'height': tb['h'] + 24}, full_page=True)
    json.dump(info, open(os.path.join(OUT, 'live_info.json'), 'w'), indent=1)
    br.close()
print(json.dumps(info, indent=1, ensure_ascii=False)[:3500])
