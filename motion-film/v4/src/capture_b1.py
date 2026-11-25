"""Crops for the single, stable rankings view: per state (UK / Country=Scotland / Local=London)
the tab bar, and the rankings heading through the bottom of the first trainer card. Mobile 390 px, 3x."""
import json, os
from playwright.sync_api import sync_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets', 'b1'); os.makedirs(OUT, exist_ok=True)
STATIC = 'nav,.fat-filters{position:static!important} .fat-mob-filter-panel,.fat-mob-filter-backdrop{display:none!important} *{transition:none!important;animation:none!important;scroll-behavior:auto!important} ::-webkit-scrollbar{display:none}'
info = {}
def rect(pg, js):
    return pg.evaluate("(() => { const e = " + js + "; const r = e.getBoundingClientRect(); return {x:r.left, y:r.top+scrollY, w:r.width, h:r.height}; })()")
with sync_playwright() as p:
    b = p.chromium.launch(); pg = b.new_context(viewport={'width': 390, 'height': 844}, device_scale_factor=3, is_mobile=True).new_page()
    pg.goto('https://www.coachcards.co.uk/find-a-trainer/', wait_until='networkidle'); pg.wait_for_timeout(1500)
    pg.add_style_tag(content=STATIC); pg.wait_for_timeout(400)
    def grab(state):
        tabs = rect(pg, "document.querySelector('#geo-tab-uk').parentElement")
        head = rect(pg, "[...document.querySelectorAll('*')].find(e => e.children.length === 0 && / Rankings$/.test(e.textContent.trim()) && e.offsetHeight > 0)")
        card = rect(pg, "[...document.querySelectorAll('a.trc')].find(e => e.offsetHeight > 0)")
        pg.screenshot(path=os.path.join(OUT, f'tabs_{state}.png'), clip={'x': 0, 'y': tabs['y'] - 10, 'width': 390, 'height': tabs['h'] + 20}, full_page=True)
        top, bot = head['y'] - 22, card['y'] + card['h'] + 22
        pg.screenshot(path=os.path.join(OUT, f'list_{state}.png'), clip={'x': 0, 'y': top, 'width': 390, 'height': bot - top}, full_page=True)
        info[state] = {'tabs': tabs, 'list_h': bot - top, 'first_card': pg.evaluate("[...document.querySelectorAll('a.trc')].find(e=>e.offsetHeight>0).innerText.replace(/\\s+/g,' ')"),
                       'heading': pg.evaluate("[...document.querySelectorAll('*')].find(e => e.children.length === 0 && / Rankings$/.test(e.textContent.trim()) && e.offsetHeight > 0).textContent.trim()")}
    grab('uk')
    pg.click('#geo-tab-country'); pg.wait_for_timeout(800); pg.select_option('#geo-country-sel', 'Scotland'); pg.wait_for_timeout(1800); grab('country')
    pg.click('#geo-tab-local'); pg.wait_for_timeout(600); pg.type('#geo-local-unified', 'London', delay=40); pg.wait_for_timeout(1800)
    [o for o in pg.query_selector_all('[role=option], [class*=sugg] li, [class*=sugg] button, [class*=dropdown] li') if o.inner_text().startswith('London')][0].click()
    pg.wait_for_timeout(2500); grab('local')
    json.dump(info, open(os.path.join(OUT, 'b1_info.json'), 'w'), indent=1); b.close()
print(json.dumps(info, indent=1, ensure_ascii=False))
