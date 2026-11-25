"""Inline every font, image and the MP3 as base64 data URIs into one self-contained HTML file."""
import base64, json, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MIME = {'.ttf': 'font/ttf', '.jpg': 'image/jpeg', '.png': 'image/png', '.mp3': 'audio/mpeg'}
def uri(path):
    return f"data:{MIME[os.path.splitext(path)[1]]};base64," + base64.b64encode(open(path, 'rb').read()).decode()

html = open(os.path.join(ROOT, 'src', 'film.template.html'), encoding='utf-8').read()
html = re.sub(r'\{\{FONT:([^}]+)\}\}', lambda m: uri(os.path.join(ROOT, 'assets', 'fonts', m.group(1))), html)
imgdir = os.path.join(ROOT, 'build', 'img')
images = {os.path.splitext(f)[0]: uri(os.path.join(imgdir, f)) for f in sorted(os.listdir(imgdir))}
html = html.replace('{{IMAGES}}', json.dumps(images))
html = html.replace('{{AUDIO}}', uri(os.path.join(ROOT, 'build', 'sound.mp3')))
out = os.path.join(ROOT, 'out', 'CoachCards-Motion-Film.html')
open(out, 'w', encoding='utf-8').write(html)
print(out, round(os.path.getsize(out) / 1e6, 2), 'MB')
