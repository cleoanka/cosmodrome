#!/usr/bin/env python3
"""make-icon.py — render the Cosmodrome app icon.

A deep-space squircle with a faint starfield and a glowing 3x3 grid of
glassy app tiles — the launch pad, seen from above at night.

Renders a 1024x1024 master with PIL, sips-resizes into AppIcon.iconset and
iconutil-compiles to Resources/AppIcon.icns.
"""
import os
import random
import shutil
import subprocess

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, ".build", "icon-work")
ICONSET = os.path.join(WORK, "AppIcon.iconset")
RESOURCES = os.path.join(ROOT, "Resources")

S = 1024      # canvas
SS = 2        # supersample factor
INSET = 100   # macOS icon grid margin (~10%)
RADIUS = 185  # reads as the macOS squircle

BG_TOP = (0x3B, 0x2E, 0x83)   # indigo dawn
BG_BOT = (0x0D, 0x0A, 0x24)   # deep space

TILE_COLORS = [
    (0xFF, 0x6B, 0x6B), (0xFF, 0xA9, 0x4D), (0xFF, 0xD4, 0x3B),
    (0x69, 0xDB, 0x7C), (0x38, 0xD9, 0xA9), (0x4D, 0xAB, 0xF7),
    (0x74, 0x8F, 0xFC), (0xDA, 0x77, 0xF2), (0xF7, 0x83, 0xAC),
]


def vgrad(w, h, top, bot):
    strip = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / (h - 1)
        strip.putpixel((0, y), tuple(round(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    return strip.resize((w, h))


def rounded_mask(size, box, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask


def render_master():
    s = S * SS
    inset, radius = INSET * SS, RADIUS * SS
    box = (inset, inset, s - inset, s - inset)

    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    # Soft drop shadow under the squircle.
    shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (box[0], box[1] + 14 * SS, box[2], box[3] + 14 * SS), radius=radius, fill=(0, 0, 0, 110)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(18 * SS))
    img.alpha_composite(shadow)

    # Squircle body: vertical space gradient.
    body = vgrad(s, s, BG_TOP, BG_BOT).convert("RGBA")
    img.paste(body, (0, 0), rounded_mask((s, s), box, radius))

    draw = ImageDraw.Draw(img)

    # Starfield, kept inside the squircle.
    random.seed(7)
    star_mask = rounded_mask((s, s), box, radius)
    stars = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(stars)
    for _ in range(140):
        x = random.randint(box[0], box[2])
        y = random.randint(box[1], box[3])
        r = random.choice([1, 1, 1, 2, 2, 3]) * SS
        a = random.randint(50, 160)
        sdraw.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, a))
    stars.putalpha(Image.composite(stars.split()[3], Image.new("L", (s, s), 0), star_mask))
    img.alpha_composite(stars)

    # Glow behind the tile grid.
    glow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    cx, cy = s // 2, s // 2 + 14 * SS
    gr = 330 * SS
    gdraw.ellipse((cx - gr, cy - gr, cx + gr, cy + gr), fill=(0x8A, 0x7B, 0xFF, 70))
    glow = glow.filter(ImageFilter.GaussianBlur(90 * SS))
    img.alpha_composite(glow)

    # 3x3 grid of glassy tiles.
    tile = 158 * SS
    gap = 40 * SS
    grid_w = tile * 3 + gap * 2
    gx = (s - grid_w) // 2
    gy = (s - grid_w) // 2 + 14 * SS
    tile_r = 36 * SS
    for row in range(3):
        for col in range(3):
            i = row * 3 + col
            x0 = gx + col * (tile + gap)
            y0 = gy + row * (tile + gap)
            box_t = (x0, y0, x0 + tile, y0 + tile)
            color = TILE_COLORS[i]

            # Tile shadow.
            tshadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
            ImageDraw.Draw(tshadow).rounded_rectangle(
                (x0, y0 + 6 * SS, x0 + tile, y0 + tile + 6 * SS), radius=tile_r, fill=(0, 0, 0, 90)
            )
            img.alpha_composite(tshadow.filter(ImageFilter.GaussianBlur(8 * SS)))

            # Tile body: per-tile vertical gradient (lighter top).
            light = tuple(min(255, round(c * 1.25 + 20)) for c in color)
            tgrad = vgrad(tile, tile, light, color).convert("RGBA")
            timg = Image.new("RGBA", (s, s), (0, 0, 0, 0))
            timg.paste(tgrad, (x0, y0), rounded_mask((tile, tile), (0, 0, tile, tile), tile_r))
            img.alpha_composite(timg)

            # Glass highlight: top half sheen.
            sheen = Image.new("RGBA", (s, s), (0, 0, 0, 0))
            sh = vgrad(tile, tile // 2, (255, 255, 255), (255, 255, 255)).convert("RGBA")
            sh.putalpha(vgrad(tile, tile // 2, (90, 90, 90), (0, 0, 0)).convert("L"))
            sheen.paste(sh, (x0, y0), rounded_mask((tile, tile // 2), (0, 0, tile, tile // 2), tile_r))
            img.alpha_composite(sheen)

            draw.rounded_rectangle(box_t, radius=tile_r, outline=(255, 255, 255, 60), width=2 * SS)

    # Rim light on the squircle itself.
    draw.rounded_rectangle(box, radius=radius, outline=(255, 255, 255, 46), width=3 * SS)

    return img.resize((S, S), Image.LANCZOS)


def main():
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(ICONSET, exist_ok=True)
    os.makedirs(RESOURCES, exist_ok=True)

    master_path = os.path.join(WORK, "master-1024.png")
    render_master().save(master_path)

    sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
    for pt, scale in sizes:
        px = pt * scale
        suffix = f"{pt}x{pt}" + ("@2x" if scale == 2 else "")
        out = os.path.join(ICONSET, f"icon_{suffix}.png")
        subprocess.run(["sips", "-z", str(px), str(px), master_path, "--out", out],
                       check=True, capture_output=True)

    icns = os.path.join(RESOURCES, "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", ICONSET, "-o", icns], check=True)
    print(f"wrote {icns}")


if __name__ == "__main__":
    main()
