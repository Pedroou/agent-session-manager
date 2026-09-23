#!/usr/bin/env fish
# Install (or update) the Claude Sessions panel widget for the current user.
#
# Safe to re-run: it upgrades in place when the widget is already installed, and
# restarts plasmashell only when asked, since that closes any open popups.

set -l here (dirname (realpath (status filename)))
set -l package $here/package
set -l id (jq -r '.KPlugin.Id' $package/metadata.json)

for tool in kpackagetool6 jq fish
    if not command -q $tool
        echo "✗ $tool is required but not on \$PATH."
        exit 1
    end
end

# The collectors use fish's `path` builtin, which arrived in 3.5. Tested for
# directly rather than by parsing a version string: the builtin is the thing
# that breaks, and an old fish would otherwise fail later with a bare
# "path: command not found" from a script nobody was looking at.
if not builtin --names | string match -q path
    echo "✗ This fish is too old: the collectors need the `path` builtin (fish 3.5+)."
    echo "  Yours is $version."
    exit 1
end

if not test -x $package/contents/scripts/claude-sessions
    echo "✗ $package/contents/scripts/claude-sessions is not executable."
    echo "  Run: chmod +x $package/contents/scripts/claude-sessions"
    exit 1
end

# The widget shells out to this on every refresh; catching a broken collector
# here beats staring at an empty popup later.
if not $package/contents/scripts/claude-sessions >/dev/null
    echo "✗ The collector script failed to run. Fix that before installing."
    exit 1
end

# kpackagetool6 walks every installed plasmoid and complains about each one that
# isn't an applet - other people's widgets, nothing to do with this package. That
# one line is dropped; every other message still gets through.
function __kpt
    kpackagetool6 --type Plasma/Applet $argv 2>&1 \
        | string match -v -- '*does not match requested format*'
    return $pipestatus[1]
end

# The icon has to live in an icon theme, not just in the package. A package's
# own icons/ directory is not on the icon search path, so the name fell through
# KDE's dash-suffix fallback - "io.github.pedroou.agentsessionmanager" has no
# dashes precisely so it cannot degrade into somebody else's "claude" icon.
set -l icon_dir $HOME/.local/share/icons/hicolor/scalable/apps
mkdir -p $icon_dir
cp $package/contents/icons/io.github.pedroou.agentsessionmanager.svg $icon_dir/
echo "→ Icon installed to $icon_dir"

if contains -- $id (__kpt --list | string trim)
    echo "→ Updating $id"
    __kpt --upgrade $package
else
    echo "→ Installing $id"
    __kpt --install $package
end
or exit $status

echo
echo "✓ Installed."
echo
echo "  Add it: right-click the panel → Add or Manage Widgets… → search \"Agent Session Manager\"."
echo
echo "  Already had it on the panel? Plasma caches the old QML, so reload the shell:"
echo "      kquitapp6 plasmashell; and kstart plasmashell"
echo "  Then check the pid changed - the restart can fail silently:"
echo "      pgrep -x plasmashell"
