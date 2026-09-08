import QtQuick
import org.kde.plasma.configuration

// Organised by where a setting takes effect rather than by what type of thing it
// is — the same split the widely-used plasmoids settle on once they have both a
// panel and a popup to configure. A colour page of its own, because six pickers
// swamp whatever page they land on.
ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "preferences-system-windows-behavior"
        source: "ConfigGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Panel")
        icon: "preferences-system-windows-effect-screenedge"
        source: "ConfigPanel.qml"
    }
    ConfigCategory {
        name: i18n("Popup")
        icon: "preferences-system-windows-effect-slidingpopups"
        source: "ConfigPopup.qml"
    }
    ConfigCategory {
        name: i18n("Colours")
        icon: "preferences-desktop-color"
        source: "ConfigColours.qml"
    }
}
