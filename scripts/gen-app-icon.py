#!/usr/bin/env python3
"""Generate the Family Record app icon variants for AppIcon.appiconset.

The mark is three strokes: a vertical rule crossed by two shorter ticks that
rise like pencil marks on a doorframe. It also reads as an "F". This mirrors
the web app's icon (Family-Portal/scripts/gen-icons.py) — keep the geometry
constants in the two scripts in sync.

Run `python3 scripts/gen-app-icon.py` after changing any constant here.
"""

import os

from PIL import Image, ImageDraw

OUT = os.path.join(
    os.path.dirname(__file__),
    "..",
    "Family-Portal-Ios",
    "Assets.xcassets",
    "AppIcon.appiconset",
)

S = 512  # design canvas; output is scaled up from here
SIZE = 1024  # iOS wants a single 1024x1024 per appearance
STROKE = 44
SS = 4  # supersample factor

# Stroke centerlines, all axis-aligned: (x1, y1, x2, y2)
STROKES = [
    (156, 106, 156, 406),  # vertical rule
    (156, 166, 356, 166),  # upper tick (tallest mark)
    (156, 286, 286, 286),  # lower tick
]

# (filename, background, foreground)
VARIANTS = [
    ("AppIcon.png", (16, 185, 129), (255, 255, 255)),  # brand green / white
    ("AppIcon-Dark.png", (11, 31, 24), (105, 219, 124)),  # near-black / green
    ("AppIcon-Tinted.png", (28, 28, 28), (242, 242, 242)),  # grayscale ramp
]


def render(bg, fg):
    """Draw one opaque, full-bleed variant. iOS applies its own corner mask."""
    n = SIZE * SS
    scale = n / S
    img = Image.new("RGB", (n, n), bg)
    d = ImageDraw.Draw(img)

    r = STROKE / 2
    for x1, y1, x2, y2 in STROKES:
        # An axis-aligned round-capped stroke is a rounded rectangle.
        box = (x1 - r, y1 - r, x2 + r, y2 + r)
        d.rounded_rectangle(
            [v * scale for v in box], radius=r * scale, fill=fg
        )
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    print("Generating app icons in Assets.xcassets/AppIcon.appiconset/")
    for name, bg, fg in VARIANTS:
        img = render(bg, fg)
        # The App Store rejects icons with an alpha channel.
        assert img.mode == "RGB", img.mode
        img.save(os.path.join(OUT, name))
        print(f"  {name} ({SIZE}x{SIZE})")


if __name__ == "__main__":
    main()
