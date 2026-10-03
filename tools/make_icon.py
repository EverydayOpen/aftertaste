"""Render the Aftertaste app icon and write App/Assets.xcassets/AppIcon.appiconset.

Stdlib only (no Pillow). Shapes are signed distance functions, so every edge gets exact analytic antialiasing at
1024 px; smaller sizes are box-filtered down from the 1024 master in premultiplied alpha.

Layout follows the macOS (Big Sur and later) icon grid: 1024 canvas, 824 px body with continuous-looking corners, soft
drop shadow. Body: dusk violet lit from the top. Glyph: one solid teal-to-violet rounded square, the item that was just
there, with the faint ghost of itself trailing up and to the left: two translucent outlines that fade. That ghost is the
app's signature (an item that moved to the Trash leaves an outline that fades). The one shape that has to survive 16 px
is the solid square; the trailing glow is what makes it read as "something was here".

Run from the repo root (about a minute):  python tools/make_icon.py
"""
import json
import math
import os
import struct
import zlib
from array import array

N = 1024
OUT = os.path.join(os.path.dirname(__file__), "..", "App", "Assets.xcassets", "AppIcon.appiconset")

# Body: 824 px square centred on the canvas. A p=3 superellipse corner with a larger radius approximates Apple's
# continuous corner (curvature ramps in instead of jumping like a circle).
HALF, CORNER, P = 412.0, 278.0, 3.0
TOP, BOTTOM = (0.21, 0.175, 0.36), (0.055, 0.048, 0.105)          # dusk violet -> near black

SQ_HALF, SQ_R, STROKE = 170.0, 76.0, 22.0                           # the square: half size, corner radius; ghost outline width
SOLID = (582.0, 582.0)                                              # centre of the solid square; the ghosts trail by 70 px each
GHOSTS = ((512.0, 512.0, 0.62, 0.15), (442.0, 442.0, 0.30, 0.07))   # cx, cy, outline alpha, fill alpha
TEAL, VIOLET = (0.30, 0.88, 0.80), (0.64, 0.50, 1.0)
LILAC = (0.82, 0.78, 1.0)


def cov(d):
    """Pixel coverage from a signed distance in pixels (negative = inside)."""
    return 0.0 if d >= 0.5 else 1.0 if d <= -0.5 else 0.5 - d


def seg(px, py, ax, ay, bx, by):
    """Distance from (px, py) to segment a-b."""
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - ax - t * dx, py - ay - t * dy)


def rrect(x, y, cx, cy, hw, hh, r):
    """Signed distance to a rounded rectangle."""
    qx, qy = abs(x - cx) - hw + r, abs(y - cy) - hh + r
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def body_sdf(x, y):
    qx, qy = abs(x - 512.0) - (HALF - CORNER), abs(y - 512.0) - (HALF - CORNER)
    if qx > 0 and qy > 0:
        return (qx ** P + qy ** P) ** (1 / P) - CORNER
    return max(qx, qy) - CORNER


def over(px, i, r, g, b, a):
    """Composite straight-alpha colour (r, g, b, a) over premultiplied pixel i."""
    k = 1.0 - a
    px[i] = r * a + px[i] * k
    px[i + 1] = g * a + px[i + 1] * k
    px[i + 2] = b * a + px[i + 2] * k
    px[i + 3] = a + px[i + 3] * k


def mix(a, b, t):
    t = min(1.0, max(0.0, t))
    return [a[c] + (b[c] - a[c]) * t for c in range(3)]


def square(x, y, cx, cy):
    return rrect(x, y, cx, cy, SQ_HALF, SQ_HALF, SQ_R)


def render():
    px = array("f", bytes(N * N * 16))
    shadow_k = 1 / (14.0 * math.sqrt(2))       # body shadow: sigma 14 px, 10 px down, 32 %
    sq_k = 1 / (20.0 * math.sqrt(2))           # the solid square's shadow: sigma 20 px, 22 px down, 55 %
    sx, sy = SOLID
    for yi in range(N):
        y = yi + 0.5
        base = mix(TOP, BOTTOM, (y - 100) / 824)
        for xi in range(N):
            x = xi + 0.5
            i = (yi * N + xi) * 4
            d_body = body_sdf(x, y)
            if d_body > -1:
                a = 0.32 * 0.5 * math.erfc(body_sdf(x, y - 10) * shadow_k)
                if a > 1 / 1024:
                    over(px, i, 0.0, 0.0, 0.0, a)
            a = cov(d_body)
            if a == 0.0:
                continue
            glow = max(0.0, 1.0 - ((x - 512) ** 2 + (y - 110) ** 2) / 640.0 ** 2) * 0.12   # soft light from the top
            over(px, i, *mix(base, (1, 1, 1), glow), a)
            lamp = max(0.0, 1.0 - ((x - 540) ** 2 + (y - 560) ** 2) / 420.0 ** 2) ** 2 * 0.22   # teal glow behind the glyph
            over(px, i, *TEAL, lamp * a)
            over(px, i, 1.0, 1.0, 1.0, 0.12 * cov(abs(d_body + 2.0) - 1.5))   # thin rim: keeps the edge on dark Docks
            if not (230 < x < 800 and 230 < y < 800):   # glyph + its shadow
                continue
            for cx, cy, line, fill in GHOSTS:           # farthest first: each ghost is the same square, one step back
                d = square(x, y, cx, cy)
                over(px, i, *LILAC, fill * cov(d))
                over(px, i, *LILAC, line * cov(abs(d + STROKE / 2) - STROKE / 2))
            d_sq = square(x, y, sx, sy)
            if d_sq < 70:
                over(px, i, 0.0, 0.0, 0.0, 0.55 * 0.5 * math.erfc(square(x, y - 22, sx, sy) * sq_k))
            t = ((x - (sx - SQ_HALF)) + (y - (sy - SQ_HALF))) / (4 * SQ_HALF)   # teal at the top left, violet at the bottom right
            over(px, i, *mix(TEAL, VIOLET, t), cov(d_sq))
            lit = max(0.0, 1.0 - (y - (sy - SQ_HALF)) / 90.0)
            over(px, i, 1.0, 1.0, 1.0, 0.30 * lit * cov(abs(d_sq + 2.5) - 2.5))   # bright top edge
            over(px, i, 1.0, 1.0, 1.0, 0.10 * lit * cov(d_sq))
    return px


def half(px, n):
    """2x2 box filter (premultiplied, so edges don't darken)."""
    m = n // 2
    out = array("f", bytes(m * m * 16))
    row = n * 4
    for y in range(m):
        r0 = 2 * y * row
        r1 = r0 + row
        o = y * m * 4
        for x in range(m):
            i, j, k = r0 + 8 * x, r1 + 8 * x, o + 4 * x
            for c in range(4):
                out[k + c] = (px[i + c] + px[i + 4 + c] + px[j + c] + px[j + 4 + c]) * 0.25
    return out


def write_png(path, px, n):
    raw = bytearray()
    for y in range(n):
        raw.append(0)  # filter: none
        for x in range(n):
            i = (y * n + x) * 4
            a = px[i + 3]
            if a < 1 / 512:
                raw += b"\0\0\0\0"
                continue
            raw += bytes(min(255, int(px[i + c] / a * 255 + 0.5)) for c in range(3))
            raw.append(min(255, int(a * 255 + 0.5)))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 6, 0, 0, 0)))
        f.write(chunk(b"sRGB", b"\0"))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))


def main():
    os.makedirs(OUT, exist_ok=True)
    images, by_size = [], {N: render()}
    n = N
    while n > 16:
        by_size[n // 2] = half(by_size[n], n)
        n //= 2
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
            write_png(os.path.join(OUT, name), by_size[pt * scale], pt * scale)
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})
    with open(os.path.join(OUT, "Contents.json"), "w", newline="\n") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")
    with open(os.path.join(OUT, "..", "Contents.json"), "w", newline="\n") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")
    print(f"wrote {len(images)} PNGs to {os.path.normpath(OUT)}")


if __name__ == "__main__":
    main()
