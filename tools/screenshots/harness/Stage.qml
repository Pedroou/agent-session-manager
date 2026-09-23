import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg

import "../code/sessions.js" as Sessions
import "Demo.js" as Demo

// The recording stage.
//
// Stands in for the plasmoid's full representation while the images are made: it
// holds a real CompactView and a real FullView, drives them through a scripted
// timeline, and writes frames out with grabToImage. Nothing here ships - it is
// copied into the demo package by patch-package.py and never into `package/`.
Item {
    id: stage

    property var widget

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    readonly property string scenario: Demo.SCENARIO
    readonly property bool wantsPanel: scenario === "panel" || scenario === "demo"
    readonly property bool wantsPopup: scenario !== "panel"
    readonly property bool wantsCursor: scenario === "usage" || scenario === "actions"
                                        || scenario === "copy"

    // The clock every age and uptime is measured against. Comes from
    // build-home.fish, which dates the fabricated records to the same moment -
    // two literals that had to agree by hand was a trap.
    readonly property double frozenNow: Demo.NOW

    // The panel behind the widget and the desktop behind the popup are one
    // colour, so the widget's own box has no edge to give away that it resized
    // when a session started.
    readonly property color surround: "#1b1e20"
    readonly property color popupColour: "#363636"
    readonly property bool onSurround: scenario !== "panel"

    // How far PlasmoidHeading's frame reaches outside its own bounds. It is
    // drawn to bleed across a Plasma dialog's padding so it meets the window
    // edge while its text stays inside - which means the popup box has to have
    // that padding for it to bleed across, or the title ends up against the edge
    // and the frame's rounded corners fall outside the box.
    KSvg.FrameSvgItem {
        id: headingFrame
        visible: false
        imagePath: "widgets/plasmoidheading"
        prefix: "header"
    }
    readonly property int popupPad: Math.max(1, Math.round(headingFrame.fixedMargins.left))

    // Optical, not geometric. The count sits to the right of the bars and its
    // glyph is lighter than the block they make, so an even split leaves the
    // cluster looking left-heavy.
    readonly property int panelNudge: 5
    // The demo's widget runs a little taller than the panel still's, because it
    // has to hold its own next to a full popup rather than stand alone.
    readonly property real panelViewH: scenario === "panel" ? 36 : 39
    // The panel still keeps the framing that was signed off: 44 units tall, a
    // whole-number box so the 9x render lands on exact pixels.
    readonly property real panelHostH: scenario === "panel" ? 44 : panelViewH + 8
    readonly property real panelHostW: scenario === "panel"
        ? 66
        : Kirigami.Units.gridUnit * 2 + panelView.Layout.maximumWidth

    readonly property real popupW: fullView.Layout.preferredWidth
    readonly property real popupBoxW: popupW + popupPad * 2
    readonly property real popupBoxH: popupH + popupPad * 2
    // Opening the usage selector makes the popup taller, and a canvas that
    // changes size halfway through a recording is not a recording. So that one
    // scenario measures the open height up front and sizes the canvas to it,
    // while the box itself still grows the way it really does.
    readonly property bool lockOpenHeight: scenario === "usage"
    property real lockedPopupH: 0
    readonly property real popupH: fullView.Layout.preferredHeight
    readonly property real canvasPopupH: lockedPopupH > 0 ? lockedPopupH : popupBoxH

    // The same air on every side. The demo is the one exception: it needs room
    // above the popup for the panel widget, and only above. Measured to the
    // widget's *ink*, not to its box - the box carries padding of its own, and
    // measuring to that left the gaps above and below differing by that padding.
    readonly property int margin: Kirigami.Units.gridUnit + 3
    readonly property int panelAir: 12
    readonly property real panelInk: (panelHostH - panelViewH) / 2 + 2
    readonly property real panelHostY: panelAir - panelInk
    readonly property real popupY: panelHostY + panelHostH + panelAir - panelInk

    readonly property int canvasW: Math.round(wantsPopup ? popupBoxW + margin * 2 : panelHostW)
    readonly property int canvasH: Math.round(rawCanvasH)
    readonly property real rawCanvasH: {
        if (!wantsPopup) {
            return panelHostH
        }
        if (wantsPanel) {
            return popupY + canvasPopupH + margin
        }
        return canvasPopupH + margin * 2
    }

    // grabToImage's target is in logical pixels and the result comes back
    // multiplied by the device pixel ratio - so the ratio, not the target, is
    // what decides the size a glyph is rasterised at. Asking for the canvas's
    // own size makes the ratio the whole zoom, which means the output is an
    // exact whole multiple of the layout: any other target has to be rounded to
    // whole logical pixels, and rounding width and height independently is a
    // fraction of a per cent of aspect error - small, but exactly the kind of
    // small that reads as "slightly stretched".
    readonly property real dpr: Screen.devicePixelRatio
    readonly property size grabSize: Qt.size(canvasW, canvasH)

    // Asked for, not relied on. plasmawindowed hands the applet whatever its
    // window ended up being - measured at 492x367 for a 492x353 request - and
    // grabToImage maps an item's *real* bounds onto the target size. Grabbing
    // the stage itself therefore squeezed every frame by the few per cent the
    // window disagreed by. So everything lives in a child of exactly the right
    // size, and that is what gets grabbed.
    implicitWidth: canvasW
    implicitHeight: canvasH
    Layout.minimumWidth: canvasW
    Layout.preferredWidth: canvasW
    Layout.minimumHeight: canvasH
    Layout.preferredHeight: canvasH

    Item {
        id: canvas
        width: stage.canvasW
        height: stage.canvasH
        x: Math.round((stage.width - width) / 2)
        y: Math.round((stage.height - height) / 2)

        Rectangle {
            anchors.fill: parent
            color: stage.surround
        }

        Item {
            id: panelHost
            visible: stage.wantsPanel
            width: stage.panelHostW
            height: stage.panelHostH
            x: Math.round((canvas.width - width) / 2)
            y: stage.wantsPopup ? Math.round(stage.panelHostY) : 0

            // Its own background, because the panel still is grabbed from this
            // item alone and an item without one grabs transparent. Same colour
            // either way, which is the point: the widget's box has no edge, so
            // nobody sees it resize when a session starts.
            Rectangle {
                anchors.fill: parent
                color: stage.surround
            }

            CompactView {
                id: panelView
                widget: stage.widget
                width: Layout.maximumWidth
                height: stage.panelViewH
                x: Math.round((parent.width - width) / 2) + stage.panelNudge
                y: Math.round((parent.height - height) / 2)
            }
        }

        Item {
            id: popupHost
            visible: stage.wantsPopup
            width: stage.popupBoxW
            height: stage.popupBoxH
            x: Math.round((canvas.width - width) / 2)
            y: stage.wantsPanel ? Math.round(stage.popupY) : stage.margin

            readonly property int corner: 4

            Rectangle {
                anchors.fill: parent
                radius: popupHost.corner
                color: stage.popupColour
            }

            // Clipped, because PlasmoidHeading's frame deliberately overhangs
            // its own bounds. Off a real dialog that overhang just sticks out,
            // which made the header look wider than the popup under it.
            Item {
                anchors.fill: parent
                clip: true

                FullView {
                    id: fullView
                    widget: stage.widget
                    x: stage.popupPad
                    y: stage.popupPad
                    width: parent.width - stage.popupPad * 2
                    height: parent.height - stage.popupPad * 2
                }
            }

            // The header and the footer run to the edge, so the box's rounded
            // corners have to be cut back out of them afterwards.
            Repeater {
                model: [[0, 0], [1, 0], [0, 1], [1, 1]]
                delegate: Canvas {
                    required property var modelData
                    width: popupHost.corner
                    height: popupHost.corner
                    x: modelData[0] ? popupHost.width - width : 0
                    y: modelData[1] ? popupHost.height - height : 0
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.fillStyle = stage.onSurround ? stage.surround : "transparent"
                        ctx.globalCompositeOperation = stage.onSurround ? "source-over"
                                                                        : "destination-out"
                        ctx.beginPath()
                        ctx.moveTo(modelData[0] ? width : 0, modelData[1] ? height : 0)
                        ctx.lineTo(modelData[0] ? 0 : width, modelData[1] ? height : 0)
                        ctx.arcTo(modelData[0] ? width : 0, modelData[1] ? height : 0,
                                  modelData[0] ? width : 0, modelData[1] ? 0 : height, width)
                        ctx.closePath()
                        ctx.fill()
                    }
                }
            }
        }

        DemoCursor {
            id: pointer
            visible: stage.wantsCursor && stage.pointerShown
            x: stage.pointerX
            y: stage.pointerY
        }
    }

    // ---------------------------------------------------------------- pointer

    property bool pointerShown: false
    property real pointerX: 0
    property real pointerY: 0
    property int pointerMs: 520

    Behavior on pointerX {
        NumberAnimation { duration: stage.pointerMs; easing.type: Easing.InOutQuad }
    }
    Behavior on pointerY {
        NumberAnimation { duration: stage.pointerMs; easing.type: Easing.InOutQuad }
    }

    onPointerXChanged: updateHover()
    onPointerYChanged: updateHover()
    onPointerShownChanged: updateHover()

    function findItem(node, name) {
        if (!node) {
            return null
        }
        if (node.objectName === name) {
            return node
        }
        var kids = node.children
        if (kids === undefined) {
            return null
        }
        for (var i = 0; i < kids.length; i++) {
            var hit = findItem(kids[i], name)
            if (hit) {
                return hit
            }
        }
        return null
    }

    // Every named item the pointer is inside. Nesting is kept rather than
    // resolved: a detail line sits inside a session row, and both really are
    // under the pointer.
    function collectHits(node, out) {
        if (!node || node.visible === false) {
            return
        }
        if (node.objectName && node.width > 0 && node.height > 0) {
            var p = node.mapFromItem(canvas, stage.pointerX, stage.pointerY)
            if (p.x >= 0 && p.y >= 0 && p.x < node.width && p.y < node.height) {
                out.push(node.objectName)
            }
        }
        var kids = node.children
        if (kids === undefined) {
            return
        }
        for (var i = 0; i < kids.length; i++) {
            collectHits(kids[i], out)
        }
    }

    // Hover follows the drawn pointer rather than the script, so the wash under
    // a row appears exactly when the arrow arrives on it. Setting it by hand a
    // step early or late was visible.
    function updateHover() {
        if (!widget || !wantsCursor) {
            return
        }
        var row = ""
        var detail = ""
        var profile = ""
        if (pointerShown) {
            var hits = []
            collectHits(canvas, hits)
            for (var i = 0; i < hits.length; i++) {
                var name = hits[i]
                if (name.indexOf("row:") === 0) {
                    row = name.substring(4)
                } else if (name.indexOf("detail:") === 0) {
                    detail = name.substring(7)
                } else if (name.indexOf("profile:") === 0) {
                    profile = name.substring(8)
                }
            }
        }
        widget.demoHoverSession = row
        widget.demoHoverDetail = detail
        widget.demoHoverProfile = profile
    }

    function moveTo(name, fx, fy, ms) {
        var it = findItem(canvas, name)
        if (!it) {
            console.log("HARNESS missing item " + name)
            return
        }
        var p = it.mapToItem(canvas, it.width * (fx === undefined ? 0.5 : fx),
                                     it.height * (fy === undefined ? 0.5 : fy))
        pointerMs = ms === undefined ? 520 : ms
        pointerShown = true
        pointerX = p.x
        pointerY = p.y
    }

    // Off the widget, and placed rather than animated: a Behavior would spend
    // the first frames sliding the pointer in from the top-left corner.
    function park() {
        pointerMs = 0
        pointerShown = true
        pointerX = Math.round(stage.canvasW * 0.80)
        pointerY = Math.round(stage.canvasH) - 6
    }

    function clickHere(rightButton) {
        pointer.click(rightButton === true)
    }

    // ------------------------------------------------------------------- data

    property var live: []

    function snapshot() {
        var out = []
        var src = stage.widget.sessions
        for (var i = 0; i < src.length; i++) {
            var copy = {}
            for (var key in src[i]) {
                copy[key] = src[i][key]
            }
            out.push(copy)
        }
        return out
    }

    readonly property var labels: ({
        waiting: "Waiting", error: "Error", running: "Running",
        working: "Working", shell: "Shell", done: "Done"
    })
    readonly property var ranks: ({
        waiting: 0, error: 1, running: 2, working: 3, shell: 4, done: 5
    })

    function setState(name, state, detail) {
        for (var i = 0; i < live.length; i++) {
            if (live[i].name === name) {
                live[i].state = state
                live[i].label = labels[state]
                live[i].detail = detail === undefined ? "" : detail
                live[i].rank = ranks[state]
            }
        }
        commit()
    }

    function drop(name) {
        var out = []
        for (var i = 0; i < live.length; i++) {
            if (live[i].name !== name) {
                out.push(live[i])
            }
        }
        live = out
        commit()
    }

    function add(session) {
        live = live.concat([session])
        commit()
    }

    // The collector sorts by state before the widget ever sees the list, so the
    // scripted timeline has to sort too or a state change would leave a row
    // sitting where a real one never would.
    function commit() {
        var sorted = live.slice().sort(function (a, b) {
            return a.rank !== b.rank ? a.rank - b.rank : a.pid - b.pid
        })
        live = sorted
        stage.widget.sessions = sorted
    }

    // Percentages come from demoWorkPercent / demoPersonalPercent rather than
    // from here, so that moving one animates the bar instead of rebuilding the
    // footer's delegates at zero.
    function usageDoc() {
        function bars() {
            return [
                {id: "session", label: "Session", percent: 0, severity: "",
                 resetsAt: "2030-01-01T00:00:00Z", active: true},
                {id: "weekly", label: "Weekly", percent: 0, severity: "",
                 resetsAt: "2030-01-05T00:00:00Z", active: false}
            ]
        }
        return {
            fetchedAt: stage.frozenNow,
            profiles: [
                {id: "/home/dev/.claude", name: "work", state: "ok", bars: bars()},
                {id: "/home/dev/.claude-personal", name: "personal", state: "ok", bars: bars()}
            ]
        }
    }

    // ------------------------------------------------------------- the timeline

    property var script: []
    property int scriptAt: 0
    property int frameNo: 0

    Timer {
        id: stepper
        onTriggered: stage.runStep()
    }

    Timer {
        id: grabber
        interval: Demo.FRAME_MS
        repeat: true
        running: false
        onTriggered: stage.grabFrame()
    }

    function pad4(n) {
        var s = "" + n
        while (s.length < 4) {
            s = "0" + s
        }
        return s
    }

    function grabFrame() {
        var name = Demo.OUT + "/f" + pad4(frameNo++) + ".png"
        canvas.grabToImage(function (result) {
            result.saveToFile(name)
        }, stage.grabSize)
    }

    function shot(item, name) {
        item.grabToImage(function (result) {
            result.saveToFile(Demo.OUT + "/" + name + ".png")
        }, Qt.size(Math.round(item.width), Math.round(item.height)))
    }

    function runStep() {
        if (scriptAt >= script.length) {
            grabber.stop()
            done.start()
            return
        }
        var entry = script[scriptAt++]
        if (entry[0]) {
            entry[0]()
        }
        stepper.interval = Math.max(1, entry[1])
        stepper.restart()
    }

    // The runner watches for this file rather than for the process exiting:
    // plasmawindowed does not connect QQmlEngine::quit(), so the harness cannot
    // close itself.
    Timer {
        id: done
        interval: 900
        onTriggered: {
            console.log("HARNESS done canvas " + canvas.width + "x" + canvas.height
                        + " dpr " + stage.dpr)
            canvas.grabToImage(function (result) {
                result.saveToFile(Demo.OUT + "/DONE.png")
            }, Qt.size(2, 2))
        }
    }

    // ------------------------------------------------------------------ scripts

    function resetConfig() {
        plasmoid.configuration.censorNames = false
        plasmoid.configuration.nicknames = "{}"
        plasmoid.configuration.usageExpanded = lockOpenHeight
        plasmoid.configuration.usageProfile = "/home/dev/.claude"
        plasmoid.configuration.usageBars = "{}"
        plasmoid.configuration.showUsage = true
        plasmoid.configuration.panelUsage = true
        plasmoid.configuration.panelUsageColour = true
        plasmoid.configuration.panelUsageThreshold = 0
        plasmoid.configuration.maxSessions = 5
        plasmoid.configuration.showDone = true
        plasmoid.configuration.countScale = 100
        stage.widget.expandedSessions = ({})
        stage.widget.renamingSession = ""
        stage.widget.demoHoverSession = ""
        stage.widget.demoHoverDetail = ""
        stage.widget.demoHoverProfile = ""
        stage.widget.demoRenameText = ""
    }

    function sid(name) {
        for (var i = 0; i < live.length; i++) {
            if (live[i].name === name) {
                return live[i].sessionId
            }
        }
        return ""
    }

    function buildScript() {
        var s = []
        if (scenario === "panel") {
            // The panel bar in a state the popup shots never show, so the
            // "colours by how much is gone" setting is visible in the README.
            s.push([function () { stage.widget.demoWorkPercent = Demo.PANEL_PERCENT }, 800])
            s.push([function () { shot(panelHost, "panel") }, 700])
        } else if (scenario === "demo") {
            buildDemoScript(s)
        } else if (scenario === "usage") {
            buildUsageScript(s)
        } else if (scenario === "actions") {
            buildActionsScript(s)
        } else if (scenario === "copy") {
            buildCopyScript(s)
        }
        script = s
    }

    // The headline recording: the panel and the popup, side by side, while
    // sessions change state, come and go, and the plan fills up.
    function buildDemoScript(s) {
        function beat(fn) {
            s.push([fn, 260])
            s.push([function () { grabFrame() }, 40])
        }
        s.push([function () { stage.widget.demoWorkPercent = 61 }, 700])
        beat(function () {})
        beat(function () {
            setState("checkout-flow-7", "working")
            stage.widget.demoWorkPercent = 68
        })
        beat(function () {
            setState("billing-api-3", "running", "pytest -q tests/billing")
            stage.widget.demoWorkPercent = 74
        })
        beat(function () {
            drop("infra-scripts-a9")
            stage.widget.demoWorkPercent = 81
        })
        beat(function () {
            setState("docs-site-b2", "done")
            stage.widget.demoWorkPercent = 88
        })
        beat(function () {
            add({pid: 7006, profile: "work", profileDir: "/home/dev/.claude",
                 profileDefault: true, name: "checkout-flow-8",
                 cwd: "/home/dev/code/checkout-flow", dir: "checkout-flow",
                 repository: "checkout-flow", branch: "main",
                 sessionId: "11111111-2222-3333-4444-700600000000",
                 kind: "interactive", status: "busy", state: "working",
                 label: "Working", detail: "", startedAt: frozenNow - 40000,
                 statusUpdatedAt: frozenNow - 6000, version: "2.1.263", rank: 3})
            stage.widget.demoWorkPercent = 92
        })
        beat(function () {
            setState("api-gateway-c1", "waiting", "choose: edit or reject the change")
            stage.widget.demoWorkPercent = 95
        })
        // The closing state is held twice as long, so the loop reads as an
        // ending rather than a stutter. Done by repeating the last frame at
        // assembly time, since every frame in a GIF shares one delay.
        s.push([null, 300])
    }

    // The plan-usage footer: opened, both accounts on screen, and the bars
    // sliding between readings so the colour thresholds are visible.
    function buildUsageScript(s) {
        s.push([function () {
            stage.widget.demoWorkPercent = 61
            stage.widget.demoPersonalPercent = 18
            park()
            grabber.start()
        }, 900])
        s.push([function () { moveTo("profile:/home/dev/.claude", 0.16, 0.5, 620) }, 800])
        s.push([function () {
            clickHere(false)
            plasmoid.configuration.usageExpanded = true
        }, 260])
        // The row it just clicked slid up to make room, so the pointer follows
        // it rather than sitting on top of the account that appeared.
        s.push([function () { moveTo("profile:/home/dev/.claude", 0.16, 0.5, 340) }, 1200])
        s.push([function () { stage.widget.demoWorkPercent = 78 }, 1600])
        s.push([function () { stage.widget.demoWorkPercent = 94 }, 1600])
        s.push([function () { stage.widget.demoPersonalPercent = 72 }, 1900])
        s.push([null, 600])
    }

    // Renaming a session, then ending one.
    function buildActionsScript(s) {
        var docs = sid("docs-site-b2")
        var api = sid("api-gateway-c1")
        s.push([function () {
            stage.widget.demoWorkPercent = 61
            stage.widget.demoPersonalPercent = 18
            park()
            grabber.start()
        }, 700])
        s.push([function () { moveTo("row:" + docs, 0.45, 0.5, 700) }, 1000])
        s.push([function () { moveTo("rename:" + docs, 0.5, 0.5, 520) }, 620])
        s.push([function () {
            clickHere(false)
            stage.widget.renamingSession = docs
        }, 700])
        var typed = "docs site rebuild"
        for (var i = 1; i <= typed.length; i++) {
            (function (n) {
                s.push([function () { stage.widget.demoRenameText = typed.substring(0, n) }, 85])
            })(i)
        }
        s.push([null, 700])
        s.push([function () {
            stage.widget.setNickname(docs, stage.widget.demoRenameText)
            stage.widget.renamingSession = ""
        }, 1100])
        s.push([function () { moveTo("row:" + api, 0.45, 0.5, 700) }, 900])
        s.push([function () { moveTo("end:" + api, 0.5, 0.5, 480) }, 600])
        s.push([function () {
            clickHere(false)
            var it = findItem(canvas, "row:" + api)
            if (it) {
                it.confirmingEnd = true
            }
        }, 1100])
        s.push([function () {
            clickHere(false)
            drop("api-gateway-c1")
        }, 1400])
        s.push([null, 500])
    }

    // Opening a session and copying out of it, by click and by right-click.
    function buildCopyScript(s) {
        var bill = sid("billing-api-3")
        s.push([function () {
            stage.widget.demoWorkPercent = 61
            stage.widget.demoPersonalPercent = 18
            park()
            grabber.start()
        }, 700])
        s.push([function () { moveTo("row:" + bill, 0.42, 0.5, 700) }, 800])
        s.push([function () {
            clickHere(false)
            stage.widget.toggleExpanded(bill)
        }, 1100])
        s.push([function () { moveTo("detail:" + bill + ":session", 0.42, 0.5, 620) }, 700])
        s.push([function () {
            clickHere(false)
            stage.widget.copyToClipboard("(demo)", "Session")
        }, 2400])
        s.push([function () { moveTo("row:" + bill, 0.42, 0.18, 560) }, 900])
        s.push([function () {
            pointer.caption = "right-click"
            clickHere(true)
            stage.widget.copyToClipboard("(demo)", "Session details")
        }, 2100])
        s.push([function () { pointer.caption = "" }, 900])
    }

    // ------------------------------------------------------------------ start

    // Waits for the collector's first (and only) result, then takes the list
    // over so nothing moves except what the script moves.
    Timer {
        id: boot
        interval: 120
        repeat: true
        running: true
        onTriggered: {
            if (!stage.widget || !stage.widget.everLoaded
                    || stage.widget.sessions.length === 0) {
                return
            }
            stop()
            stage.widget.now = stage.frozenNow
            stage.widget.demoFreezeNow = true
            stage.widget.usage = stage.usageDoc()
            stage.live = stage.snapshot()
            stage.resetConfig()
            settle.start()
        }
    }

    // One idle beat so the first layout pass is over before anything is
    // measured, positioned or grabbed.
    Timer {
        id: settle
        interval: 400
        onTriggered: {
            if (stage.lockOpenHeight) {
                stage.lockedPopupH = stage.popupBoxH
                plasmoid.configuration.usageExpanded = false
            }
            console.log("HARNESS ready canvas " + stage.canvasW + "x" + stage.canvasH
                        + " dpr " + stage.dpr + " pad " + stage.popupPad
                        + " popup " + stage.popupW + "x" + stage.popupH)
            stage.buildScript()
            stage.runStep()
        }
    }
}
