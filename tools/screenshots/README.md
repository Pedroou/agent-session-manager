# The screenshot rig

Every image in `docs/screenshots/` is produced by this directory. It exists for
two reasons, and the second one is the important one.

The first is that the images have to agree with each other. A screenshot taken
by hand shows whatever was running at the time, so retaking one to fix a detail
meant retaking all of them, and the ages drifted between shots.

The second is privacy. The widget's whole job is to display directories, branch
names and session ids - so a screenshot of it is a screenshot of whoever took
it. That is not a leak you can fix afterwards: the images are rendered pixels,
so a real path in one cannot be found by grepping the repository. It has to not
be there in the first place.

So the rig fabricates a home directory and mounts it at `/home/dev` with
`bwrap`. Inside that sandbox `/home/dev/code/docs-site` is a path the collector
genuinely walks, with a real `.git/HEAD` at the end of it. Nothing on the machine
taking the picture is reachable.

## Running it

```sh
tools/screenshots/build-all.sh
```

That fabricates the home and produces every image, in two sets:

| where | size | for |
|---|---|---|
| `docs/screenshots/` | each the natural size of what it shows, at 2x | the README and GitHub's social card |
| `docs/screenshots/store/` | every picture 1920x1080, rendered at 2.5x and centred | the KDE Store gallery |

The store set is one size because the gallery shows pictures one after another
in the same box, and five sizes made it jump as you paged through. 1920x1080 is
the size the most-downloaded Plasma 6 widgets use when they pick a size on
purpose (the rest upload raw screenshots of every shape), and the 16:9 that
Flathub and Steam ask screenshots to be. The frames are rendered at a scale that
already fits, and `pad-frames.py` only adds the stage's own background colour
around them - nothing is resampled. The panel still is README-only.

Each capture opens a window on the current display: the rig renders through
xcb, see below. One scenario at a time, by hand:

```sh
tools/screenshots/build-home.fish            # fabricate the home
tools/screenshots/capture.sh demo 50 2       # <scenario> <frame-ms> <scale>
tools/screenshots/assemble.sh home/frames demo.gif 1 200  # frames, fps, colours
```

Scenarios: `panel`, `demo`, `usage`, `actions` (jump, rename, end) and `copy`.
The scale is the device pixel ratio and it is the whole zoom - see below.

## What each piece does

| file | what it is |
|---|---|
| `build-all.sh` | every image, both sets, in one go |
| `build-home.fish` | fabricates the home: five sessions, their `/proc` entries, transcripts giving each a model and a context fill, git repositories, two accounts, a transcript ending on a failed turn |
| `patch-package.py` | copies `package/` into the home and edits the copy so a script can drive it. `package/` is never touched |
| `harness/Stage.qml` | the stage: a real `CompactView` and `FullView`, a scripted timeline per scenario, and the frame grabber |
| `harness/DemoCursor.qml` | the drawn pointer. `grabToImage` renders the item, not the screen, so the real cursor cannot appear |
| `capture.sh` | runs one scenario under `bwrap` |
| `pad-frames.py` | centres frames on the store's 1920x1080 canvas |
| `assemble.sh` | frames to GIF |

Every replacement in `patch-package.py` is asserted to match exactly once, so a
change to the shipped QML fails loudly here rather than producing a subtly wrong
screenshot.

## Things that were learned the hard way

**The clock is frozen.** `build-home.fish` writes every timestamp as an offset
from a fixed epoch and the stage pins the widget's `now` to the same number. An
age that re-times itself is an image you cannot retake to match the others.

The catch is that the epoch is a literal, and it ages. The committed images say
"34m" because they were taken when it was current; run the rig today and the
same sessions read "13d 20h", because the fabricated records are dated to a
moment now well in the past. Nothing shipped depends on it - but before
regenerating any image, move `NOW` in `build-home.fish` forward to roughly the
current time, or the screenshots will claim every session has been idle for a
fortnight. It is written in one place and carried to the harness through
`Demo.js`, so that is the only line to change.

**Grab a child, never the stage.** `plasmawindowed` hands the applet whatever
its window ended up being - measured at 492x367 for a 492x353 request - and
`grabToImage` maps an item's *real* bounds onto the target size. Grabbing the
stage squeezed every frame by the few per cent the window disagreed by, which
reads as the widget being stretched sideways. Everything lives in a child of
exactly the right size and that is what gets grabbed.

**The device pixel ratio is the zoom.** `grabToImage`'s result comes back
multiplied by the ratio, so the ratio is what decides the resolution a glyph is
*rasterised* at rather than magnified from. Asking for the canvas's own size
makes the output an exact whole multiple of the layout; any other target has to
be rounded to whole logical pixels, and rounding width and height independently
is a fraction of a per cent of aspect error.

**`QT_QPA_PLATFORM=offscreen` draws rounded rectangles square.** No GL context
means the software renderer, and the bars lose their caps. `xcb` is required.

**Three environment variables or the images are wrong.** `QT_STYLE_OVERRIDE`
must be unset (a Kvantum override has no QML style module, and the popup fails
to load); `QT_FONT_DPI=96` (XWayland reports 144 on a scaled display, making
every label 1.5x too large relative to the layout); and `XftSubPixel=none` in
the fabricated `kdeglobals`, because subpixel antialiasing paints coloured
fringes down every glyph edge - invisible on a screen, very visible at nine
times the size.

**Nothing is rescaled on the way to the GIF.** The frames are already the output
size. A 780-to-700 lanczos pass is indistinguishable from the content having
been upscaled, which is what made the first batch look soft.

**Hover follows the pointer, not the script.** The stage hit-tests the drawn
pointer against named items every frame. Setting the hover by hand a step early
or late was visible.

## The social card

`preview.png` is a layout rather than a scenario, so it has its own script,
which `build-all.sh` runs; `--store` builds the gallery's copy, the same card at
1.5x centred on 1920x1080:

```sh
tools/screenshots/build-preview.py [--store]
```

It captures the widget fresh at 61% and takes the popup from the first frame of
`demo.gif` (the store's own, for `--store`). Both of those matter: the committed
`panel.png` is deliberately at 93% so the README can show the bar red, and a red
bar beside a popup reading 61% reads as a mistake rather than as a different
moment.

## Not covered here

`logo.png` is a render of `package/contents/icons/…svg` and the chips in
`docs/screenshots/chips/` are solid swatches of the six status colours. Both are
one-offs; rebuild them by hand if they ever need to change.
