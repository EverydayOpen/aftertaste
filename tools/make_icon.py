"""Render the Aftertaste app icon and write App/Assets.xcassets/AppIcon.appiconset.

Stdlib only (no Pillow). Shapes are signed distance functions, so every edge gets exact analytic antialiasing at
1024 px; smaller sizes are box-filtered down from the 1024 master in premultiplied alpha.

Layout follows the macOS (Big Sur and later) icon grid: 1024 canvas, 824 px body with continuous-looking corners, soft
drop shadow. The drawing is docs/DESIGN.md section 7, the same mark as the app's welcome screen and menu bar glyph: a
violet-black body with the afterglow (a teal horizon at 70 % of the body's height, a soft teal pool below it and a violet
haze above it) and, in lilac, the mark: a dashed rounded-square outline centred on the horizon with its top-right corner
missing, and a small solid tile set diagonally above the gap (the thing that left). It reads at 16 px as a dark square, a
teal line and a dashed square with a dot.

Run from the repo root (a few minutes):  python tools/make_icon.py
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
TOP, BOTTOM = (14 / 255, 11 / 255, 31 / 255), (20 / 255, 24 / 255, 39 / 255)    # #0E0B1F -> #141827

# Colours shared with tools/make_og.py (it imports these three).
TEAL, VIOLET = (0.30, 0.88, 0.80), (0.64, 0.50, 1.0)
LILAC = (0.82, 0.78, 1.0)

HORIZON_TEAL, HORIZON_CORE = (127 / 255, 227 / 255, 214 / 255), (239 / 255, 1.0, 252 / 255)   # #7FE3D6, #EFFFFC
MARK = (183 / 255, 168 / 255, 1.0)                                                                # #B7A8FF
HORIZON = 100.0 + 0.70 * 824.0                                                                    # 70 % of the body's height

# The mark: the outline's centre sits on the horizon. Half size, corner radius (0.27 of the side, as in the app's mark), stroke
# (1/14 of the side), and the dashes: 16 round-capped pills around the perimeter (4 per side), one centred on every corner.
MX, MY = 452.0, HORIZON
M_HALF, M_R = 190.0, 100.0
M_W = 2 * M_HALF / 14
M_L = 2 * (M_HALF - M_R)                       # one straight run
M_A = math.pi * M_R / 2                        # one corner arc
M_P = 4 * (M_L + M_A)                          # perimeter
M_PERIOD = M_P / 16
M_PHASE = M_L + M_A / 2 - 3 * M_PERIOD         # puts dash 3 on the middle of the top-right arc, so one sits on every corner
M_CORE = 22.0                                  # dash length between the cap centres; the caps add a stroke width
M_MISSING = (3,)                               # the top-right corner dash

# The tile that left: diagonally above the gap, with the outline's corner ratio.
TILE_C, TILE_HALF, TILE_R = (MX + M_HALF + 56.0, MY - M_HALF - 54.0), 60.0, 33.0


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


def perimeter_at(u, v):
    """Arc length, clockwise from the start of the top run, of the outline's point nearest to (u, v) (centre-relative, y down)."""
    k = M_HALF - M_R
    a, b = abs(u) - k, abs(v) - k
    clamp = lambda t: max(0.0, min(M_L, t))
    if a > 0 and b > 0:                                  # a corner: the angle round its arc
        if u > 0 and v < 0:
            return M_L + M_R * math.atan2(a, b)                          # top right, from up to right
        if u > 0:
            return 2 * M_L + M_A + M_R * math.atan2(b, a)                # bottom right, from right to down
        if v > 0:
            return 3 * M_L + 2 * M_A + M_R * math.atan2(a, b)            # bottom left, from down to left
        return 4 * M_L + 3 * M_A + M_R * math.atan2(b, a)                # top left, from left to up
    if a >= b:                                           # a vertical side
        return M_L + M_A + clamp(v + k) if u > 0 else 3 * M_L + 3 * M_A + clamp(k - v)
    return clamp(u + k) if v < 0 else 2 * M_L + 2 * M_A + clamp(k - u)


def dashes_sdf(x, y):
    """Signed distance to the dashed outline (round-capped pills along the perimeter, minus the missing ones)."""
    u, v = x - MX, y - MY
    d = abs(rrect(u, v, 0.0, 0.0, M_HALF, M_HALF, M_R))
    if d > M_W / 2 + 2:
        return d - M_W / 2
    s = perimeter_at(u, v)
    k0 = round((s - M_PHASE) / M_PERIOD)
    best = 1e9
    for k in (k0 - 1, k0, k0 + 1):
        if k % 16 in M_MISSING:
            continue
        along = abs((s - (M_PHASE + k * M_PERIOD) + M_P / 2) % M_P - M_P / 2)
        best = min(best, math.hypot(d, max(0.0, along - M_CORE / 2)))
    return best - M_W / 2


def tile_sdf(x, y, dy=0.0):
    return rrect(x, y - dy, TILE_C[0], TILE_C[1], TILE_HALF, TILE_HALF, TILE_R)


def render():
    px = array("f", bytes(N * N * 16))
    shadow_k = 1 / (14.0 * math.sqrt(2))       # body shadow: sigma 14 px, 10 px down, 32 %
    tile_k = 1 / (16.0 * math.sqrt(2))         # the tile's shadow: sigma 16 px, 18 px down, 50 %
    tx, ty = TILE_C
    for yi in range(N):
        y = yi + 0.5
        base = mix(TOP, BOTTOM, (y - 100) / 824)
        dy = y - HORIZON
        # Pool below the horizon (long and soft), a thin glow above it; the haze above is violet and sits behind the mark.
        pool_y = math.exp(-(dy / 105.0) ** 2) if dy >= 0 else math.exp(-(dy / 16.0) ** 2)
        haze_y = math.exp(-(dy / 170.0) ** 2) if dy < 0 else math.exp(-(dy / 26.0) ** 2)
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
            glow = max(0.0, 1.0 - ((x - 512) ** 2 + (y - 110) ** 2) / 640.0 ** 2) * 0.07   # the faint highlight at the top
            over(px, i, *mix(base, (1, 1, 1), glow), a)
            dx = x - 512.0
            over(px, i, *VIOLET, 0.30 * math.exp(-(dx / 300.0) ** 2) * haze_y * a)          # violet haze above the horizon
            over(px, i, *HORIZON_TEAL, 0.34 * math.exp(-(dx / 290.0) ** 2) * pool_y * a)    # teal pool below it
            fade = max(0.0, 1.0 - (abs(dx) / 404.0) ** 3) * a                                # the line dies out toward the body's edges
            ady = abs(dy)
            over(px, i, *HORIZON_TEAL, 0.30 * math.exp(-(ady / 14.0) ** 2) * fade)           # the line's glow
            over(px, i, *HORIZON_TEAL, 0.95 * cov(ady - 4.5) * fade)                         # the line
            over(px, i, *HORIZON_CORE, 0.95 * cov(ady - 1.8) * fade)                         # its core
            over(px, i, 1.0, 1.0, 1.0, 0.12 * cov(abs(d_body + 2.0) - 1.5))                  # thin rim: keeps the edge on dark Docks
            if 240 < x < 800 and 350 < y < 900:                                              # the mark and the tile
                d = dashes_sdf(x, y)
                if d < 1:
                    over(px, i, *MARK, 0.96 * cov(d))
                if abs(x - tx) < 120 and abs(y - ty) < 140:
                    d_t = tile_sdf(x, y)
                    if d_t < 70:
                        over(px, i, 0.0, 0.0, 0.0, 0.50 * 0.5 * math.erfc(tile_sdf(x, y, 18.0) * tile_k))
                    t = (y - (ty - TILE_HALF)) / (2 * TILE_HALF)                              # lighter at the top
                    over(px, i, *mix((0.84, 0.80, 1.0), MARK, t), cov(d_t))
                    lit = max(0.0, 1.0 - (y - (ty - TILE_HALF)) / 38.0)
                    over(px, i, 1.0, 1.0, 1.0, 0.45 * lit * cov(abs(d_t + 2.0) - 2.0))      # the specular edge on the solid tile
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
