# Ongaku About banner, laid out like Musify's (logo card on the left, name
# on the right, ring and beads as accents) in Ongaku's own look: the icon's
# burgundy ink and its folded-paper facets in pink, red, violet and gold.
# Usage: python3 scripts/make_about_banner.py assets/icons/ongaku_icon.png \
#   assets/fonts/inter/Inter-800.ttf assets/icons/ongaku_banner.png
import math, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

icon_path, font_path, out = sys.argv[1:4]
S = 3
W, H = 1200 * S, 400 * S
PINK, RED, VIOLET, GOLD = (242, 112, 143), (232, 38, 79), (110, 68, 232), (255, 210, 63)

# Background: the icon's gradient, burgundy at the top left to ink.
bg = Image.new('RGB', (W, H))
px = bg.load()
for y in range(0, H, 2):
    for x in range(0, W, 2):
        t = min(1, max(0, (x / W) * 0.75 + (y / H) * 0.55 - 0.05))
        c = (int(60 - 44 * t), int(20 - 6 * t), int(30 - 12 * t))
        px[x, y] = c
        if x + 1 < W: px[x + 1, y] = c
        if y + 1 < H:
            px[x, y + 1] = c
            if x + 1 < W: px[x + 1, y + 1] = c

def overlay(draw_fn, blur=0, alpha=255):
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(layer))
    if blur:
        layer = layer.filter(ImageFilter.GaussianBlur(blur))
    if alpha != 255:
        a = layer.split()[3].point(lambda v: v * alpha // 255)
        layer.putalpha(a)
    bg.paste(layer, (0, 0), layer)

# A soft pink light behind the name.
overlay(lambda d: d.ellipse((W * .42, H * .05, W * .95, H * 1.0), fill=PINK + (255,)), blur=150 * S, alpha=40)

# Folded-paper facets across the scene, faint.
def facets(d):
    shapes = [
        ([(W*.36, H), (W*.50, H*.62), (W*.62, H)], VIOLET, 46),
        ([(W*.50, H*.62), (W*.62, H), (W*.70, H*.70)], PINK, 26),
        ([(W*.70, H*.70), (W*.62, H), (W*.86, H)], RED, 34),
        ([(W*.70, H*.70), (W*.86, H), (W*.92, H*.78)], VIOLET, 30),
        ([(W*.92, H*.78), (W*.86, H), (W, H), (W, H*.70)], PINK, 22),
        ([(W*.40, 0), (W*.47, 0), (W*.43, H*.16)], GOLD, 40),
        ([(W*.75, 0), (W*.83, H*.20), (W*.88, 0)], PINK, 24),
    ]
    for poly, col, a in shapes:
        d.polygon(poly, fill=col + (a,))
overlay(facets)

# Ring at the top right, beads on a thin arc at the bottom right.
def accents(d):
    cx, cy, r = W * .975, H * .10, H * .30
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=PINK + (110,), width=24 * S)
    ax, ay, ar = W * 1.03, H * 1.25, H * .62
    d.arc((ax - ar, ay - ar, ax + ar, ay + ar), 188, 330, fill=(255, 255, 255, 70), width=2 * S)
    for ang, col in ((204, GOLD), (262, PINK), (269, PINK)):
        t = math.radians(ang)
        x, y = ax + ar * math.cos(t), ay + ar * math.sin(t)
        d.ellipse((x - 7 * S, y - 7 * S, x + 7 * S, y + 7 * S), fill=col + (235,))
overlay(accents)

# The app icon as a slanted card, cut by the left edge.
icon = Image.open(icon_path).convert('RGBA')
size = int(H * 0.86)
tile = icon.resize((size, size), Image.LANCZOS).rotate(-9, resample=Image.BICUBIC, expand=True)
tx, ty = int(-size * 0.12), int(H / 2 - tile.height / 2)
shadow = Image.new('L', (W, H), 0)
shadow.paste(tile.split()[3], (tx + 14 * S, ty + 22 * S))
shadow = shadow.filter(ImageFilter.GaussianBlur(22 * S)).point(lambda v: v * 170 // 255)
bg.paste((0, 0, 0), (0, 0), shadow)
# A thin light edge so the dark tile stands out from the dark scene.
edge = Image.new('L', tile.size, 0)
edge.paste(tile.split()[3].filter(ImageFilter.MaxFilter(7)), (0, 0))
rim = Image.new('RGBA', tile.size, PINK + (0,))
rim.putalpha(edge.point(lambda v: v * 70 // 255))
bg.paste(rim, (tx, ty), rim)
bg.paste(tile, (tx, ty), tile)

# The name, in Inter like the app's titles.
d = ImageDraw.Draw(bg)
font = ImageFont.truetype(font_path, int(150 * S))
text = 'Ongaku'
tb = d.textbbox((0, 0), text, font=font)
x = W * .655 - (tb[2] - tb[0]) / 2 - tb[0]
y = H * .5 - (tb[3] + tb[1]) / 2
ts = Image.new('L', (W, H), 0)
ImageDraw.Draw(ts).text((x + 4 * S, y + 8 * S), text, font=font, fill=190)
ts = ts.filter(ImageFilter.GaussianBlur(12 * S))
bg.paste((0, 0, 0), (0, 0), ts)
d.text((x, y), text, font=font, fill=(255, 255, 255))

bg.resize((1200, 400), Image.LANCZOS).save(out, optimize=True)
