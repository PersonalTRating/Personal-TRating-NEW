"""Assemble the 30.000 s advert: original opener frames 0-235 (unchanged) + the 484-frame segment, 1280x720 @ 24 fps.
Audio: opener audio to the cut, a 1.5 s gym tail, a quiet ambience bed under the segment, and the segment effects."""
import os, subprocess, wave
import numpy as np
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FF = r'C:\Users\moder\AppData\Roaming\Python\Python314\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v9.0.2.exe'
OPENER = r'C:\Users\moder\OneDrive\Desktop\CoachCards-Doorway-Edit.mp4'
B = os.path.join(ROOT, 'build'); SR, FPS, CUT, TOTAL = 48000, 24, 236, 720
run = lambda *a: subprocess.run([FF, '-hide_banner', '-v', 'error', *a], check=True)

# segment-only MP4 (1920x1080, 24 fps) straight from the HTML frames
run('-framerate', '24', '-i', os.path.join(B, 'frames', 'f%04d.png'), '-i', os.path.join(B, 'sfx.wav'), '-map', '0:v', '-map', '1:a',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '17', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '256k', '-movflags', '+faststart', '-y', os.path.join(ROOT, 'out', 'CoachCards-Feature-Segment.mp4'))

# soundtrack
run('-i', OPENER, '-vn', '-ac', '2', '-ar', str(SR), '-c:a', 'pcm_s16le', '-y', os.path.join(B, 'opener.wav'))
rd = lambda p: (lambda w: np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).reshape(-1, 2).astype(float) / 32768)(wave.open(p))
src, sfx = rd(os.path.join(B, 'opener.wav')), rd(os.path.join(B, 'sfx.wav'))
n = TOTAL * SR // FPS; cut = CUT * SR // FPS; out = np.zeros((n, 2))
out[:cut] = src[:cut]
tail = src[cut:cut + int(1.5 * SR)].copy(); tail *= np.linspace(1, 0, len(tail))[:, None] ** 1.5; out[cut:cut + len(tail)] += tail
loop = src[int(7.8 * SR):int(9.2 * SR)]; XF = int(.35 * SR); bed = loop.copy()
fo, fi = np.cos(np.linspace(0, np.pi / 2, XF))[:, None], np.sin(np.linspace(0, np.pi / 2, XF))[:, None]
while len(bed) < n - cut:
    nxt = loop if (len(bed) // len(loop)) % 2 == 0 else loop[::-1]; bed = np.concatenate([bed[:-XF], bed[-XF:] * fo + nxt[:XF] * fi, nxt[XF:]])
bed = bed[:n - cut]; bed *= 10 ** (-44 / 20) / np.sqrt((bed ** 2).mean()); tt = np.arange(len(bed)) / SR
envb = np.clip(tt / 1.2, 0, 1) * np.clip(1 - (tt - (27.0 * SR - cut) / SR) / 2.8, 0, 1); out[cut:] += bed * envb[:, None]
out[cut:cut + len(sfx)] += sfx[:n - cut] * 10 ** (8 / 20)          # effects sit ~8 dB above their standalone level
pk = np.abs(out).max(); out *= min(1, 10 ** (-1 / 20) / pk)
with wave.open(os.path.join(B, 'advert.wav'), 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes((np.clip(out, -1, 1) * 32767).astype(np.int16).tobytes())

# picture: opener frames 0-235 untouched in timing; segment scaled 1920x1080 -> 1280x720 (opener's size and aspect)
run('-i', OPENER, '-framerate', '24', '-i', os.path.join(B, 'frames', 'f%04d.png'), '-i', os.path.join(B, 'advert.wav'),
    '-filter_complex', '[0:v]trim=end_frame=236,setpts=PTS-STARTPTS,format=yuv420p,setsar=1[a];[1:v]scale=1280:720:flags=lanczos,format=yuv420p,setsar=1,setpts=PTS-STARTPTS[b];[a][b]concat=n=2:v=1:a=0,fps=24[v]',
    '-map', '[v]', '-map', '2:a', '-c:v', 'libx264', '-preset', 'slow', '-crf', '17', '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-r', '24',
    '-c:a', 'aac', '-b:a', '256k', '-ar', '48000', '-movflags', '+faststart', '-t', '30', '-y', os.path.join(ROOT, 'out', 'CoachCards-30s-Advert-v2.mp4'))
print('assembled')
