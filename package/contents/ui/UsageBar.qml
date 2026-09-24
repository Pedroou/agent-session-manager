import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "../code/usage.js" as Usage
import "../code/sessions.js" as Sessions

// One plan limit: a track, a fill coloured by how close it is, and the number.
// When there is nothing to draw, the message takes the whole width - a profile
// that is signed out should say so, not show an empty bar reading zero.
RowLayout {
    id: usage

    property var bar
    property string message: ""
    // Non-empty when this account can be signed back in, in which case the
    // message itself is the button - there is nowhere else on the row to put
    // one, and the message is already saying what is wrong.
    property string signInDir: ""
    signal signInRequested(string dir)
    property double now: Date.now()
    // True when these bars are the last good reading rather than a fresh one.
    property bool stale: false
    property double since: 0

    readonly property string level: Usage.severity(bar)
    readonly property color fillColor: {
        switch (level) {
        case "critical": return Kirigami.Theme.negativeTextColor
        case "warning": return Kirigami.Theme.neutralTextColor
        default: return Kirigami.Theme.positiveTextColor
        }
    }

    spacing: Kirigami.Units.smallSpacing

    PlasmaComponents3.Label {
        id: messageLabel
        Layout.fillWidth: true
        visible: usage.bar === null || usage.message !== ""
        text: usage.message
        font.family: Kirigami.Theme.smallFont.family
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        font.underline: usage.signInDir !== "" && messageHover.hovered
        color: usage.signInDir !== "" ? Kirigami.Theme.linkColor
                                      : Kirigami.Theme.disabledTextColor
        elide: Text.ElideRight

        HoverHandler {
            id: messageHover
            enabled: usage.signInDir !== ""
            cursorShape: Qt.PointingHandCursor
        }

        MouseArea {
            anchors.fill: parent
            enabled: usage.signInDir !== ""
            onClicked: usage.signInRequested(usage.signInDir)
        }

        PlasmaComponents3.ToolTip.text: i18n("Opens a terminal for this account, where Claude Code will ask you to log in")
        PlasmaComponents3.ToolTip.visible: messageHover.hovered
        PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
    }

    PlasmaComponents3.Label {
        visible: usage.bar !== null && usage.message === ""
        text: usage.bar ? usage.bar.label : ""
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.disabledTextColor
    }

    // The track and the fill are siblings, not parent and child: opacity in QML
    // multiplies down, so a fill inside a faded track could never come out solid.
    Item {
        id: track
        visible: usage.bar !== null && usage.message === ""
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        implicitHeight: Math.max(4, Math.round(Kirigami.Units.gridUnit / 3))

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Kirigami.Theme.textColor
            opacity: 0.15
        }

        Rectangle {
            id: fill
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            radius: height / 2
            color: usage.fillColor

            // The animation is on the *fraction*, not on the width in pixels.
            // Animating width conflates two different events: the value changing,
            // which should slide, and the track being laid out or resized, which
            // should not. That was the double-take on opening - the bar drew at
            // its real width, the layout pass then moved the track, and the
            // Behavior replayed the whole fill from empty.
            property real portion: 0
            width: parent.width * portion

            Behavior on portion {
                NumberAnimation {
                    duration: Kirigami.Units.longDuration
                    easing.type: Easing.OutCubic
                }
            }

            // Bound after creation so the first reading animates in from empty
            // rather than snapping, and every reading after that slides.
            Component.onCompleted: fill.portion = Qt.binding(function () {
                return Math.max(0, Math.min(100, usage.bar ? usage.bar.percent : 0)) / 100
            })
        }
    }

    PlasmaComponents3.Label {
        visible: usage.bar !== null && usage.message === ""
        text: usage.bar ? i18nc("percentage of a plan limit used", "%1%", usage.bar.percent) : ""
        font: Kirigami.Theme.smallFont
        color: usage.fillColor
        Layout.minimumWidth: Kirigami.Units.gridUnit * 1.6
        horizontalAlignment: Text.AlignRight

        HoverHandler {
            id: percentHover
        }

        PlasmaComponents3.ToolTip.text: {
            if (!usage.bar) {
                return ""
            }
            var text = Usage.resetText(usage.bar.resetsAt, usage.now)
            if (usage.stale) {
                var age = Sessions.age(usage.since, usage.now)
                var note = age ? i18n("couldn't refresh - reading is %1 old", age)
                              : i18n("couldn't refresh")
                return text ? text + " · " + note : note
            }
            return text
        }
        PlasmaComponents3.ToolTip.visible: percentHover.hovered
                                           && PlasmaComponents3.ToolTip.text !== ""
        PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
    }
}
