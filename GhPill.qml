import QtQuick
import "Singletons"

/**
 * Rounded toggle/action chip used by the GitHub detail panes. `on` lights it in
 * `tint`, `enabledLook` dims it, `hoverable` turns hover/click off.
 */
Rectangle {
    id: pl

    property real s: 1
    property string text: ""
    property color tint: Theme.subtle
    property bool on: false
    property bool enabledLook: true
    property bool hoverable: true
    signal clicked()

    width: plText.implicitWidth + 18 * pl.s
    height: 24 * pl.s
    radius: height / 2
    color: on ? Qt.alpha(tint, 0.2) : (plArea.containsMouse && hoverable ? Qt.alpha(tint, 0.1) : "transparent")
    border.width: 1
    border.color: on ? Qt.alpha(tint, 0.55) : (plArea.containsMouse && hoverable ? Qt.alpha(tint, 0.4) : Theme.frameBorder)
    opacity: enabledLook ? 1 : 0.45
    Behavior on color { ColorAnimation { duration: Motion.fast } }

    Text {
        id: plText
        anchors.centerIn: parent
        text: pl.text
        color: pl.on ? pl.tint : (plArea.containsMouse && pl.hoverable ? Theme.bright : Theme.subtle)
        font.family: Theme.font
        font.pixelSize: 10 * pl.s
        font.weight: pl.on ? Font.Bold : Font.DemiBold
    }
    MouseArea {
        id: plArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: pl.hoverable
        cursorShape: Qt.PointingHandCursor
        onClicked: pl.clicked()
    }
}
