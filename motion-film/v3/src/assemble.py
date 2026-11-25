"""Assemble the 30.000 s advert: opener frames 0-359 (15.000 s, untouched timing) + the 360-frame features segment, 1280x720 @ 24 fps.
Audio: opener audio for its 15 s, a quiet gym ambience bed (looped from the opener's quietest stretch) across the cut, plus segment effects."""
import os, subprocess, wave
import numpy as np
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FF = r'C:\Users\moder\AppData\Roaming\Python\Python314\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v9.0.2.exe'
OPENER = r'C:\Users\moder\OneDrive\Desktop\FINAL VID SEEDANCE.mp4'
B = os.path.join(ROOT, 'build'); SR, FPS, CUT, TOTAL = 48000, 24, 360, 720
run = lambda *a: subprocess.run([FF, '-hide_banner', '-v', 'error', *a], check=True)
run('-framerate', '24', '-i', os.path.join(B, 'frames', 'f%04d.png'), '-i', os.path.join(B, 'sfx.wav'), '-map', '0:v', '-map', '1:a',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '17', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '256k', '-movflags', '+faststart', '-y', os.path.join(ROOT, 'out', 'CoachCards-Features-15s.mp4'))
run('-i', OPENER, '-vn', '-ac', '2', '-ar', str(SR), '-c:a', 'pcm_s16le', '-y', os.path.join(B, 'opener.wav'))
rd = lambda p: (lambda w: np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).reshape(-1, 2).astype(float) / 32768)(wave.open(p))
src, sfx = rd(os.path.join(B, 'opener.wav')), rd(os.path.join(B, 'sfx.wav'))
n = TOTAL * SR // FPS; cut = CUT * SR // FPS; out = np.zeros((n, 2))
k = min(cut, len(src)); out[:k] = src[:k]
fade = int(0.08 * SR); out[cut - fade:cut] *= np.linspace(1, 0.35, fade)[:, None]      # soften the opener's last syllable into the cut
loop = src[int(12.5 * SR):int(14.0 * SR)]; XF = int(.35 * SR); bed = loop.copy()
fo, fi = np.cos(np.linspace(0, np.pi / 2, XF))[:, None], np.sin(np.linspace(0, np.pi / 2, XF))[:, None]
while len(bed) < n - cut:
    nxt = loop if (len(bed) // len(loop)) % 2 == 0 else loop[::-1]; bed = np.concatenate([bed[:-XF], bed[-XF:] * fo + nxt[:XF] * fi, nxt[XF:]])
bed = bed[:n - cut]; bed *= 10 ** (-44 / 20) / np.sqrt((bed ** 2).mean()); tt = np.arange(len(bed)) / SR
envb = np.clip(1 - (tt - 12.5) / 2.3, 0, 1); out[cut:] += bed * envb[:, None]
out[cut:cut + len(sfx)] += sfx[:n - cut] * 10 ** (8 / 20)
out *= min(1, 10 ** (-1 / 20) / np.abs(out).max())
with wave.open(os.path.join(B, 'advert.wav'), 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes((np.clip(out, -1, 1) * 32767).astype(np.int16).tobytes())
run('-i', OPENER, '-framerate', '24', '-i', os.path.join(B, 'frames', 'f%04d.png'), '-i', os.path.join(B, 'advert.wav'),
    '-filter_complex', f'[0:v]trim=end_frame={CUT},setpts=PTS-STARTPTS,format=yuv420p,setsar=1[a];[1:v]scale=1280:720:flags=lanczos,format=yuv420p,setsar=1,setpts=PTS-STARTPTS[b];[a][b]concat=n=2:v=1:a=0,fps=24[v]',
    '-map', '[v]', '-map', '2:a', '-c:v', 'libx264', '-preset', 'slow', '-crf', '17', '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-r', '24',
    '-c:a', 'aac', '-b:a', '256k', '-ar', '48000', '-movflags', '+faststart', '-t', '30', '-y', os.path.join(ROOT, 'out', 'CoachCards-30s-Advert-v3.mp4'))
print('assembled')
