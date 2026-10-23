"""Ongaku icon: a faceted origami eighth note on a dark ink tile (ORIKAMI DA)."""
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024
INK = (18, 12, 20)
GOLD = (255, 210, 63)
# pink -> violet, light to dark
P1, P2, P3, P4, P5 = (255, 120, 150), (250, 45, 72), (214, 30, 96), (160, 60, 200), (112, 70, 235)

def darker(c, f=0.62):
    return tuple(int(v * f) for v in c)

# note facets in unit coords (0..1 of the drawing box), centred below
_raw = [
    # stem: folded strip, two faces
    ([(0.47, 0.71), (0.47, 0.13), (0.515, 0.10), (0.515, 0.68)], P2),
    ([(0.515, 0.68), (0.515, 0.10), (0.56, 0.13), (0.56, 0.69)], P4),
    # flag: front face, lower face, then the gold folded corner
    ([(0.515, 0.10), (0.85, 0.29), (0.60, 0.36)], P1),
    ([(0.60, 0.36), (0.85, 0.29), (0.66, 0.53)], P3),
    ([(0.85, 0.29), (0.83, 0.50), (0.66, 0.53)], GOLD),
    # head: a kite folded along its long diagonal
    ([(0.12, 0.77), (0.37, 0.57), (0.58, 0.68)], P1),
    ([(0.12, 0.77), (0.58, 0.68), (0.33, 0.90)], P5),
    ([(0.12, 0.77), (0.24, 0.67), (0.27, 0.745)], P2),
]
_xs = [p[0] for f, _ in _raw for p in f]
_ys = [p[1] for f, _ in _raw for p in f]
_dx = 0.5 - (min(_xs) + max(_xs)) / 2
_dy = 0.5 - (min(_ys) + max(_ys)) / 2
_k = 1 / max(max(_xs) - min(_xs), max(_ys) - min(_ys))
facets = [
    ([(0.5 + (x + _dx - 0.5) * _k, 0.5 + (y + _dy - 0.5) * _k) for x, y in f], c)
    for f, c in _raw
]

def draw_note(img, box, mono=False, shadow=True):
    x0, y0, size = box
    def pt(p):
        return (x0 + p[0] * size, y0 + p[1] * size)
    if shadow:
        sh = Image.new('RGBA', img.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(sh)
        off = size * 0.025
        for poly, _ in facets:
            d.polygon([(pt(p)[0] + off, pt(p)[1] + off) for p in poly], fill=(0, 0, 0, 140))
        sh = sh.filter(ImageFilter.GaussianBlur(size * 0.012))
        img.alpha_composite(sh)
    d = ImageDraw.Draw(img)
    w = max(2, int(size * 0.008))
    for poly, col in facets:
        pts = [pt(p) for p in poly]
        fill = (255, 255, 255, 255) if mono else col + (255,)
        d.polygon(pts, fill=fill)
        if not mono:
            d.line(pts + [pts[0]], fill=darker(col) + (255,), width=w, joint='curve')

def tile(size_px, radius=0.225):
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    m = Image.new('L', (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, S - 1, S - 1), int(S * radius), fill=255)
    bg = Image.new('RGBA', (S, S), INK + (255,))
    # subtle pink glow from the top-left
    glow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((-S * 0.3, -S * 0.3, S * 0.8, S * 0.8), fill=(250, 45, 72, 46))
    bg.alpha_composite(glow.filter(ImageFilter.GaussianBlur(S * 0.12)))
    img.paste(bg, (0, 0), m)
    draw_note(img, (S * 0.26, S * 0.26, S * 0.48))
    return img.resize((size_px, size_px), Image.LANCZOS)

def foreground(size_px, mono=False):
    # adaptive canvas 108dp, safe zone 66dp: the note lives in the inner ~60dp
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    inner = S * 49 / 108
    draw_note(img, ((S - inner) / 2, (S - inner) / 2, inner), mono=mono, shadow=not mono)
    return img.resize((size_px, size_px), Image.LANCZOS)

if __name__ == '__main__':
    res, out = sys.argv[1], sys.argv[2]
    import os
    dens = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
    for k, f in dens.items():
        dd = os.path.join(res, f'mipmap-{k}')
        os.makedirs(dd, exist_ok=True)
        tile(int(48 * f)).save(os.path.join(dd, 'ic_launcher.png'))
        foreground(int(108 * f)).save(os.path.join(dd, 'ic_launcher_adaptive_fore.png'))
        foreground(int(108 * f), mono=True).save(os.path.join(dd, 'ic_launcher_monochrome.png'))
    tile(1024).save(os.path.join(out, 'ongaku-icon-1024.png'))
    tile(512).save(os.path.join(out, 'ongaku-icon-512.png'))
