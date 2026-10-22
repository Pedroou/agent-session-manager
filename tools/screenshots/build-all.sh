#!/usr/bin/env bash
# Rebuild every screenshot, in both sizes, from the fabricated home.
#
#   docs/screenshots/*        the README's: each the natural size of what it
#                             shows, at 2x, so they sit at the README's widths
#   docs/screenshots/store/*  the KDE Store gallery's: every picture 1920x1080,
#                             rendered at 2.5x and centred, so paging through
#                             the gallery does not jump between sizes
#
# Opens a window on the current display for each capture - the rig renders
# through xcb, because the offscreen platform draws rounded corners square.
#
# Usage: build-all.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SHOTS="$REPO/docs/screenshots"
STORE="$SHOTS/store"
HOME_DIR="${RIG_HOME:-$HERE/home}"
FRAMES="$HOME_DIR/frames"
export RIG_HOME="$HOME_DIR"

# The store scale: the tallest canvas (usage, ~405 logical px) at 2.5x is
# ~1012 px, which leaves the 1080 frame a margin on every side.
README_SCALE=2
STORE_SCALE=2.5

# Recordings: scenario, frame interval in ms (what capture.sh records at), and
# the frame rate the GIF plays at. The demo is a slideshow of state changes, so
# it plays at one frame a second; the others are live motion.
RECORDINGS=(
    "demo 50 1"
    "usage 60 16.667"
    "actions 60 16.667"
    "copy 60 16.667"
)

fish --no-config "$HERE/build-home.fish" "$HOME_DIR"
mkdir -p "$STORE"

# The demo's last state is held twice as long, so the loop reads as an ending
# rather than a stutter. Every frame in a GIF shares one delay, so the hold is
# a repeated frame.
hold_last() {
    local last next
    last=$(find "$FRAMES" -name 'f*.png' | sort | tail -n 1)
    next=$(printf '%s/f%04d.png' "$FRAMES" $((10#$(basename "$last" .png | tr -d f) + 1)))
    cp "$last" "$next"
}

record() {
    local scenario=$1 ms=$2 fps=$3 scale=$4 out=$5 pad=$6
    "$HERE/capture.sh" "$scenario" "$ms" "$scale"
    if ! compgen -G "$FRAMES/f*.png" >/dev/null; then
        echo "✗ $scenario captured no frames - see $HERE/capture.log" >&2
        exit 1
    fi
    if [[ $scenario == demo ]]; then
        hold_last
    fi
    if [[ $pad == yes ]]; then
        "$HERE/pad-frames.py" "$FRAMES"
    fi
    "$HERE/assemble.sh" "$FRAMES" "$out" "$fps" 200
}

for entry in "${RECORDINGS[@]}"; do
    read -r scenario ms fps <<<"$entry"
    record "$scenario" "$ms" "$fps" "$README_SCALE" "$SHOTS/$scenario.gif" no
done

# The panel still is README-only: on its own it is too small to be a gallery
# picture, and the store card below already shows it.
"$HERE/capture.sh" panel 50 9
cp "$FRAMES/panel.png" "$SHOTS/panel.png"

# The social card is composed from demo.gif, so it comes after the README's.
"$HERE/build-preview.py"

for entry in "${RECORDINGS[@]}"; do
    read -r scenario ms fps <<<"$entry"
    record "$scenario" "$ms" "$fps" "$STORE_SCALE" "$STORE/$scenario.gif" yes
done
"$HERE/build-preview.py" --store
