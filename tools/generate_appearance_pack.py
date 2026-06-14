#!/usr/bin/env python3
"""Generate a Mochi appearance pack from one or more reference images.

This wraps the local Codex image generation CLI when available. It writes four
PNG files named for the app's appearance slots:

    companion.png, work.png, rest.png, slack.png, drag.png

Use --install to copy the generated pack into ~/.mochi/appearances so the app
can load it immediately.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_IMAGE_CLI = Path.home() / ".codex/skills/.system/imagegen/scripts/image_gen.py"
DEFAULT_KEY_REMOVER = Path.home() / ".codex/skills/.system/imagegen/scripts/remove_chroma_key.py"
DEFAULT_OUT = ROOT / "work/appearance-pack"
DEFAULT_INSTALL = Path.home() / ".mochi/appearances"

ROLES = {
    "companion": "陪伴形态：清醒、亲近、安静陪在桌面上，表情温和。",
    "work": "工作形态：认真盯着屏幕或键盘，像在陪主人一起干活。",
    "rest": "休息形态：闭眼打盹或蜷起来睡觉，安静放松。",
    "slack": "摸鱼形态：发呆、趴着、懒洋洋，但仍然可爱。",
    "drag": "拖拽形态：站起来，前爪抬起，像被主人轻轻拎起来或拖动时有点惊讶。",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", action="append", required=True, help="Reference image. Repeat for multiple images.")
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT), help="Where to write the generated pack.")
    parser.add_argument("--install", action="store_true", help="Copy final PNGs to ~/.mochi/appearances.")
    parser.add_argument("--dry-run", action="store_true", help="Print generation commands without calling the API.")
    parser.add_argument("--quality", default="medium", choices=["low", "medium", "high", "auto"])
    parser.add_argument("--size", default="1024x1024")
    parser.add_argument("--image-cli", default=os.environ.get("MOCHI_IMAGE_CLI", str(DEFAULT_IMAGE_CLI)))
    parser.add_argument("--key-remover", default=os.environ.get("MOCHI_KEY_REMOVER", str(DEFAULT_KEY_REMOVER)))
    return parser.parse_args()


def role_prompt(role: str, description: str, reference_count: int) -> str:
    refs = ", ".join(f"Image {i + 1}" for i in range(reference_count))
    return f"""Use case: style-transfer
Asset type: transparent desktop pet sprite for the Mochi macOS app
Primary request: Create the "{role}" appearance for the user's real cat, using the input reference image(s) to preserve the cat's identity, fur pattern, face shape, color, and personality.
Input images: {refs} are identity and style references for the same cat.
Subject: the same cat as a cute desktop companion sprite.
State: {description}
Style/medium: polished soft digital pet sprite, clean edges, slightly simplified but still recognizable as the real cat.
Composition/framing: full body or bust, centered, generous padding, readable at small desktop size, no crop through ears or face.
Lighting/mood: soft friendly lighting, no dramatic shadows.
Background: perfectly flat solid #ff00ff chroma-key background for removal.
Constraints: preserve the cat's identity and fur markings; one cat only; no collar unless visible in references; no text; no watermark; no props except subtle role-implied posture.
Avoid: photorealistic clutter, humans, extra animals, duplicated limbs, busy backgrounds, gradients, shadows on the background, using #ff00ff in the subject.
"""


def run(cmd: list[str], dry_run: bool) -> None:
    print("+ " + " ".join(quote(part) for part in cmd))
    if not dry_run:
        subprocess.run(cmd, check=True)


def quote(value: str) -> str:
    if not value or any(c.isspace() or c in "\"'\\$" for c in value):
        return repr(value)
    return value


def main() -> int:
    args = parse_args()
    image_cli = Path(args.image_cli)
    key_remover = Path(args.key_remover)
    out_dir = Path(args.out_dir).expanduser().resolve()
    raw_dir = out_dir / "raw"
    prompt_dir = out_dir / "prompts"
    final_dir = out_dir / "final"

    images = [Path(p).expanduser().resolve() for p in args.image]
    missing = [str(p) for p in images if not p.exists()]
    if missing:
        print("Missing reference image(s): " + ", ".join(missing), file=sys.stderr)
        return 1

    if not image_cli.exists():
        print(f"Image generation CLI not found: {image_cli}", file=sys.stderr)
        print("Set MOCHI_IMAGE_CLI to a compatible image_gen.py path.", file=sys.stderr)
        return 1

    if not key_remover.exists():
        print(f"Chroma-key remover not found: {key_remover}", file=sys.stderr)
        return 1

    dry_run = args.dry_run
    if not os.environ.get("OPENAI_API_KEY"):
        print("OPENAI_API_KEY is not set; running as dry-run only.", file=sys.stderr)
        dry_run = True

    prompt_dir.mkdir(parents=True, exist_ok=True)
    raw_dir.mkdir(parents=True, exist_ok=True)
    final_dir.mkdir(parents=True, exist_ok=True)

    for role, description in ROLES.items():
        prompt_path = prompt_dir / f"{role}.txt"
        raw_path = raw_dir / f"{role}-key.png"
        final_path = final_dir / f"{role}.png"
        prompt_path.write_text(role_prompt(role, description, len(images)), encoding="utf-8")

        edit_cmd = [
            sys.executable,
            str(image_cli),
            "edit",
            "--model",
            "gpt-image-2",
            "--prompt-file",
            str(prompt_path),
            "--quality",
            args.quality,
            "--size",
            args.size,
            "--out",
            str(raw_path),
            "--force",
        ]
        for image in images:
            edit_cmd.extend(["--image", str(image)])
        run(edit_cmd, dry_run=dry_run)

        remove_cmd = [
            sys.executable,
            str(key_remover),
            "--input",
            str(raw_path),
            "--out",
            str(final_path),
            "--auto-key",
            "border",
            "--soft-matte",
            "--transparent-threshold",
            "12",
            "--opaque-threshold",
            "220",
            "--despill",
        ]
        run(remove_cmd, dry_run=dry_run)

    if args.install and not dry_run:
        DEFAULT_INSTALL.mkdir(parents=True, exist_ok=True)
        for role in ROLES:
            shutil.copy2(final_dir / f"{role}.png", DEFAULT_INSTALL / f"{role}.png")
        print(f"Installed appearance pack to {DEFAULT_INSTALL}")
    else:
        print(f"Appearance pack output: {final_dir}")
        if dry_run:
            print("Dry-run only. Set OPENAI_API_KEY and rerun to generate images.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
