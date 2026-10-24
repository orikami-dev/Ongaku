#!/usr/bin/env python3
"""Synthesises Ongaku's demo sample (assets/sounds/ongaku_demo.ogg).

A short original loop that covers the whole spectrum (deep kick and bass,
warm chords, a bell melody, crisp hats), so the difference before and after
a sound correction is easy to hear. Needs numpy and ffmpeg.

    python3 scripts/make_demo_sample.py
"""

import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

RATE = 44100
BPM = 96
BEAT = 60 / BPM
BARS = 8
LENGTH = int(RATE * BEAT * 4 * BARS) + RATE  # one second of tail
rng = np.random.default_rng(7)


def note(n):
    """Frequency of MIDI note n."""
    return 440 * 2 ** ((n - 69) / 12)


def env(n, attack, decay):
    t = np.arange(n) / RATE
    a = np.minimum(1, t / max(attack, 1e-4))
    return a * np.exp(-t / decay)


def lowpass(x, cutoff):
    alpha = 1 - np.exp(-2 * np.pi * cutoff / RATE)
    y = np.empty_like(x)
    s = 0.0
    for i, v in enumerate(x):
        s += alpha * (v - s)
        y[i] = s
    return y


def saw(freq, n, detune=0.0):
    t = np.arange(n) / RATE
    f = freq * (1 + detune)
    return 2 * ((t * f) % 1) - 1


left = np.zeros(LENGTH)
right = np.zeros(LENGTH)


def add(signal, start_beat, pan=0.0, gain=1.0):
    i = int(start_beat * BEAT * RATE)
    n = min(len(signal), LENGTH - i)
    if n <= 0:
        return
    left[i : i + n] += signal[:n] * gain * np.sqrt((1 - pan) / 2)
    right[i : i + n] += signal[:n] * gain * np.sqrt((1 + pan) / 2)


# Chords: Am - F - C - G (i - VI - III - VII), two beats... one bar each.
chords = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]
bass_notes = [33, 29, 36, 31]

for bar in range(BARS):
    chord = chords[bar % 4]
    beat0 = bar * 4

    # Pad: detuned saws through a soft low-pass, swelling over the bar.
    n = int(4 * BEAT * RATE)
    pad = sum(
        saw(note(m), n, d) for m in chord for d in (-0.004, 0.004)
    ) / 6
    pad = lowpass(pad, 1800) * env(n, 0.35, 3.0)
    add(pad, beat0, pan=-0.3, gain=0.22)
    add(pad, beat0, pan=0.3, gain=0.22)

    # Bass: round saw, on beats 1, 2.5, 3 and 4.
    for b in (0, 1.5, 2, 3):
        n = int(0.9 * BEAT * RATE)
        tone = saw(note(bass_notes[bar % 4]), n)
        tone = lowpass(tone, 300) * env(n, 0.005, 0.35)
        add(tone, beat0 + b, gain=0.55)

    # Kick on 1 and 3 (and 3.5 every other bar), snare on 2 and 4.
    for b in (0, 2) + ((2.5,) if bar % 2 else ()):
        n = int(0.4 * RATE)
        t = np.arange(n) / RATE
        freq = 45 + 110 * np.exp(-t * 35)
        kick = np.sin(2 * np.pi * np.cumsum(freq) / RATE) * np.exp(-t * 9)
        add(kick, beat0 + b, gain=0.9)
    for b in (1, 3):
        n = int(0.25 * RATE)
        t = np.arange(n) / RATE
        body = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30)
        noise = rng.uniform(-1, 1, n)
        noise = (noise - lowpass(noise, 1500)) * np.exp(-t * 18)
        add(body * 0.5 + noise * 0.6, beat0 + b, gain=0.5)

    # Hats on every eighth, alternating sides, from bar 2.
    if bar >= 1:
        for k in range(8):
            n = int(0.08 * RATE)
            t = np.arange(n) / RATE
            noise = rng.uniform(-1, 1, n)
            hat = (noise - lowpass(noise, 7000)) * np.exp(-t * 60)
            add(hat, beat0 + k / 2, pan=0.5 if k % 2 else -0.5,
                gain=0.32 if k % 2 else 0.22)

    # Bell melody from bar 3.
    if bar >= 2:
        melody = [76, 72, 74, 71] if bar % 2 == 0 else [72, 74, 76, 79]
        for k, m in enumerate(melody):
            n = int(1.5 * RATE)
            t = np.arange(n) / RATE
            bell = (
                np.sin(2 * np.pi * note(m) * t)
                + 0.4 * np.sin(2 * np.pi * note(m) * 2.76 * t) * np.exp(-t * 4)
                + 0.2 * np.sin(2 * np.pi * note(m) * 5.4 * t) * np.exp(-t * 8)
            ) * env(n, 0.002, 0.6)
            add(bell, beat0 + k, pan=0.2, gain=0.18)

# Gentle fade in and out, normalised to -1 dBFS.
fade = int(0.05 * RATE)
tail = int(1.2 * RATE)
ramp = np.ones(LENGTH)
ramp[:fade] = np.linspace(0, 1, fade)
ramp[-tail:] = np.linspace(1, 0, tail)
stereo = np.stack([left * ramp, right * ramp], axis=1)
stereo *= 10 ** (-1 / 20) / np.abs(stereo).max()

root = Path(__file__).resolve().parent.parent
out = root / "assets" / "sounds" / "ongaku_demo.ogg"
out.parent.mkdir(parents=True, exist_ok=True)
wav = out.with_suffix(".wav")
with wave.open(str(wav), "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(RATE)
    w.writeframes((stereo * 32767).astype("<i2").tobytes())
subprocess.run(
    ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis",
     "-q:a", "5", str(out)],
    check=True,
)
wav.unlink()
print(out, out.stat().st_size, "bytes", file=sys.stderr)
