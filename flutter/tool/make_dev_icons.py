"""Build the green "development build" icon used by Debug builds.

The release icon stays the blue app icon. This script re-tints the existing
blue icon set to green (hue rotation that keeps lightness, so the rounded
square, gloss and white glyph are preserved) and writes it to
`macos/Runner/Assets.xcassets/AppIconDev.appiconset`, then packs a Windows
`app_icon_dev.ico`. Run it from the `flutter` directory when the base icon set
changes.
"""

from __future__ import annotations

import colorsys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RELEASE_SET = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
DEV_SET = ROOT / "macos/Runner/Assets.xcassets/AppIconDev.appiconset"
SIZES = [16, 32, 64, 128, 256, 512, 1024]
TARGET_HUE = 0.40  # emerald green, matching the "done" status tone
LIGHTNESS = 0.70  # keeps the deep, glossy body of the release icon
SATURATION = 0.62


def retint(image: Image.Image) -> Image.Image:
    out = image.convert("RGBA")
    pixels = out.load()
    width, height = out.size
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            if s < 0.16:
                # Neutral highlights and shadows stay neutral.
                if s > 0.04:
                    pixels[x, y] = (r, g, b, a)
                continue
            # Scale rather than replace, so gradients and gloss survive.
            nr, ng, nb = colorsys.hls_to_rgb(
                TARGET_HUE, min(1.0, l * LIGHTNESS), min(1.0, s * SATURATION)
            )
            pixels[x, y] = (round(nr * 255), round(ng * 255), round(nb * 255), a)
    return out


def main() -> None:
    DEV_SET.mkdir(parents=True, exist_ok=True)
    (DEV_SET / "Contents.json").write_text(
        (RELEASE_SET / "Contents.json").read_text(encoding="utf-8"),
        encoding="utf-8",
    )
    for size in SIZES:
        source = RELEASE_SET / f"app_icon_{size}.png"
        retint(Image.open(source)).save(DEV_SET / f"app_icon_{size}.png")
    windows_ico = ROOT / "windows/runner/resources/app_icon_dev.ico"
    with Image.open(DEV_SET / "app_icon_1024.png") as icon:
        icon.save(
            windows_ico,
            sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
        )
    print(f"生成开发版图标：{DEV_SET}、{windows_ico}")


if __name__ == "__main__":
    main()
