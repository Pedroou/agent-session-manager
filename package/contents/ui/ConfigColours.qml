import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kquickcontrols as KQuickControls

import "../code/sessions.js" as Sessions

// One page for the six status colours, because six pickers swamp whatever page
// they share. The built-in values live in code/sessions.js so the widget, this
// page and the node tests all read them from one place.
// Wrapped in a KCM.SimpleKCM rather than left as a bare FormLayout. That wrapper
// is what gives a config page its title and its margins: the dialog instantiates
// each page with `title` set to the category's name, so a root that has a title
// property picks it up for free. It is how Plasma's own About and Keyboard
// Shortcuts pages get theirs, and why ours sat flush against the top with no
// heading at all.

KCM.SimpleKCM {
    id: page
    property alias cfg_customColors: customColors.checked
    property alias cfg_colorWaiting: waitingColor.color
    property alias cfg_colorError: errorColor.color
    property alias cfg_colorRunning: runningColor.color
    property alias cfg_colorWorking: workingColor.color
    property alias cfg_colorShell: shellColor.color
    property alias cfg_colorDone: doneColor.color

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: customColors
            Kirigami.FormData.label: i18n("Status colours:")
            text: i18n("Customize")
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            text: i18n("Turning this off goes back to the built-in colours.")
        }

        // Hidden rather than disabled while the box is unticked: leaving the pickers
        // on screen would suggest the colours in them were still in force. They keep
        // their values, but nothing reads them until it is ticked again.
        RowLayout {
            Kirigami.FormData.label: i18n("Waiting:")
            visible: customColors.checked
            spacing: Kirigami.Units.smallSpacing

            KQuickControls.ColorButton {
                id: waitingColor
                showAlphaChannel: false
                dialogTitle: i18n("Colour for waiting sessions")
            }

            QQC2.Button {
                icon.name: "edit-undo"
                flat: true
                display: QQC2.AbstractButton.IconOnly
                text: i18n("Use the built-in colour")
                onClicked: waitingColor.color = Sessions.defaultColor("waiting")

                QQC2.ToolTip.text: text
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Error:")
            visible: customColors.checked
            spacing: Kirigami.Units.smallSpacing

            KQuickControls.ColorButton {
                id: errorColor
                showAlphaChannel: false
                dialogTitle: i18n("Colour for error sessions")
            }

            QQC2.Button {
                icon.name: "edit-undo"
                flat: true
                display: QQC2.AbstractButton.IconOnly
                text: i18n("Use the built-in colour")
                onClicked: errorColor.color = Sessions.defaultColor("error")

                QQC2.ToolTip.text: text
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Running:")
            visible: customColors.checked
            spacing: Kirigami.Units.smallSpacing

            KQuickControls.ColorButton {
                id: runningColor
                showAlphaChannel: false
                dialogTitle: i18n("Colour for running sessions")
            }

            QQC2.Button {
                icon.name: "edit-undo"
                flat: true
                display: QQC2.AbstractButton.IconOnly
                text: i18n("Use the built-in colour")
                onClicked: runningColor.color = Sessions.defaultColor("running")

                QQC2.ToolTip.text: text
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Working:")
            visible: customColors.checked
            spacing: Kirigami.Units.smallSpacing

            KQuickControls.ColorButton {
                id: workingColor
                showAlphaChannel: false
                dialogTitle: i18n("Colour for working sessions")
            }

            QQC2.Button {
                icon.name: "edit-undo"
                flat: true
                display: QQC2.AbstractButton.IconOnly
                text: i18n("Use the built-in colour")
                onClicked: workingColor.color = Sessions.defaultColor("working")

                QQC2.ToolTip.text: text
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Shell:")
            visible: customColors.checked
            spacing: Kirigami.Units.smallSpacing

            KQuickControls.ColorButton {
                id: shellColor
                showAlphaChannel: false
                dialogTitle: i18n("Colour for shell sessions")
            }

            QQC2.Button {
                icon.name: "edit-undo"
                flat: true
                display: QQC2.AbstractButton.IconOnly
                text: i18n("Use the built-in colour")
                onClicked: shellColor.color = Sessions.defaultColor("shell")

                QQC2.ToolTip.text: text
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Done:")
            visible: customColors.checked
            spacing: Kirigami.Units.smallSpacing

            KQuickControls.ColorButton {
                id: doneColor
                showAlphaChannel: false
                dialogTitle: i18n("Colour for done sessions")
            }

            QQC2.Button {
                icon.name: "edit-undo"
                flat: true
                display: QQC2.AbstractButton.IconOnly
                text: i18n("Use the built-in colour")
                onClicked: doneColor.color = Sessions.defaultColor("done")

                QQC2.ToolTip.text: text
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }
    }
}
