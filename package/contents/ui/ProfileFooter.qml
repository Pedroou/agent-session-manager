import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

import "../code/usage.js" as Usage

// How much of the plan each account has used. Collapsed it shows the one account
// you picked; expanded, all of them - because the reason to open it is to
// compare them.
ColumnLayout {
    id: footer

    property var widget

    // How much of the popup's width the list's scrollbar is occupying, so the
    // footer can stop short of it and stay lined up with the rows.
    property real scrollbarInset: 0

    // Whether the rule above the accounts is drawn. It exists to divide the
    // footer from the session list; with no sessions there is nothing to divide.
    // Hidden by opacity, not visibility, so it keeps its room: the popup's
    // height is fixed on purpose and must not shift when the last session ends.
    property bool showRule: true

    readonly property var usage: widget ? widget.usage : null
    readonly property bool expanded: plasmoid.configuration.usageExpanded
    // Most recently shown first. The account on screen is always the newest
    // entry in that history, so it sits on top, and the one before it second.
    readonly property var profiles: Usage.byRecency(Usage.selectableProfiles(usage),
                                                    widget ? widget.usageRecent : [])
    // Resolved rather than read straight off the setting: the account that was
    // selected can be renamed away or removed, and a stale id would leave the
    // footer showing nothing at all.
    readonly property string selected: Usage.selectedId(usage, plasmoid.configuration.usageProfile)

    // Two accounts fit; past that the list scrolls rather than pushing the
    // session list out of the popup. Measured from the tallest thing on a row -
    // the limit picker - rather than from a delegate, which does not exist yet
    // when the popup is asking how tall it needs to be.
    readonly property int visibleRows: 2
    readonly property real rowHeight: Kirigami.Units.iconSizes.medium
                                      + Kirigami.Units.smallSpacing * 2
    readonly property int shownRows: expanded ? Math.max(1, Math.min(profiles.length, visibleRows))
                                              : 1

    // Both chevrons on a row measure from here. One is a bare icon and the other
    // is a button's icon, which are sized by different rules - so the size is
    // stated once rather than twice in units that happen to disagree.
    readonly property real chevron: Kirigami.Units.iconSizes.small

    spacing: 0

    // Kept on the widget rather than here: the choice is stored per config
    // directory, and the panel view has to read the same map.
    function barIdFor(profileId) {
        return footer.widget ? footer.widget.barIdFor(profileId) : ""
    }

    function setBarFor(profileId, barId) {
        if (footer.widget) {
            footer.widget.setBarFor(profileId, barId)
        }
    }

    Kirigami.Separator {
        opacity: footer.showRule ? 1 : 0
        Layout.fillWidth: true
        // The popup pads its own edges more generously than a row pads itself, so
        // without this the footer sits hard up against the rule while having room
        // to spare on every other side.
        Layout.bottomMargin: Kirigami.Units.largeSpacing
    }

    PlasmaComponents3.ScrollView {
        id: scroller
        Layout.fillWidth: true
        Layout.preferredHeight: footer.rowHeight * footer.shownRows
        implicitHeight: footer.rowHeight * footer.shownRows
        PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

        ListView {
            id: accounts
            model: footer.profiles
            spacing: 0
            clip: true
            reuseItems: false

            delegate: Item {
                id: profileRow
                required property var modelData

                // Collapsed, only the chosen account is on screen; the others
                // are one click away rather than gone. Given no height rather
                // than filtered out of the model, so expanding is the same list
                // growing rather than a different one being built.
                readonly property bool isSelected: modelData.id === footer.selected
                visible: footer.expanded || isSelected

                width: accounts.width
                height: visible ? footer.rowHeight : 0

                readonly property var bar: Usage.barFor(modelData, footer.barIdFor(modelData.id))
                readonly property string message: Usage.stateMessage(modelData)

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing / 2
                    radius: Math.round(Kirigami.Units.gridUnit / 4)
                    color: Kirigami.Theme.textColor
                    opacity: rowHover.hovered ? 0.09 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: Kirigami.Units.shortDuration }
                    }
                }

                HoverHandler {
                    id: rowHover
                }

                // Not over the limit picker: it has a tooltip of its own, and two
                // at once would stack.
                PlasmaComponents3.ToolTip.text: limit.hint
                PlasmaComponents3.ToolTip.visible: rowHover.hovered && !picker.hovered
                                                   && !barMenu.opened && limit.hint !== ""
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        // Picking an account that is already showing collapses
                        // the list again; picking another one selects it.
                        if (!footer.expanded) {
                            plasmoid.configuration.usageExpanded = true
                        } else if (profileRow.isSelected) {
                            plasmoid.configuration.usageExpanded = false
                        } else {
                            plasmoid.configuration.usageProfile = profileRow.modelData.id
                            plasmoid.configuration.usageExpanded = false
                        }
                    }
                }

                RowLayout {
                    id: line
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    // Matched to SessionRow's own margins so the footer lines up
                    // with the list above it.
                    anchors.leftMargin: Kirigami.Units.largeSpacing
                    anchors.rightMargin: Kirigami.Units.largeSpacing + footer.scrollbarInset
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: footer.expanded ? "go-down-symbolic" : "go-next-symbolic"
                        implicitWidth: footer.chevron
                        implicitHeight: footer.chevron
                        opacity: profileRow.isSelected ? 1 : 0
                        Layout.alignment: Qt.AlignVCenter
                    }

                    PlasmaComponents3.Label {
                        text: Usage.displayName(profileRow.modelData)
                        // Piecemeal: assigning the whole `font` group and one of
                        // its members in the same object is a QML error.
                        font.family: Kirigami.Theme.smallFont.family
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        font.weight: profileRow.isSelected ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        Layout.minimumWidth: Kirigami.Units.gridUnit * 3.5
                        Layout.maximumWidth: Kirigami.Units.gridUnit * 7
                        Layout.alignment: Qt.AlignVCenter
                    }

                    // The bar-type picker. It sits on every row, including the
                    // ones not currently selected, so you can set them up
                    // without switching to them first.
                    PlasmaComponents3.ToolButton {
                        id: picker
                        // Not another chevron: one arrow already means "this is
                        // the selected account", and a second one beside it read
                        // as a repeat rather than as a different control. An
                        // overflow mark says "there are options behind this",
                        // which is the job.
                        icon.name: "overflow-menu"
                        icon.width: footer.chevron
                        icon.height: footer.chevron
                        display: PlasmaComponents3.AbstractButton.IconOnly
                        flat: true
                        enabled: profileRow.modelData.bars.length > 0
                        implicitWidth: Kirigami.Units.iconSizes.medium
                        implicitHeight: Kirigami.Units.iconSizes.medium
                        text: i18n("Choose which limit to show")
                        onClicked: barMenu.open()

                        PlasmaComponents3.ToolTip.text: text
                        PlasmaComponents3.ToolTip.visible: hovered
                        PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay

                        PlasmaComponents3.Menu {
                            id: barMenu
                            y: parent.height

                            Repeater {
                                model: profileRow.modelData.bars
                                delegate: PlasmaComponents3.MenuItem {
                                    required property var modelData
                                    text: modelData.label
                                    // Not checkboxes. Only one limit can be
                                    // shown at a time, so a set of boxes
                                    // promises a choice the control does not
                                    // offer - the current one is marked the way
                                    // the selected account is marked above.
                                    font.weight: profileRow.bar
                                                 && modelData.id === profileRow.bar.id
                                                 ? Font.DemiBold : Font.Normal
                                    onTriggered: footer.setBarFor(profileRow.modelData.id, modelData.id)
                                }
                            }
                        }
                    }

                    UsageBar {
                        id: limit
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        bar: profileRow.bar
                        message: profileRow.message
                        stale: profileRow.modelData.stale === true
                        since: profileRow.modelData.since || 0
                        now: footer.widget ? footer.widget.now : Date.now()
                    }
                }
            }
        }
    }
}
