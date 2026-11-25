"""Synthesised sound design for the 17.2 s film (effects only, no music). Every event is placed on its frame."""
import math, os, wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR, DUR = 48000, 17.2
N = int(SR * DUR)
L = np.zeros(N); R = np.zeros(N)
rng = np.random.default_rng(11)

def place(sig, t, gain=1.0, pan=0.0):
    i = int(round(t * SR)); s = sig * gain
    j = min(N, i + len(s)); s = s[:j - i]
    l, r = math.cos((pan + 1) * math.pi / 4), math.sin((pan + 1) * math.pi / 4)
    L[i:j] += s * l * 1.414; R[i:j] += s * r * 1.414

def env(n, a, d):
    t = np.arange(n) / SR
    return np.minimum(1, t / max(a, 1e-4)) * np.exp(-t / d)

def lowpass(x, k):
    k = max(1, int(k)); return np.convolve(x, np.ones(k) / k, 'same')

def pop(f=520):
    n = int(.09 * SR); t = np.arange(n) / SR
    return np.sin(2 * np.pi * (f * (1 + 1.5 * np.exp(-t / .01))) * t) * env(n, .002, .025)

def tap(f=1600, d=.012):
    n = int(.05 * SR); t = np.arange(n) / SR
    return (0.6 * np.sin(2 * np.pi * f * t) + 0.4 * lowpass(rng.standard_normal(n), 4)) * env(n, .0008, d)

def wood(f):
    n = int(.14 * SR); t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t) * np.exp(-t / .035) + 0.35 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t / .012)
    return s * np.minimum(1, t / .001)

def whoosh(dur=.45, bright=6):
    n = int(dur * SR); t = np.arange(n) / SR
    noise = rng.standard_normal(n); shape = np.sin(np.pi * t / dur) ** 2
    lo = lowpass(noise, 40); hi = lowpass(noise, bright)
    sweep = t / dur
    return (lo * (1 - sweep) + hi * sweep) * shape

def swell(dur=.4):
    n = int(dur * SR); t = np.arange(n) / SR
    return lowpass(rng.standard_normal(n), 30) * (t / dur) ** 2.2

def thump(f=58, d=.16):
    n = int(.45 * SR); t = np.arange(n) / SR
    return np.sin(2 * np.pi * (f * (1 + .8 * np.exp(-t / .03))) * t) * env(n, .002, d)

def click(rel=False):
    n = int(.03 * SR); t = np.arange(n) / SR
    s = lowpass(rng.standard_normal(n), 2 if not rel else 5) * env(n, .0003, .004 if not rel else .003)
    s += (0.5 if not rel else 0.25) * np.sin(2 * np.pi * (3200 if not rel else 2400) * t) * env(n, .0003, .003)
    return s * (1 if not rel else 0.45)

def impact():
    return thump(44, .35) * 1.0 + lowpass(rng.standard_normal(int(.45 * SR)), 60) * env(int(.45 * SR), .003, .12) * 0.5

def thock(f=180):
    n = int(.2 * SR); t = np.arange(n) / SR
    return (np.sin(2 * np.pi * f * t) * np.exp(-t / .05) + 0.3 * lowpass(rng.standard_normal(n), 10) * np.exp(-t / .01))

def felt_chord(freqs, dur=1.9):
    n = int(dur * SR); t = np.arange(n) / SR; s = np.zeros(n)
    for k, f in enumerate(freqs):
        tone = sum((0.55 ** h) * np.sin(2 * np.pi * f * (h + 1) * t + k) for h in range(4))
        s += tone * np.exp(-t / (0.9 - 0.08 * k))
    hammer = lowpass(rng.standard_normal(n), 25) * np.exp(-t / .008) * 0.4
    return lowpass(s, 3) * np.minimum(1, t / .006) + hammer

FPS = 30
# hook
place(pop(560), 0.28, .9)
place(swell(.7), 0.15, .25)
for i in range(21):
    d = abs(i - 10); tin = .28 if i == 10 else .42 + d * .022
    if i != 10: place(tap(2200, .006), tin, .12, (i - 10) / 12)
for i in range(21):
    ft = .95 + math.sqrt(i / 20) * 1.0
    place(wood(420 * 2 ** (i / 24)), ft, .5, -0.8 + 1.6 * i / 20)
place(whoosh(.42, 5), 1.98, .55)
# intro
place(swell(.36), 2.02, .45); place(thump(60, .18), 2.38, 1.0)
# cursor presses and releases
for p in (4.05, 5.32, 6.22, 8.33, 9.48): place(click(), p, .9)
for r in (4.68, 8.62): place(click(True), r, .9)
# transitions
place(whoosh(.36), 6.42, .55); place(whoosh(.36), 8.30, .55)
place(whoosh(.5, 8), 10.16, .65); place(impact(), 10.42, .9)
place(whoosh(.42, 4), 11.62, .7)
# outputs
for p in (12.15, 13.0, 13.85, 14.7): place(thock(170), p, .8)
# end chord (C major, felt piano)
place(felt_chord([261.63, 329.63, 392.0, 523.25]), 15.75, .55)

# light reverb: short exponential-noise impulse response
ir_n = int(.55 * SR); ir = rng.standard_normal(ir_n) * np.exp(-np.arange(ir_n) / SR / .14); ir /= np.abs(ir).sum() / 3
def rev(x): return x + 0.22 * np.convolve(x, ir)[:N]
L, R = rev(L), rev(R)
st = np.stack([L, R], 1)

# loudness: approximate integrated LUFS with K-weighting-free gated RMS, then exact check via ffmpeg later
def lufs_est(x):
    blk = int(.4 * SR); hop = int(.1 * SR)
    p = [np.mean(x[i:i + blk] ** 2) for i in range(0, len(x) - blk, hop)]
    p = np.array([v for v in p if 10 * np.log10(v + 1e-12) > -70])
    rel = 10 * np.log10(p.mean()) - 10; p = p[10 * np.log10(p) > rel]
    return -0.691 + 10 * np.log10(p.mean() * 2)
target = float(os.environ.get('TARGET_GAIN_DB', 'nan'))
g = 10 ** (target / 20) if not math.isnan(target) else 10 ** ((-28 - lufs_est(st[:, 0])) / 20)
st *= g
pk = np.abs(st).max()
if pk > 10 ** (-1 / 20): st *= 10 ** (-1 / 20) / pk
pcm = (np.clip(st, -1, 1) * 32767).astype(np.int16)
with wave.open(os.path.join(ROOT, 'build', 'sound.wav'), 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
print('seconds', len(pcm) / SR, 'gain dB', round(20 * math.log10(g), 2), 'peak dBFS', round(20 * math.log10(np.abs(st).max()), 2))
