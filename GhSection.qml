import QtQuick
import "Singletons"

/**
 * Small uppercase section heading used by the GitHub detail panes.
 */
Text {
    id: sec

    property real s: 1
    color: Theme.subtle
    font.family: Theme.font
    font.pixelSize: 9.5 * sec.s
    font.weight: Font.Bold
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 1.2 * sec.s
    topPadding: 6 * sec.s
}
