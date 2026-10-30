#!/usr/bin/env bash
# Install (or update) the Claude Sessions panel widget for the current user.
#
# Safe to re-run: it upgrades in place when the widget is already installed, and
# restarts plasmashell only when asked, since that closes any open popups.

here=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
package=$here/package

# timeout bounds every collector run the widget starts (see refresh() in main.qml).
for tool in kpackagetool6 jq bash timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "✗ $tool is required but not on \$PATH."
        exit 1
    fi
done

id=$(jq -r '.KPlugin.Id' "$package/metadata.json")

if [[ ! -x $package/contents/scripts/agent-sessions ]]; then
    echo "✗ $package/contents/scripts/agent-sessions is not executable."
    echo "  Run: chmod +x $package/contents/scripts/agent-sessions"
    exit 1
fi

# The widget shells out to this on every refresh; catching a broken collector
# here beats staring at an empty popup later.
if ! "$package/contents/scripts/agent-sessions" >/dev/null; then
    echo "✗ The collector script failed to run. Fix that before installing."
    exit 1
fi

# kpackagetool6 walks every installed plasmoid and complains about each one that
# isn't an applet - other people's widgets, nothing to do with this package. That
# one line is dropped; every other message still gets through, and the exit
# status is kpackagetool6's own.
__kpt() {
    kpackagetool6 --type Plasma/Applet "$@" 2>&1 |
        grep -v -F -- 'does not match requested format'
    return "${PIPESTATUS[0]}"
}

# The icon has to live in an icon theme, not just in the package. A package's
# own icons/ directory is not on the icon search path, so the name fell through
# KDE's dash-suffix fallback - "io.github.pedroou.agentsessionmanager" has no
# dashes precisely so it cannot degrade into somebody else's "claude" icon.
icon_dir=$HOME/.local/share/icons/hicolor/scalable/apps
mkdir -p "$icon_dir"
cp "$package/contents/icons/io.github.pedroou.agentsessionmanager.svg" "$icon_dir/"
echo "→ Icon installed to $icon_dir"

installed=false
mapfile -t listed < <(__kpt --list)
for entry in "${listed[@]}"; do
    entry=${entry#"${entry%%[![:space:]]*}"}
    entry=${entry%"${entry##*[![:space:]]}"}
    if [[ $entry == "$id" ]]; then
        installed=true
        break
    fi
done

if [[ $installed == true ]]; then
    echo "→ Updating $id"
    __kpt --upgrade "$package"
else
    echo "→ Installing $id"
    __kpt --install "$package"
fi || exit

echo
echo "✓ Installed."
echo
echo "  Add it: right-click the panel → Add or Manage Widgets… → search \"Agent Session Manager\"."
echo
echo "  Already had it on the panel? Plasma caches the old QML, so reload the shell:"
echo "      kquitapp6 plasmashell && kstart plasmashell"
echo "  Then check the pid changed - the restart can fail silently:"
echo "      pgrep -x plasmashell"
