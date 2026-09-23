#!/usr/bin/env python3
"""Composite docs/screenshots/preview.png, the repository's social card.

GitHub shows this whenever the repository is linked anywhere, so it is the one
image most people see before they see the README.

The popup comes from the first frame of the demo recording, and the widget is
captured fresh at the same usage percentage - the committed panel.png is
deliberately at 93% so the README can show the bar red, and a red bar next to a
popup reading 61% looks like a mistake rather than a different moment.

Run it after retaking the screenshots. Needs a display, because it captures.

Usage: build-preview.py
"""
import os
import pathlib
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont, ImageSequence

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
SHOTS = REPO / "docs/screenshots"

W, H = 1280, 640
BG = (27, 30, 32)
TEXT = (233, 236, 239)
DIM = (150, 158, 157)

# Measured off the card that was signed off, so a rebuild lands where the old
# one did rather than drifting a little each time.
WIDGET_TOP, WIDGET_LEFT = 168, 123
TITLE_Y, TITLE_X = 310, 82
TAGLINE_Y = 385
FOOTER_Y = 478
POPUP_X, POPUP_Y, POPUP_W = 748, 165, 452

TITLE = "Agent Session Manager"
TAGLINE = ["See which of your Claude Code", "sessions needs you, from the panel."]
FOOTER = "KDE Plasma 6   ·   MIT"


def font(name, size):
    path = subprocess.run(["fc-match", "-f", "%{file}", name],
                          capture_output=True, text=True).stdout.strip()
    if not path:
        sys.exit(f"no font for {name}")
    return ImageFont.truetype(path, size)


def ink_box(im, bg, tol=18):
    """The bounding box of everything that is not the background."""
    px = im.convert("RGB")
    w, h = px.size
    def ink(x, y):
        p = px.getpixel((x, y))
        return abs(p[0]-bg[0]) + abs(p[1]-bg[1]) + abs(p[2]-bg[2]) > tol
    cols = [x for x in range(w) if any(ink(x, y) for y in range(h))]
    rows = [y for y in range(h) if any(ink(x, y) for x in range(w))]
    return (cols[0], rows[0], cols[-1] + 1, rows[-1] + 1)


def main():
    card = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(card)

    # Captured rather than read off disk, at the percentage the popup shows.
    here = pathlib.Path(__file__).resolve().parent
    home = os.environ.get("RIG_HOME", str(here / "home"))
    subprocess.run([str(here / "capture.sh"), "panel", "50", "9"],
                   env={**os.environ, "RIG_HOME": home, "PANEL_PERCENT": "61"},
                   check=True, capture_output=True)

    # Cropped to its ink so the layout does not depend on how much air the
    # panel shot happens to carry.
    panel = Image.open(pathlib.Path(home) / "frames/panel.png").convert("RGB")
    panel = panel.crop(ink_box(panel, BG))
    scale = 142 / panel.height
    panel = panel.resize((round(panel.width * scale), 142), Image.LANCZOS)
    card.paste(panel, (WIDGET_LEFT, WIDGET_TOP))

    # The popup, taken from the first frame of the demo recording rather than
    # from a still of its own - it is the same render, and one fewer asset to
    # keep in step.
    frame = next(iter(ImageSequence.Iterator(Image.open(SHOTS / "demo.gif")))).convert("RGB")
    fw, fh = frame.size
    def is_card(p): return abs(p[0]-54) + abs(p[1]-54) + abs(p[2]-54) < 30
    rows = [y for y in range(fh) if is_card(frame.getpixel((fw // 2, y)))]
    cols = [x for x in range(fw) if is_card(frame.getpixel((x, (rows[0] + rows[-1]) // 2)))]
    popup = frame.crop((cols[0], rows[0], cols[-1] + 1, rows[-1] + 1))
    popup = popup.resize((POPUP_W, round(popup.height * POPUP_W / popup.width)), Image.LANCZOS)
    card.paste(popup, (POPUP_X, POPUP_Y))

    draw.text((TITLE_X, TITLE_Y), TITLE, font=font("Noto Sans:bold", 52), fill=TEXT)
    tag = font("Noto Sans", 25)
    for i, line in enumerate(TAGLINE):
        draw.text((TITLE_X + 1, TAGLINE_Y + i * 34), line, font=tag, fill=DIM)
    draw.text((TITLE_X + 1, FOOTER_Y), FOOTER, font=font("Noto Sans", 19), fill=DIM)

    out = SHOTS / "preview.png"
    card.save(out)
    print(f"{out}  {card.size[0]}x{card.size[1]}  "
          f"{out.stat().st_size // 1024} KiB")


if __name__ == "__main__":
    main()
