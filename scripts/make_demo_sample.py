#!/usr/bin/env python3
"""Synthesises Ongaku's demo samples, one per theme
(assets/sounds/demo_<theme>.ogg).

Short original loops that each cover the whole spectrum (deep kick and bass,
warm chords, a melody, crisp hats), so the difference before and after a
sound correction is easy to hear. Each theme has its own mood. Needs numpy
and ffmpeg.

    python3 scripts/make_demo_sample.py            # every theme
    python3 scripts/make_demo_sample.py sakura     # one theme
"""

import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

RATE = 44100
BARS = 8

# chords: one per bar (MIDI notes), bass: root of each bar, beats: bass hits,
# kicks/snares: beats in the bar, lead: instrument, melody: two phrases of
# (beat, note, length) alternating every bar, swing: delay of the off-beat
# eighths, cutoff: pad brightness.
STYLES = {
    # Ongaku: the original pop loop, bell melody.
    "ongaku": dict(
        bpm=96,
        chords=[[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]],
        bass=[33, 29, 36, 31],
        beats=(0, 1.5, 2, 3),
        kicks=(0, 2),
        snares=(1, 3),
        lead="bell",
        melody=[
            [(0, 76, 1), (1, 72, 1), (2, 74, 1), (3, 71, 1)],
            [(0, 72, 1), (1, 74, 1), (2, 76, 1), (3, 79, 1)],
        ],
        swing=0.0,
        cutoff=1800,
    ),
    # Washi: warm lo-fi, electric piano, swung hats.
    "washi": dict(
        bpm=82,
        chords=[[50, 53, 57, 60], [43, 47, 50, 53], [48, 52, 55, 59],
                [45, 48, 52, 55]],
        bass=[38, 31, 36, 33],
        beats=(0, 2.5),
        kicks=(0, 2.5),
        snares=(1, 3),
        lead="epiano",
        melody=[
            [(0.5, 69, 1), (1.5, 72, 0.5), (2, 74, 1.5)],
            [(0, 72, 0.5), (0.5, 71, 1), (2, 67, 2)],
        ],
        swing=0.12,
        cutoff=1200,
    ),
    # Sumi: ink-dark synthwave, plucked arpeggio.
    "sumi": dict(
        bpm=100,
        chords=[[48, 51, 55], [44, 48, 51], [51, 55, 58], [46, 50, 53]],
        bass=[36, 32, 39, 34],
        beats=(0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5),
        kicks=(0, 1, 2, 3),
        snares=(1, 3),
        lead="arp",
        melody=[],
        swing=0.0,
        cutoff=1500,
    ),
    # Ai: indigo, Japanese pentatonic plucks like a koto.
    "ai": dict(
        bpm=88,
        chords=[[50, 54, 57], [47, 50, 54], [43, 47, 50], [45, 49, 52]],
        bass=[38, 35, 31, 33],
        beats=(0, 2),
        kicks=(0, 2.5),
        snares=(2,),
        lead="koto",
        melody=[
            [(0, 74, 0.5), (0.5, 76, 0.5), (1, 78, 1), (2.5, 81, 0.5),
             (3, 78, 1)],
            [(0, 76, 1), (1, 74, 0.5), (1.5, 71, 0.5), (2, 69, 2)],
        ],
        swing=0.0,
        cutoff=2000,
    ),
    # Matcha: green and calm, bossa groove with a marimba.
    "matcha": dict(
        bpm=110,
        chords=[[48, 52, 55, 59], [45, 48, 52, 55], [50, 53, 57, 60],
                [43, 47, 50, 53]],
        bass=[36, 33, 38, 31],
        beats=(0, 1.5, 2, 3.5),
        kicks=(0, 1.5, 2, 3.5),
        snares=(),
        lead="marimba",
        melody=[
            [(0, 76, 0.5), (0.5, 74, 0.5), (1, 72, 1), (2.5, 71, 0.5),
             (3, 72, 1)],
            [(0, 69, 1), (1.5, 72, 0.5), (2, 76, 1), (3, 74, 1)],
        ],
        swing=0.0,
        cutoff=1600,
    ),
    # Sakura: bright city pop, bells and a busy bass.
    "sakura": dict(
        bpm=112,
        chords=[[53, 57, 60, 64], [52, 55, 59, 62], [50, 53, 57, 60],
                [48, 52, 55, 59]],
        bass=[41, 40, 38, 36],
        beats=(0, 0.75, 1.5, 2, 2.75, 3.5),
        kicks=(0, 1.5, 2),
        snares=(1, 3),
        lead="bell",
        melody=[
            [(0, 81, 0.5), (0.5, 79, 0.5), (1, 77, 1), (2, 76, 0.5),
             (2.5, 77, 1.5)],
            [(0, 79, 1), (1, 76, 0.5), (1.5, 74, 0.5), (2, 72, 2)],
        ],
        swing=0.0,
        cutoff=2400,
    ),
    # Kin: gold, disco funk with brass stabs on the off-beats.
    "kin": dict(
        bpm=118,
        chords=[[52, 55, 59, 62], [57, 61, 64, 67], [52, 55, 59, 62],
                [54, 57, 60, 64]],
        bass=[40, 45, 40, 42],
        beats=(0, 0.5, 1.5, 2, 2.5, 3.5),
        kicks=(0, 1, 2, 3),
        snares=(1, 3),
        lead="brass",
        melody=[
            [(0.5, 76, 0.25), (1.5, 76, 0.25), (2.5, 79, 0.5), (3.5, 76, 0.5)],
            [(0.5, 74, 0.25), (1.5, 76, 0.25), (2.5, 71, 0.5), (3.5, 74, 0.5)],
        ],
        swing=0.0,
        cutoff=2200,
    ),
}


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


def lead_tone(kind, freq, seconds):
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    if kind == "epiano":
        tone = np.sin(2 * np.pi * freq * t) + 0.3 * np.sin(
            2 * np.pi * freq * 2 * t
        ) * np.exp(-t * 6)
        return tone * (1 + 0.15 * np.sin(2 * np.pi * 5 * t)) * env(n, 0.004, 0.9)
    if kind == "koto":
        tone = sum(
            np.sin(2 * np.pi * freq * k * t) * np.exp(-t * (3 + 2 * k)) / k
            for k in (1, 2, 3, 4)
        )
        return tone * env(n, 0.001, 0.8)
    if kind == "marimba":
        tone = np.sin(2 * np.pi * freq * t) + 0.25 * np.sin(
            2 * np.pi * freq * 4 * t
        ) * np.exp(-t * 20)
        return tone * env(n, 0.001, 0.35)
    if kind == "brass":
        tone = lowpass(saw(freq, n, 0.003) + saw(freq, n, -0.003), 2500)
        return tone * 0.5 * env(n, 0.02, 0.4)
    # bell
    return (
        np.sin(2 * np.pi * freq * t)
        + 0.4 * np.sin(2 * np.pi * freq * 2.76 * t) * np.exp(-t * 4)
        + 0.2 * np.sin(2 * np.pi * freq * 5.4 * t) * np.exp(-t * 8)
    ) * env(n, 0.002, 0.6)


def render(name, style):
    rng = np.random.default_rng(7)
    beat = 60 / style["bpm"]
    length = int(RATE * beat * 4 * BARS) + RATE  # one second of tail
    left = np.zeros(length)
    right = np.zeros(length)

    def add(signal, start_beat, pan=0.0, gain=1.0):
        frac = start_beat % 1
        if style["swing"] and abs(frac - 0.5) < 1e-6:
            start_beat += style["swing"]
        i = int(start_beat * beat * RATE)
        n = min(len(signal), length - i)
        if n <= 0:
            return
        left[i : i + n] += signal[:n] * gain * np.sqrt((1 - pan) / 2)
        right[i : i + n] += signal[:n] * gain * np.sqrt((1 + pan) / 2)

    for bar in range(BARS):
        chord = style["chords"][bar % 4]
        beat0 = bar * 4

        # Pad: detuned saws through a soft low-pass, swelling over the bar.
        n = int(4 * beat * RATE)
        pad = sum(
            saw(note(m), n, d) for m in chord for d in (-0.004, 0.004)
        ) / (2 * len(chord))
        pad = lowpass(pad, style["cutoff"]) * env(n, 0.35, 3.0)
        add(pad, beat0, pan=-0.3, gain=0.22)
        add(pad, beat0, pan=0.3, gain=0.22)

        # Bass: round saw.
        for b in style["beats"]:
            n = int(0.9 * beat * RATE)
            tone = saw(note(style["bass"][bar % 4]), n)
            tone = lowpass(tone, 300) * env(n, 0.005, 0.35)
            add(tone, beat0 + b, gain=0.55)

        for b in style["kicks"]:
            n = int(0.4 * RATE)
            t = np.arange(n) / RATE
            freq = 45 + 110 * np.exp(-t * 35)
            kick = np.sin(2 * np.pi * np.cumsum(freq) / RATE) * np.exp(-t * 9)
            add(kick, beat0 + b, gain=0.9)
        for b in style["snares"]:
            n = int(0.25 * RATE)
            t = np.arange(n) / RATE
            body = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30)
            noise = rng.uniform(-1, 1, n)
            noise = (noise - lowpass(noise, 1500)) * np.exp(-t * 18)
            add(body * 0.5 + noise * 0.6, beat0 + b, gain=0.5)
        if not style["snares"]:
            # Rim clicks instead (bossa).
            for b in (0.75, 2.25, 3.0):
                n = int(0.05 * RATE)
                t = np.arange(n) / RATE
                click = np.sin(2 * np.pi * 1700 * t) * np.exp(-t * 90)
                add(click, beat0 + b, pan=0.3, gain=0.35)

        # Hats on every eighth, alternating sides, from bar 2.
        if bar >= 1:
            for k in range(8):
                n = int(0.08 * RATE)
                t = np.arange(n) / RATE
                noise = rng.uniform(-1, 1, n)
                hat = (noise - lowpass(noise, 7000)) * np.exp(-t * 60)
                add(hat, beat0 + k / 2, pan=0.5 if k % 2 else -0.5,
                    gain=0.32 if k % 2 else 0.22)

        # Lead from bar 3 (the arpeggio from bar 2).
        if style["lead"] == "arp" and bar >= 1:
            notes = [m + 12 for m in chord] + [chord[0] + 24]
            for k in range(16):
                m = notes[k % len(notes)]
                n = int(0.3 * RATE)
                tone = lowpass(saw(note(m), n), 3000) * env(n, 0.002, 0.12)
                add(tone, beat0 + k / 4, pan=0.4 if k % 2 else -0.4,
                    gain=0.16)
        elif bar >= 2:
            for b, m, dur in style["melody"][bar % 2]:
                tone = lead_tone(style["lead"], note(m), dur * beat + 0.8)
                add(tone, beat0 + b, pan=0.2, gain=0.18)

    # Gentle fade in and out, normalised to -1 dBFS.
    fade = int(0.05 * RATE)
    tail = int(1.2 * RATE)
    ramp = np.ones(length)
    ramp[:fade] = np.linspace(0, 1, fade)
    ramp[-tail:] = np.linspace(1, 0, tail)
    stereo = np.stack([left * ramp, right * ramp], axis=1)
    stereo *= 10 ** (-1 / 20) / np.abs(stereo).max()

    root = Path(__file__).resolve().parent.parent
    out = root / "assets" / "sounds" / f"demo_{name}.ogg"
    out.parent.mkdir(parents=True, exist_ok=True)
    wav = out.with_suffix(".wav")
    with wave.open(str(wav), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((stereo * 32767).astype("<i2").tobytes())
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a",
         "libvorbis", "-q:a", "4", str(out)],
        check=True,
    )
    wav.unlink()
    print(out, out.stat().st_size, "bytes", file=sys.stderr)


for name in sys.argv[1:] or STYLES:
    render(name, STYLES[name])
