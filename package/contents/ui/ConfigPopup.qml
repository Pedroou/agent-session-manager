import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// The full view: the list that opens when you click the widget.
Kirigami.FormLayout {
    id: page

    property alias cfg_maxPopupHeight: popupHeight.value
    property alias cfg_showDone: showDone.checked
    property alias cfg_showUsage: showUsage.checked

    property alias cfg_detailRepository: detailRepository.checked
    property alias cfg_detailBranch: detailBranch.checked
    property alias cfg_detailSession: detailSession.checked
    property alias cfg_detailProcess: detailProcess.checked
    property alias cfg_detailVersion: detailVersion.checked
    property alias cfg_branchSeparate: branchSeparate.checked
    property alias cfg_shortLabels: shortLabels.checked

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
        id: branchSeparate
        text: i18n("…on its own row, not appended to the repository")
        enabled: detailBranch.checked
        Layout.leftMargin: Kirigami.Units.gridUnit
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

    QQC2.CheckBox {
        id: shortLabels
        Kirigami.FormData.label: i18n("Their labels:")
        text: i18n("Shorten “Directory” and “Repository” to “Dir” and “Repo”")
    }
}
