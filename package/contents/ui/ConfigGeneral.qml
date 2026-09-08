import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "../code/sessions.js" as Sessions

// How the widget behaves, wherever you happen to be looking at it. Anything that
// only affects one of the two views lives on that view's page instead.
Kirigami.FormLayout {
    id: page

    property alias cfg_refreshInterval: interval.value
    property alias cfg_attentionWhenWaiting: attention.checked
    property alias cfg_censorNames: censorNames.checked

    // Owned by other pages or by the widget itself, and declared here only so the
    // reset at the bottom can put every setting back, not just this page's.
    property bool cfg_showTotal: true
    property int cfg_countScale: 100
    property bool cfg_panelUsage: true
    property int cfg_panelUsageThreshold: 0
    property bool cfg_panelUsageColour: true
    property int cfg_maxPopupHeight: 21
    property bool cfg_showDone: true
    property bool cfg_showUsage: true
    property bool cfg_detailRepository: true
    property bool cfg_detailBranch: true
    property bool cfg_detailSession: true
    property bool cfg_detailProcess: true
    property bool cfg_detailVersion: true
    property bool cfg_branchSeparate: false
    property bool cfg_shortLabels: false
    property bool cfg_customColors: false
    property color cfg_colorWaiting: Sessions.defaultColor("waiting")
    property color cfg_colorError: Sessions.defaultColor("error")
    property color cfg_colorRunning: Sessions.defaultColor("running")
    property color cfg_colorWorking: Sessions.defaultColor("working")
    property color cfg_colorShell: Sessions.defaultColor("shell")
    property color cfg_colorDone: Sessions.defaultColor("done")
    property string cfg_nicknames: "{}"
    property string cfg_usageProfile: "work"
    property bool cfg_usageExpanded: false
    property string cfg_usageBarWork: "session"
    property string cfg_usageBarPersonal: "session"

    QQC2.SpinBox {
        id: interval
        Kirigami.FormData.label: i18n("Check every:")
        from: 1
        to: 60
        stepSize: 1
        textFromValue: function (value) {
            return i18np("%1 second", "%1 seconds", value)
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
        text: i18n("While the popup is open it always refreshes every second.")
    }

    Item {
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: attention
        Kirigami.FormData.label: i18n("Behaviour:")
        text: i18n("Highlight the widget when a session is waiting on me")
    }

    QQC2.CheckBox {
        id: censorNames
        text: i18n("Hide session names and paths")
    }

    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.disabledTextColor
        text: i18n("For screen-sharing. The eye in the popup's header does the same thing.")
    }

    // Last, and set apart. Plasma's applet dialog has no Defaults button of its
    // own, so the widget provides one — and a control that undoes every page
    // belongs at the end of the first page, not competing with the settings it
    // would throw away.
    Item {
        Kirigami.FormData.isSection: true
    }

    QQC2.Button {
        Kirigami.FormData.label: i18n("Everything:")
        icon.name: "edit-undo"
        text: i18n("Reset all settings to defaults")
        onClicked: page.resetToDefaults()
    }

    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.disabledTextColor
        text: i18n("Covers every page, including colours and any session nicknames. Takes effect when you press OK or Apply.")
    }

    function resetToDefaults() {
        interval.value = 5
        attention.checked = true
        censorNames.checked = false

        page.cfg_showTotal = true
        page.cfg_countScale = 100
        page.cfg_panelUsage = true
        page.cfg_panelUsageThreshold = 0
        page.cfg_panelUsageColour = true

        page.cfg_maxPopupHeight = 21
        page.cfg_showDone = true
        page.cfg_showUsage = true
        page.cfg_detailRepository = true
        page.cfg_detailBranch = true
        page.cfg_detailSession = true
        page.cfg_detailProcess = true
        page.cfg_detailVersion = true
        page.cfg_branchSeparate = false
        page.cfg_shortLabels = false

        page.cfg_customColors = false
        page.cfg_colorWaiting = Sessions.defaultColor("waiting")
        page.cfg_colorError = Sessions.defaultColor("error")
        page.cfg_colorRunning = Sessions.defaultColor("running")
        page.cfg_colorWorking = Sessions.defaultColor("working")
        page.cfg_colorShell = Sessions.defaultColor("shell")
        page.cfg_colorDone = Sessions.defaultColor("done")

        page.cfg_nicknames = "{}"
        page.cfg_usageProfile = "work"
        page.cfg_usageExpanded = false
        page.cfg_usageBarWork = "session"
        page.cfg_usageBarPersonal = "session"
    }
}
