#!/usr/bin/env python3
"""
Generate a clean, macOS Big Sur+ compliant AppIcon for EnvMatrix.

The output is a 1024x1024 RGBA PNG with:
  - a transparent background;
  - a rounded-square tile (~824x824, centered) that follows Apple's
    recommended ~82% safe area for macOS app icons;
  - a subtle top-to-bottom gradient and a soft inner highlight;
  - a "matrix / environment" glyph in the middle (a 3x3 grid of chips
    that hints at multiple runtimes / envs).

The image intentionally does NOT include an outer shadow — macOS renders
its own shadow underneath the icon at display time.

Usage:
  python3 tools/icon-picker/generate_appicon.py \
      --out tools/icon-picker/generated/AppIcon-final.png
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


CANVAS = 1024
SAFE_AREA = 824
CORNER_RADIUS = 185

# Palette (roughly aligned with the sidebar accent colors used in the app)
BG_TOP = (68, 132, 255, 255)
BG_BOTTOM = (28, 78, 214, 255)

CHIP_COLORS = [
    (255, 214, 92, 255),   # yellow
    (255, 122, 122, 255),  # coral red
    (144, 226, 172, 255),  # mint
    (155, 138, 255, 255),  # violet
    (255, 255, 255, 255),  # white (center highlight)
    (110, 199, 255, 255),  # sky blue
    (255, 173, 122, 255),  # peach
    (140, 233, 205, 255),  # teal
    (215, 156, 255, 255),  # lavender
]


def linear_gradient(width: int, height: int, top: tuple, bottom: tuple) -> Image.Image:
    grad = Image.new("RGBA", (1, height), 0)
    tr, tg, tb, ta = top
    br, bg, bb, ba = bottom
    for y in range(height):
        t = y / max(1, height - 1)
        r = round(tr + (br - tr) * t)
        g = round(tg + (bg - tg) * t)
        b = round(tb + (bb - tb) * t)
        a = round(ta + (ba - ta) * t)
        grad.putpixel((0, y), (r, g, b, a))
    return grad.resize((width, height), Image.BILINEAR)


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return mask


def draw_chip(base: Image.Image, box: tuple[int, int, int, int], color: tuple,
              radius: int) -> None:
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0

    chip = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cd = ImageDraw.Draw(chip)
    cd.rounded_rectangle([0, 0, w - 1, h - 1], radius=radius, fill=color)

    # subtle inner highlight (top edge)
    highlight = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    hd = ImageDraw.Draw(highlight)
    hd.rounded_rectangle([2, 2, w - 3, int(h * 0.5)],
                         radius=max(1, radius - 2),
                         fill=(255, 255, 255, 45))
    highlight = highlight.filter(ImageFilter.GaussianBlur(radius=3))
    chip.alpha_composite(highlight)

    base.alpha_composite(chip, dest=(x0, y0))


def build_icon() -> Image.Image:
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    # ---- rounded tile with gradient -----------------------------------------
    tile_size = SAFE_AREA
    tile_origin = ((CANVAS - tile_size) // 2, (CANVAS - tile_size) // 2)

    gradient = linear_gradient(tile_size, tile_size, BG_TOP, BG_BOTTOM)
    tile_mask = rounded_mask((tile_size, tile_size), CORNER_RADIUS)
    tile = Image.new("RGBA", (tile_size, tile_size), (0, 0, 0, 0))
    tile.paste(gradient, (0, 0), mask=tile_mask)

    # soft top-inner highlight to give it depth
    inner_hi = Image.new("RGBA", (tile_size, tile_size), (0, 0, 0, 0))
    ih = ImageDraw.Draw(inner_hi)
    ih.rounded_rectangle(
        [24, 24, tile_size - 24, int(tile_size * 0.55)],
        radius=CORNER_RADIUS - 10,
        fill=(255, 255, 255, 40),
    )
    inner_hi = inner_hi.filter(ImageFilter.GaussianBlur(radius=28))
    inner_hi.putalpha(
        Image.eval(inner_hi.split()[-1], lambda a: int(a))  # keep alpha as-is
    )
    tile.alpha_composite(inner_hi)

    canvas.alpha_composite(tile, dest=tile_origin)

    # ---- 3x3 chip grid ------------------------------------------------------
    grid_pad = int(tile_size * 0.14)           # padding from tile edge
    grid_area = tile_size - grid_pad * 2
    gap = int(tile_size * 0.035)
    chip_side = (grid_area - gap * 2) // 3
    chip_radius = int(chip_side * 0.24)

    origin_x = tile_origin[0] + grid_pad
    origin_y = tile_origin[1] + grid_pad

    idx = 0
    for row in range(3):
        for col in range(3):
            x0 = origin_x + col * (chip_side + gap)
            y0 = origin_y + row * (chip_side + gap)
            color = CHIP_COLORS[idx % len(CHIP_COLORS)]
            draw_chip(canvas, (x0, y0, x0 + chip_side, y0 + chip_side),
                      color, chip_radius)
            idx += 1

    # ---- center emphasis: a small "M" on the middle white chip --------------
    center_col, center_row = 1, 1
    cx0 = origin_x + center_col * (chip_side + gap)
    cy0 = origin_y + center_row * (chip_side + gap)
    cx1, cy1 = cx0 + chip_side, cy0 + chip_side

    m_layer = Image.new("RGBA", (chip_side, chip_side), (0, 0, 0, 0))
    md = ImageDraw.Draw(m_layer)
    stroke = max(6, chip_side // 10)
    inset = int(chip_side * 0.22)
    # Draw a stylized "M" using 4 straight strokes
    md.line([(inset, chip_side - inset),
             (inset, inset)], fill=(46, 92, 220, 255), width=stroke)
    md.line([(inset, inset),
             (chip_side // 2, chip_side // 2)],
            fill=(46, 92, 220, 255), width=stroke)
    md.line([(chip_side // 2, chip_side // 2),
             (chip_side - inset, inset)],
            fill=(46, 92, 220, 255), width=stroke)
    md.line([(chip_side - inset, inset),
             (chip_side - inset, chip_side - inset)],
            fill=(46, 92, 220, 255), width=stroke)

    canvas.alpha_composite(m_layer, dest=(cx0, cy0))

    return canvas


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True, help="Output PNG path.")
    args = parser.parse_args()

    out = Path(args.out).expanduser().resolve()
    out.parent.mkdir(parents=True, exist_ok=True)

    icon = build_icon()
    icon.save(out, "PNG")
    print(f"Wrote {out} ({icon.size[0]}x{icon.size[1]}, mode={icon.mode})")


if __name__ == "__main__":
    main()
