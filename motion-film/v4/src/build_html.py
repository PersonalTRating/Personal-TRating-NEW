"""Inline fonts, images and the guide mix (MP3) into one self-contained HTML file."""
import base64, json, os, re
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MIME = {'.ttf': 'font/ttf', '.jpg': 'image/jpeg', '.png': 'image/png', '.mp3': 'audio/mpeg'}
uri = lambda p: f"data:{MIME[os.path.splitext(p)[1]]};base64," + base64.b64encode(open(p, 'rb').read()).decode()
html = open(os.path.join(ROOT, 'src', 'film.template.html'), encoding='utf-8').read()
html = re.sub(r'\{\{FONT:([^}]+)\}\}', lambda m: uri(os.path.join(ROOT, 'assets', 'fonts', m.group(1))), html)
d = os.path.join(ROOT, 'build', 'img')
used = set(re.findall(r"IMG\.([A-Za-z0-9_]+)", html)) | set(re.findall(r"IMG\['([A-Za-z0-9_-]+)'", html))
used = {u for u in used if not u.endswith('_')}
for s in ('uk', 'country', 'local'): used |= {f'tabs_{s}', f'list_{s}'}
imgs = {os.path.splitext(f)[0]: os.path.join(d, f) for f in sorted(os.listdir(d))}
missing = used - set(imgs); assert not missing, missing
html = html.replace('{{IMAGES}}', json.dumps({k: uri(imgs[k]) for k in sorted(used)}))
html = html.replace('{{AUDIO}}', uri(os.path.join(ROOT, 'build', 'seg_mix.mp3')))
out = os.path.join(ROOT, 'out', 'CoachCards-Overview-15s.html'); open(out, 'w', encoding='utf-8').write(html)
print(out, round(os.path.getsize(out) / 1e6, 2), 'MB')
