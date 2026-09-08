import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// Confirmation that something reached the clipboard.
//
// It floats over the list rather than sitting in the layout, so a copy never
// reflows the popup underneath the pointer — and it says *what* was copied,
// because with several copy targets on one row "Copied" alone leaves you
// wondering which one you hit.
//
// Deliberately not a system notification: this is a keystroke-sized action, and
// putting it in the notification centre would bury the messages that matter
// under a pile of "copied a path".
Rectangle {
    id: toast

    property string notice: ""

    // Held separately so the text does not vanish halfway through the fade out,
    // which would shrink the pill as it disappears.
    property string lastNotice: ""
    onNoticeChanged: if (notice !== "") {
        lastNotice = notice
    }

    implicitWidth: content.implicitWidth + Kirigami.Units.largeSpacing * 2
    implicitHeight: content.implicitHeight + Kirigami.Units.smallSpacing * 2
    radius: height / 2
    color: Kirigami.Theme.highlightColor

    opacity: notice !== "" ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation {
            duration: Kirigami.Units.longDuration
            easing.type: Easing.OutCubic
        }
    }

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            source: "edit-copy-symbolic"
            isMask: true
            color: Kirigami.Theme.highlightedTextColor
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: Kirigami.Units.iconSizes.small
            Layout.alignment: Qt.AlignVCenter
        }

        PlasmaComponents3.Label {
            text: toast.lastNotice
            color: Kirigami.Theme.highlightedTextColor
            font: Kirigami.Theme.smallFont
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
