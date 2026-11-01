#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""《！？珠珠？！》— 命运回廊 · 8bit / chiptune 程序化音频合成器（v1.3）

全部 BGM / SFX 均为芯片音乐风格：
  - 方波主音 / 琶音（占空比 12.5% / 25% / 50%）
  - 三角波贝斯（NES 三角通道质感）
  - 噪声鼓组（类 NES 噪声通道，短包络）
  - 快速 arpeggio、音符滑音、8bit 位深量化
  - 短延迟（不做长混响），整体偏单声道、干净利落
旋律骨架仍是 D 小调五声音阶：D F G A C。

循环处理：
  - menu / battle / shop 按整小节长度合成；音符与延迟均做回绕（wrap / 循环 shift）
  - 首尾各 1.5ms 余弦渐变，消除 OGG 首尾采样跳变
  - 输出 44.1kHz 立体声 OGG Vorbis q=5（ffmpeg libvorbis，不可用则退 libsndfile / WAV）
SFX：44.1kHz 单声道 16bit WAV，峰值 -1dBFS（peg/click 等密集音效内部压低）。

可重复运行（固定随机种子）。用法：
    python tools/gen_audio.py                # 生成全部
    python tools/gen_audio.py --only bgm     # 只生成 BGM
    python tools/gen_audio.py --only sfx     # 只生成 SFX

依赖：numpy、soundfile（项目外 G:\\GoDot\\_toolchain\\pylibs 已安装）。
"""

import argparse
import math
import os
import shutil
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

# ---------------------------------------------------------------- 环境 / 路径
PROJECT = Path(__file__).resolve().parent.parent
TOOLCHAIN = Path(r"G:\GoDot\_toolchain")
PYLIBS = TOOLCHAIN / "pylibs"
if PYLIBS.is_dir():
    sys.path.insert(0, str(PYLIBS))

try:
    import numpy as np
except ImportError:  # pragma: no cover
    sys.exit("[gen_audio] 缺少 numpy，请安装到 %s 或用项目自带 python 运行" % PYLIBS)

try:
    import soundfile as sf
except ImportError:  # pragma: no cover
    sf = None

SR = 44100
BGM_DIR = PROJECT / "assets" / "audio" / "bgm"
SFX_DIR = PROJECT / "assets" / "audio" / "sfx"
TMP_DIR = Path(tempfile.mkdtemp(prefix="dsh_chip_"))

TAU = 2.0 * math.pi


# ---------------------------------------------------------------- 基础工具
def db2lin(db):
    return 10.0 ** (db / 20.0)


def pitch(name):
    """'D2' / 'F#3' / 'Bb4' -> Hz"""
    base = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5,
            "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10,
            "Bb": 10, "B": 11}
    letter = name[0]
    rest = name[1:]
    acc = ""
    if rest and rest[0] in "#b":
        acc = rest[0]
        rest = rest[1:]
    octv = int(rest)
    midi = 12 * (octv + 1) + base[letter + acc]
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


PENTA = [0, 3, 5, 7, 10]  # D 小调五声音阶


def penta(deg, octave):
    deg = int(deg) % 5
    midi = 12 * (int(octave) + 1) + 2 + PENTA[deg]
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def tline(n):
    return np.arange(n, dtype=np.float64) / SR


def fade_edges(x, fade_in=0.002, fade_out=0.01):
    n = len(x)
    two = x.ndim == 2
    a = min(n, int(fade_in * SR))
    b = min(n, int(fade_out * SR))
    if a > 1:
        e = 0.5 - 0.5 * np.cos(np.linspace(0.0, math.pi, a, dtype=np.float64))
        x[:a] *= e[:, None] if two else e
    if b > 1:
        e = 0.5 + 0.5 * np.cos(np.linspace(0.0, math.pi, b, dtype=np.float64))
        x[n - b:] *= e[:, None] if two else e
    return x


def quantize(x, bits=8):
    """位深量化：芯片 DAC 的颗粒感。"""
    levels = float(2 ** (bits - 1))
    return np.round(np.clip(x, -1.0, 1.0) * levels) / levels


# ---------------------------------------------------------------- 滤波器
def _freqs(nfft):
    return np.fft.rfftfreq(nfft, 1.0 / SR)


def _lp_mag(f, cutoff, order=2):
    return 1.0 / np.sqrt(1.0 + (f / max(cutoff, 1e-6)) ** (2 * order))


def _hp_mag(f, cutoff, order=2):
    with np.errstate(divide="ignore", invalid="ignore"):
        r = np.where(f > 0, cutoff / np.maximum(f, 1e-9), 1e9)
    return 1.0 / np.sqrt(1.0 + r ** (2 * order))


def _bp_mag(f, lo, hi, order=2):
    return _hp_mag(f, lo, order) * _lp_mag(f, hi, order)


def linear_filter(x, hfunc, pad=8192):
    n = len(x)
    nfft = 1 << max(1, int(math.ceil(math.log2(n + pad * 2))))
    X = np.fft.rfft(x, nfft)
    y = np.fft.irfft(X * hfunc(_freqs(nfft)), nfft)
    return y[:n]


def lin_lp(x, cutoff, order=2, pad=8192):
    return linear_filter(x, lambda f: _lp_mag(f, cutoff, order), pad)


def lin_hp(x, cutoff, order=2, pad=8192):
    return linear_filter(x, lambda f: _hp_mag(f, cutoff, order), pad)


def lin_bp(x, lo, hi, order=2, pad=8192):
    return linear_filter(x, lambda f: _bp_mag(f, lo, hi, order), pad)


def circ_lp(x, cutoff, order=2):
    n = len(x)
    X = np.fft.rfft(x)
    return np.fft.irfft(X * _lp_mag(_freqs(n), cutoff, order), n)


def circ_hp(x, cutoff, order=2):
    n = len(x)
    X = np.fft.rfft(x)
    return np.fft.irfft(X * _hp_mag(_freqs(n), cutoff, order), n)


# ---------------------------------------------------------------- 噪声（NES 风格 LFSR）
_NOISE_TABLE = None


def _build_noise_table(seconds=2.5, seed=0x2A3B):
    n = int(seconds * SR)
    reg = seed & 0x7FFF
    if reg == 0:
        reg = 1
    out = np.empty(n, dtype=np.float64)
    for i in range(n):
        bit = ((reg >> 0) ^ (reg >> 1)) & 1
        reg = (reg >> 1) | (bit << 14)
        out[i] = 1.0 if (reg & 1) else -1.0
    return out


def lfsr_noise(n, offset, rate=1):
    global _NOISE_TABLE
    if _NOISE_TABLE is None:
        _NOISE_TABLE = _build_noise_table()
    idx = (int(offset) + np.arange(n) // max(1, int(rate))) % len(_NOISE_TABLE)
    return _NOISE_TABLE[idx]


# ---------------------------------------------------------------- 芯片音色
def _phase_series(freq, dur, slide_to=None, vib_hz=0.0, vib_cents=0.0):
    n = max(2, int(round(dur * SR)))
    t = tline(n)
    f = np.full(n, float(freq))
    if vib_cents:
        f = f * (2.0 ** (vib_cents / 1200.0 * np.sin(TAU * vib_hz * t)))
    if slide_to is not None:
        f = f * (float(slide_to) / float(freq)) ** (t / max(dur, 1e-6))
    return TAU * np.cumsum(f) / SR, t, n


def _env(t, dur, attack=0.002, release=0.012, decay_tau=None):
    n = len(t)
    env = np.ones(n)
    a = min(n, max(1, int(attack * SR)))
    env[:a] = np.linspace(0.0, 1.0, a)
    if decay_tau is not None:
        env *= np.exp(-t / max(decay_tau, 1e-4))
    r = min(n, max(1, int(release * SR)))
    env[n - r:] *= np.linspace(1.0, 0.0, r)
    return env


def pulse(freq, dur, duty=0.5, amp=1.0, attack=0.002, release=0.012,
          decay_tau=None, slide_to=None, vib_hz=0.0, vib_cents=0.0):
    """方波（占空比可变）。"""
    ph, t, n = _phase_series(freq, dur, slide_to, vib_hz, vib_cents)
    frac = (ph / TAU) % 1.0
    wave = np.where(frac < duty, 1.0, -1.0)
    return amp * wave * _env(t, dur, attack, release, decay_tau)


def triangle(freq, dur, amp=1.0, attack=0.002, release=0.012,
             decay_tau=None, slide_to=None):
    """三角波（贝斯 / 鼓体）。"""
    ph, t, n = _phase_series(freq, dur, slide_to)
    frac = (ph / TAU) % 1.0
    wave = 1.0 - 4.0 * np.abs(frac - 0.5)
    return amp * wave * _env(t, dur, attack, release, decay_tau)


def noise_burst(dur, amp=1.0, offset=0, rate=1, hp=None, lp=None,
                attack=0.0008, release=0.01, decay_tau=None, rng=None):
    n = max(2, int(round(dur * SR)))
    t = tline(n)
    if rng is not None:
        offset = int(rng.integers(0, SR))
    x = lfsr_noise(n, offset, rate)
    if hp is not None:
        x = lin_hp(x, hp, order=2)
    if lp is not None:
        x = lin_lp(x, lp, order=2)
    m = float(np.max(np.abs(x)))
    if m > 1e-9:
        x /= m
    return amp * x * _env(t, dur, attack, release, decay_tau)


# ---------------------------------------------------------------- 鼓组
def kick(amp=1.0, dur=0.18, f0=150.0, f1=42.0):
    n = max(2, int(dur * SR))
    body = triangle(f0, dur, amp=1.0, attack=0.001, release=0.02,
                    decay_tau=0.055, slide_to=f1)
    click = np.zeros(n)
    cn = min(n, int(0.012 * SR))
    click[:cn] = np.linspace(1.0, -1.0, cn) * np.linspace(1.0, 0.0, cn)
    out = body + 0.25 * click
    m = float(np.max(np.abs(out)))
    return amp * out / max(m, 1e-9)


def snare(amp=1.0, dur=0.16, rng=None):
    n = max(2, int(dur * SR))
    t = tline(n)
    body = triangle(190.0, dur, amp=0.55, decay_tau=0.03)
    nz = noise_burst(dur, amp=0.9, hp=1400.0, lp=10000.0, decay_tau=0.05, rng=rng)
    out = body + nz
    m = float(np.max(np.abs(out)))
    return amp * out / max(m, 1e-9)


def hat(amp=1.0, dur=0.055, rng=None):
    return noise_burst(dur, amp=amp, hp=6000.0, lp=15000.0,
                       decay_tau=0.012, rng=rng)


def tom(amp=1.0, dur=0.2, f0=220.0, f1=130.0, rng=None):
    n = max(2, int(dur * SR))
    body = triangle(f0, dur, amp=1.0, decay_tau=0.09, slide_to=f1)
    nz = noise_burst(dur, amp=0.25, hp=500.0, lp=4000.0,
                     decay_tau=0.05, rng=rng)
    out = body + nz
    m = float(np.max(np.abs(out)))
    return amp * out / max(m, 1e-9)


# ---------------------------------------------------------------- 混音缓冲
class Mix:
    def __init__(self, dur):
        self.n = int(round(dur * SR))
        self.buf = np.zeros((self.n, 2), dtype=np.float64)

    def add(self, sig, t, gain=1.0, pan=0.0, wrap=True):
        if gain == 0.0 or len(sig) == 0:
            return
        gl = math.cos((pan + 1.0) * math.pi / 4.0)
        gr = math.sin((pan + 1.0) * math.pi / 4.0)
        start = int(round(t * SR))
        x = np.asarray(sig, dtype=np.float64)
        if wrap:
            # 右声道 +0.7ms 制造轻微立体感（仍接近单声道）
            self._place(x * (gl * gain), start % self.n, 0)
            self._place(x * (gr * gain), (start + int(0.0007 * SR)) % self.n, 1)
        else:
            self._place(x * (gl * gain), start, 0)
            self._place(x * (gr * gain), start, 1)

    def _place(self, x, start, ch):
        n = len(x)
        N = self.n
        pos = 0
        while pos < n and start < N:
            take = min(n - pos, N - start)
            self.buf[start:start + take, ch] += x[pos:pos + take]
            pos += take
            start = 0


# ---------------------------------------------------------------- 分析 / 成品
def band_energy(x):
    mono = np.mean(x, axis=1) if x.ndim == 2 else x
    n = len(mono)
    X = np.abs(np.fft.rfft(mono)) ** 2
    f = np.fft.rfftfreq(n, 1.0 / SR)
    lo = float(np.sum(X[f < 200.0]))
    mid = float(np.sum(X[(f >= 200.0) & (f < 2000.0)]))
    hi = float(np.sum(X[f >= 2000.0]))
    total = lo + mid + hi + 1e-12
    centroid = float(np.sum(X * f) / (np.sum(X) + 1e-12))
    return lo / total, mid / total, hi / total, centroid


def _rms_db(x):
    mono = np.mean(x, axis=1) if x.ndim == 2 else x
    return 20.0 * math.log10(max(float(np.sqrt(np.mean(mono * mono))), 1e-12))


def soft_limit(x, threshold=0.55, ceiling=0.98):
    a = np.abs(x)
    y = x.copy()
    mask = a > threshold
    if np.any(mask):
        t = (a[mask] - threshold) / (ceiling - threshold)
        y[mask] = np.sign(x[mask]) * (threshold + (ceiling - threshold) * np.tanh(t))
    return y


def match_loudness(out, peak_db, rms_lo=-21.0, rms_hi=-17.0, max_iter=6):
    """把 RMS 约束在 [rms_lo, rms_hi]；偏轻用逐级软限幅抬，偏响则整体衰减。"""
    rms = _rms_db(out)
    if rms > rms_hi:
        out *= db2lin(rms_hi - rms)
        return out
    th_ratio = 0.55
    for _ in range(max_iter):
        if _rms_db(out) >= rms_lo:
            break
        peak = float(np.max(np.abs(out)))
        th = th_ratio * peak
        ceiling = th + (peak - th) * 0.72
        for ch in range(out.shape[1]):
            out[:, ch] = soft_limit(out[:, ch], threshold=th, ceiling=ceiling)
        peak = float(np.max(np.abs(out)))
        out *= db2lin(peak_db) / peak
        th_ratio *= 0.80
    return out


def add_delay_circular(out, delay_s=0.09, mix=0.18, feedback=0.3, taps=3):
    """循环延迟（尾音回绕），不破坏无缝循环。"""
    d = max(1, int(delay_s * SR))
    dry = out.copy()
    wet = np.zeros_like(out)
    for k in range(1, taps + 1):
        g = (feedback ** (k - 1)) * mix
        wet[:, 0] += g * np.roll(dry[:, 1], d * k)
        wet[:, 1] += g * np.roll(dry[:, 0], d * k)
    return out + wet


def add_delay_linear(out, delay_s=0.09, mix=0.18, feedback=0.3, taps=3):
    d = max(1, int(delay_s * SR))
    dry = out.copy()
    wet = np.zeros_like(out)
    for k in range(1, taps + 1):
        g = (feedback ** (k - 1)) * mix
        shift = d * k
        if shift >= len(out):
            break
        wet[shift:, 0] += g * dry[:-shift, 1]
        wet[shift:, 1] += g * dry[:-shift, 0]
    return out + wet


def finalize_bgm(dry, peak_db=-6.0, rms_lo=-19.0, rms_hi=-15.0,
                 delay_s=0.09, delay_mix=0.18, bits=9):
    """BGM 成品：轻微延迟 + 高通/低通 + 8bit 量化 + 接缝渐变 + 归一。"""
    x = dry.copy()
    peak = float(np.max(np.abs(x)))
    if peak > 1e-9:
        x *= 0.85 / peak
    x = add_delay_circular(x, delay_s, delay_mix)
    for ch in range(2):
        x[:, ch] = circ_hp(x[:, ch], 30.0, order=2)
        x[:, ch] = circ_lp(x[:, ch], 15500.0, order=2)
    head = float(np.max(np.abs(x)))
    if head > 1e-9:
        x *= 0.95 / head  # 量化前留余量，避免 8bit 量化削顶
    x = quantize(x, bits)
    x -= x.mean(axis=0)
    fade_edges(x, 0.0015, 0.0015)
    peak = float(np.max(np.abs(x)))
    x *= db2lin(peak_db) / peak
    x = match_loudness(x, peak_db, rms_lo, rms_hi)
    return x


def finalize_oneshot(dry, peak_db=-6.0, rms_lo=-19.0, rms_hi=-15.0,
                     delay_s=0.09, delay_mix=0.16, bits=9, fade_out=1.2):
    n = len(dry)
    x = dry.copy()
    peak = float(np.max(np.abs(x)))
    if peak > 1e-9:
        x *= 0.85 / peak
    x = add_delay_linear(x, delay_s, delay_mix)
    if len(x) > n:
        x = x[:n]
    for ch in range(2):
        x[:, ch] = lin_hp(x[:, ch], 28.0, order=2)
        x[:, ch] = lin_lp(x[:, ch], 15500.0, order=2)
    head = float(np.max(np.abs(x)))
    if head > 1e-9:
        x *= 0.95 / head
    x = quantize(x, bits)
    env = np.ones(n)
    b = min(n, int(fade_out * SR))
    env[n - b:] = 0.5 + 0.5 * np.cos(np.linspace(0.0, math.pi, b))
    x *= env[:, None]
    peak = float(np.max(np.abs(x)))
    x *= db2lin(peak_db) / peak
    x = match_loudness(x, peak_db, rms_lo, rms_hi)
    return x


def finalize_sfx(x, peak_db=-1.0, fade_in=0.001, fade_out=0.008,
                 hp=28.0, bits=8):
    x = np.asarray(x, dtype=np.float64)
    x = lin_hp(x, hp, order=2)
    x -= float(np.mean(x))
    head = float(np.max(np.abs(x)))
    if head > 1e-9:
        x *= 0.95 / head
    x = quantize(x, bits)
    fade_edges(x, fade_in, fade_out)
    peak = float(np.max(np.abs(x)))
    if peak > 1e-9:
        x *= db2lin(peak_db) / peak
    return x


# ================================================================ BGM：菜单
def build_menu(seed=7101):
    rng = np.random.default_rng(seed)
    bpm = 72.0
    beat = 60.0 / bpm
    bar = beat * 4.0
    bars = 24
    dur = bars * bar  # 80.0s
    mix = Mix(dur)

    chords = [("D3", "A3"), ("C3", "G3"), ("F3", "C4"), ("G3", "D4")]
    for ci, (root_name, fifth_name) in enumerate(chords):
        f_root = pitch(root_name)
        f_fifth = pitch(fifth_name)
        start_bar = ci * 6
        for b in range(6):
            bar_t = (start_bar + b) * bar
            # 三角波贝斯：八分音符、断奏
            for off, f, g in ((0.0, f_root, 1.0), (0.5, f_root, 0.7),
                              (1.0, f_fifth, 0.8), (1.5, f_root, 0.6),
                              (2.0, f_root, 0.9), (2.5, f_fifth, 0.6),
                              (3.0, f_root, 0.8), (3.5, f_fifth, 0.7)):
                mix.add(triangle(f, beat * 0.80, amp=1.0, decay_tau=0.17),
                        bar_t + off * beat, gain=0.15 * g, pan=0.0)
            # 12.5% 方波琶音：每小节 16 分音符
            arp_tones = [f_root * 2, f_fifth * 2, f_root * 4, f_fifth * 2]
            for i in range(16):
                f = arp_tones[i % 4]
                mix.add(pulse(f, beat * 0.11, duty=0.125, amp=1.0,
                              decay_tau=0.05), bar_t + i * beat * 0.25,
                        gain=0.075 if (ci + b) % 4 else 0.095, pan=0.25)
            # 和声通道：第 2、4 拍的和弦短音
            for off in (1.0, 3.0):
                for f in (f_root * 2, f_fifth * 2):
                    mix.add(pulse(f, beat * 0.32, duty=0.25, amp=1.0,
                                  decay_tau=0.10),
                            bar_t + off * beat, gain=0.050, pan=-0.18)

    # 主旋律：25% 方波，4 小节乐句；每 8 小节出现 8 小节
    phrase = [
        [(0.0, 0, 5, 0.9), (0.5, 2, 5, 0.45), (1.0, 4, 5, 0.9),
         (2.0, 3, 5, 0.9), (3.0, 2, 5, 0.9)],
        [(0.0, 1, 5, 0.9), (1.0, 2, 5, 0.45), (1.5, 3, 5, 0.45),
         (2.0, 4, 6, 1.2), (3.0, 3, 5, 0.9)],
        [(0.0, 2, 5, 0.9), (0.5, 4, 5, 0.45), (1.0, 3, 5, 0.9),
         (2.0, 2, 5, 1.8)],
        [(0.0, 1, 5, 0.45), (0.5, 0, 5, 0.9), (1.5, 2, 5, 0.9),
         (2.5, 0, 4, 1.8)],
    ]
    for b in range(bars):
        if (b // 8) % 2 != 0:
            continue
        for off, deg, octv, ml in phrase[b % 4]:
            f = penta(deg, octv)
            mix.add(pulse(f, max(0.12, ml * beat), duty=0.25, amp=1.0,
                          decay_tau=0.55, vib_hz=5.0, vib_cents=8.0),
                    b * bar + off * beat, gain=0.17, pan=-0.12)

    # 噪声鼓：心跳感 + 轻镲
    for b in range(bars):
        if b % 2 == 0:
            mix.add(kick(amp=1.0, f0=130.0, f1=44.0), b * bar, gain=0.12)
            mix.add(kick(amp=1.0, f0=110.0, f1=40.0),
                    b * bar + beat * 2.5, gain=0.06)
        for off in (0.5, 1.5, 2.5, 3.5):
            mix.add(hat(amp=1.0, rng=rng), b * bar + off * beat,
                    gain=0.028, pan=0.2)

    return finalize_bgm(mix.buf, delay_mix=0.24, delay_s=0.105,
                        rms_lo=-19.5, rms_hi=-15.5), dur, bpm


# ================================================================ BGM：战斗
def build_battle(seed=7202):
    rng = np.random.default_rng(seed)
    bpm = 100.0
    beat = 60.0 / bpm
    bar = beat * 4.0
    bars = 36
    dur = bars * bar  # 86.4s
    mix = Mix(dur)

    # 三角波贝斯固定音型（八分音符）
    bass_pattern = [(0.0, 0, 3), (0.5, 0, 3), (1.0, 2, 3), (1.5, 2, 3),
                    (2.0, 4, 4), (2.5, 4, 4), (3.0, 1, 3), (3.5, 1, 3)]
    for b in range(bars):
        for off, deg, octv in bass_pattern:
            accent = 1.0 if off in (0.0, 2.0) else 0.72
            mix.add(triangle(penta(deg, octv), beat * 0.72, amp=1.0,
                             decay_tau=0.13),
                    b * bar + off * beat, gain=0.19 * accent, pan=0.0)

    # 12.5% 方波 16 分琶音（驱动感）
    arp_degrees = [0, 2, 4, 2, 1, 3, 1, 2]
    for b in range(bars):
        for i in range(16):
            deg = arp_degrees[i % 8]
            octv = 5 if i % 4 else 6
            mix.add(pulse(penta(deg, octv), beat * 0.12, duty=0.125,
                          amp=1.0, decay_tau=0.045),
                    b * bar + i * beat * 0.25, gain=0.095, pan=0.22)
        # 和声通道：反拍和弦短音（经典 NES 第二脉冲通道）
        for off, da, db in ((1.5, 0, 2), (3.5, 0, 3)):
            for d in (da, db):
                mix.add(pulse(penta(d, 4), beat * 0.30, duty=0.125, amp=1.0,
                              decay_tau=0.09),
                        b * bar + off * beat, gain=0.060, pan=-0.2)

    # 50% 方波主旋律：4 小节乐句，隔 4 小节出现
    phrase = [
        [(0.0, 0, 5, 0.9), (1.0, 4, 5, 0.45), (1.5, 3, 5, 0.45),
         (2.5, 2, 5, 0.9)],
        [(0.0, 1, 5, 0.9), (0.5, 2, 5, 0.45), (1.0, 4, 6, 0.9),
         (2.0, 3, 5, 0.9)],
        [(0.0, 2, 5, 0.9), (1.0, 4, 5, 0.45), (1.5, 3, 5, 0.45),
         (2.5, 0, 5, 1.2)],
        [(0.0, 3, 5, 0.45), (0.5, 4, 5, 0.45), (1.0, 3, 5, 0.9),
         (2.0, 1, 4, 1.5)],
    ]
    for b in range(bars):
        if (b // 4) % 2 != 0:
            continue
        for off, deg, octv, ml in phrase[b % 4]:
            f = penta(deg, octv)
            mix.add(pulse(f, max(0.15, ml * beat * 1.4), duty=0.5, amp=1.0,
                          decay_tau=0.5, vib_hz=5.5, vib_cents=10.0),
                    b * bar + off * beat, gain=0.19, pan=-0.15)

    # 噪声鼓组
    pat_a = [(0.0, 1.0), (1.5, 0.55), (2.0, 0.8), (2.5, 0.4)]
    pat_b = [(0.0, 1.0), (1.0, 0.6), (2.5, 0.85), (3.5, 0.5)]
    pat_c = [(0.0, 1.0), (0.75, 0.45), (1.5, 0.7), (2.0, 0.85), (3.0, 0.6)]
    for b in range(bars):
        pats = {0: pat_a, 1: pat_b, 2: pat_c, 3: pat_a}
        for off, g in pats[b % 4]:
            mix.add(kick(amp=1.0, f0=150.0, f1=44.0),
                    b * bar + off * beat, gain=0.15 * g)
        if b % 2 == 1:
            mix.add(snare(amp=1.0, rng=rng), b * bar + beat, gain=0.12, pan=0.1)
            mix.add(snare(amp=1.0, rng=rng), b * bar + beat * 3.0,
                    gain=0.12, pan=-0.1)
        for i in range(8):
            mix.add(hat(amp=1.0, rng=rng), b * bar + i * beat * 0.5,
                    gain=0.055 if i % 2 == 0 else 0.035, pan=0.26)
        if b % 8 == 7:
            for k in range(3):
                mix.add(tom(amp=1.0, rng=rng), b * bar + (2.5 + k * 0.25) * beat,
                        gain=0.10 - 0.02 * k, pan=-0.15)

    return finalize_bgm(mix.buf, delay_mix=0.13, delay_s=0.075,
                        rms_lo=-17.5, rms_hi=-14.5), dur, bpm


# ================================================================ BGM：商店
def build_shop(seed=7303):
    rng = np.random.default_rng(seed)
    bpm = 88.0
    beat = 60.0 / bpm
    bar = beat * 4.0
    bars = 20
    dur = bars * bar  # 54.545s
    mix = Mix(dur)

    chords = [("D3", "A3"), ("F3", "C4"), ("G3", "D4"),
              ("D3", "A3"), ("C3", "G3")]
    for ci, (root_name, fifth_name) in enumerate(chords):
        f_root = pitch(root_name)
        f_fifth = pitch(fifth_name)
        start_bar = ci * 4
        for b in range(4):
            bar_t = (start_bar + b) * bar
            # 三角波贝斯四分音符
            for off, f, g in ((0.0, f_root, 1.0), (1.0, f_root, 0.75),
                              (2.0, f_fifth, 0.85), (3.0, f_root, 0.7)):
                mix.add(triangle(f, beat * 0.85, amp=1.0, decay_tau=0.2),
                        bar_t + off * beat, gain=0.17 * g)
            # 琶音点缀
            arp_tones = [f_root * 2, f_fifth * 2, f_root * 4, f_fifth * 4]
            for i in range(8):
                mix.add(pulse(arp_tones[i % 4], beat * 0.12, duty=0.125,
                              amp=1.0, decay_tau=0.05),
                        bar_t + i * beat * 0.5,
                        gain=0.085, pan=0.22)
            # 和声通道：小节内反拍和弦
            for off in (1.5, 3.5):
                for f in (f_root * 2, f_fifth * 2):
                    mix.add(pulse(f, beat * 0.28, duty=0.25, amp=1.0,
                                  decay_tau=0.10),
                            bar_t + off * beat, gain=0.048, pan=-0.18)

    # 25% 方波铃声旋律：2 小节动机，隔 2 小节出现
    motifs = [
        [(0.0, 4, 6, 0.5), (0.5, 2, 6, 0.5), (1.0, 0, 6, 1.0),
         (2.0, 2, 6, 0.5), (2.5, 4, 6, 1.0), (3.0, 3, 6, 0.5)],
        [(0.0, 0, 6, 0.5), (0.5, 3, 6, 0.5), (1.0, 4, 6, 1.5),
         (2.0, 4, 6, 0.5), (2.5, 3, 5, 0.5), (3.0, 1, 5, 1.0)],
        [(0.0, 2, 6, 0.5), (0.5, 1, 6, 0.5), (1.0, 0, 6, 1.0),
         (2.0, 1, 6, 0.5), (2.5, 2, 6, 0.5), (3.0, 4, 6, 1.5)],
        [(0.0, 3, 5, 0.5), (0.5, 4, 5, 0.5), (1.0, 3, 5, 1.0),
         (2.0, 2, 5, 0.5), (2.5, 1, 5, 0.5), (3.0, 0, 5, 1.5)],
    ]
    for b in range(bars):
        if (b // 2) % 2 == 1:
            continue
        for off, deg, octv, ml in motifs[(b // 2) % 4]:
            f = penta(deg, octv)
            mix.add(pulse(f, max(0.10, ml * beat), duty=0.25, amp=1.0,
                          decay_tau=0.4, vib_hz=6.0, vib_cents=8.0),
                    b * bar + off * beat, gain=0.17, pan=-0.12)
            mix.add(pulse(f * 2.0, max(0.08, ml * beat * 0.6), duty=0.125,
                          amp=1.0, decay_tau=0.15),
                    b * bar + off * beat, gain=0.035, pan=0.25)

    # 轻鼓组
    for b in range(bars):
        mix.add(kick(amp=1.0, f0=135.0, f1=45.0), b * bar, gain=0.105)
        mix.add(kick(amp=1.0, f0=120.0, f1=42.0),
                b * bar + beat * 2.0, gain=0.065)
        for i in range(8):
            mix.add(hat(amp=1.0, rng=rng), b * bar + i * beat * 0.5,
                    gain=0.035 if i % 2 == 0 else 0.020, pan=0.24)
        if b % 2 == 1:
            mix.add(snare(amp=1.0, rng=rng), b * bar + beat * 3.0,
                    gain=0.055, pan=-0.12)

    return finalize_bgm(mix.buf, delay_mix=0.20, delay_s=0.095,
                        rms_lo=-19.0, rms_hi=-15.0), dur, bpm


# ================================================================ BGM：胜利
def build_victory(seed=7404):
    rng = np.random.default_rng(seed)
    dur = 7.0
    mix = Mix(dur)

    # 上行 16 分琶音
    run = [(0.00, 0, 4), (0.09, 2, 4), (0.18, 3, 4), (0.27, 4, 4),
           (0.36, 0, 5), (0.45, 2, 5), (0.54, 4, 5), (0.63, 0, 6)]
    for tt, deg, octv in run:
        f = penta(deg, octv)
        mix.add(pulse(f, 0.30, duty=0.5, amp=1.0, decay_tau=0.18),
                tt, gain=0.22, pan=0.1)
        mix.add(triangle(f * 0.5, 0.30, amp=1.0, decay_tau=0.2),
                tt, gain=0.10, pan=0.0)

    # 终止和弦（快速琶音后长音）
    for k, (deg, octv) in enumerate(((0, 5), (2, 5), (4, 5), (0, 6))):
        mix.add(pulse(penta(deg, octv), 1.4, duty=0.25, amp=1.0,
                      decay_tau=0.9, vib_hz=5.0, vib_cents=6.0),
                0.85 + 0.04 * k, gain=0.11, pan=-0.25 + 0.16 * k)
    # 三角波低音
    mix.add(triangle(pitch("D3"), 3.0, amp=1.0, decay_tau=1.6,
                     attack=0.01), 0.0, gain=0.15)
    mix.add(triangle(pitch("A3"), 2.5, amp=1.0, decay_tau=1.4,
                     attack=0.01), 0.85, gain=0.08)
    # 噪声星尘
    for tt in (0.6, 1.2, 1.8, 2.5):
        mix.add(noise_burst(0.18, amp=1.0, hp=5000.0, lp=15000.0,
                            decay_tau=0.05, rng=rng), tt,
                gain=0.06, pan=0.3)

    return finalize_oneshot(mix.buf, delay_mix=0.18, delay_s=0.095,
                            rms_lo=-18.0, rms_hi=-14.0, fade_out=1.6), dur, 120.0


# ================================================================ BGM：失败
def build_defeat(seed=7505):
    rng = np.random.default_rng(seed)
    dur = 7.0
    mix = Mix(dur)

    # 下行方波旋律（带滑音）
    seq = [(0.00, 3, 5), (0.30, 2, 5), (0.60, 1, 5), (0.90, 0, 5),
           (1.20, 4, 4), (1.55, 3, 4), (1.90, 2, 4), (2.30, 1, 4)]
    for tt, deg, octv in seq:
        f = penta(deg, octv)
        mix.add(pulse(f, 0.55, duty=0.25, amp=1.0, decay_tau=0.35,
                      slide_to=f * 0.94), tt, gain=0.16, pan=0.0)

    # 低音下坠
    mix.add(triangle(pitch("D3"), 3.5, amp=1.0, decay_tau=1.8,
                     slide_to=pitch("D2")), 0.0, gain=0.24)
    mix.add(triangle(pitch("A2"), 3.0, amp=1.0, decay_tau=1.6,
                     slide_to=pitch("A1")), 0.4, gain=0.14)
    # 噪声下行扫频
    nz = noise_burst(3.4, amp=1.0, hp=300.0, lp=9000.0, rng=rng)
    td = tline(len(nz))
    nz *= np.exp(-td / 1.2)
    mix.add(nz, 1.0, gain=0.10, pan=0.0)
    # 低沉的失败终止音
    for k, (deg, octv) in enumerate(((0, 3), (3, 2), (0, 2))):
        mix.add(pulse(penta(deg, octv), 2.4, duty=0.5, amp=1.0,
                      decay_tau=1.2), 2.6 + 0.18 * k, gain=0.10, pan=0.0)

    return finalize_oneshot(mix.buf, delay_mix=0.20, delay_s=0.11,
                            rms_lo=-18.0, rms_hi=-14.0, fade_out=1.8), dur, 72.0


# ================================================================ SFX
def nsamp(dur):
    return max(2, int(round(dur * SR)))


def overlay(out, sig, start_s, gain=1.0):
    """把 sig 叠加到 out 的 start_s 秒处，自动截断（长度不一致也安全）。"""
    idx = int(round(start_s * SR))
    if idx < 0 or idx >= len(out):
        return
    ln = min(len(sig), len(out) - idx)
    if ln > 0:
        out[idx:idx + ln] += gain * np.asarray(sig[:ln], dtype=np.float64)


def _blip(freq, dur, duty=0.5, decay_tau=None, slide_to=None):
    return pulse(freq, dur, duty=duty, amp=1.0,
                 decay_tau=(decay_tau if decay_tau is not None else dur * 0.35),
                 slide_to=slide_to, attack=0.001, release=0.004)


def sfx_launch(rng):
    dur = 0.35
    n = nsamp(dur)
    t = tline(n)
    out = 0.7 * _blip(190.0, dur, duty=0.125, decay_tau=0.16,
                      slide_to=980.0)[:n]
    nz = noise_burst(dur, amp=1.0, hp=700.0, lp=9000.0, rng=rng)[:n]
    nz *= np.minimum(1.0, t / 0.03) * np.exp(-t / 0.13)
    out += 0.55 * nz
    return finalize_sfx(out, peak_db=-1.0)


def sfx_peg(rng):
    dur = 0.08
    out = np.zeros(nsamp(dur))
    overlay(out, _blip(1520.0, dur, duty=0.125, decay_tau=0.018), 0.0, 0.9)
    overlay(out, noise_burst(0.01, amp=0.7, hp=2000.0, lp=12000.0,
                             rng=rng), 0.0, 0.5)
    return finalize_sfx(out, peak_db=-1.0, fade_out=0.012)


def sfx_peg_yellow(rng):
    dur = 0.12
    out = np.zeros(nsamp(dur))
    overlay(out, _blip(2280.0, dur, duty=0.25, decay_tau=0.035), 0.0, 0.85)
    overlay(out, _blip(3420.0, dur, duty=0.125, decay_tau=0.02), 0.0, 0.30)
    return finalize_sfx(out, peak_db=-1.0)


def sfx_peg_green(rng):
    dur = 0.15
    out = np.zeros(nsamp(dur))
    overlay(out, _blip(1046.0, 0.09, duty=0.25, decay_tau=0.04), 0.0, 0.75)
    overlay(out, _blip(1568.0, 0.10, duty=0.25, decay_tau=0.04), 0.028, 0.65)
    overlay(out, triangle(1046.0, dur, amp=1.0, decay_tau=0.05), 0.0, 0.28)
    return finalize_sfx(out, peak_db=-1.0)


def sfx_slot(rng):
    dur = 0.5
    out = np.zeros(nsamp(dur))
    for k, (tt, f) in enumerate(((0.00, 988.0), (0.06, 1319.0),
                                  (0.12, 1760.0), (0.19, 2637.0))):
        overlay(out, _blip(f, 0.14, duty=0.25, decay_tau=0.05), tt,
                0.7 - 0.08 * k)
    overlay(out, noise_burst(0.09, amp=1.0, hp=4000.0, lp=14000.0,
                             decay_tau=0.02, rng=rng), 0.23, 0.35)
    overlay(out, triangle(95.0, 0.22, amp=1.0, decay_tau=0.08,
                          slide_to=55.0), 0.20, 0.45)
    return finalize_sfx(out, peak_db=-1.0, fade_out=0.02)


def sfx_void(rng):
    dur = 0.7
    n = nsamp(dur)
    t = tline(n)
    out = 0.65 * pulse(620.0, dur, duty=0.5, amp=1.0, decay_tau=0.35,
                       slide_to=62.0, attack=0.003)[:n]
    nz = noise_burst(dur, amp=1.0, hp=200.0, lp=7000.0, rng=rng)[:n]
    nz *= np.minimum(1.0, t / 0.05) * np.exp(-t / 0.28)
    out += 0.35 * nz
    out += 0.35 * triangle(110.0, dur, amp=1.0, decay_tau=0.3,
                           slide_to=38.0)[:n]
    return finalize_sfx(out, peak_db=-1.0)


def sfx_coin(rng):
    dur = 0.2
    out = np.zeros(nsamp(dur))
    for tt, f in ((0.0, 2093.0), (0.055, 3136.0)):
        overlay(out, _blip(f, 0.1, duty=0.25, decay_tau=0.03), tt, 0.8)
    return finalize_sfx(out, peak_db=-1.0)


def sfx_buy(rng):
    dur = 0.4
    out = np.zeros(nsamp(dur))
    for k, (deg, octv) in enumerate(((0, 5), (2, 5), (4, 5), (0, 6))):
        f = penta(deg, octv)
        overlay(out, _blip(f, 0.22, duty=0.25, decay_tau=0.10),
                0.035 * k, 0.55)
    for deg in (0, 2, 4):
        overlay(out, pulse(penta(deg, 5), 0.38, duty=0.25, amp=1.0,
                           decay_tau=0.16, attack=0.01), 0.0, 0.10)
    return finalize_sfx(out, peak_db=-1.0)


def sfx_click(rng):
    dur = 0.05
    out = _blip(1080.0, dur, duty=0.5, decay_tau=0.008)
    overlay(out, noise_burst(0.012, amp=0.5, hp=3000.0, lp=12000.0,
                             rng=rng), 0.0, 0.5)
    return finalize_sfx(out, peak_db=-1.0, fade_in=0.0, fade_out=0.01)


def sfx_guardian(rng):
    dur = 0.5
    n = nsamp(dur)
    out = 0.75 * triangle(58.0, dur, amp=1.0, decay_tau=0.16,
                          slide_to=40.0)[:n]
    out += 0.30 * noise_burst(dur, amp=1.0, hp=300.0, lp=2500.0,
                              decay_tau=0.18, rng=rng)[:n]
    out += 0.30 * pulse(300.0, dur, duty=0.25, amp=1.0, decay_tau=0.3,
                        slide_to=75.0)[:n]
    return finalize_sfx(out, peak_db=-1.0)


def sfx_crack(rng):
    dur = 0.4
    out = np.zeros(nsamp(dur))
    events = [0.0, 0.025, 0.07, 0.12, 0.18, 0.26]
    for i, tt in enumerate(events):
        ln = min(0.06, dur - tt)
        if ln <= 0:
            continue
        overlay(out, noise_burst(ln, amp=1.0, hp=2500.0, lp=12000.0,
                                 decay_tau=0.012, rng=rng), tt,
                0.9 - 0.12 * i)
    overlay(out, triangle(140.0, dur, amp=1.0, decay_tau=0.03,
                          slide_to=70.0), 0.0, 0.35)
    return finalize_sfx(out, peak_db=-1.0, bits=7)


def sfx_win(rng):
    dur = 1.5
    out = np.zeros(nsamp(dur))
    for k, (deg, octv) in enumerate(((0, 4), (2, 4), (3, 4), (4, 4),
                                     (0, 5), (2, 5), (4, 5), (0, 6))):
        overlay(out, _blip(penta(deg, octv), 0.22, duty=0.5,
                           decay_tau=0.12), 0.055 * k, 0.42)
    for k, (deg, octv) in enumerate(((0, 5), (2, 5), (4, 6))):
        overlay(out, pulse(penta(deg, octv), 1.0, duty=0.25, amp=1.0,
                           decay_tau=0.5, vib_hz=5.5, vib_cents=8.0),
                0.45 + 0.05 * k, 0.20)
    overlay(out, triangle(pitch("D3"), 1.2, amp=1.0, decay_tau=0.6),
            0.0, 0.22)
    for tt in (0.45, 0.7, 1.0):
        overlay(out, noise_burst(0.12, amp=1.0, hp=6000.0, lp=15000.0,
                                 decay_tau=0.03, rng=rng), tt, 0.07)
    return finalize_sfx(out, peak_db=-1.0, fade_out=0.05)


def sfx_lose(rng):
    dur = 1.5
    out = np.zeros(nsamp(dur))
    seq = [(0.00, 0, 4), (0.22, 3, 3), (0.44, 2, 3), (0.66, 1, 3),
           (0.88, 0, 3)]
    for tt, deg, octv in seq:
        f = penta(deg, octv)
        overlay(out, pulse(f, 0.35, duty=0.25, amp=1.0, decay_tau=0.25,
                           slide_to=f * 0.92), tt, 0.30)
    overlay(out, triangle(pitch("D2"), 1.5, amp=1.0, decay_tau=0.8,
                          slide_to=pitch("D1")), 0.0, 0.30)
    overlay(out, noise_burst(1.1, amp=1.0, hp=180.0, lp=1200.0,
                             decay_tau=0.5, rng=rng), 0.0, 0.15)
    return finalize_sfx(out, peak_db=-1.0, fade_out=0.1)


SFX_SPECS = {
    # 名称: (合成函数, 相对 -1dBFS 的内部衰减 dB)
    "launch": (sfx_launch, 0.0),
    "peg": (sfx_peg, -10.0),
    "peg_yellow": (sfx_peg_yellow, -5.0),
    "peg_green": (sfx_peg_green, -5.0),
    "slot": (sfx_slot, 0.0),
    "void": (sfx_void, 0.0),
    "coin": (sfx_coin, 0.0),
    "buy": (sfx_buy, 0.0),
    "click": (sfx_click, -12.0),
    "guardian": (sfx_guardian, 0.0),
    "crack": (sfx_crack, 0.0),
    "win": (sfx_win, 0.0),
    "lose": (sfx_lose, 0.0),
}


# ---------------------------------------------------------------- 编码 / IO
def find_ffmpeg():
    cands = []
    env = os.environ.get("FFMPEG")
    if env:
        cands.append(Path(env))
    cands.append(TOOLCHAIN / "ffmpeg.exe")
    if PYLIBS.is_dir():
        cands.extend(sorted(PYLIBS.glob("imageio_ffmpeg/binaries/ffmpeg*.exe")))
    w = shutil.which("ffmpeg")
    if w:
        cands.append(Path(w))
    for c in cands:
        if c.is_file():
            try:
                r = subprocess.run([str(c), "-hide_banner", "-version"],
                                   capture_output=True, text=True, timeout=20)
                if r.returncode == 0:
                    return c, "libvorbis" in (r.stdout + r.stderr)
            except Exception:
                continue
    return None, False


def write_wav(path, x, subtype="PCM_16"):
    if sf is None:
        raise RuntimeError("需要 soundfile 才能写 WAV")
    sf.write(str(path), x, SR, subtype=subtype)


def encode_ogg(x, out_path, ffmpeg, quality=5):
    if ffmpeg is not None:
        tmp_wav = TMP_DIR / (out_path.stem + ".wav")
        tmp_ogg = TMP_DIR / (out_path.stem + ".ogg")
        write_wav(tmp_wav, x, subtype="PCM_24")
        cmd = [str(ffmpeg), "-y", "-hide_banner", "-loglevel", "error",
               "-i", str(tmp_wav), "-c:a", "libvorbis", "-q:a", str(quality),
               "-ar", "44100", "-ac", "2", str(tmp_ogg)]
        subprocess.run(cmd, check=True, timeout=300)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(tmp_ogg, out_path)
        return "ogg-vorbis-q%d(ffmpeg)" % quality
    if sf is not None and "OGG" in sf.available_formats():
        tmp = TMP_DIR / (out_path.stem + "-sf.ogg")
        sf.write(str(tmp), x, SR, format="OGG", subtype="VORBIS")
        out_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(tmp, out_path)
        return "ogg-vorbis(libsndfile)"
    return None


def analyze(x, name, loop=False):
    mono = np.mean(x, axis=1) if x.ndim == 2 else x
    peak = float(np.max(np.abs(x)))
    rms = float(np.sqrt(np.mean(mono ** 2)))
    crest = 20.0 * math.log10(max(peak, 1e-12) / max(rms, 1e-12))
    lo, mid, hi, centroid = band_energy(x)
    info = dict(name=name, dur=len(x) / SR,
                peak_db=20 * math.log10(max(peak, 1e-12)),
                rms_db=20 * math.log10(max(rms, 1e-12)), crest=crest,
                band=(lo, mid, hi), centroid=centroid)
    if loop:
        x2 = x if x.ndim == 2 else x[:, None]
        seam = float(np.max(np.abs(x2[0] - x2[-1])))
        adj = float(np.mean(np.abs(np.diff(x2, axis=0))))
        win = int(0.02 * SR)
        rs = float(np.sqrt(np.mean(x2[:win] ** 2)))
        re = float(np.sqrt(np.mean(x2[-win:] ** 2)))
        info["seam"] = seam
        info["seam_ratio"] = seam / max(adj, 1e-12)
        info["edge_rms_db"] = (20 * math.log10(max(rs, 1e-12)),
                               20 * math.log10(max(re, 1e-12)))
    return info


# ---------------------------------------------------------------- 主流程
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", choices=["bgm", "sfx"], default=None)
    ap.add_argument("--no-encode", action="store_true",
                    help="只合成不写成品文件")
    args = ap.parse_args()

    BGM_DIR.mkdir(parents=True, exist_ok=True)
    SFX_DIR.mkdir(parents=True, exist_ok=True)
    ffmpeg, has_vorbis = find_ffmpeg()
    print("[gen_audio] chiptune mode | ffmpeg:", ffmpeg,
          "| libvorbis:", has_vorbis)
    print("[gen_audio] temp:", TMP_DIR)

    bgm = [("bgm_menu", build_menu), ("bgm_battle", build_battle),
           ("bgm_shop", build_shop), ("bgm_victory", build_victory),
           ("bgm_defeat", build_defeat)]
    report = []
    ext = ".ogg"
    enc_desc = ""

    if args.only != "sfx":
        for name, builder in bgm:
            x, dur, bpm = builder()
            loop = name in ("bgm_menu", "bgm_battle", "bgm_shop")
            info = analyze(x, name, loop=loop)
            info["bpm"] = bpm
            info["loop"] = loop
            if not args.no_encode:
                used = encode_ogg(x, BGM_DIR / (name + ".ogg"),
                                  ffmpeg if has_vorbis else None)
                if used is None:
                    ext = ".wav"
                    write_wav(BGM_DIR / (name + ".wav"), x, subtype="PCM_16")
                    enc_desc = "wav-fallback"
                    info["ext"] = ".wav"
                else:
                    enc_desc = used
                    info["ext"] = ".ogg"
            report.append(info)
            print("[bgm] %-11s %6.2fs %6.1f BPM  peak %5.1f dBFS  "
                  "RMS %5.1f dB  crest %4.1f dB  L/M/H %.2f/%.2f/%.2f  "
                  "centroid %.0f Hz"
                  % (name, dur, bpm, info["peak_db"], info["rms_db"],
                     info["crest"], *info["band"], info["centroid"]))
            if loop:
                print("        seam step %.5f (ratio %.2f)  edge RMS %.1f/%.1f dB"
                      % (info["seam"], info["seam_ratio"],
                         *info["edge_rms_db"]))

    if args.only != "bgm":
        for key, (fn, trim_db) in SFX_SPECS.items():
            rng = np.random.default_rng(zlib.crc32(key.encode("utf-8")))
            sig = fn(rng)
            if trim_db:
                sig = sig * db2lin(trim_db)
            path = SFX_DIR / ("sfx_" + key + ".wav")
            if not args.no_encode:
                write_wav(path, sig, subtype="PCM_16")
            info = analyze(sig, "sfx_" + key)
            report.append(info)
            print("[sfx] %-14s %5.3fs  peak %6.1f dBFS  RMS %6.1f dB"
                  % ("sfx_" + key, info["dur"], info["peak_db"],
                     info["rms_db"]))

    if args.no_encode:
        print("[gen_audio] --no-encode：未写成品")
        shutil.rmtree(TMP_DIR, ignore_errors=True)
        return

    # ---- 成品读回复核
    print("\n[verify] read-back")
    total = 0
    for info in report:
        req = ext if info["name"].startswith("bgm_") else ".wav"
        p = (BGM_DIR if info["name"].startswith("bgm_") else SFX_DIR) / \
            (info["name"] + req)
        if not p.is_file():
            print("  MISSING", p)
            continue
        total += p.stat().st_size
        dec = None
        sr = 0
        if sf is not None:
            try:
                dec, sr = sf.read(str(p), dtype="float32")
                if dec.ndim == 1:
                    dec = dec[:, None]
            except Exception as e:  # pragma: no cover
                print("  decode fail", p.name, e)
        print("  %-18s %7.2fs  %7.1f KB  %s"
              % (p.name, (len(dec) / SR if dec is not None else 0.0),
                 p.stat().st_size / 1024.0, sr if dec is not None else "?"))
        if dec is not None and info["name"].startswith("bgm_") and info["loop"]:
            d = dec if dec.ndim == 2 else dec[:, None]
            seam = float(np.max(np.abs(d[0] - d[-1])))
            adj = float(np.mean(np.abs(np.diff(d, axis=0))))
            print("      decoded seam step %.5f  ratio %.2f  decoded peak "
                  "%.1f dBFS" % (seam, seam / max(adj, 1e-12),
                                 20 * math.log10(max(float(np.max(np.abs(d))),
                                                     1e-12))))
    print("\n[verify] total %.2f MB (%d files, ext=%s, encoder=%s)"
          % (total / 1048576.0, len(report), ext, enc_desc or "n/a"))
    if total > 9.5 * 1048576:
        print("  !! 超过 10MB 预算，需要降低码率/时长")
    shutil.rmtree(TMP_DIR, ignore_errors=True)


if __name__ == "__main__":
    main()
