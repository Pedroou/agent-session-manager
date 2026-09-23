import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as Plasma5Support

// The accounts to watch.
//
// Claude Code's own mechanism for a second account is $CLAUDE_CONFIG_DIR, and
// it takes any path at all - so there is no list to hardcode and no name to
// assume. The widget reads whatever is in here, and this page is how it gets
// there: search a directory for accounts, or name one outright.
//
// Searching only ever happens because someone asked for it. An account removed
// from this list has to stay removed across restarts, and it cannot if anything
// re-runs the search on its own.
KCM.SimpleKCM {
    id: page

    property string cfg_profiles: "[]"
    property alias cfg_profileSearchPath: searchPath.text

    // The list, parsed. Held rather than re-parsed on every read: the rows below
    // edit it, and re-parsing on each keystroke would throw away the text cursor
    // along with everything else.
    property var entries: []
    property string notice: ""
    property bool busy: false
    // Set while writing back, so the round trip through the setting does not
    // look like the dialog handing us a new list to load.
    property bool writing: false

    readonly property string scriptPath: {
        var url = Qt.resolvedUrl("../scripts/claude-find-profiles").toString()
        return url.replace(/^file:\/\//, "")
    }

    Component.onCompleted: reload()
    onCfg_profilesChanged: if (!writing) {
        reload()
    }

    function reload() {
        try {
            var list = JSON.parse(cfg_profiles || "[]")
            entries = Array.isArray(list) ? list : []
        } catch (e) {
            entries = []
        }
    }

    function commit(next) {
        entries = next
        writing = true
        cfg_profiles = JSON.stringify(next)
        writing = false
    }

    function copyEntries() {
        var out = []
        for (var i = 0; i < entries.length; i++) {
            out.push({dir: entries[i].dir, name: entries[i].name,
                      enabled: entries[i].enabled !== false})
        }
        return out
    }

    function hasDir(dir) {
        for (var i = 0; i < entries.length; i++) {
            if (entries[i].dir === dir) {
                return true
            }
        }
        return false
    }

    function addFound(found) {
        var next = copyEntries()
        var added = 0
        for (var i = 0; i < found.length; i++) {
            if (!found[i] || !found[i].dir || hasDir(found[i].dir)) {
                continue
            }
            next.push({dir: found[i].dir, name: found[i].name || found[i].dir,
                       enabled: true})
            added += 1
        }
        if (added > 0) {
            commit(next)
        }
        return added
    }

    function removeAt(index) {
        var next = copyEntries()
        next.splice(index, 1)
        commit(next)
        notice = i18n("Removed from the list. The account itself is untouched, and a search will find it again.")
    }

    function updateAt(index, field, value) {
        var next = copyEntries()
        next[index][field] = value
        commit(next)
    }

    function shellQuote(text) {
        return "'" + String(text).replace(/'/g, "'\\''") + "'"
    }

    // What the last run was asked to do, so the result can be reported in the
    // words of the button that was pressed.
    property string pending: ""

    function run(path, what) {
        if (busy || path === "") {
            return
        }
        busy = true
        pending = what
        notice = ""
        finder.connectSource(shellQuote(scriptPath) + " " + shellQuote(path))
    }

    Plasma5Support.DataSource {
        id: finder
        engine: "executable"
        connectedSources: []

        onNewData: function (source, data) {
            disconnectSource(source)
            page.busy = false

            var out = (data["stdout"] || "").trim()
            if (data["exit code"] !== 0 || out === "") {
                page.notice = i18n("Couldn't read that path.")
                return
            }
            var found = []
            try {
                found = JSON.parse(out)
            } catch (e) {
                page.notice = i18n("Couldn't read that path.")
                return
            }

            if (found.length === 0) {
                page.notice = page.pending === "add"
                    ? i18n("That isn't a Claude Code config directory: no .claude.json or .credentials.json in it.")
                    : i18n("No accounts found there.")
                return
            }

            var added = page.addFound(found)
            if (added === 0) {
                page.notice = i18n("Nothing new: already in the list.")
            } else if (added === 1) {
                page.notice = i18n("Added 1 account.")
            } else {
                page.notice = i18n("Added %1 accounts.", added)
            }
            if (page.pending === "add") {
                manualPath.text = ""
            }
        }
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Heading {
            level: 4
            text: i18n("Search for accounts")
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 26
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            text: i18n("Looks one level down for directories Claude Code has written to. Your home directory is where a second account usually goes, since CLAUDE_CONFIG_DIR is normally pointed at a sibling of ~/.claude.")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: searchPath
                Layout.fillWidth: true
                placeholderText: "~"
                onAccepted: page.run(text, "search")
            }

            QQC2.Button {
                icon.name: "search"
                text: i18n("Search")
                enabled: !page.busy && searchPath.text !== ""
                onClicked: page.run(searchPath.text, "search")
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        Kirigami.Heading {
            level: 4
            text: i18n("Or name one directly")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: manualPath
                Layout.fillWidth: true
                placeholderText: i18n("~/.claude-work")
                onAccepted: page.run(text, "add")
            }

            QQC2.Button {
                icon.name: "list-add"
                text: i18n("Add")
                enabled: !page.busy && manualPath.text !== ""
                onClicked: page.run(manualPath.text, "add")
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 26
            wrapMode: Text.WordWrap
            visible: page.notice !== ""
            font: Kirigami.Theme.smallFont
            text: page.notice
        }

        Kirigami.Separator { Layout.fillWidth: true }

        RowLayout {
            Layout.fillWidth: true

            Kirigami.Heading {
                level: 4
                Layout.fillWidth: true
                text: page.entries.length === 1 ? i18n("1 account")
                                                : i18n("%1 accounts", page.entries.length)
            }
        }

        // Empty means empty. It used to mean "fall back to ~/.claude", which
        // the popup then showed under a name nobody had chosen while this page
        // said there were none.
        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 26
            wrapMode: Text.WordWrap
            visible: page.entries.length === 0
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            text: i18n("Nothing is being watched. Search, or name a directory below.")
        }

        Kirigami.AbstractCard {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 30
            Layout.preferredHeight: Math.min(Math.max(page.entries.length, 1), 6)
                                    * (Kirigami.Units.gridUnit * 2 + Kirigami.Units.smallSpacing)
                                    + Kirigami.Units.largeSpacing
            visible: page.entries.length > 0

            contentItem: QQC2.ScrollView {
                clip: true

                ListView {
                    model: page.entries
                    spacing: Kirigami.Units.smallSpacing
                    reuseItems: false

                    delegate: RowLayout {
                        required property int index
                        required property var modelData
                        width: ListView.view.width
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.CheckBox {
                            checked: modelData.enabled !== false
                            // Off keeps the account in the list but out of the
                            // widget, which is what you want for one you are
                            // not using this week.
                            QQC2.ToolTip.text: i18n("Show this account in the widget")
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                            onToggled: page.updateAt(index, "enabled", checked)
                        }

                        QQC2.TextField {
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                            text: modelData.name || ""
                            placeholderText: i18n("Name")
                            onEditingFinished: if (text !== modelData.name) {
                                page.updateAt(index, "name", text)
                            }
                        }

                        QQC2.Label {
                            Layout.fillWidth: true
                            text: modelData.dir
                            elide: Text.ElideMiddle
                            maximumLineCount: 1
                            font: Kirigami.Theme.smallFont
                            color: Kirigami.Theme.disabledTextColor
                            opacity: modelData.enabled !== false ? 1 : 0.5

                            QQC2.ToolTip.text: modelData.dir
                            QQC2.ToolTip.visible: dirHover.hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                            HoverHandler { id: dirHover }
                        }

                        QQC2.ToolButton {
                            icon.name: "list-remove"
                            display: QQC2.AbstractButton.IconOnly
                            text: i18n("Remove from the list")
                            QQC2.ToolTip.text: text
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                            onClicked: page.removeAt(index)
                        }
                    }
                }
            }
        }
    }
}
