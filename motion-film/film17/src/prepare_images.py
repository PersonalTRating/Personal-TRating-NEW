"""Crop and compress the live captures into the exact images the film uses (build/img)."""
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(ROOT, 'assets', 'img'); B = os.path.join(ROOT, 'build', 'img'); os.makedirs(B, exist_ok=True)
S = 1.5  # desktop capture scale (px per css px)

def save(im, name, w=None, q=86):
    im = im.convert('RGB')
    if w and im.width != w: im = im.resize((w, round(im.height * w / im.width)), Image.LANCZOS)
    im.save(os.path.join(B, name), quality=q, optimize=True); print(name, im.size)

any_ = Image.open(os.path.join(A, 'desk_fat_any.png')); wl = Image.open(os.path.join(A, 'desk_fat_weightloss.png'))
# scene A: css y 520 .. 1610 (window shows 1090 css rows at 0.767 display scale)
for im, n in ((any_, 'fatA_any.jpg'), (wl, 'fatA_wl.jpg')):
    crop = im.crop((0, int(520 * S), im.width, min(im.height, int(1640 * S))))
    if crop.height < int(1120 * S):
        pad = Image.new('RGB', (crop.width, int(1120 * S)), (10, 19, 11)); pad.paste(crop, (0, 0)); crop = pad
    save(crop, n, w=1440)
# real coach cards (Weight Loss result)
save(wl.crop((int(202 * S), int(828.1 * S), int(1238 * S), int(980.7 * S))), 'card_tracy.jpg', w=1300)
save(wl.crop((int(202 * S), int(996.7 * S), int(1238 * S), int(1123.7 * S))), 'card_paul.jpg', w=1300)
# Tracy profile header (signed out, desktop)
save(Image.open(os.path.join(A, 'desk_profile_tracy.png')).crop((0, 0, int(1440 * S), int(650 * S))), 'profile_hero.jpg', w=1440)
# Carole Taylor review card from the user's signed-in iPhone screenshot (924x2000)
save(Image.open(os.path.join(A, 'profile_reviews_signedin_user.webp')).crop((46, 262, 878, 775)), 'review_card.jpg', w=832, q=90)
# mobile screens for the outputs story card
for src, n in (('fat_any_y0000.jpg', 'mob_fat.jpg'), ('fat_any_y0750.jpg', 'mob_cards.jpg'), ('profile_reviews_signedin_user.webp', 'mob_reviews.jpg')):
    save(Image.open(os.path.join(A, src)), n, w=600)
save(Image.open(os.path.join(A, 'trainer-portrait.webp')), 'trainer.jpg', w=687, q=90)
for n in ('cc-logo.png', 'coachcards-founder-badge.png'):
    Image.open(os.path.join(A, n)).save(os.path.join(B, n), optimize=True); print(n)
