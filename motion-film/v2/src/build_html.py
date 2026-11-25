"""Inline fonts, images, verified card data and the MP3 into one self-contained HTML file."""
import base64, json, os, re
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MIME = {'.ttf': 'font/ttf', '.jpg': 'image/jpeg', '.png': 'image/png', '.mp3': 'audio/mpeg'}
uri = lambda p: f"data:{MIME[os.path.splitext(p)[1]]};base64," + base64.b64encode(open(p, 'rb').read()).decode()
live = json.load(open(os.path.join(ROOT, 'assets', 'live_info.json')))
def card(prefix):   # fields exactly as shown on the live London leaderboard card
    c = [x for x in live['cards'] if x['text'].startswith(prefix)][0]['text']
    name, rest = prefix, c[len(prefix):].strip()
    loc, rest = rest.split(' ', 1)
    spec = rest.split(' verified reviews')[0].rsplit(' ', 1)[0]
    return {'name': name, 'location': loc, 'specialty': spec}
rv = Image.open(os.path.join(ROOT, 'build', 'img', 'review_card.jpg'))
DATA = {'paul': card('Paul Davies'), 'mike': card('Mike Wilson'), 'review_w': rv.width, 'review_h': rv.height}
html = open(os.path.join(ROOT, 'src', 'film.template.html'), encoding='utf-8').read()
html = re.sub(r'\{\{FONT:([^}]+)\}\}', lambda m: uri(os.path.join(ROOT, 'assets', 'fonts', m.group(1))), html)
d = os.path.join(ROOT, 'build', 'img')
html = html.replace('{{IMAGES}}', json.dumps({os.path.splitext(f)[0]: uri(os.path.join(d, f)) for f in sorted(os.listdir(d))}))
html = html.replace('{{DATA}}', json.dumps(DATA)).replace('{{AUDIO}}', uri(os.path.join(ROOT, 'build', 'sfx.mp3')))
out = os.path.join(ROOT, 'out', 'CoachCards-Feature-Segment.html'); open(out, 'w', encoding='utf-8').write(html)
print(DATA); print(out, round(os.path.getsize(out) / 1e6, 2), 'MB')
