"""Prepare v3 images (build/img): UK leaderboard heading and cards, Tracy Gibson's profile header, Carole Taylor's review, opener last frame."""
import os
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(ROOT, 'assets'); B = os.path.join(ROOT, 'build', 'img'); os.makedirs(B, exist_ok=True)
MF = os.path.dirname(ROOT); REPO = os.path.dirname(MF)
def save(im, name, q=88, w=None):
    if w: im = im.resize((w, round(im.height * w / im.width)), Image.LANCZOS)
    (im.save(os.path.join(B, name), optimize=True) if name.endswith('.png') else im.convert('RGB').save(os.path.join(B, name), quality=q, optimize=True)); print(name, im.size)
save(Image.open(os.path.join(A, 'uk_heading.png')), 'heading.png', w=900)
for k in ('tracy_gibson', 'paul_davies', 'joe_wilson'): save(Image.open(os.path.join(A, f'card_{k}.png')), f'card_{k}.png')
prof = Image.open(os.path.join(A, 'tracy_profile_top.png'))
save(prof.crop((0, 0, prof.width, 440 * 3)), 'profile.jpg', w=900)          # down to the name row, above "@peachcamp"
save(Image.open(os.path.join(MF, 'captures', 'profile_reviews_signedin_user.webp')).crop((46, 262, 878, 775)), 'review_card.jpg', q=92)   # user's signed-in screenshot
save(Image.open(os.path.join(ROOT, 'build', 'opener_f359.png')), 'opener_last.jpg', q=92)
save(Image.open(os.path.join(REPO, 'assets', 'production', 'logos', 'cc-logo.png')), 'cc-logo.png')
