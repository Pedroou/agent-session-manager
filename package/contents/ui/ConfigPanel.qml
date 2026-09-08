import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

// The compact view: what the widget looks like sitting in the panel.
// Wrapped in a KCM.SimpleKCM rather than left as a bare FormLayout. That wrapper
// is what gives a config page its title and its margins: the dialog instantiates
// each page with `title` set to the category's name, so a root that has a title
// property picks it up for free. It is how Plasma's own About and Keyboard
// Shortcuts pages get theirs, and why ours sat flush against the top with no
// heading at all.

KCM.SimpleKCM {
    id: page
    property alias cfg_showTotal: showTotal.checked
    property alias cfg_countScale: countScale.value
    property alias cfg_panelUsage: panelUsage.checked
    property alias cfg_panelUsageColour: panelUsageColour.checked
    property int cfg_panelUsageThreshold: 0

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: showTotal
            Kirigami.FormData.label: i18n("Session count:")
            text: i18n("Show the number beside the bars")
        }

        QQC2.SpinBox {
            id: countScale
            Kirigami.FormData.label: i18n("Its size:")
            enabled: showTotal.checked
            from: 60
            to: 200
            stepSize: 10
            textFromValue: function (value) {
                return value + "%"
            }
            valueFromText: function (text) {
                return parseInt(text, 10)
            }
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: panelUsage
            Kirigami.FormData.label: i18n("Plan usage:")
            text: i18n("Show a usage bar under the session bars")
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            text: i18n("Tracks the same limit and profile the popup's usage bar is set to, without the numbers.")
        }

        QQC2.ComboBox {
            id: threshold
            Kirigami.FormData.label: i18n("Show it:")
            enabled: panelUsage.checked
            textRole: "label"
            valueRole: "value"

            model: [
                {label: i18n("Always"), value: 0},
                {label: i18n("Past 25% used"), value: 25},
                {label: i18n("Past 50% used"), value: 50},
                {label: i18n("Past 75% used"), value: 75},
                {label: i18n("Past 90% used"), value: 90}
            ]

            // A ComboBox cannot be aliased to an int setting, so the two are kept in
            // step by hand — currentIndex out of the value on load, value out of the
            // selection on change.
            Component.onCompleted: threshold.currentIndex = threshold.indexOfValue(page.cfg_panelUsageThreshold)
            onActivated: page.cfg_panelUsageThreshold = threshold.currentValue

            Connections {
                target: page
                function onCfg_panelUsageThresholdChanged() {
                    var i = threshold.indexOfValue(page.cfg_panelUsageThreshold)
                    if (i >= 0 && i !== threshold.currentIndex) {
                        threshold.currentIndex = i
                    }
                }
            }
        }

        QQC2.CheckBox {
            id: panelUsageColour
            enabled: panelUsage.checked
            text: i18n("Colour it by how much is used")
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            text: i18n("Green, amber, then red — the same thresholds the popup uses. Off keeps it a plain neutral bar.")
        }
    }
}
