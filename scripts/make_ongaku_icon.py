"""Ongaku icon: a faceted origami eighth note on a dark ink tile (ORIKAMI DA)."""
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024
INK = (18, 12, 20)
GOLD = (255, 210, 63)
GLOW = (250, 45, 72)
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
    ImageDraw.Draw(glow).ellipse((-S * 0.3, -S * 0.3, S * 0.8, S * 0.8), fill=GLOW + (46,))
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

if __name__ == '__main__' and sys.argv[1] != '--palettes':
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


# --- Palette icons (themes shared with Kamishibai) -------------------------
# One launcher icon per palette: the same folded note in shades of the
# palette's accent, the gold corner kept, on an ink tile tinted by it.
#
#   python3 scripts/make_ongaku_icon.py --palettes android/app/src/main/res assets/icons/palettes

PALETTES = {
    'washi': (255, 90, 64),
    'sumi': (123, 78, 255),
    'ai': (122, 157, 232),
    'matcha': (141, 194, 106),
    'sakura': (242, 141, 171),
    'kin': (232, 185, 49),
}


# Faces given by Kamishibai's Sumi icon, so both apps match.
SUMI_SHADES = {
    'P1': (169, 140, 255),  # #A98CFF
    'P2': (123, 78, 255),  # #7B4EFF
    'P3': (76, 48, 158),  # #4C309E
    'P4': (47, 30, 97),  # #2F1E61
    'P5': (58, 36, 122),  # #3A247A
}


def _mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def palette_tile_ink(name, accent):
    if name == 'sumi':
        return (0, 0, 0)
    return _mix((15, 15, 19), accent, 0.07)


def with_palette(name, accent, fn):
    """Runs fn with the module colours swapped for the palette's."""
    global INK, GLOW, facets
    saved_ink, saved_glow, saved_facets = INK, GLOW, facets
    shades = {
        P1: _mix(accent, (255, 255, 255), 0.35),
        P2: accent,
        P3: _mix(accent, (0, 0, 0), 0.22),
        P4: _mix(accent, (0, 0, 0), 0.42),
        P5: _mix(accent, (0, 0, 0), 0.30),
    }
    if name == 'sumi':
        shades.update({globals()[k]: v for k, v in SUMI_SHADES.items()})
    # Kin is gold already: its folded corner turns to cream.
    shades[GOLD] = (255, 244, 214) if name == 'kin' else GOLD
    INK = palette_tile_ink(name, accent)
    GLOW = accent
    facets = [(poly, shades.get(col, col)) for poly, col in saved_facets]
    try:
        return fn()
    finally:
        INK, GLOW, facets = saved_ink, saved_glow, saved_facets


def write_palette_icons(res, assets):
    import os
    dens = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
    os.makedirs(assets, exist_ok=True)
    os.makedirs(os.path.join(res, 'mipmap-anydpi-v26'), exist_ok=True)
    colors = []
    for name, accent in PALETTES.items():
        for k, f in dens.items():
            dd = os.path.join(res, f'mipmap-{k}')
            with_palette(name, accent, lambda: tile(int(48 * f))).save(
                os.path.join(dd, f'ic_launcher_{name}.png'))
            with_palette(name, accent, lambda: foreground(int(108 * f))).save(
                os.path.join(dd, f'ic_launcher_{name}_fore.png'))
        with open(os.path.join(res, 'mipmap-anydpi-v26', f'ic_launcher_{name}.xml'), 'w') as x:
            x.write(
                '<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                f'  <background android:drawable="@color/ic_launcher_background_{name}"/>\n'
                f'  <foreground android:drawable="@mipmap/ic_launcher_{name}_fore"/>\n'
                '  <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
                '</adaptive-icon>\n')
        ink = palette_tile_ink(name, accent)
        colors.append(f'    <color name="ic_launcher_background_{name}">#{ink[0]:02X}{ink[1]:02X}{ink[2]:02X}</color>\n')
        with_palette(name, accent, lambda: tile(192)).save(os.path.join(assets, f'{name}.png'))
    tile(192).save(os.path.join(assets, 'ongaku.png'))
    with open(os.path.join(res, 'values', 'ongaku_palette_icons.xml'), 'w') as x:
        x.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
                '    <!-- Made by scripts/make_ongaku_icon.py with palettes. -->\n'
                + ''.join(colors) + '</resources>\n')


if __name__ == '__main__' and sys.argv[1] == '--palettes':
    write_palette_icons(sys.argv[2], sys.argv[3])
