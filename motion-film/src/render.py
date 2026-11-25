"""CoachCards 30 s advert: frame-addressable renderer for the walkthrough (frames 236-719 at 24 fps).

render(n) is a pure function of the frame number n. Every visual is computed from n; nothing is
time-stepped. Source pixels come only from live coachcards.co.uk mobile captures (captures/) and the
user's signed-in mobile screenshot of Tracy Gibson's reviews.
"""
import math, os, sys
from functools import lru_cache
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAP = os.path.join(ROOT, 'captures')
BUILD = os.path.join(ROOT, 'build')
REPO = os.path.dirname(ROOT)
FONTS = os.path.join(REPO, 'assets', 'production', 'fonts')
LOGO = os.path.join(REPO, 'assets', 'production', 'logos', 'cc-logo.png')

FPS = 24
W, H = 1280, 720
CUT = 236            # first walkthrough frame (opener frames 0-235)
END_CARD = 648       # end card fully visible from here to 719 (72 frames = 3.000 s)
LAST = 719

GREEN = (58, 181, 74)
WHITE = (255, 255, 255)

SW, SH = 750, 1624   # phone screen canvas (375x812 css at 2x)
STATUS_H = 88        # status bar rows taken from the user's real iPhone screenshot
CSS = 2              # canvas px per css px

# ---------- easing ----------
def clamp(x, a=0.0, b=1.0): return max(a, min(b, x))
def ease(x): x = clamp(x); return x * x * (3 - 2 * x)
def ease_out(x): x = clamp(x); return 1 - (1 - x) ** 3
def seg(n, a, b): return clamp((n - a) / (b - a)) if b > a else float(n >= b)
def lerp(a, b, t): return a + (b - a) * t

# ---------- sources ----------
def _w750(im):
    im = im.convert('RGB')
    if im.width != SW:
        im = im.resize((SW, round(im.height * SW / im.width)), Image.LANCZOS)
    return im

@lru_cache(None)
def page(name):
    """Stitched full-page images at 750 px width (2 px per css px)."""
    if name == 'any':
        a = _w750(Image.open(os.path.join(CAP, 'fat_any_y0000.jpg')))
        b = _w750(Image.open(os.path.join(CAP, 'fat_any_y0750.jpg')))
        c = _w750(Image.open(os.path.join(CAP, 'fat_any_y1190.jpg')))
        out = Image.new('RGB', (SW, 1190 * CSS + c.height))
        out.paste(a, (0, 0)); out.paste(c, (0, 1190 * CSS)); out.paste(b, (0, 750 * CSS)); return out
    if name == 'inp':
        a = _w750(Image.open(os.path.join(CAP, 'fat_inperson_y0000.png')))
        b = _w750(Image.open(os.path.join(CAP, 'fat_inperson_y0542.jpg')))
        out = Image.new('RGB', (SW, 542 * CSS + b.height)); out.paste(a, (0, 0)); out.paste(b, (0, 542 * CSS)); return out
    if name == 'hero':
        return _w750(Image.open(os.path.join(CAP, 'profile_signedout_y0000.jpg')))
    if name == 'reviews':
        im = _w750(Image.open(os.path.join(CAP, 'profile_reviews_signedin_user.webp')))
        return im.crop((0, 0, SW, SH)) if im.height >= SH else im
    raise KeyError(name)

NAV_H = {'any': 126, 'inp': 126, 'hero': 130}

@lru_cache(None)
def status_bar():
    return page('reviews').crop((0, 0, SW, STATUS_H))

def screen(name, s_css=0.0):
    """One phone screen: real status bar, page scrolled by s_css, page's own nav pinned on top."""
    if name == 'reviews':
        return page('reviews').copy()
    p = page(name)
    c = Image.new('RGB', (SW, SH), (10, 18, 11))
    y0 = int(round(s_css * CSS))
    view = p.crop((0, y0, SW, y0 + SH - STATUS_H))
    c.paste(view, (0, STATUS_H))
    c.paste(p.crop((0, 0, SW, NAV_H[name])), (0, STATUS_H))
    c.paste(status_bar(), (0, 0))
    return c

def page_to_screen(name, x_css, y_css, s_css):
    return x_css * CSS, STATUS_H + (y_css - s_css) * CSS

# card / control rectangles on the live pages, in css px (measured in the browser at 375 px width)
DELIVERY = (89.6, 654.0, 193.6, 684.4)
TRACY_CARD = (32, 885, 343, 1064)
PAUL_CARD = (32, 1080, 343, 1234)
REVIEW_CARD = (39, 215, 711, 627)    # Carole Taylor card, already in canvas px on the reviews screenshot

# ---------- drawing helpers ----------
@lru_cache(None)
def font(name, size): return ImageFont.truetype(os.path.join(FONTS, name), size)

def rrect_mask(size, r):
    m = Image.new('L', size, 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), r, fill=255); return m

def highlight(scr, rect, alpha, top=STATUS_H + 126):
    """Dim the page content outside rect (status bar and nav stay clean) and outline rect in brand green."""
    if alpha <= 0: return scr
    x0, y0, x1, y1 = rect
    dim = Image.new('L', scr.size, int(110 * alpha))
    dd = ImageDraw.Draw(dim)
    dd.rectangle((0, 0, scr.width, top), fill=0)
    dd.rounded_rectangle((x0, y0, x1, y1), 28, fill=0)
    scr = Image.composite(Image.new('RGB', scr.size, (0, 0, 0)), scr, dim)
    ov = Image.new('RGBA', scr.size, (0, 0, 0, 0))
    ImageDraw.Draw(ov).rounded_rectangle((x0 - 4, y0 - 4, x1 + 4, y1 + 4), 32, outline=GREEN + (int(255 * alpha),), width=7)
    scr = scr.convert('RGBA'); scr.alpha_composite(ov); return scr.convert('RGB')

# ---------- phone ----------
BEZ = 0.045          # bezel thickness relative to screen width
def phone_image(scr, screen_h):
    """Flat phone (bezel + screen + island) with the screen scaled to screen_h px tall."""
    sh = max(8, int(round(screen_h))); sw = int(round(sh * SW / SH))
    b = int(round(sw * BEZ))
    pw, ph = sw + 2 * b, sh + 2 * b
    ph_img = Image.new('RGBA', (pw, ph), (0, 0, 0, 0))
    body = Image.new('RGBA', (pw, ph), (12, 12, 12, 255))
    ImageDraw.Draw(body).rounded_rectangle((1, 1, pw - 2, ph - 2), int(sw * 0.16), outline=(70, 74, 72, 255), width=max(1, b // 4))
    ph_img.paste(body, (0, 0), rrect_mask((pw, ph), int(sw * 0.17)))
    s = scr.resize((sw, sh), Image.LANCZOS).convert('RGBA')
    ph_img.paste(s, (b, b), rrect_mask((sw, sh), int(sw * 0.13)))
    d = ImageDraw.Draw(ph_img)
    iw, ih = sw * 0.30, sh * 0.024
    d.rounded_rectangle((pw / 2 - iw / 2, b + sh * 0.012, pw / 2 + iw / 2, b + sh * 0.012 + ih), ih / 2, fill=(0, 0, 0, 255))
    return ph_img, b

# target pose: screen 600 px tall, centred at (PX, PY)
PX, PY, BASE_H = 860, 360, 600.0
# real phone screen corners in opener frame 235 (TL, TR, BR, BL); bottom runs off-frame
SRC_QUAD = [(420, 64), (740, 26), (801, 726), (472, 764)]

def _solve_persp(dst, src):
    """Coefficients mapping output (dst) points to input (src) points for Image.transform PERSPECTIVE."""
    A, B = [], []
    for (x, y), (u, v) in zip(dst, src):
        A.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); B.append(u)
        A.append([0, 0, 0, x, y, 1, -v * x, -v * y]); B.append(v)
    n = 8
    M = [row[:] + [B[i]] for i, row in enumerate(A)]
    for c in range(n):
        p = max(range(c, n), key=lambda r: abs(M[r][c])); M[c], M[p] = M[p], M[c]
        for r in range(n):
            if r != c:
                f = M[r][c] / M[c][c]
                M[r] = [a - f * b for a, b in zip(M[r], M[c])]
    return [M[i][n] / M[i][i] for i in range(n)]

def place_phone(frame, scr, cx, cy, k=1.0, quad=None):
    """Paste the phone. Without quad: upright, screen BASE_H*k tall centred at (cx, cy).
    With quad: perspective-warp so the screen lands on the given 4 corners."""
    if quad is None:
        img, b = phone_image(scr, BASE_H * k)
        frame.alpha_composite(img, (int(round(cx - img.width / 2)), int(round(cy - img.height / 2))))
        return
    img, b = phone_image(scr, 760)
    sw, sh = img.width - 2 * b, img.height - 2 * b
    src = [(b, b), (b + sw, b), (b + sw, b + sh), (b, b + sh)]
    coeffs = _solve_persp(quad, src)
    warped = img.transform((W, H), Image.PERSPECTIVE, coeffs, Image.BICUBIC)
    frame.alpha_composite(warped)

def screen_to_frame(xs, ys, cx, cy, k):
    sh = BASE_H * k; sw = sh * SW / SH
    return cx - sw / 2 + xs * sw / SW, cy - sh / 2 + ys * sh / SH

# ---------- background ----------
@lru_cache(None)
def background():
    gym = Image.open(os.path.join(BUILD, 'opener_bg_src.png')).convert('RGB').resize((W, H))
    bg = gym.filter(ImageFilter.GaussianBlur(28))
    bg = Image.blend(bg, Image.new('RGB', (W, H), (8, 18, 10)), 0.80)
    glow = Image.new('L', (W, H), 0)
    ImageDraw.Draw(glow).ellipse((PX - 380, PY - 380, PX + 380, PY + 380), fill=60)
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    bg = Image.composite(Image.new('RGB', (W, H), GREEN), bg, glow)
    return bg.convert('RGBA')

# ---------- captions ----------
CAPTIONS = [  # (text lines, in frame, out frame)
    (['Find a personal', 'trainer'], 258, 366),
    (['Compare', 'coaches'], 374, 500),
    (['See what', 'clients say'], 508, 638),
]
CAP_X = 128           # inside 10% title-safe margin
def draw_caption(frame, n):
    d = ImageDraw.Draw(frame)
    for lines, a, b in CAPTIONS:
        if not (a <= n < b): continue
        t_in = ease_out(seg(n, a, a + 10)); t_out = 1 - ease(seg(n, b - 8, b))
        al = t_in * t_out
        if al <= 0: continue
        dy = (1 - t_in) * 18
        f = font('PlayfairDisplay-900.ttf', 64)
        lh = 74; total = lh * len(lines)
        y = 360 - total / 2 + dy
        bar = Image.new('RGBA', frame.size, (0, 0, 0, 0)); bd = ImageDraw.Draw(bar)
        bd.rounded_rectangle((CAP_X, y - 26, CAP_X + 64, y - 20), 3, fill=GREEN + (int(255 * al),))
        for i, ln in enumerate(lines):
            col = (GREEN if i == len(lines) - 1 else WHITE) + (int(255 * al),)
            bd.text((CAP_X, y + i * lh), ln, font=f, fill=col)
        frame.alpha_composite(bar)

# ---------- taps ----------
TAPS = []   # filled by timeline: (frame, name, x_canvas, y_canvas) resolved at render time
def draw_tap(frame, n, tap_frame, fx, fy):
    p = (n - tap_frame) / 10.0
    if not (0 <= p <= 1): return
    ov = Image.new('RGBA', frame.size, (0, 0, 0, 0)); d = ImageDraw.Draw(ov)
    r = lerp(9, 30, ease_out(p)); a = int(230 * (1 - p))
    d.ellipse((fx - r, fy - r, fx + r, fy + r), outline=(255, 255, 255, a), width=3)
    if p < 0.5:
        r2 = 10; d.ellipse((fx - r2, fy - r2, fx + r2, fy + r2), fill=(255, 255, 255, int(150 * (1 - p * 2))))
    frame.alpha_composite(ov)

# ---------- end card ----------
@lru_cache(None)
def end_card():
    c = Image.new('RGB', (W, H), (10, 19, 11))
    glow = Image.new('L', (W, H), 0)
    ImageDraw.Draw(glow).ellipse((W / 2 - 420, 120, W / 2 + 420, 600), fill=46)
    glow = glow.filter(ImageFilter.GaussianBlur(140))
    c = Image.composite(Image.new('RGB', (W, H), GREEN), c, glow).convert('RGBA')
    logo = Image.open(LOGO).convert('RGBA').resize((168, 168), Image.LANCZOS)
    c.alpha_composite(logo, (W // 2 - 84, 150))
    d = ImageDraw.Draw(c)
    f1 = font('PlayfairDisplay-900.ttf', 76); t1 = 'Find your trainer'
    d.text((W / 2 - d.textlength(t1, font=f1) / 2, 352), t1, font=f1, fill=WHITE)
    f2 = font('Manrope-700.ttf', 36); t2 = 'coachcards.co.uk'
    d.text((W / 2 - d.textlength(t2, font=f2) / 2, 470), t2, font=f2, fill=GREEN)
    return c

# ---------- timeline ----------
S_MATCH = 815        # scroll that matches the clip's screen (header + Tracy card at top)
S_FILTER = 420       # Delivery filter visible
S_PAUL = 1010

def state(n):
    """Return dict describing the walkthrough at frame n."""
    st = dict(page='any', s=S_MATCH, k=1.0, cx=PX, cy=PY, hl=None, hl_a=0.0, quad=None, xfade=None)
    # match-cut transition 236-255: phone eases from the real phone's pose to the target pose
    if n < 256:
        p = ease(seg(n, CUT, 256))
        tgt_h = BASE_H; tgt_w = tgt_h * SW / SH
        T = [(PX - tgt_w / 2, PY - tgt_h / 2), (PX + tgt_w / 2, PY - tgt_h / 2), (PX + tgt_w / 2, PY + tgt_h / 2), (PX - tgt_w / 2, PY + tgt_h / 2)]
        st['quad'] = [(lerp(a[0], b[0], p), lerp(a[1], b[1], p)) for a, b in zip(SRC_QUAD, T)]
        return st
    # beat 1: find a trainer
    if n < 312:
        st['s'] = lerp(S_MATCH, S_FILTER, ease(seg(n, 276, 300))); return st
    if n < 316:
        st['s'] = S_FILTER; return st
    if n < 345:
        st['page'] = 'inp'; st['s'] = S_FILTER; return st
    if n < 380:
        st['s'] = lerp(S_FILTER, S_MATCH, ease(seg(n, 358, 380))); return st
    # beat 2: compare coaches (zoom toward the cards, highlight one at a time)
    if n < 504:
        zin = ease(seg(n, 380, 400)); zout = ease(seg(n, 494, 504))
        z = zin * (1 - zout)
        st['k'] = 1 + 0.45 * z
        mv = ease(seg(n, 440, 458)); back = ease(seg(n, 494, 504))
        st['s'] = lerp(lerp(S_MATCH, S_PAUL, mv), S_MATCH, back)
        tr = TRACY_CARD; pa = PAUL_CARD
        rect_css = tuple(lerp(a, b, mv) for a, b in zip(tr, pa))
        x0, y0 = page_to_screen('any', rect_css[0], rect_css[1], st['s']); x1, y1 = page_to_screen('any', rect_css[2], rect_css[3], st['s'])
        st['hl'] = (x0, y0, x1, y1); st['hl_a'] = ease(seg(n, 380, 392)) * (1 - ease(seg(n, 494, 502)))
        # keep the highlighted card near the vertical centre while zoomed
        cyc = (y0 + y1) / 2
        st['cy'] = PY - (cyc - SH / 2) * (BASE_H * st['k'] / SH) * z
        return st
    # beat 3: open Tracy's profile, hold on a verbatim review
    if n < 516:
        return st
    if n < 526:   # slide profile in from the right
        st['xfade'] = ('any', S_MATCH, 'hero', 0, ease(seg(n, 516, 526)), 'h'); return st
    if n < 556:
        st['page'] = 'hero'; st['s'] = 0; return st
    if n < 566:   # scroll-style move up into the reviews section
        st['xfade'] = ('hero', 0, 'reviews', 0, ease(seg(n, 556, 566)), 'v'); return st
    st['page'] = 'reviews'; st['s'] = 0
    z = ease(seg(n, 566, 586)); st['k'] = 1 + 0.45 * z
    st['hl'] = REVIEW_CARD; st['hl_a'] = ease(seg(n, 566, 576))
    cyc = (REVIEW_CARD[1] + REVIEW_CARD[3]) / 2
    st['cy'] = PY - (cyc - SH / 2) * (BASE_H * st['k'] / SH) * z
    return st

TAP_EVENTS = [  # (frame, page, x_css, y_css, scroll) -- reviews coords would be canvas px
    (312, 'any', (DELIVERY[0] + DELIVERY[2]) / 2, (DELIVERY[1] + DELIVERY[3]) / 2, S_FILTER),
    (341, 'inp', (DELIVERY[0] + DELIVERY[2]) / 2, (DELIVERY[1] + DELIVERY[3]) / 2, S_FILTER),
    (512, 'any', (TRACY_CARD[0] + TRACY_CARD[2]) / 2, (TRACY_CARD[1] + TRACY_CARD[3]) / 2, S_MATCH),
]

def build_screen(st):
    if st['xfade']:
        a, sa, b, sb, p, axis = st['xfade']
        A = screen(a, sa); B = screen(b, sb)
        c = Image.new('RGB', (SW, SH))
        if axis == 'h':
            off = int(SW * p); c.paste(A, (-off // 3, 0)); c.paste(B, (SW - off, 0))
        else:   # content scrolls up under a pinned status bar + nav (hero nav ends 218 px, reviews nav 215 px)
            top_a, top_b = STATUS_H + NAV_H['hero'], 215
            off = int((SH - top_b) * p)
            body_a = A.crop((0, top_a, SW, SH)); body_b = B.crop((0, top_b, SW, SH))
            c.paste(body_a, (0, top_b - off)); c.paste(body_b, (0, SH - off))
            c.paste(B.crop((0, 0, SW, top_b)), (0, 0))
        return c
    scr = screen(st['page'], st['s'])
    if st['hl'] and st['hl_a'] > 0:
        scr = highlight(scr, st['hl'], st['hl_a'], top=215 if st['page'] == 'reviews' else STATUS_H + 126)
    return scr

def render(n):
    assert CUT <= n <= LAST
    if n >= END_CARD:
        return end_card().convert('RGB')
    frame = background().copy()
    st = state(n)
    scr = build_screen(st)
    place_phone(frame, scr, st['cx'], st['cy'], st['k'], st['quad'])
    for tf, pg, xc, yc, s in TAP_EVENTS:
        if tf <= n <= tf + 10:
            xs, ys = page_to_screen(pg, xc, yc, s)
            fx, fy = screen_to_frame(xs, ys, st['cx'], st['cy'], st['k'])
            draw_tap(frame, n, tf, fx, fy)
    draw_caption(frame, n)
    if n >= END_CARD - 8:   # 8-frame dissolve into the static end card
        a = ease(seg(n, END_CARD - 8, END_CARD))
        frame = Image.blend(frame, end_card(), a)
    return frame.convert('RGB')

if __name__ == '__main__':
    out = sys.argv[1]; frames = [int(x) for x in sys.argv[2].split(',')] if len(sys.argv) > 2 else range(CUT, LAST + 1)
    os.makedirs(out, exist_ok=True)
    for n in frames:
        render(n).save(os.path.join(out, f'f{n:04d}.png'))
    print('rendered', len(list(frames)))
