#!/usr/bin/env python3
"""Generate the Mochi macOS app icon as an .icns file."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
ICONSET = ASSETS / "AppIcon.iconset"
PNG_1024 = ASSETS / "AppIcon-1024.png"
ICNS = ASSETS / "AppIcon.icns"


def rounded_rect_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size, size), radius=radius, fill=255)
    return mask


def draw_icon(size: int = 1024) -> Image.Image:
    scale = size / 1024
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    bg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bg_draw = ImageDraw.Draw(bg)
    for y in range(size):
        t = y / max(size - 1, 1)
        r = int(238 * (1 - t) + 191 * t)
        g = int(255 * (1 - t) + 239 * t)
        b = int(246 * (1 - t) + 226 * t)
        bg_draw.line((0, y, size, y), fill=(r, g, b, 255))
    img.alpha_composite(bg)

    # Soft floor shadow.
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.ellipse(
        tuple(int(v * scale) for v in (235, 740, 790, 850)),
        fill=(38, 71, 62, 60),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(34 * scale)))
    img.alpha_composite(shadow)

    body = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(body)

    # Body: rounded top with a flatter bottom, matching the in-app Mochi.
    left, top, right, bottom = [int(v * scale) for v in (205, 245, 819, 782)]
    radius = int(245 * scale)
    d.rounded_rectangle((left, top, right, bottom), radius=radius, fill=(124, 212, 174, 255))
    d.rectangle((left, int(555 * scale), right, bottom), fill=(124, 212, 174, 255))

    # Subtle outline and bottom weight.
    d.rounded_rectangle(
        (left, top, right, bottom),
        radius=radius,
        outline=(72, 163, 134, 230),
        width=int(18 * scale),
    )
    d.line(
        (left + int(28 * scale), bottom, right - int(28 * scale), bottom),
        fill=(62, 151, 126, 190),
        width=int(18 * scale),
    )

    # Highlight.
    d.ellipse(
        tuple(int(v * scale) for v in (315, 330, 485, 420)),
        fill=(185, 241, 216, 130),
    )

    # Face.
    eye = (33, 49, 47, 255)
    d.ellipse(tuple(int(v * scale) for v in (382, 480, 442, 552)), fill=eye)
    d.ellipse(tuple(int(v * scale) for v in (582, 480, 642, 552)), fill=eye)
    d.ellipse(tuple(int(v * scale) for v in (408, 492, 426, 514)), fill=(237, 255, 248, 230))
    d.ellipse(tuple(int(v * scale) for v in (608, 492, 626, 514)), fill=(237, 255, 248, 230))
    d.arc(
        tuple(int(v * scale) for v in (450, 520, 575, 630)),
        start=25,
        end=155,
        fill=eye,
        width=int(15 * scale),
    )

    img.alpha_composite(body)

    mask = rounded_rect_mask(size, int(218 * scale))
    img.putalpha(mask)
    return img


def save_iconset(source: Image.Image) -> None:
    if ICONSET.exists():
        shutil.rmtree(ICONSET)
    ICONSET.mkdir(parents=True)

    entries = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    for pixels, name in entries:
        resized = source.resize((pixels, pixels), Image.Resampling.LANCZOS)
        resized.save(ICONSET / name)


def main() -> None:
    ASSETS.mkdir(exist_ok=True)
    icon = draw_icon()
    icon.save(PNG_1024)
    save_iconset(icon)
    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)], check=True)
    shutil.rmtree(ICONSET)
    print(f"Generated {ICNS}")


if __name__ == "__main__":
    main()
