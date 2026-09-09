import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "../code/sessions.js" as Sessions
import "../code/usage.js" as Usage

// The panel only has to answer one question: is anything waiting on me? So the
// sessions are drawn as bars - one each, in the colour of its state - with the
// running total beside them in the colour of whichever state dominates, and a
// thin usage bar underneath when the plan is worth worrying about.
MouseArea {
    id: compact

    property var widget

    readonly property bool sideways: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property var shown: widget ? widget.shown : []
    readonly property var counts: widget ? widget.shownCounts : ({total: 0})
    readonly property bool failed: widget ? widget.failure !== "" : false

    // Past a point the bars stop being countable and the number carries the load.
    readonly property int maxRails: 8
    readonly property var railed: shown.slice(0, maxRails)

    readonly property real thickness: Math.max(2, Math.round(Kirigami.Units.smallSpacing * 0.8))
    readonly property real gap: Math.max(2, Math.round(thickness * 0.9))

    // Breathing room against the widget's own edges, so the outermost bar does
    // not sit flush against whatever is next to it in the panel.
    readonly property real pad: Kirigami.Units.smallSpacing

    // The same limit, on the same profile, that the popup's footer is showing.
    readonly property var usageBar: widget
        ? Usage.panelBar(widget.usage, plasmoid.configuration.usageProfile,
                         plasmoid.configuration.usageProfile === "personal"
                            ? plasmoid.configuration.usageBarPersonal
                            : plasmoid.configuration.usageBarWork)
        : null
    // Below three bars the strip is barely wider than it is tall and reads as a
    // smudge rather than a measurement, so it waits until there is width to fill.
    readonly property int usageMinBars: 3
    readonly property bool usageVisible: plasmoid.configuration.panelUsage
        && usageBar !== null
        && railed.length >= usageMinBars
        && Usage.pastThreshold(usageBar, plasmoid.configuration.panelUsageThreshold)
    readonly property real stripThickness: Math.max(2, Math.round(thickness * 0.85))

    // One small gap, not two: the bars are the whole point of the panel view, so
    // they take as much of it as they can without touching the edges - less
    // whatever the usage strip underneath is using.
    readonly property real track: Math.max(Kirigami.Units.iconSizes.small,
                                           (sideways ? compact.width : compact.height)
                                           - Kirigami.Units.smallSpacing
                                           - (usageVisible && !sideways ? stripThickness + gap : 0))

    // Measured from the panel's own thickness rather than from the bar track,
    // which shrinks when the usage strip appears - sizing the number off that
    // made it get smaller the moment the strip showed up.
    readonly property real countBase: (sideways ? compact.width : compact.height)
                                      - Kirigami.Units.smallSpacing
    readonly property real countSize: Math.max(8, Math.round(
        Math.min(countBase * 0.72, Kirigami.Units.gridUnit * 1.3)
        * Math.max(60, plasmoid.configuration.countScale) / 100))

    function tone(state) {
        return widget ? widget.tone(state) : Kirigami.Theme.disabledTextColor
    }

    activeFocusOnTab: true
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton

    Accessible.role: Accessible.Button
    Accessible.name: i18n("Claude Code sessions")
    Accessible.description: Sessions.tooltipLines(compact.counts).replace(/\n/g, ", ")
    Accessible.onPressAction: widget.expanded = !widget.expanded

    onClicked: mouse => {
        if (mouse.button === Qt.MiddleButton) {
            widget.refresh()
        } else {
            widget.expanded = !widget.expanded
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            widget.expanded = !widget.expanded
            event.accepted = true
        }
    }

    // The panel owns one axis and the content owns the other: height in a
    // horizontal panel, width in a vertical one. Deriving either from the
    // content's own size on the axis the panel controls would be a binding loop,
    // since the bars are measured from it.
    Layout.fillWidth: sideways
    Layout.fillHeight: !sideways
    Layout.minimumWidth: sideways ? 0 : content.implicitWidth + compact.pad * 2
    Layout.maximumWidth: sideways ? Number.POSITIVE_INFINITY : content.implicitWidth + compact.pad * 2
    Layout.minimumHeight: sideways ? content.implicitHeight + compact.pad * 2 : 0
    Layout.maximumHeight: sideways ? content.implicitHeight + compact.pad * 2 : Number.POSITIVE_INFINITY

    GridLayout {
        id: content
        anchors.centerIn: parent
        flow: compact.sideways ? GridLayout.TopToBottom : GridLayout.LeftToRight
        columnSpacing: Kirigami.Units.smallSpacing
        rowSpacing: Kirigami.Units.smallSpacing

        ColumnLayout {
            spacing: compact.gap
            Layout.alignment: Qt.AlignCenter

            GridLayout {
                id: cluster
                flow: compact.sideways ? GridLayout.TopToBottom : GridLayout.LeftToRight
                columnSpacing: compact.gap
                rowSpacing: compact.gap
                Layout.alignment: Qt.AlignCenter

                Repeater {
                    model: compact.railed
                    delegate: Rail {
                        required property var modelData
                        sessionState: modelData.state
                        fraction: Sessions.railFraction()
                        color: compact.tone(modelData.state)
                        track: compact.track
                        thickness: compact.thickness
                        sideways: compact.sideways
                        Layout.alignment: Qt.AlignCenter
                    }
                }

                // Nothing running: one faint tick, so the widget reads as quiet
                // rather than broken.
                Rail {
                    visible: compact.railed.length === 0
                    sessionState: "none"
                    fraction: 0.14
                    color: compact.failed ? Kirigami.Theme.negativeTextColor
                                          : Kirigami.Theme.disabledTextColor
                    track: compact.track
                    thickness: compact.thickness
                    sideways: compact.sideways
                    Layout.alignment: Qt.AlignCenter
                }
            }

            // The plan limit, as a bar and nothing else. No number: at panel size
            // a percentage is unreadable, and the point here is the glance.
            Item {
                id: strip
                visible: compact.usageVisible
                Layout.fillWidth: true
                Layout.preferredHeight: compact.stripThickness
                implicitHeight: compact.stripThickness

                readonly property real portion: Math.max(0, Math.min(100,
                    compact.usageBar ? compact.usageBar.percent : 0)) / 100
                readonly property color fill: {
                    if (!plasmoid.configuration.panelUsageColour) {
                        return Kirigami.Theme.textColor
                    }
                    switch (Usage.severity(compact.usageBar)) {
                    case "critical": return Kirigami.Theme.negativeTextColor
                    case "warning": return Kirigami.Theme.neutralTextColor
                    default: return Kirigami.Theme.positiveTextColor
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Kirigami.Theme.textColor
                    opacity: 0.25
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * strip.portion
                    radius: height / 2
                    color: strip.fill
                }
            }
        }

        PlasmaComponents3.Label {
            visible: compact.counts.total > 0 && plasmoid.configuration.showTotal
            text: compact.counts.total
            color: compact.tone(Sessions.dominantState(compact.counts))
            font.pixelSize: compact.countSize
            font.weight: Font.DemiBold
            Layout.alignment: Qt.AlignCenter
        }
    }
}
