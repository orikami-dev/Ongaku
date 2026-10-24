#!/usr/bin/env python3
"""Ongaku: shows "Ongaku" instead of "Musify" in the app's texts.

Rewrites the translation files (lib/localization/app_*.arb) in place, line by
line so upstream formatting is kept. The translate / translateDescription
texts keep "Musify": they point at Musify's translation project on Crowdin.
Run after every upstream merge (sync_upstream.sh does it); verify.sh checks it.

Usage: scripts/brand_strings.py [--check]
"""
import pathlib
import re
import sys

KEEP = {"translate", "translateDescription"}
LINE = re.compile(r'^(\s*"([^"@]+)"\s*:\s*")(.*)$')

changed = []
for arb in sorted(pathlib.Path("lib/localization").glob("app_*.arb")):
    lines = arb.read_text(encoding="utf-8").split("\n")
    out = []
    for line in lines:
        m = LINE.match(line)
        if m and m.group(2) not in KEEP and "Musify" in m.group(3):
            text = m.group(3).replace("Musify", "Ongaku")
            if arb.name == "app_fr.arb":  # French elision before a vowel
                text = re.sub(r"\b(qu|d)e Ongaku", r"\1'Ongaku", text)
            line = m.group(1) + text
        out.append(line)
    if out != lines:
        changed.append(str(arb))
        if "--check" not in sys.argv:
            arb.write_text("\n".join(out), encoding="utf-8")

if "--check" in sys.argv and changed:
    print("Texts still say Musify, run scripts/brand_strings.py:", *changed)
    sys.exit(1)
print(f"{len(changed)} file(s) {'to fix' if '--check' in sys.argv else 'updated'}")
