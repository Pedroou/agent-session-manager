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
    property alias cfg_maxSessions: popupHeight.value
    property alias cfg_showDone: showDone.checked
    property alias cfg_showUsage: showUsage.checked
    property string cfg_usageDefaultBar: "session"
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
            Kirigami.FormData.label: i18n("Popup Max Height:")
            from: 3
            to: 25
            stepSize: 1
            textFromValue: function (value) {
                return i18np("%1 session", "%1 sessions", value)
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
            text: i18n("Sets a fixed popup height. If past the limit, a scrollbar appears.")
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
            text: i18n("Uses the network: Requests Anthropic for your plan limits every five minutes through the current Claude Code login.")
        }

        // Here rather than on the Panel page, even though the panel strip
        // follows it too: this decides *which limit* plan usage means, and the
        // control it is the default for - the one behind the dots in the footer
        // - is in the popup.
        QQC2.ComboBox {
            id: defaultBar
            Kirigami.FormData.label: i18n("Limit Shown:")
            enabled: showUsage.checked
            textRole: "label"
            valueRole: "value"

            // Only the two every plan has. A scoped limit is per-model and not
            // every plan carries one, so defaulting to a limit a plan lacks
            // would silently fall through to something else - which is the
            // behaviour this setting exists to replace.
            model: [
                {label: i18n("Session"), value: "session"},
                {label: i18n("Weekly"), value: "weekly"}
            ]

            // A ComboBox cannot be aliased to a string setting, so the two are
            // kept in step by hand, the same way the panel threshold is.
            Component.onCompleted: defaultBar.currentIndex = defaultBar.indexOfValue(page.cfg_usageDefaultBar)
            onActivated: page.cfg_usageDefaultBar = defaultBar.currentValue

            Connections {
                target: page
                function onCfg_usageDefaultBarChanged() {
                    var i = defaultBar.indexOfValue(page.cfg_usageDefaultBar)
                    if (i >= 0 && i !== defaultBar.currentIndex) {
                        defaultBar.currentIndex = i
                    }
                }
            }
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            text: i18n("What an account shows until you pick a limit for it behind the dots in the footer. A pick made there wins, and is remembered per account.")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: detailRepository
            Kirigami.FormData.label: i18n("Row Details:")
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
            text: i18n("Profile, uptime and directory always show.")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.ComboBox {
            id: branchPlacement
            Kirigami.FormData.label: i18n("Branch Display:")
            enabled: detailBranch.checked
            textRole: "label"
            valueRole: "value"

            model: [
                {label: i18n("repository/branch"), value: false},
                {label: i18n("On its own row"), value: true}
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

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: shortLabels
            Kirigami.FormData.label: i18n("Shorten Labels:")
            text: i18n("Directory -> Dir | Repository -> Repo")
        }
    }
}
