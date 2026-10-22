#!/usr/bin/env python3
"""Centre every frame of a recording on a fixed-size canvas, for the KDE Store.

The store's gallery shows pictures one after another in the same box, so five
pictures of five sizes jump around as you page through them. The store copies
are all 1920x1080: 16:9 is the size the most-downloaded Plasma widgets that pick
a size on purpose use, and the one Flathub and Steam ask screenshots to be.

The frames are rendered at a scale that already fits, so this only adds
background around them - nothing is resampled. The background is the stage's
own surround colour, so the added border is indistinguishable from the margin
the stage already draws.

Usage: pad-frames.py <frames-dir> [width height]
"""
import pathlib
import sys

from PIL import Image

SURROUND = (0x1b, 0x1e, 0x20)


def main():
    frames = pathlib.Path(sys.argv[1])
    w, h = (int(sys.argv[2]), int(sys.argv[3])) if len(sys.argv) > 3 else (1920, 1080)
    paths = sorted(frames.glob("f*.png"))
    if not paths:
        sys.exit(f"no frames in {frames}")
    for path in paths:
        frame = Image.open(path).convert("RGB")
        if frame.width > w or frame.height > h:
            sys.exit(f"{path.name} is {frame.width}x{frame.height}, larger than {w}x{h}:"
                     " capture it at a smaller scale rather than shrinking it here")
        canvas = Image.new("RGB", (w, h), SURROUND)
        canvas.paste(frame, ((w - frame.width) // 2, (h - frame.height) // 2))
        canvas.save(path)
    print(f"padded {len(paths)} frames to {w}x{h}")


if __name__ == "__main__":
    main()
