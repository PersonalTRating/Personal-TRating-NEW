"""Effects stem for the 15 s features segment (segment time; advert time = 15 + t). No music, no voice."""
import math, os, wave
import numpy as np
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR = 48000; N = int(SR * 15.0)
L = np.zeros(N); R = np.zeros(N); rng = np.random.default_rng(31)
def place(sig, t, gain=1.0, pan=0.0):
    i = int(round(t * SR)); s = sig * gain; j = min(N, i + len(s)); s = s[:j - i]
    L[i:j] += s * math.cos((pan + 1) * math.pi / 4) * 1.414; R[i:j] += s * math.sin((pan + 1) * math.pi / 4) * 1.414
def env(n, a, d): t = np.arange(n) / SR; return np.minimum(1, t / max(a, 1e-4)) * np.exp(-t / d)
def lp(x, k): k = max(1, int(k)); return np.convolve(x, np.ones(k) / k, 'same')
def pop(f=520): n = int(.09 * SR); t = np.arange(n) / SR; return np.sin(2 * np.pi * (f * (1 + 1.5 * np.exp(-t / .01))) * t) * env(n, .002, .025)
def wood(f): n = int(.14 * SR); t = np.arange(n) / SR; return (np.sin(2 * np.pi * f * t) * np.exp(-t / .035) + .35 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t / .012)) * np.minimum(1, t / .001)
def whoosh(d=.45, b=6):
    n = int(d * SR); t = np.arange(n) / SR; x = rng.standard_normal(n); s = t / d
    return (lp(x, 40) * (1 - s) + lp(x, b) * s) * np.sin(np.pi * t / d) ** 2
def swell(d=.4): n = int(d * SR); t = np.arange(n) / SR; return lp(rng.standard_normal(n), 30) * (t / d) ** 2.2
def thump(f=55, d=.2): n = int(.5 * SR); t = np.arange(n) / SR; return np.sin(2 * np.pi * (f * (1 + .8 * np.exp(-t / .03))) * t) * env(n, .002, d)
def thock(f=170): n = int(.2 * SR); t = np.arange(n) / SR; return np.sin(2 * np.pi * f * t) * np.exp(-t / .05) + .3 * lp(rng.standard_normal(n), 10) * np.exp(-t / .01)
def chord(fs, d=2.0):
    n = int(d * SR); t = np.arange(n) / SR; s = np.zeros(n)
    for k, f in enumerate(fs): s += sum((.55 ** h) * np.sin(2 * np.pi * f * (h + 1) * t + k) for h in range(4)) * np.exp(-t / (1.0 - .1 * k))
    return lp(s, 3) * np.minimum(1, t / .006) + lp(rng.standard_normal(n), 25) * np.exp(-t / .008) * .4
place(swell(.42), 0.0, .5); place(thump(52, .2), 0.42, .9); place(whoosh(.5, 5), 0.4, .45)     # push into the phone, open out
for i, t0 in enumerate((0.55, 0.67, 0.79)): place(pop(480 + 60 * i), t0 + 0.05, .45, 0.3)
place(thock(), 0.85, .7)
for i, tf in enumerate((1.45, 1.95, 2.95)): place(wood(440 * 2 ** (i / 6)), tf, .45, -0.2 + 0.2 * i)
place(whoosh(.55, 10), 2.2, .3)
place(whoosh(.45), 4.18, .5); place(thock(150), 4.8, .7)
place(pop(700), 5.27, .35); place(pop(760), 6.64, .35)
place(whoosh(.45), 7.98, .5); place(thock(160), 8.2, .7)
place(pop(600), 8.78, .4); place(swell(.5), 9.4, .3)
place(whoosh(.42, 8), 12.45, .6); place(thump(46, .3), 12.6, .9)
place(chord([261.63, 329.63, 392.0, 523.25]), 13.05, .5)
ir_n = int(.5 * SR); ir = rng.standard_normal(ir_n) * np.exp(-np.arange(ir_n) / SR / .13); ir /= np.abs(ir).sum() / 3
L = L + .22 * np.convolve(L, ir)[:N]; R = R + .22 * np.convolve(R, ir)[:N]
st = np.stack([L, R], 1) * 10 ** (float(os.environ.get('GAIN_DB', '-17')) / 20)
st *= min(1, 10 ** (-1 / 20) / np.abs(st).max())
with wave.open(os.path.join(ROOT, 'build', 'sfx.wav'), 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes((np.clip(st, -1, 1) * 32767).astype(np.int16).tobytes())
print('sfx 15.0 s, peak dBFS', round(20 * math.log10(np.abs(st).max()), 2))
