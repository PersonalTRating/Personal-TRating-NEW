"""Prepare v4 images (build/img)."""
import os
from PIL import Image, ImageFilter, ImageEnhance
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(ROOT, 'assets'); B = os.path.join(ROOT, 'build', 'img'); os.makedirs(B, exist_ok=True)
MF = os.path.dirname(ROOT); REPO = os.path.dirname(MF); V3 = os.path.join(MF, 'v3')
def save(im, name, q=88, w=None):
    if w: im = im.resize((w, round(im.height * w / im.width)), Image.LANCZOS)
    (im.save(os.path.join(B, name), optimize=True) if name.endswith('.png') else im.convert('RGB').save(os.path.join(B, name), quality=q, optimize=True)); print(name, im.size)
for n in ('uk', 'country', 'local'): save(Image.open(os.path.join(A, f'search_{n}.png')), f'search_{n}.jpg', w=900)
m = Image.open(os.path.join(A, 'map.png')); save(m.crop((0, 150, m.width, 150 + 1500)), 'map.jpg', w=800)
save(Image.open(os.path.join(A, 'bmp_panel.png')), 'bmp_panel.png', w=1050)
save(Image.open(os.path.join(A, 'tiers.png')), 'tiers.png', w=1688)
save(Image.open(os.path.join(ROOT, 'brief', 'image6.png')), 'trending_mike.png')                     # user's snapshot, as supplied
save(Image.open(os.path.join(MF, 'captures', 'profile_reviews_signedin_user.webp')).crop((46, 262, 878, 775)), 'review_card.jpg', q=92)
# anonymised leaderboard rows: real card crops, heavily blurred so no trainer is identifiable
for i, n in enumerate(('tracy_gibson', 'paul_davies', 'joe_wilson')):
    im = Image.open(os.path.join(V3, 'assets', f'card_{n}.png')).convert('RGB').resize((708, None or round(Image.open(os.path.join(V3, 'assets', f'card_{n}.png')).height * 708 / 1062)), Image.LANCZOS)
    im = ImageEnhance.Color(im.filter(ImageFilter.GaussianBlur(16))).enhance(0.75)
    save(im, f'ghost{i}.jpg', q=80)
save(Image.open(os.path.join(ROOT, 'build', 'opener2_f359.png')), 'opener_last.jpg', q=92)   # 'SEEDANCE ACUAL FINAL VIDEO', frame 359
save(Image.open(os.path.join(REPO, 'assets', 'production', 'logos', 'cc-logo.png')), 'cc-logo.png')
