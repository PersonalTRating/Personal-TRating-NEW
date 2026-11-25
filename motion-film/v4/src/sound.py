"""v4 audio stems (segment time; advert time = 15 + t):
  build/sfx.wav       synthesised effects only
  build/vo_guide.wav  PLACEHOLDER guide narration (Windows 'Hazel' voice) on the cue times, to be replaced by the user's recording
  build/seg_mix.wav   effects + guide, for the HTML player and the segment MP4"""
import math, os, wave
import numpy as np
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR = 48000; N = int(SR * 15.0); rng = np.random.default_rng(41)
CUES = [0.6, 5.3, 8.3]                   # narration line starts (segment seconds), one per feature beat
L = np.zeros(N); R = np.zeros(N)
def place(sig, t, gain=1.0, pan=0.0, A=None):
    A = A if A is not None else (L, R); i = int(round(t * SR)); s = sig * gain; j = min(N, i + len(s)); s = s[:j - i]
    A[0][i:j] += s * math.cos((pan + 1) * math.pi / 4) * 1.414; A[1][i:j] += s * math.sin((pan + 1) * math.pi / 4) * 1.414
def env(n, a, d): t = np.arange(n) / SR; return np.minimum(1, t / max(a, 1e-4)) * np.exp(-t / d)
def lp(x, k): k = max(1, int(k)); return np.convolve(x, np.ones(k) / k, 'same')
def pop(f=520): n = int(.09 * SR); t = np.arange(n) / SR; return np.sin(2 * np.pi * (f * (1 + 1.5 * np.exp(-t / .01))) * t) * env(n, .002, .025)
def tap(): n = int(.05 * SR); t = np.arange(n) / SR; return (0.6 * np.sin(2 * np.pi * 1700 * t) + 0.4 * lp(rng.standard_normal(n), 4)) * env(n, .0008, .008)
def whoosh(d=.45, b=6):
    n = int(d * SR); t = np.arange(n) / SR; x = rng.standard_normal(n); s = t / d
    return (lp(x, 40) * (1 - s) + lp(x, b) * s) * np.sin(np.pi * t / d) ** 2
def swell(d=.4): n = int(d * SR); t = np.arange(n) / SR; return lp(rng.standard_normal(n), 30) * (t / d) ** 2.2
def thump(f=55, d=.2): n = int(.5 * SR); t = np.arange(n) / SR; return np.sin(2 * np.pi * (f * (1 + .8 * np.exp(-t / .03))) * t) * env(n, .002, d)
def thock(f=170): n = int(.2 * SR); t = np.arange(n) / SR; return np.sin(2 * np.pi * f * t) * np.exp(-t / .05) + .3 * lp(rng.standard_normal(n), 10) * np.exp(-t / .01)
def rocket(d=1.1):
    n = int(d * SR); t = np.arange(n) / SR; x = rng.standard_normal(n); s = t / d
    rumble = lp(x, 60) * 1.2 + lp(x, 6) * s * .6
    return rumble * np.sin(np.pi * np.minimum(1, s * 1.15)) ** 1.5
def chime(f): n = int(.5 * SR); t = np.arange(n) / SR; return sum((.5 ** h) * np.sin(2 * np.pi * f * (h + 1) * t) for h in range(3)) * env(n, .003, .12)
def chord(fs, d=1.9):
    n = int(d * SR); t = np.arange(n) / SR; s = np.zeros(n)
    for k, f in enumerate(fs): s += sum((.55 ** h) * np.sin(2 * np.pi * f * (h + 1) * t + k) for h in range(4)) * np.exp(-t / (1.0 - .1 * k))
    return lp(s, 3) * np.minimum(1, t / .006) + lp(rng.standard_normal(n), 25) * np.exp(-t / .008) * .4
place(swell(.42), 0.0, .5); place(thump(52, .2), 0.42, .9); place(whoosh(.5, 5), 0.4, .45)
place(thock(), 0.62, .6)
place(tap(), 1.95, .7); place(tap(), 2.85, .7)                                     # Country, Local taps
place(whoosh(.35), 3.8, .35); place(pop(560), 4.32, .4); place(pop(640), 4.67, .4)   # map opens, pins pulse
place(whoosh(.4), 5.03, .4); place(thock(150), 5.3, .6)
place(pop(700), 5.25, .4); place(pop(620), 5.62, .4)                                # score, review land
place(whoosh(.5), 8.0, .5); place(thock(160), 8.27, .6)
place(rocket(1.15), 8.45, .7); place(thump(48, .3), 9.5, 1.0); place(chime(880), 9.52, .25)    # climb, settle
place(whoosh(.42, 8), 12.02, .6); place(thump(46, .3), 12.15, .9)
place(chord([261.63, 329.63, 392.0, 523.25]), 12.85, .5)
ir_n = int(.5 * SR); ir = rng.standard_normal(ir_n) * np.exp(-np.arange(ir_n) / SR / .13); ir /= np.abs(ir).sum() / 3
L = L + .22 * np.convolve(L, ir)[:N]; R = R + .22 * np.convolve(R, ir)[:N]
sfx = np.stack([L, R], 1) * 10 ** (-17 / 20); sfx *= min(1, 10 ** (-1 / 20) / np.abs(sfx).max())
# guide narration
vo = np.zeros((N, 2))
for i, c in enumerate(CUES):
    w = wave.open(os.path.join(ROOT, 'build', 'vo', f'line{i + 1}.wav')); a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float) / 32768
    idx = np.where(np.abs(a) > 0.01)[0]; a = a[max(0, idx[0] - 480):idx[-1] + 2400]          # trim leading/trailing silence
    k = int(c * SR); j = min(N, k + len(a)); vo[k:j] += a[:j - k, None]
vo *= 10 ** (-3 / 20) / np.abs(vo).max()
def write(name, x):
    with wave.open(os.path.join(ROOT, 'build', name), 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
write('sfx.wav', sfx); write('vo_guide.wav', vo)
mix = vo * 0.9 + sfx * 10 ** (6 / 20); mix *= min(1, 10 ** (-1 / 20) / np.abs(mix).max()); write('seg_mix.wav', mix)
print('stems written; guide VO line ends:', [round(c, 2) for c in CUES])
