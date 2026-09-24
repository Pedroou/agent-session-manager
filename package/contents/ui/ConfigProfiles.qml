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
            var entry = {dir: entries[i].dir, name: entries[i].name,
                         enabled: entries[i].enabled !== false}
            if (entries[i].found === true) {
                entry.found = true
            }
            out.push(entry)
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

    // A search puts what it finds in the list without adding it. Searching a
    // directory is a question, not an instruction, and answering it by wiring
    // up every account it happens to contain is the widget deciding something
    // the user did not ask for.
    function stageFound(found) {
        var next = copyEntries()
        var staged = 0
        for (var i = 0; i < found.length; i++) {
            if (!found[i] || !found[i].dir || hasDir(found[i].dir)) {
                continue
            }
            next.push({dir: found[i].dir, name: found[i].name || found[i].dir,
                       enabled: true, found: true})
            staged += 1
        }
        if (staged > 0) {
            commit(next)
        }
        return staged
    }

    // Naming one outright is an instruction, so it goes straight in.
    function addOne(entry) {
        if (!entry || !entry.dir || hasDir(entry.dir)) {
            return false
        }
        var next = copyEntries()
        next.push({dir: entry.dir, name: entry.name || entry.dir, enabled: true})
        commit(next)
        return true
    }

    function confirmAt(index) {
        var next = copyEntries()
        delete next[index].found
        commit(next)
    }

    function stagedCount() {
        var n = 0
        for (var i = 0; i < entries.length; i++) {
            if (entries[i].found === true) {
                n += 1
            }
        }
        return n
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

            if (page.pending === "add") {
                if (page.addOne(found[0])) {
                    page.notice = i18n("Added.")
                    manualPath.text = ""
                } else {
                    page.notice = i18n("Already in the list.")
                }
                return
            }

            var staged = page.stageFound(found)
            if (staged === 0) {
                page.notice = i18n("Nothing new: already in the list.")
            } else if (staged === 1) {
                page.notice = i18n("Found 1 account. Press + to add it.")
            } else {
                page.notice = i18n("Found %1 accounts. Press + to add them.", staged)
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

        Kirigami.Separator {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
            Layout.bottomMargin: Kirigami.Units.largeSpacing
        }

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

        Kirigami.Separator {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
            Layout.bottomMargin: Kirigami.Units.largeSpacing
        }

        RowLayout {
            Layout.fillWidth: true

            Kirigami.Heading {
                level: 4
                Layout.fillWidth: true
                text: {
                    var staged = page.stagedCount()
                    var added = page.entries.length - staged
                    var label = added === 1 ? i18n("1 account") : i18n("%1 accounts", added)
                    return staged > 0 ? i18n("%1, %2 found", label, staged) : label
                }
            }
        }

        // Empty means empty. It used to mean "fall back to ~/.claude", which
        // the popup then showed under a name nobody had chosen while this page
        // said there were none.
        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 26
            wrapMode: Text.WordWrap
            // Search results do not count: the list can be full of them and
            // still have nothing wired up.
            visible: page.entries.length - page.stagedCount() === 0
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            text: page.stagedCount() > 0
                  ? i18n("Nothing added yet. Press + on a result to add it.")
                  : i18n("Nothing is being watched. Search, or name a directory below.")
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
                        // Found by a search and not added yet. Still in the
                        // list, still removable, but the widget does not read
                        // it until the plus is pressed.
                        readonly property bool staged: modelData.found === true
                        width: ListView.view.width
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.CheckBox {
                            checked: !staged && modelData.enabled !== false
                            // Nothing to switch on or off until it is added.
                            enabled: !staged
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
                            // Editable while staged on purpose: naming it
                            // before adding it is the natural order.
                            opacity: staged ? 0.7 : 1
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
                            opacity: staged ? 0.5
                                            : (modelData.enabled !== false ? 1 : 0.5)

                            QQC2.ToolTip.text: modelData.dir
                            QQC2.ToolTip.visible: dirHover.hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                            HoverHandler { id: dirHover }
                        }

                        QQC2.Label {
                            visible: staged
                            text: i18n("found")
                            font: Kirigami.Theme.smallFont
                            color: Kirigami.Theme.neutralTextColor
                        }

                        // Kept in the layout when it does nothing, rather than
                        // hidden: a button that appears and disappears shifts
                        // the remove button under the pointer.
                        QQC2.ToolButton {
                            icon.name: "list-add"
                            display: QQC2.AbstractButton.IconOnly
                            opacity: staged ? 1 : 0
                            enabled: staged
                            text: i18n("Add this account")
                            QQC2.ToolTip.text: text
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                            onClicked: page.confirmAt(index)
                        }

                        QQC2.ToolButton {
                            icon.name: "list-remove"
                            display: QQC2.AbstractButton.IconOnly
                            // Works on a search result too. Nothing changes for
                            // the widget, but a list you cannot tidy is worse
                            // than one you can.
                            text: staged ? i18n("Discard this result")
                                         : i18n("Remove from the list")
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
