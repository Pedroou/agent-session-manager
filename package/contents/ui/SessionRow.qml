import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "../code/sessions.js" as Sessions

// One session. The rail on the left is the same device the panel uses, so the
// popup reads as the panel opened up rather than as a different screen.
Item {
    id: row

    property var session
    property var widget
    property bool showProfile: false
    // Held by the widget, keyed by session id, so re-sorting the list cannot
    // move an open row's state onto a different session.
    readonly property bool detailsOpen: widget ? widget.isExpanded(session.sessionId) : false
    readonly property bool renaming: widget ? widget.renamingSession === session.sessionId : false
    // Ending a session is one click away from losing what it was doing, so the
    // button asks once. The timer puts it back if the answer never comes.
    property bool confirmingEnd: false

    readonly property color tone: widget ? widget.tone(session.state) : Kirigami.Theme.textColor
    readonly property double now: widget ? widget.now : Date.now()
    readonly property bool censored: widget ? widget.censored : false
    readonly property string name: widget
        ? Sessions.displayName(session, widget.nicknames, censored)
        : session.name
    readonly property var rows: Sessions.detailRows(session, plasmoid.configuration, now, censored)

    implicitHeight: body.implicitHeight + Kirigami.Units.smallSpacing * 2

    Connections {
        target: row.widget
        function onCollapseAll() {
            row.confirmingEnd = false
        }
    }

    Timer {
        id: confirmTimeout
        interval: 4000
        onTriggered: row.confirmingEnd = false
    }
    onConfirmingEndChanged: if (confirmingEnd) {
        confirmTimeout.restart()
    } else {
        confirmTimeout.stop()
    }

    // Tracks the whole row including its buttons, so reaching for one does not
    // make the others vanish out from under the pointer.
    HoverHandler {
        id: rowHover
    }

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        radius: Math.round(Kirigami.Units.gridUnit / 4)
        // A neutral wash rather than the theme accent: the accent is a colour,
        // and every colour in this row already means something.
        color: Kirigami.Theme.textColor
        opacity: rowHover.hovered ? 0.09 : 0
        Behavior on opacity {
            NumberAnimation { duration: Kirigami.Units.shortDuration }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                // Collapsed, the useful thing to paste is the way back in.
                // Expanded, it is everything on screen.
                if (row.detailsOpen) {
                    row.widget.copyToClipboard(
                        Sessions.detailsAsText(row.session, plasmoid.configuration,
                                               row.now, row.widget.nicknames, row.censored),
                        i18n("Session details"))
                } else {
                    row.widget.copyToClipboard(Sessions.resumeCommand(row.session),
                                               i18n("Resume command"))
                }
            } else {
                row.widget.toggleExpanded(row.session.sessionId)
            }
        }
    }

    RowLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Kirigami.Units.largeSpacing
        anchors.rightMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        Rail {
            id: rail
            sessionState: row.session.state
            fraction: 1.0
            color: row.tone
            thickness: 3
            // Stretched to the row rather than measured from any one column.
            // It used to take its length from the headings, so censoring - which
            // removes the second line - left the rail visibly short of its own
            // row. `track: 0` keeps it from claiming height of its own; the
            // layout gives it whatever the tallest column ends up being.
            track: 0
            Layout.fillHeight: true
        }

        ColumnLayout {
            id: headings
            Layout.fillWidth: true
            // A layout's ceiling is its children's, and the name below has one.
            // Without this, a censored row - the name and nothing else - stopped
            // growing at the end of its text and left the status adrift.
            Layout.maximumWidth: Infinity
            Layout.alignment: Qt.AlignTop
            spacing: 0

            // The name is a link to the session itself: click it and its
            // terminal comes forward, on the right tab. The rest of the row
            // still opens the details. Only as wide as the text, so the link is
            // where it looks like it is.
            //
            // fillWidth with the text as its ceiling, not a maximumWidth bound
            // to the column. Without fillWidth a layout pins an item to its
            // preferred width, which made the name the column's minimum: a long
            // one pushed the status out of the popup, and the hover buttons
            // appearing pushed it out again. This way it can shrink to nothing
            // and elides instead. Rounded up because the layout hands out whole
            // pixels, and 109 for a 109.2 name elides a name that fits.
            PlasmaComponents3.Label {
                id: nameLink
                Layout.fillWidth: true
                Layout.preferredWidth: Math.ceil(implicitWidth)
                Layout.maximumWidth: Math.ceil(implicitWidth)
                text: row.name
                elide: Text.ElideRight
                maximumLineCount: 1
                visible: !row.renaming
                font.underline: nameHover.hovered

                HoverHandler {
                    id: nameHover
                    cursorShape: Qt.PointingHandCursor
                }

                MouseArea {
                    anchors.fill: parent
                    // Left only: a right-click falls through to the row, which
                    // copies, as it does anywhere else on it.
                    acceptedButtons: Qt.LeftButton
                    onClicked: row.widget.jumpTo(row.session)
                }

                PlasmaComponents3.ToolTip.text: i18n("Go to this session")
                PlasmaComponents3.ToolTip.visible: nameHover.hovered
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }

            PlasmaComponents3.TextField {
                id: renameField
                Layout.fillWidth: true
                visible: row.renaming
                placeholderText: row.session.name
                onAccepted: {
                    row.widget.setNickname(row.session.sessionId, text.trim())
                    row.widget.renamingSession = ""
                }
                Keys.onEscapePressed: row.widget.renamingSession = ""
                onVisibleChanged: if (visible) {
                    text = row.widget.nicknames[row.session.sessionId] || ""
                    forceActiveFocus()
                    selectAll()
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: Sessions.context(row.session, row.showProfile, row.censored)
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
                elide: Text.ElideMiddle
                maximumLineCount: 1
                visible: text !== "" && !row.renaming
            }

            // Opened by clicking the row: the things you would otherwise go
            // hunting through `ps` for. Click a value to copy it.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: row.detailsOpen ? Kirigami.Units.smallSpacing : 0
                spacing: 0
                visible: row.detailsOpen

                Repeater {
                    model: row.detailsOpen ? row.rows : []

                    delegate: Item {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: detailLine.implicitHeight

                        Rectangle {
                            anchors.fill: parent
                            anchors.rightMargin: Kirigami.Units.smallSpacing
                            radius: Math.round(Kirigami.Units.gridUnit / 6)
                            color: Kirigami.Theme.textColor
                            opacity: detailHover.hovered && modelData.copyable ? 0.09 : 0
                        }

                        HoverHandler {
                            id: detailHover
                            cursorShape: modelData.copyable ? Qt.PointingHandCursor : Qt.ArrowCursor
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: modelData.copyable
                            onClicked: row.widget.copyToClipboard(modelData.value, modelData.key)
                        }

                        RowLayout {
                            id: detailLine
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: Kirigami.Units.smallSpacing

                            PlasmaComponents3.Label {
                                text: modelData.key
                                font: Kirigami.Theme.smallFont
                                color: Kirigami.Theme.disabledTextColor
                                Layout.minimumWidth: Kirigami.Units.gridUnit * 3.5
                            }
                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                text: modelData.value
                                font: Kirigami.Theme.smallFont
                                elide: Text.ElideMiddle
                                maximumLineCount: 1
                            }
                        }
                    }
                }
            }
        }

        // Only on hover, and sitting before the status so the status never moves.
        //
        // There is no "interrupt" button here on purpose. Claude Code handles
        // Ctrl+C by reading the byte off a raw-mode terminal, not as a signal;
        // its actual SIGINT handler calls the same shutdown(0) as SIGTERM. So a
        // signal cannot pause a session, only end it, and a button labelled
        // "interrupt" that quietly ended sessions would be worse than none.
        RowLayout {
            id: controls
            spacing: 0
            // Top, not centre: an expanded row grows downwards, and controls that
            // drift to the middle of the details end up nowhere near the name
            // they act on.
            Layout.alignment: Qt.AlignTop
            // fillHeight off explicitly. A layout nested in a layout is stretched
            // by default, and capping it with maximumHeight did not stop that -
            // it just let the row fill to 90px with the buttons floating in the
            // middle of it. Off, it takes its own height and the alignment above
            // finally means something.
            Layout.fillHeight: false
            visible: rowHover.hovered && !row.renaming

            PlasmaComponents3.ToolButton {
                icon.name: "edit-rename"
                icon.width: Kirigami.Units.iconSizes.small
                icon.height: Kirigami.Units.iconSizes.small
                // Padding, not layout hints. A RowLayout takes its implicit
                // height from its children's implicit heights, and a Control
                // derives that from content plus padding - so Layout.preferred
                // and Layout.minimum were both ignored and the button stayed
                // 32px, taller than a censored row's 28. Trimming the padding
                // shrinks the thing the layout is actually reading.
                padding: Math.round(Kirigami.Units.smallSpacing / 2)
                Layout.alignment: Qt.AlignTop
                display: PlasmaComponents3.AbstractButton.IconOnly
                flat: true
                text: i18n("Rename in this widget")
                onClicked: row.widget.renamingSession = row.session.sessionId

                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }

            PlasmaComponents3.ToolButton {
                // Only offered when the session can be ended safely: a known
                // pid above 1 with a known start time (see Sessions.endCommand).
                visible: Sessions.endCommand(row.session) !== ""
                icon.name: row.confirmingEnd ? "dialog-warning" : "window-close"
                icon.width: Kirigami.Units.iconSizes.small
                icon.height: Kirigami.Units.iconSizes.small
                // Padding, not layout hints. A RowLayout takes its implicit
                // height from its children's implicit heights, and a Control
                // derives that from content plus padding - so Layout.preferred
                // and Layout.minimum were both ignored and the button stayed
                // 32px, taller than a censored row's 28. Trimming the padding
                // shrinks the thing the layout is actually reading.
                padding: Math.round(Kirigami.Units.smallSpacing / 2)
                Layout.alignment: Qt.AlignTop
                display: PlasmaComponents3.AbstractButton.IconOnly
                flat: true
                icon.color: row.confirmingEnd ? Kirigami.Theme.negativeTextColor : undefined
                text: row.confirmingEnd ? i18n("Click again to end this session")
                                        : i18n("End this session")
                onClicked: {
                    if (row.confirmingEnd) {
                        row.widget.endSession(row.session)
                        row.confirmingEnd = false
                    } else {
                        row.confirmingEnd = true
                    }
                }

                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 0
            }
        }

        ColumnLayout {
            id: statusBlock
            spacing: 0
            // Same reasoning as the controls: the status belongs beside the name.
            Layout.alignment: Qt.AlignTop

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label {
                    text: Sessions.age(row.session.statusUpdatedAt, row.now)
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.disabledTextColor
                    visible: text !== ""
                }

                PlasmaComponents3.Label {
                    text: row.session.label
                    color: row.tone
                    // Breathes with the rail by following it, rather than running a
                    // second animation of its own: two identical animations started
                    // in the same frame look synchronised right up until something
                    // restarts one of them.
                    opacity: rail.opacity
                    // Set piecemeal: assigning the whole `font` group and one of its
                    // members in the same object is a QML error.
                    font.family: Kirigami.Theme.smallFont.family
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.weight: Font.DemiBold
                }
            }

            // The model, and how full its context is. Only once there is a reply
            // to read them from: a session nobody has typed into has neither.
            // Each part can be switched off in the settings; the line goes with
            // the last of them.
            RowLayout {
                id: modelLine
                readonly property string model: Sessions.modelLabel(row.session.model)
                readonly property int percent: Sessions.contextPercent(row.session)
                readonly property bool showModel: plasmoid.configuration.rowModel && model !== ""
                readonly property bool showBar: plasmoid.configuration.rowContextBar && percent >= 0
                readonly property bool showPercent: plasmoid.configuration.rowContextPercent
                                                    && percent >= 0
                Layout.alignment: Qt.AlignRight
                spacing: Kirigami.Units.smallSpacing
                visible: showModel || showBar || showPercent

                HoverHandler {
                    id: modelHover
                }
                PlasmaComponents3.ToolTip.text: modelLine.percent < 0 ? ""
                    : i18n("%1 of %2 tokens of context",
                           Sessions.tokenCount(row.session.contextTokens),
                           Sessions.tokenCount(Sessions.contextWindow(row.session.model,
                                                                      row.session.agent,
                                                                      row.session.contextTokens)))
                PlasmaComponents3.ToolTip.visible: modelHover.hovered
                                                   && PlasmaComponents3.ToolTip.text !== ""
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay

                PlasmaComponents3.Label {
                    visible: modelLine.showModel
                    text: modelLine.model
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.disabledTextColor
                }

                // Siblings rather than parent and child, as in UsageBar: opacity
                // multiplies down, so a fill inside the faded track would be faded too.
                Item {
                    visible: modelLine.showBar
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Kirigami.Units.gridUnit * 3
                    implicitHeight: Math.max(4, Math.round(Kirigami.Units.gridUnit / 3))

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: Kirigami.Theme.textColor
                        opacity: 0.15
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * Math.max(0, modelLine.percent) / 100
                        radius: height / 2
                        // The accent until the context is nearly spent - past that a
                        // turn may compact it, which is worth seeing coming.
                        color: modelLine.percent >= 90 ? Kirigami.Theme.negativeTextColor
                             : modelLine.percent >= 75 ? Kirigami.Theme.neutralTextColor
                             : Kirigami.Theme.highlightColor
                    }
                }

                PlasmaComponents3.Label {
                    visible: modelLine.showPercent
                    text: i18nc("percentage of the context window in use", "%1%", modelLine.percent)
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.disabledTextColor
                    // As wide as "100%" whatever it reads, so the bars line up
                    // from one row to the next.
                    Layout.minimumWidth: percentMetrics.width
                    horizontalAlignment: Text.AlignRight

                    TextMetrics {
                        id: percentMetrics
                        font: Kirigami.Theme.smallFont
                        text: "100%"
                    }
                }
            }
        }
    }
}
