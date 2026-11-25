"""Build the 30.000 s soundtrack: original opener audio, a 1.5 s gym-ambience tail across the cut,
and subtle synthesised taps on the exact tap frames. No voiceover, no music."""
import os, wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR, FPS, TOTAL = 48000, 24, 720
CUT = 236
TAIL_S = 1.5
TAP_FRAMES = [312, 341, 512]

w = wave.open(os.path.join(ROOT, 'build', 'opener_audio.wav'))
src = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).reshape(-1, 2).astype(np.float64) / 32768

n_total = TOTAL * SR // FPS                     # 1,440,000 samples = 30.000 s
out = np.zeros((n_total, 2))
cut = CUT * SR // FPS                           # 9.8333 s
out[:cut] = src[:cut]
tail_n = int(TAIL_S * SR)
tail = src[cut:cut + tail_n].copy()
tail *= np.linspace(1, 0, len(tail))[:, None] ** 1.5
out[cut:cut + len(tail)] += tail

# quiet gym ambience bed under the walkthrough: loop the opener's quietest room tone (7.80-9.20 s,
# before the tap sound) with equal-power crossfades, fade it in under the tail and out over the end card
BED_SRC = (7.80, 9.20)
BED_RMS_DB = -44.0
XF = int(0.35 * SR)
loop = src[int(BED_SRC[0] * SR):int(BED_SRC[1] * SR)].copy()
need = n_total - cut
bed = loop.copy()
fade_out = np.cos(np.linspace(0, np.pi / 2, XF))[:, None]; fade_in = np.sin(np.linspace(0, np.pi / 2, XF))[:, None]
while len(bed) < need:
    nxt = loop if (len(bed) // len(loop)) % 2 == 0 else loop[::-1]   # alternate direction to avoid an audible repeat
    bed = np.concatenate([bed[:-XF], bed[-XF:] * fade_out + nxt[:XF] * fade_in, nxt[XF:]])
bed = bed[:need]
bed *= 10 ** (BED_RMS_DB / 20) / (np.sqrt((bed ** 2).mean()) + 1e-12)
t = np.arange(need) / SR
env = np.clip(t / 1.2, 0, 1)                                   # fade in under the 1.5 s tail
end_t = (27.0 * SR - cut) / SR
env *= np.clip(1 - (t - end_t) / 2.8, 0, 1)                    # fade out 27.0 -> 29.8 s across the end card
out[cut:] += bed * env[:, None]

def tap():
    t = np.arange(int(0.045 * SR)) / SR
    tone = np.sin(2 * np.pi * 1700 * t) * np.exp(-t / 0.007)
    rng = np.random.default_rng(7)
    noise = np.convolve(rng.standard_normal(len(t)), np.ones(6) / 6, 'same') * np.exp(-t / 0.004)
    s = 0.6 * tone + 0.4 * noise
    return s / np.abs(s).max() * 10 ** (-20 / 20)   # peak -20 dBFS: subtle

for f in TAP_FRAMES:
    i = f * SR // FPS; s = tap()
    out[i:i + len(s)] += s[:, None]

peak = np.abs(out).max()
if peak > 10 ** (-1 / 20):
    out *= 10 ** (-1 / 20) / peak
pcm = (np.clip(out, -1, 1) * 32767).astype(np.int16)
with wave.open(os.path.join(ROOT, 'build', 'soundtrack.wav'), 'wb') as o:
    o.setnchannels(2); o.setsampwidth(2); o.setframerate(SR); o.writeframes(pcm.tobytes())
print('samples', len(pcm), 'seconds', len(pcm) / SR, 'peak dBFS', round(20 * np.log10(np.abs(out).max()), 2))
