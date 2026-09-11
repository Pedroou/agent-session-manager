import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

import "../code/sessions.js" as Sessions
import "../code/usage.js" as Usage

PlasmoidItem {
    id: root

    // Everything the collector last told us, plus a clock the views bind to so
    // "4m ago" keeps counting without each row owning a timer.
    property var sessions: []
    property var profiles: []
    property var usage: null
    property string failure: ""
    property double now: Date.now()
    // Until the first result lands there is nothing to say, and "No sessions
    // running" would be a guess rather than an answer.
    property bool everLoaded: false

    readonly property var shown: Sessions.visible(sessions, plasmoid.configuration)
    readonly property var shownCounts: Sessions.countsFor(shown)
    readonly property bool censored: plasmoid.configuration.censorNames
    // The account only earns space on a row when the list on screen actually
    // spans more than one of them.
    readonly property bool showProfiles: {
        var seen = ({})
        var distinct = 0
        for (var i = 0; i < sessions.length; i++) {
            var key = sessions[i].profileDir || sessions[i].profile || ""
            if (!seen[key]) {
                seen[key] = true
                distinct += 1
            }
        }
        return distinct > 1
    }

    // The accounts to read, as configured. An empty list is not a broken state:
    // the collectors fall back to the stock directory on their own, so the
    // widget works before anyone has opened the settings.
    readonly property var profileList: {
        try {
            var list = JSON.parse(plasmoid.configuration.profiles || "[]")
            return Array.isArray(list) ? list : []
        } catch (e) {
            return []
        }
    }
    readonly property var activeProfiles: profileList.filter(function (p) {
        return p && p.dir && p.enabled !== false
    })

    // Which limit each account tracks, keyed by its config directory. A map
    // rather than a setting per account, because there is no fixed number of
    // them any more.
    readonly property var usageBars: {
        try {
            var map = JSON.parse(plasmoid.configuration.usageBars || "{}")
            return (map && typeof map === "object") ? map : ({})
        } catch (e) {
            return ({})
        }
    }

    function barIdFor(profileId) {
        return usageBars[profileId] || ""
    }

    function setBarFor(profileId, barId) {
        var map = {}
        for (var key in usageBars) {
            map[key] = usageBars[key]
        }
        map[profileId] = barId
        plasmoid.configuration.usageBars = JSON.stringify(map)
    }

    // Told to every open row when the popup closes, so the next opening starts
    // collapsed rather than showing whatever was left expanded.
    signal collapseAll()

    // Which sessions are open, and which one is being renamed - keyed by session
    // id rather than kept inside the row.
    //
    // The collector sorts by state, so a session changing status reorders the
    // list, and a delegate that held its own "expanded" flag would hand it to
    // whichever session slid into that position. That was rows appearing to
    // close, or open, on their own whenever anything changed.
    property var expandedSessions: ({})
    property string renamingSession: ""

    function isExpanded(sessionId) {
        return expandedSessions[sessionId] === true
    }

    function toggleExpanded(sessionId) {
        var next = {}
        for (var key in expandedSessions) {
            next[key] = expandedSessions[key]
        }
        if (next[sessionId]) {
            delete next[sessionId]
        } else {
            next[sessionId] = true
        }
        expandedSessions = next
    }

    // Status colours are the widget's own, not the theme's: the theme accent is
    // usually blue, which is exactly what disappears into a blue panel. The
    // defaults live in code/sessions.js so the node tests can check them.
    function tone(state) {
        if (state === "none" || state === "unknown") {
            return Kirigami.Theme.disabledTextColor
        }
        if (!plasmoid.configuration.customColors) {
            return Sessions.defaultColor(state)
        }
        switch (state) {
        case "waiting": return plasmoid.configuration.colorWaiting
        case "error": return plasmoid.configuration.colorError
        case "running": return plasmoid.configuration.colorRunning
        case "working": return plasmoid.configuration.colorWorking
        case "shell": return plasmoid.configuration.colorShell
        case "done": return plasmoid.configuration.colorDone
        default: return Kirigami.Theme.disabledTextColor
        }
    }

    // Widget-local session names. Claude Code owns the real one and rewrites its
    // record constantly, so a rename here is a nickname the widget keeps.
    readonly property var nicknames: {
        try {
            return JSON.parse(plasmoid.configuration.nicknames || "{}")
        } catch (e) {
            return {}
        }
    }

    function setNickname(sessionId, name) {
        var map = {}
        for (var key in nicknames) {
            map[key] = nicknames[key]
        }
        if (name === "" || name === undefined) {
            delete map[sessionId]
        } else {
            map[sessionId] = name
        }
        plasmoid.configuration.nicknames = JSON.stringify(map)
    }

    compactRepresentation: CompactView { widget: root }
    fullRepresentation: FullView { widget: root }

    Plasmoid.status: {
        if (shownCounts.waiting > 0 && plasmoid.configuration.attentionWhenWaiting) {
            return PlasmaCore.Types.NeedsAttentionStatus
        }
        return shownCounts.total > 0 ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus
    }

    toolTipMainText: i18n("Claude Code Sessions")
    toolTipSubText: failure !== "" ? failure : Sessions.tooltipLines(shownCounts)
    toolTipTextFormat: Text.PlainText

    Plasma5Support.DataSource {
        id: collector
        engine: "executable"
        connectedSources: []

        onNewData: function (source, data) {
            disconnectSource(source)
            root.everLoaded = true

            var stdout = (data["stdout"] || "").trim()
            if (data["exit code"] !== 0 || stdout === "") {
                root.failure = (data["stderr"] || "").trim()
                        || i18n("Couldn't read the session registry.")
                return
            }
            try {
                var payload = JSON.parse(stdout)
            } catch (e) {
                root.failure = i18n("The session registry didn't parse.")
                return
            }
            root.failure = ""
            root.sessions = payload.sessions || []
            root.profiles = payload.profiles || []
            root.now = Date.now()
        }
    }

    // Plan usage is a network call and plan limits move slowly, so it runs on its
    // own much lazier schedule rather than riding the session poll.
    Plasma5Support.DataSource {
        id: usageSource
        engine: "executable"
        connectedSources: []

        onNewData: function (source, data) {
            disconnectSource(source)
            var stdout = (data["stdout"] || "").trim()
            if (data["exit code"] !== 0 || stdout === "") {
                return
            }
            try {
                // Merged rather than replaced: a profile that failed this time
                // keeps the bars it had, so a rate-limited moment does not blank
                // a reading that was right a minute ago.
                root.usage = Usage.merge(root.usage, JSON.parse(stdout))
            } catch (e) {
                // Leave the last good reading on screen rather than blanking it.
            }
        }
    }

    readonly property string usagePath: {
        var url = Qt.resolvedUrl("../scripts/claude-usage").toString()
        return url.replace(/^file:\/\//, "")
    }

    // The endpoint rate-limits, and plan limits move slowly. Opening the popup
    // asks for a reading, but no more often than this - otherwise a habit of
    // opening and closing the widget is enough to get you throttled, and the
    // punishment lands as an empty bar.
    readonly property int usageMinGapMs: 60000
    property double lastUsageFetch: 0

    function refreshUsage(force) {
        if (!plasmoid.configuration.showUsage && !plasmoid.configuration.panelUsage) {
            return
        }
        var now = Date.now()
        if (!force && lastUsageFetch > 0 && (now - lastUsageFetch) < usageMinGapMs) {
            return
        }
        lastUsageFetch = now
        usageSource.connectSource(profilesEnv + shellQuote(usagePath))
    }

    Timer {
        interval: 5 * 60 * 1000
        running: plasmoid.configuration.showUsage || plasmoid.configuration.panelUsage
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshUsage(true)
    }

    // Kept apart from the collector so a signal's empty output is never mistaken
    // for a failed read of the registry.
    Plasma5Support.DataSource {
        id: actions
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            disconnectSource(source)
            root.refresh()
        }
    }

    // SIGTERM is the graceful path: Claude Code registers a handler for it that
    // runs its own shutdown, so the session closes the way it would if you shut
    // the terminal. The transcript is on disk either way, and `claude --resume`
    // picks it back up - which is what right-clicking the row copies.
    function endSession(pid) {
        actions.connectSource("kill -TERM " + parseInt(pid, 10))
    }

    // QML has no clipboard of its own; a TextEdit does, and this is the usual way
    // to borrow it.
    TextEdit {
        id: clipboard
        visible: false
        function put(text) {
            clipboard.text = text
            clipboard.selectAll()
            clipboard.copy()
            clipboard.deselect()
        }
    }

    // What the popup is currently confirming, or "" for nothing. Callers pass the
    // name of the thing rather than a bare "Copied", because a row has several
    // copy targets and knowing which one you hit is the whole value of the
    // confirmation.
    property string copyNotice: ""

    function copyToClipboard(text, what) {
        clipboard.put(text)
        copyNotice = (what && what !== "") ? i18n("%1 copied", what) : i18n("Copied")
        copyNoticeTimer.restart()
    }

    Timer {
        id: copyNoticeTimer
        interval: 1900
        onTriggered: root.copyNotice = ""
    }

    // The collector lives beside this file inside the package, so it is found
    // whether the widget was installed for the user or shipped system-wide.
    readonly property string collectorPath: {
        var url = Qt.resolvedUrl("../scripts/claude-sessions").toString()
        return url.replace(/^file:\/\//, "")
    }

    function shellQuote(text) {
        return "'" + String(text).replace(/'/g, "'\\''") + "'"
    }

    // The accounts go to both collectors through the environment rather than the
    // command line. A name is the user's own text and a directory is a path;
    // one JSON document quoted once is less to get wrong than an argument list
    // built out of both.
    readonly property string profilesEnv: {
        if (activeProfiles.length === 0) {
            return ""
        }
        var slim = activeProfiles.map(function (p) {
            return {name: String(p.name || ""), dir: String(p.dir)}
        })
        return "CLAUDE_PROFILES=" + shellQuote(JSON.stringify(slim)) + " "
    }

    function refresh() {
        collector.connectSource(profilesEnv + shellQuote(collectorPath))
    }

    // Poll faster while the popup is open - that is the only time a stale second
    // is actually visible - and back off to the configured interval when closed.
    Timer {
        interval: root.expanded ? 1000 : Math.max(1, plasmoid.configuration.refreshInterval) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 1000
        running: root.expanded
        repeat: true
        onTriggered: root.now = Date.now()
    }

    onExpandedChanged: {
        if (expanded) {
            now = Date.now()
            refresh()
            refreshUsage()
        } else {
            collapseAll()
            expandedSessions = ({})
            renamingSession = ""
            copyNotice = ""
        }
    }
}
