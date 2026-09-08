import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

// The full view: the list that opens when you click the widget.
// Wrapped in a KCM.SimpleKCM rather than left as a bare FormLayout. That wrapper
// is what gives a config page its title and its margins: the dialog instantiates
// each page with `title` set to the category's name, so a root that has a title
// property picks it up for free. It is how Plasma's own About and Keyboard
// Shortcuts pages get theirs, and why ours sat flush against the top with no
// heading at all.

KCM.SimpleKCM {
    id: page
    property alias cfg_maxPopupHeight: popupHeight.value
    property alias cfg_showDone: showDone.checked
    property alias cfg_showUsage: showUsage.checked
    property alias cfg_detailRepository: detailRepository.checked
    property alias cfg_detailBranch: detailBranch.checked
    property alias cfg_detailSession: detailSession.checked
    property alias cfg_detailProcess: detailProcess.checked
    property alias cfg_detailVersion: detailVersion.checked
    property bool cfg_branchSeparate: false
    property alias cfg_shortLabels: shortLabels.checked

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: popupHeight
            Kirigami.FormData.label: i18n("Tallest it gets:")
            from: 8
            to: 60
            stepSize: 1
            textFromValue: function (value) {
                return i18np("%1 line", "%1 lines", value)
            }
            valueFromText: function (text) {
                return parseInt(text, 10)
            }
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            text: i18n("Fewer sessions make a shorter popup. More than this and it scrolls.")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: showDone
            Kirigami.FormData.label: i18n("Show:")
            text: i18n("Sessions that are done")
        }

        QQC2.CheckBox {
            id: showUsage
            text: i18n("Plan usage for each profile")
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            text: i18n("The only part of the widget that uses the network. It asks Anthropic for your plan limits every five minutes, with the login Claude Code already has.")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: detailRepository
            Kirigami.FormData.label: i18n("Row details:")
            text: i18n("Repository")
        }

        QQC2.CheckBox {
            id: detailBranch
            text: i18n("Branch")
        }

        QQC2.CheckBox {
            id: detailSession
            text: i18n("Session")
        }

        QQC2.CheckBox {
            id: detailProcess
            text: i18n("Process")
        }

        QQC2.CheckBox {
            id: detailVersion
            text: i18n("Version")
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            text: i18n("Profile, uptime and directory always show — they are what opening a row is for.")
        }

        QQC2.ComboBox {
            id: branchPlacement
            Kirigami.FormData.label: i18n("Branch shows:")
            enabled: detailBranch.checked
            textRole: "label"
            valueRole: "value"

            model: [
                {label: i18n("With the repository, as repo/branch"), value: false},
                {label: i18n("On a row of its own"), value: true}
            ]

            // Kept in step by hand: a ComboBox cannot be aliased to a bool.
            Component.onCompleted: branchPlacement.currentIndex = page.cfg_branchSeparate ? 1 : 0
            onActivated: page.cfg_branchSeparate = branchPlacement.currentValue

            Connections {
                target: page
                function onCfg_branchSeparateChanged() {
                    var want = page.cfg_branchSeparate ? 1 : 0
                    if (want !== branchPlacement.currentIndex) {
                        branchPlacement.currentIndex = want
                    }
                }
            }
        }

        QQC2.CheckBox {
            id: shortLabels
            Kirigami.FormData.label: i18n("Labels:")
            text: i18n("Shorten “Directory” and “Repository” to “Dir” and “Repo”")
        }
    }
}
