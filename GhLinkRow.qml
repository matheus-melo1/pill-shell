import QtQuick
import "Singletons"

/**
 * Clickable row with an icon, text and a small right-aligned meta tag; opens
 * `url` in the browser unless `clicked` is handled (set `external: false`).
 */
Rectangle {
    id: lr

    property real s: 1
    property string icon: ""
    property color iconColor: Theme.subtle
    property string text: ""
    property string meta: ""
    property color metaColor: Theme.dim
    property string url: ""
    property bool external: true
    signal clicked()
    width: parent ? parent.width : 0
    height: 32 * lr.s
    radius: 9 * lr.s
    color: lrArea.containsMouse ? Theme.frameBg : "transparent"

    GlyphIcon {
        id: lrIcon
        anchors.left: parent.left
        anchors.leftMargin: 8 * lr.s
        anchors.verticalCenter: parent.verticalCenter
        width: 13 * lr.s
        height: width
        name: lr.icon
        color: lr.iconColor
        stroke: 2
    }
    Text {
        anchors.left: lrIcon.right
        anchors.leftMargin: 9 * lr.s
        anchors.right: lrMeta.left
        anchors.rightMargin: 8 * lr.s
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: lr.text
        color: lrArea.containsMouse ? Theme.bright : Theme.cream
        font.family: Theme.font
        font.pixelSize: 11.5 * lr.s
    }
    Text {
        id: lrMeta
        anchors.right: parent.right
        anchors.rightMargin: 8 * lr.s
        anchors.verticalCenter: parent.verticalCenter
        text: lr.meta
        color: lr.metaColor
        font.family: Theme.font
        font.pixelSize: 9 * lr.s
        font.weight: Font.Bold
        font.capitalization: Font.AllUppercase
    }
    MouseArea {
        id: lrArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: lr.external ? Qt.openUrlExternally(lr.url) : lr.clicked()
    }
}
