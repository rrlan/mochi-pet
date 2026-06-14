#!/usr/bin/env python3
"""Install generated cat appearance sprites into ~/.mochi/appearances.

The generated sheets often have uneven spacing. This installer removes the
magenta key and then splits sprites by their actual alpha silhouette, so one
pose does not leak into the next pose.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
INSTALL = Path.home() / ".mochi/appearances"
ASSET_OUT = ROOT / "assets/cat-appearance/final"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--states-sheet", required=True, help="Four-pose sheet: companion, work, rest, slack.")
    parser.add_argument("--walk-sheet", required=True, help="Multi-frame right-facing walk sheet.")
    parser.add_argument("--drag", required=True, help="Single drag/standing sprite.")
    return parser.parse_args()


def remove_magenta_hard(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            is_key = r > 175 and b > 145 and g < 125 and abs(r - b) < 120
            pixels[x, y] = (r, g, b, 0) if is_key else (r, g, b, 255)
    return image


def crop_with_padding(image: Image.Image, bbox: tuple[int, int, int, int], pad: int = 18) -> Image.Image:
    left, top, right, bottom = bbox
    return image.crop((
        max(0, left - pad),
        max(0, top - pad),
        min(image.width, right + pad),
        min(image.height, bottom + pad),
    ))


def find_x_segments(image: Image.Image, expected: int) -> list[tuple[int, int]]:
    alpha = image.getchannel("A")
    threshold = max(8, image.height // 120)
    occupied = []
    for x in range(image.width):
        count = sum(1 for y in range(image.height) if alpha.getpixel((x, y)) > 0)
        occupied.append(count > threshold)

    segments: list[tuple[int, int]] = []
    start: int | None = None
    for index, on in enumerate(occupied + [False]):
        if on and start is None:
            start = index
        elif not on and start is not None:
            if index - start > 8:
                segments.append((start, index))
            start = None

    while len(segments) > expected:
        gaps = [(segments[i + 1][0] - segments[i][1], i) for i in range(len(segments) - 1)]
        _, index = min(gaps)
        segments[index] = (segments[index][0], segments[index + 1][1])
        del segments[index + 1]

    if len(segments) != expected:
        raise RuntimeError(f"Expected {expected} sprites, got {len(segments)}: {segments}")
    return segments


def split_sheet(source: Path, names: list[str], output_dir: Path) -> list[Path]:
    image = remove_magenta_hard(Image.open(source))
    segments = find_x_segments(image, len(names))
    output_dir.mkdir(parents=True, exist_ok=True)
    outputs: list[Path] = []

    for name, (left, right) in zip(names, segments):
        band = image.crop((left, 0, right, image.height))
        bbox = band.getchannel("A").getbbox()
        if bbox is None:
            raise RuntimeError(f"No sprite content found for {name}")
        sprite = crop_with_padding(band, bbox)
        target = output_dir / f"{name}.png"
        sprite.save(target)
        outputs.append(target)
    return outputs


def main() -> int:
    args = parse_args()
    INSTALL.mkdir(parents=True, exist_ok=True)
    (INSTALL / "walk").mkdir(parents=True, exist_ok=True)
    ASSET_OUT.mkdir(parents=True, exist_ok=True)
    (ASSET_OUT / "walk").mkdir(parents=True, exist_ok=True)

    state_names = ["companion", "work", "rest", "slack"]
    for path in split_sheet(Path(args.states_sheet), state_names, ASSET_OUT):
        (INSTALL / path.name).write_bytes(path.read_bytes())

    for old in (INSTALL / "walk").glob("*.png"):
        old.unlink()
    walk_image = Image.open(args.walk_sheet)
    frame_count = 6 if walk_image.width / walk_image.height > 2.4 else 4
    frame_names = [f"frame_{index:02d}" for index in range(frame_count)]
    for path in split_sheet(Path(args.walk_sheet), frame_names, ASSET_OUT / "walk"):
        (INSTALL / "walk" / path.name).write_bytes(path.read_bytes())

    drag = remove_magenta_hard(Image.open(args.drag))
    bbox = drag.getchannel("A").getbbox()
    if bbox is None:
        raise RuntimeError("No sprite content found for drag")
    drag = crop_with_padding(drag, bbox, pad=20)
    drag_path = ASSET_OUT / "drag.png"
    drag.save(drag_path)
    (INSTALL / "drag.png").write_bytes(drag_path.read_bytes())

    print(f"Installed cat appearances to {INSTALL}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
