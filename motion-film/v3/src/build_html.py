"""Inline fonts, images, verified card fields and the MP3 into one self-contained HTML file."""
import base64, json, os, re
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MIME = {'.ttf': 'font/ttf', '.jpg': 'image/jpeg', '.png': 'image/png', '.mp3': 'audio/mpeg'}
uri = lambda p: f"data:{MIME[os.path.splitext(p)[1]]};base64," + base64.b64encode(open(p, 'rb').read()).decode()
live = json.load(open(os.path.join(ROOT, 'assets', 'live_info.json')))
text = {c['key']: c['text'] for c in live['cards']}
# fields exactly as printed on the live UK leaderboard cards (checked against live_info.json below)
DATA = {'tracy': {'name': 'Tracy Gibson', 'fields': ['Scotland', 'Weight Loss', 'Online & In Person']},
        'paul': {'name': 'Paul Davies', 'fields': ['London', 'Weight Loss']}}
for k, key in (('tracy', 'tracy_gibson'), ('paul', 'paul_davies')):
    for f in DATA[k]['fields'] + [DATA[k]['name']]:
        assert f in text[key], (f, text[key])
assert 'In Person' not in text['paul_davies']
rv = Image.open(os.path.join(ROOT, 'build', 'img', 'review_card.jpg')); DATA.update(review_w=rv.width, review_h=rv.height)
html = open(os.path.join(ROOT, 'src', 'film.template.html'), encoding='utf-8').read()
html = re.sub(r'\{\{FONT:([^}]+)\}\}', lambda m: uri(os.path.join(ROOT, 'assets', 'fonts', m.group(1))), html)
d = os.path.join(ROOT, 'build', 'img')
html = html.replace('{{IMAGES}}', json.dumps({os.path.splitext(f)[0]: uri(os.path.join(d, f)) for f in sorted(os.listdir(d))}))
html = html.replace('{{DATA}}', json.dumps(DATA)).replace('{{AUDIO}}', uri(os.path.join(ROOT, 'build', 'sfx.mp3')))
out = os.path.join(ROOT, 'out', 'CoachCards-Features-15s.html'); open(out, 'w', encoding='utf-8').write(html)
print('fields verified against live cards;', out, round(os.path.getsize(out) / 1e6, 2), 'MB')
