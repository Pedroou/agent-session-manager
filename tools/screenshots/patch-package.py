#!/usr/bin/env python3
"""Turn a copy of the shipped package into a recording rig.

`package/` itself is never touched. This copies it into the fabricated home and
applies the smallest set of edits that let a script drive it: a frozen clock, a
hover that can be forced, names for the items the pointer aims at, and a usage
percentage that can be moved without rebuilding the footer's delegates - which
would restart the bar animation from zero instead of continuing it.

Every replacement is asserted to match exactly once, so a change to the shipped
QML fails here loudly rather than producing a subtly wrong screenshot.

Usage: patch-package.py <home-dir> <scenario> <frame-ms>
"""
import json
import pathlib
import shutil
import sys

HERE = pathlib.Path(__file__).resolve().parent
SRC = HERE.parent.parent / "package"
PLUGIN_ID = "io.github.pedroou.agentsessionmanager"

# The accounts the screenshots are taken against, named the way the footer
# shows them.
PROFILES = [
    {"dir": "/home/dev/.claude", "name": "work", "enabled": True},
    {"dir": "/home/dev/.claude-personal", "name": "personal", "enabled": True},
]


def patch(path, *pairs):
    text = path.read_text()
    for old, new in pairs:
        found = text.count(old)
        if found != 1:
            sys.exit(f"{path.name}: expected exactly one match, found {found}, for:\n{old}")
        text = text.replace(old, new)
    path.write_text(text)


def main(home, scenario, frame_ms):
    pkg = pathlib.Path(home) / ".local/share/plasma/plasmoids" / PLUGIN_ID
    if pkg.exists():
        shutil.rmtree(pkg)
    shutil.copytree(SRC, pkg)
    ui = pkg / "contents/ui"

    patch(ui / "main.qml",
        ("fullRepresentation: FullView { widget: root }",
         "fullRepresentation: Stage { widget: root }"),
        ("    property bool everLoaded: false\n",
         "    property bool everLoaded: false\n"
         "\n"
         "    // ---- recording rig only; not in the shipped package ----\n"
         "    property bool demoFreezeNow: false\n"
         "    property string demoHoverSession: \"\"\n"
         "    property string demoHoverDetail: \"\"\n"
         "    property string demoHoverProfile: \"\"\n"
         "    property string demoRenameText: \"\"\n"
         "    property int demoWorkPercent: -1\n"
         "    property int demoPersonalPercent: -1\n"
         "    function demoPercent(id) {\n"
         "        return id === \"/home/dev/.claude-personal\"\n"
         "            ? demoPersonalPercent : demoWorkPercent\n"
         "    }\n"),
        # A clock that keeps running would re-time every age between scenarios.
        ("            root.now = Date.now()\n",
         "            if (!root.demoFreezeNow) { root.now = Date.now() }\n"),
        ("        onTriggered: root.now = Date.now()",
         "        onTriggered: if (!root.demoFreezeNow) { root.now = Date.now() }"),
        ("            now = Date.now()\n",
         "            if (!root.demoFreezeNow) { now = Date.now() }\n"),
        # The rig sets root.usage itself; no network call is ever made.
        ("    function refreshUsage(force) {\n",
         "    function refreshUsage(force) {\n"
         "        return // rig: the stage supplies usage directly\n"),
        # The fabricated pids are real pids on this machine. Never signal them.
        ("        actions.connectSource(\"kill -TERM \" + parseInt(pid, 10))",
         "        console.log(\"RIG endSession \" + pid) // rig: signals nothing"),
        ("        running: plasmoid.configuration.showUsage || plasmoid.configuration.panelUsage\n"
         "        repeat: true",
         "        running: false\n"
         "        repeat: true"),
        # One poll, then the script owns the list.
        ("        interval: root.expanded ? 1000 : Math.max(1, plasmoid.configuration.refreshInterval) * 1000\n"
         "        running: true\n"
         "        repeat: true",
         "        interval: 200\n"
         "        running: true\n"
         "        repeat: false"),
    )

    patch(ui / "SessionRow.qml",
        ("    property bool confirmingEnd: false\n",
         "    property bool confirmingEnd: false\n"
         "    // Recording rig: a hover the script can hold open, and a name the\n"
         "    // pointer can aim at.\n"
         "    readonly property bool demoHover: widget\n"
         "        ? widget.demoHoverSession === session.sessionId : false\n"
         "    objectName: \"row:\" + session.sessionId\n"),
        ("        opacity: rowHover.hovered ? 0.09 : 0",
         "        opacity: (rowHover.hovered || row.demoHover) ? 0.09 : 0"),
        ("            visible: rowHover.hovered && !row.renaming",
         "            visible: (rowHover.hovered || row.demoHover) && !row.renaming"),
        ("                icon.name: \"edit-rename\"",
         "                objectName: \"rename:\" + row.session.sessionId\n"
         "                icon.name: \"edit-rename\""),
        ("                icon.name: row.confirmingEnd ? \"dialog-warning\" : \"window-close\"",
         "                objectName: \"end:\" + row.session.sessionId\n"
         "                icon.name: row.confirmingEnd ? \"dialog-warning\" : \"window-close\""),
        ("                    delegate: Item {\n"
         "                        required property var modelData\n",
         "                    delegate: Item {\n"
         "                        required property var modelData\n"
         "                        objectName: \"detail:\" + row.session.sessionId\n"
         "                                    + \":\" + modelData.id\n"),
        ("                            opacity: detailHover.hovered && modelData.copyable ? 0.09 : 0",
         "                            opacity: ((detailHover.hovered\n"
         "                                       || (row.widget && row.widget.demoHoverDetail\n"
         "                                           === row.session.sessionId + \":\" + modelData.id))\n"
         "                                      && modelData.copyable) ? 0.09 : 0"),
        ("                onVisibleChanged: if (visible) {\n"
         "                    text = row.widget.nicknames[row.session.sessionId] || \"\"\n",
         "                Connections {\n"
         "                    target: row.widget\n"
         "                    function onDemoRenameTextChanged() {\n"
         "                        if (row.renaming) { renameField.text = row.widget.demoRenameText }\n"
         "                    }\n"
         "                }\n"
         "                onVisibleChanged: if (visible) {\n"
         "                    text = row.widget.demoRenameText\n"),
    )

    patch(ui / "ProfileFooter.qml",
        ("                id: profileRow\n                required property var modelData\n",
         "                id: profileRow\n                required property var modelData\n"
         "                objectName: \"profile:\" + modelData.id\n"),
        ("                    opacity: rowHover.hovered ? 0.09 : 0",
         "                    opacity: (rowHover.hovered\n"
         "                              || (footer.widget\n"
         "                                  && footer.widget.demoHoverProfile === modelData.id))\n"
         "                             ? 0.09 : 0"),
        # Swapped in here rather than in the usage document, so the model array
        # keeps its identity and the bar slides instead of rebuilding at zero.
        ("                readonly property var bar: Usage.barFor(modelData, footer.barIdFor(modelData.id))",
         "                readonly property var bar: {\n"
         "                    var b = Usage.barFor(modelData, footer.barIdFor(modelData.id))\n"
         "                    var o = footer.widget ? footer.widget.demoPercent(modelData.id) : -1\n"
         "                    if (b && o >= 0) {\n"
         "                        return {id: b.id, label: b.label, percent: o, severity: \"\",\n"
         "                                resetsAt: b.resetsAt, active: b.active}\n"
         "                    }\n"
         "                    return b\n"
         "                }"),
    )

    patch(ui / "CompactView.qml",
        ("        var id = Usage.selectedId(widget.usage, plasmoid.configuration.usageProfile)\n"
         "        return Usage.panelBar(widget.usage, id, widget.barIdFor(id))",
         "        var id = Usage.selectedId(widget.usage, plasmoid.configuration.usageProfile)\n"
         "        var b = Usage.panelBar(widget.usage, id, widget.barIdFor(id))\n"
         "        var o = widget.demoPercent(id)\n"
         "        if (b && o >= 0) {\n"
         "            return {id: b.id, label: b.label, percent: o, severity: \"\",\n"
         "                    resetsAt: b.resetsAt, active: b.active}\n"
         "        }\n"
         "        return b"),
    )

    # The accounts, baked in as the default so no config file is needed.
    patch(pkg / "contents/config/main.xml",
        ("<entry name=\"profiles\" type=\"String\">\n      <default>[]</default>",
         "<entry name=\"profiles\" type=\"String\">\n      <default>%s</default>"
         % json.dumps(PROFILES)),
    )

    shutil.copy(HERE / "harness/Stage.qml", ui / "Stage.qml")
    shutil.copy(HERE / "harness/DemoCursor.qml", ui / "DemoCursor.qml")
    epoch = (pathlib.Path(home) / "epoch").read_text().strip()
    (ui / "Demo.js").write_text(
        f'var SCENARIO = "{scenario}"\n'
        f'var OUT = "/home/dev/frames"\n'
        f'var FRAME_MS = {frame_ms}\n'
        f'var NOW = {epoch}\n')
    print(f"patched for scenario={scenario} frame_ms={frame_ms}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]))
