"""Prepare v2 images (build/img) from live captures, the opener and (when supplied) the review screenshot."""
import os, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(ROOT, 'assets'); B = os.path.join(ROOT, 'build', 'img'); os.makedirs(B, exist_ok=True)
REPO = os.path.dirname(os.path.dirname(ROOT))
FF = r'C:\Users\moder\AppData\Roaming\Python\Python314\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v9.0.2.exe'
OPENER = r'C:\Users\moder\OneDrive\Desktop\CoachCards-Doorway-Edit.mp4'

def save(im, name, q=88, w=None):
    if w: im = im.resize((w, round(im.height * w / im.width)), Image.LANCZOS)
    if name.endswith('.png'): im.save(os.path.join(B, name), optimize=True)
    else: im.convert('RGB').save(os.path.join(B, name), quality=q, optimize=True)
    print(name, im.size)

# phone-screen view for the match-cut (status/nav area included, as on the phone)
save(Image.open(os.path.join(A, 'london_phone_view.png')), 'phone_view.jpg', w=900)
save(Image.open(os.path.join(A, 'london_heading.png')), 'heading.png', w=900)
for n in ('paul_davies', 'joseph_mitchell', 'mike_wilson'):
    save(Image.open(os.path.join(A, f'card_{n}.png')), f'card_{n}.png', w=1062)
# Paul Davies profile header: top of page down to the name row (css y 410), above the @handle line
prof = Image.open(os.path.join(A, 'paul_profile_top.png'))
save(prof.crop((0, 0, prof.width, 410 * 3)), 'profile_paul.jpg', w=900)
# frozen last opener frame (frame 235) for the handoff
f235 = os.path.join(ROOT, 'build', 'opener_f235.png')
if not os.path.exists(f235):
    subprocess.run([FF, '-v', 'error', '-i', OPENER, '-vf', r"select='eq(n\,235)'", '-fps_mode', 'passthrough', '-frames:v', '1', '-y', f235], check=True)
save(Image.open(f235), 'opener_last.jpg', q=92)
save(Image.open(os.path.join(REPO, 'assets', 'production', 'logos', 'cc-logo.png')), 'cc-logo.png')
# review card: user-supplied signed-in screenshot if present, else a clearly marked placeholder
rv = [f for f in os.listdir(A) if f.startswith('review_paul')]
if rv:
    im = Image.open(os.path.join(A, rv[0])); box = [int(v) for v in os.environ.get('REVIEW_BOX', '0,0,0,0').split(',')]
    if box[2] > 0: im = im.crop(box)
    save(im, 'review_card.jpg', q=92)
else:
    ph = Image.new('RGB', (828, 420), (255, 255, 255)); d = ImageDraw.Draw(ph)
    d.rounded_rectangle((4, 4, 823, 415), 28, outline=(232, 72, 72), width=6)
    f = ImageFont.truetype(os.path.join(REPO, 'assets', 'production', 'fonts', 'Manrope-700.ttf'), 34)
    d.text((60, 150), 'PLACEHOLDER — awaiting signed-in', font=f, fill=(232, 72, 72)); d.text((60, 200), 'screenshot of Paul Davies review', font=f, fill=(232, 72, 72))
    save(ph, 'review_card.jpg')
