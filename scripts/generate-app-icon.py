#!/usr/bin/env python3
"""Generate ArchSight macOS app icon assets."""

from __future__ import annotations

import math
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
RESOURCE_DIR = ROOT / "apps" / "macos" / "Resources"
ICONSET_DIR = RESOURCE_DIR / "ArchSight.iconset"
PREVIEW_PATH = RESOURCE_DIR / "ArchSightIcon.png"
ICNS_PATH = RESOURCE_DIR / "ArchSight.icns"


def mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def vertical_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    image = Image.new("RGB", (size, size))
    px = image.load()
    for y in range(size):
        t = y / (size - 1)
        base = mix(top, bottom, t)
        for x in range(size):
            px[x, y] = base
    return image


def body_material(size: int) -> Image.Image:
    image = Image.new("RGB", (size, size))
    px = image.load()
    for y in range(size):
        for x in range(size):
            nx = x / (size - 1)
            ny = y / (size - 1)
            linear = mix((250, 252, 253), (126, 141, 153), ny)
            highlight = math.exp(-(((nx - 0.28) / 0.34) ** 2 + ((ny - 0.18) / 0.24) ** 2))
            cool_shadow = math.exp(-(((nx - 0.82) / 0.5) ** 2 + ((ny - 0.9) / 0.4) ** 2))
            r, g, b = linear
            r = min(255, int(r + 34 * highlight - 22 * cool_shadow))
            g = min(255, int(g + 34 * highlight - 18 * cool_shadow))
            b = min(255, int(b + 32 * highlight - 10 * cool_shadow))
            px[x, y] = (r, g, b)
    return image


def alpha_composite_rounded(
    base: Image.Image,
    rect: tuple[int, int, int, int],
    radius: int,
    fill: Image.Image | tuple[int, int, int, int],
) -> None:
    x0, y0, x1, y1 = rect
    width = x1 - x0
    height = y1 - y0
    mask = Image.new("L", (width, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width - 1, height - 1), radius=radius, fill=255)
    if isinstance(fill, Image.Image):
        layer = fill.convert("RGBA")
    else:
        layer = Image.new("RGBA", (width, height), fill)
    base.alpha_composite(Image.composite(layer, Image.new("RGBA", (width, height)), mask), (x0, y0))


def draw_icon(size: int = 1024) -> Image.Image:
    scale = size / 1024
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    body_rect = tuple(int(v * scale) for v in (76, 52, 948, 940))
    body_size = body_rect[2] - body_rect[0]
    body_radius = int(166 * scale)

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        tuple(int(v * scale) for v in (90, 86, 942, 956)),
        radius=body_radius,
        fill=(0, 0, 0, 92),
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(int(42 * scale))))

    body = body_material(body_size).convert("RGBA")
    body_mask = rounded_mask(body_size, body_radius)
    body_layer = Image.composite(body, Image.new("RGBA", body.size), body_mask)
    canvas.alpha_composite(body_layer, body_rect[:2])

    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(body_rect, radius=body_radius, outline=(255, 255, 255, 150), width=max(1, int(4 * scale)))
    draw.rounded_rectangle(
        tuple(int(v * scale) for v in (108, 86, 916, 904)),
        radius=int(142 * scale),
        outline=(60, 73, 84, 40),
        width=max(1, int(3 * scale)),
    )

    window_rect = tuple(int(v * scale) for v in (252, 228, 758, 734))
    win_w = window_rect[2] - window_rect[0]
    win_fill = vertical_gradient(win_w, (31, 42, 51), (13, 18, 24)).convert("RGBA")
    alpha_composite_rounded(canvas, window_rect, int(84 * scale), win_fill)
    draw.rounded_rectangle(window_rect, radius=int(84 * scale), outline=(255, 255, 255, 34), width=max(1, int(5 * scale)))
    draw.rounded_rectangle(
        tuple(int(v * scale) for v in (276, 254, 732, 706)),
        radius=int(68 * scale),
        outline=(0, 0, 0, 92),
        width=max(1, int(7 * scale)),
    )

    # Subtle internal panel reflection.
    reflection = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ref_draw = ImageDraw.Draw(reflection)
    ref_draw.polygon(
        [
            (int(300 * scale), int(240 * scale)),
            (int(710 * scale), int(240 * scale)),
            (int(550 * scale), int(392 * scale)),
            (int(260 * scale), int(392 * scale)),
        ],
        fill=(255, 255, 255, 18),
    )
    canvas.alpha_composite(reflection)

    code_specs = [
        (336, 336, 612, 372, 1.00),
        (336, 430, 532, 466, 0.86),
        (336, 524, 584, 560, 0.72),
    ]
    for x0, y0, x1, y1, opacity in code_specs:
        rect = tuple(int(v * scale) for v in (x0, y0, x1, y1))
        bar = Image.new("RGBA", (rect[2] - rect[0], rect[3] - rect[1]), (0, 0, 0, 0))
        bar_px = bar.load()
        for x in range(bar.width):
            t = x / max(1, bar.width - 1)
            color = mix((91, 233, 169), (32, 153, 103), t)
            for y in range(bar.height):
                bar_px[x, y] = (*color, int(235 * opacity))
        glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ImageDraw.Draw(glow).rounded_rectangle(rect, radius=int(17 * scale), fill=(50, 213, 143, int(60 * opacity)))
        canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(int(14 * scale))))
        alpha_composite_rounded(canvas, rect, int(17 * scale), bar)

    lens_center = (int(718 * scale), int(720 * scale))
    lens_outer = int(137 * scale)
    lens_box = (
        lens_center[0] - lens_outer,
        lens_center[1] - lens_outer,
        lens_center[0] + lens_outer,
        lens_center[1] + lens_outer,
    )
    lens_shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(lens_shadow).ellipse(lens_box, fill=(0, 0, 0, 112))
    canvas.alpha_composite(lens_shadow.filter(ImageFilter.GaussianBlur(int(18 * scale))), (int(5 * scale), int(12 * scale)))

    lens = Image.new("RGBA", (lens_outer * 2, lens_outer * 2), (0, 0, 0, 0))
    lens_px = lens.load()
    for y in range(lens.height):
        for x in range(lens.width):
            dx = (x - lens_outer) / lens_outer
            dy = (y - lens_outer) / lens_outer
            dist = math.sqrt(dx * dx + dy * dy)
            if dist <= 1:
                light = math.exp(-(((dx + 0.34) / 0.46) ** 2 + ((dy + 0.36) / 0.46) ** 2))
                edge = max(0.0, dist - 0.62) / 0.38
                color = mix((255, 231, 161), (138, 94, 28), min(1.0, edge * 0.85))
                r = min(255, int(color[0] + light * 34))
                g = min(255, int(color[1] + light * 25))
                b = min(255, int(color[2] + light * 10))
                lens_px[x, y] = (r, g, b, 255)
    canvas.alpha_composite(lens, (lens_center[0] - lens_outer, lens_center[1] - lens_outer))

    inner = int(76 * scale)
    draw.ellipse(
        (lens_center[0] - inner, lens_center[1] - inner, lens_center[0] + inner, lens_center[1] + inner),
        fill=(25, 34, 42, 245),
        outline=(255, 255, 255, 48),
        width=max(1, int(4 * scale)),
    )
    draw.ellipse(
        tuple(int(v * scale) for v in (670, 662, 718, 710)),
        fill=(93, 219, 174, 44),
    )
    draw.arc(
        tuple(int(v * scale) for v in (642, 642, 790, 790)),
        start=218,
        end=314,
        fill=(255, 239, 183, 120),
        width=max(1, int(8 * scale)),
    )

    # Soft body highlight, clipped to the top half so it reads as material
    # sheen instead of a dividing line.
    sheen = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sheen_mask = Image.new("L", (size, size), 0)
    sheen_draw = ImageDraw.Draw(sheen_mask)
    sheen_draw.rounded_rectangle(
        tuple(int(v * scale) for v in (122, 86, 900, 520)),
        radius=int(132 * scale),
        fill=62,
    )
    clip = Image.new("L", (size, size), 0)
    ImageDraw.Draw(clip).rectangle(tuple(int(v * scale) for v in (0, 0, 1024, 404)), fill=255)
    sheen_mask = Image.composite(sheen_mask, Image.new("L", (size, size), 0), clip)
    ImageDraw.Draw(sheen).rectangle((0, 0, size, size), fill=(255, 255, 255, 28))
    canvas.alpha_composite(Image.composite(sheen, Image.new("RGBA", (size, size)), sheen_mask))

    return canvas


def save_iconset(source: Image.Image) -> None:
    if ICONSET_DIR.exists():
        shutil.rmtree(ICONSET_DIR)
    ICONSET_DIR.mkdir(parents=True)

    sizes = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    for filename, pixels in sizes:
        resized = source.resize((pixels, pixels), Image.Resampling.LANCZOS)
        resized.save(ICONSET_DIR / filename)


def main() -> None:
    RESOURCE_DIR.mkdir(parents=True, exist_ok=True)
    source = draw_icon()
    source.save(PREVIEW_PATH)
    save_iconset(source)

    if ICNS_PATH.exists():
        ICNS_PATH.unlink()
    subprocess.run(["iconutil", "-c", "icns", str(ICONSET_DIR), "-o", str(ICNS_PATH)], check=True)
    print(f"Wrote {PREVIEW_PATH}")
    print(f"Wrote {ICONSET_DIR}")
    print(f"Wrote {ICNS_PATH}")


if __name__ == "__main__":
    main()
