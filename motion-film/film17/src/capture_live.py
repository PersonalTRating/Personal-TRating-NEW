"""Capture live coachcards.co.uk desktop screens (1440 px wide, 1.5x) for the app-window demo."""
import json, os, sys
from playwright.sync_api import sync_playwright

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'assets', 'img')
BASE = 'https://www.coachcards.co.uk'
STATIC = 'nav,.fat-filters{position:static!important} .fat-mob-filter-panel,.fat-mob-filter-backdrop,#pt-lightbox{display:none!important} *{transition:none!important;scroll-behavior:auto!important}'

with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={'width': 1440, 'height': 900}, device_scale_factor=1.5)
    info = {}
    pg.goto(BASE + '/find-a-trainer/', wait_until='networkidle'); pg.wait_for_timeout(1500)
    pg.add_style_tag(content=STATIC); pg.wait_for_timeout(400)
    info['chips'] = pg.eval_on_selector_all('button.chip', 'els => els.map(e => e.textContent.trim())')
    def geo(sel):
        return pg.eval_on_selector_all(sel, 'els => els.filter(e=>e.offsetHeight).map(e => {const r=e.getBoundingClientRect(); return [r.left, r.top+scrollY, r.width, r.height, e.innerText.replace(/\\s+/g," ").slice(0,90)]})')
    info['any_cards'] = geo('a.trc'); info['any_chips'] = geo('button.chip')
    pg.screenshot(path=os.path.join(OUT, 'desk_fat_any.png'), full_page=True)
    pg.click('button.chip:has-text("Weight Loss")'); pg.wait_for_timeout(1500)
    info['wl_cards'] = geo('a.trc'); info['wl_count'] = pg.inner_text('body').count('verified reviews')
    pg.screenshot(path=os.path.join(OUT, 'desk_fat_weightloss.png'), full_page=True)
    pg.goto(BASE + '/trainers/ed71661a-2515-4df0-b0fe-0f486968d104/', wait_until='networkidle'); pg.wait_for_timeout(1500)
    pg.add_style_tag(content=STATIC); pg.wait_for_timeout(400)
    pg.screenshot(path=os.path.join(OUT, 'desk_profile_tracy.png'), clip={'x': 0, 'y': 0, 'width': 1440, 'height': 900})
    json.dump(info, open(os.path.join(OUT, 'desk_info.json'), 'w'), indent=1)
    print(json.dumps(info, indent=1)[:3000])
    b.close()
