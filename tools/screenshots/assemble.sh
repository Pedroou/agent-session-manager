#!/usr/bin/env bash
# Frames to GIF.
#
# One palette for the whole clip: a per-frame palette makes a flat background
# crawl, which is very visible on a widget that is mostly one dark colour.
# Rectangle diffing is what keeps a mostly static popup from costing megabytes.
#
# Nothing is rescaled. The frames are already the output size - resampling them
# on the way through is what softened the first batch, and a 780-to-700 lanczos
# pass is indistinguishable from the content having been upscaled.
#
# Usage: assemble.sh <frames-dir> <out.gif> <fps> [colours]
set -euo pipefail
DIR="$1"; OUT="$2"; FPS="$3"; COLOURS="${4:-200}"
ffmpeg -y -loglevel error -framerate "$FPS" -i "$DIR/f%04d.png" \
    -vf "split[a][b];[a]palettegen=max_colors=${COLOURS}:stats_mode=full[p];[b][p]paletteuse=dither=none:diff_mode=rectangle" \
    -loop 0 "$OUT"
printf '%s  %s  %s KiB\n' "$OUT" \
    "$(ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0 "$OUT")" \
    "$(( $(stat -c%s "$OUT") / 1024 ))"
