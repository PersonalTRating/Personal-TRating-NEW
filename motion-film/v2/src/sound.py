"""Effects stem for the v2 segment (segment time; advert time = 9.8333 + t). No music, no voice."""
import math, os, sys, wave
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'film17', 'src'))

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR = 48000; DUR = 484 / 24; N = int(round(SR * DUR))
L = np.zeros(N); R = np.zeros(N); rng = np.random.default_rng(23)
def place(sig, t, gain=1.0, pan=0.0):
    i = int(round(t * SR)); s = sig * gain; j = min(N, i + len(s)); s = s[:j - i]
    L[i:j] += s * math.cos((pan + 1) * math.pi / 4) * 1.414; R[i:j] += s * math.sin((pan + 1) * math.pi / 4) * 1.414
def env(n, a, d): t = np.arange(n) / SR; return np.minimum(1, t / max(a, 1e-4)) * np.exp(-t / d)
def lp(x, k): return np.convolve(x, np.ones(max(1, int(k))) / max(1, int(k)), 'same')
def tap(): n = int(.05 * SR); t = np.arange(n) / SR; return (0.6 * np.sin(2 * np.pi * 1700 * t) + 0.4 * lp(rng.standard_normal(n), 4)) * env(n, .0008, .008)
def pop(f=520): n = int(.09 * SR); t = np.arange(n) / SR; return np.sin(2 * np.pi * (f * (1 + 1.5 * np.exp(-t / .01))) * t) * env(n, .002, .025)
def wood(f): n = int(.14 * SR); t = np.arange(n) / SR; return (np.sin(2 * np.pi * f * t) * np.exp(-t / .035) + .35 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t / .012)) * np.minimum(1, t / .001)
def whoosh(d=.45, b=6):
    n = int(d * SR); t = np.arange(n) / SR; x = rng.standard_normal(n); s = t / d
    return (lp(x, 40) * (1 - s) + lp(x, b) * s) * np.sin(np.pi * t / d) ** 2
def swell(d=.4): n = int(d * SR); t = np.arange(n) / SR; return lp(rng.standard_normal(n), 30) * (t / d) ** 2.2
def thump(f=55, d=.2): n = int(.5 * SR); t = np.arange(n) / SR; return np.sin(2 * np.pi * (f * (1 + .8 * np.exp(-t / .03))) * t) * env(n, .002, d)
def thock(f=170): n = int(.2 * SR); t = np.arange(n) / SR; return np.sin(2 * np.pi * f * t) * np.exp(-t / .05) + .3 * lp(rng.standard_normal(n), 10) * np.exp(-t / .01)
def chord(fs, d=2.6):
    n = int(d * SR); t = np.arange(n) / SR; s = np.zeros(n)
    for k, f in enumerate(fs): s += sum((.55 ** h) * np.sin(2 * np.pi * f * (h + 1) * t + k) for h in range(4)) * np.exp(-t / (1.1 - .1 * k))
    return lp(s, 3) * np.minimum(1, t / .006) + lp(rng.standard_normal(n), 25) * np.exp(-t / .008) * .4

place(tap(), 0.0, .9)                                   # the single tap bridging footage to screen
place(whoosh(.7, 5), 0.08, .5)                           # phone grows into the leaderboard
for i, t0 in enumerate((0.72, 0.88, 1.04)): place(pop(480 + 60 * i), t0 + 0.05, .5, 0.3)
place(thock(), 1.0, .7)                                  # headline
for i in range(3): place(wood(440 * 2 ** (i / 6)), 1.75 + i * 0.55, .45, -0.2 + 0.2 * i)   # rank focus 1-2-3
place(whoosh(.6, 10), 3.55, .3)                          # scroll to #3
place(whoosh(.5), T := 5.15, .5); place(thock(150), 5.87, .7)
place(pop(700), 6.85, .35); place(pop(760), 8.95, .35)   # field focus
place(whoosh(.5), 11.15, .5); place(thock(160), 11.42, .7)
place(pop(600), 12.4, .4); place(swell(.55), 13.35, .35)
place(whoosh(.45, 8), 17.12, .6); place(thump(46, .3), 17.3, .9)
place(chord([261.63, 329.63, 392.0, 523.25]), 17.85, .5)
ir_n = int(.55 * SR); ir = rng.standard_normal(ir_n) * np.exp(-np.arange(ir_n) / SR / .14); ir /= np.abs(ir).sum() / 3
L = L + .22 * np.convolve(L, ir)[:N]; R = R + .22 * np.convolve(R, ir)[:N]
st = np.stack([L, R], 1)
g = 10 ** (float(os.environ.get('GAIN_DB', '-17')) / 20); st *= g
pk = np.abs(st).max();  st *= min(1, 10 ** (-1 / 20) / pk)
with wave.open(os.path.join(ROOT, 'build', 'sfx.wav'), 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes((np.clip(st, -1, 1) * 32767).astype(np.int16).tobytes())
print('sfx seconds', N / SR, 'peak dBFS', round(20 * math.log10(np.abs(st).max()), 2))
