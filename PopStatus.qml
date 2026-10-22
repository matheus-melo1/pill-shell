import QtQuick
import "Singletons"

/**
 * Live-state card for the stepped popovers: a dot (pulsing while `pulse`) and
 * `text` in `tint`, over a `detail` line, on a wash of the same tint.
 */
Rectangle {
    id: ps

    property real s: 1
    property string text: ""
    property string detail: ""
    property color tint: Theme.claude
    property bool pulse: false

    height: col.implicitHeight + 24 * s
    radius: 12 * s
    color: Qt.alpha(tint, 0.08)
    border.width: 1
    border.color: Qt.alpha(tint, 0.28)
    Behavior on color { ColorAnimation { duration: Motion.standard } }

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 12 * ps.s
        anchors.rightMargin: 12 * ps.s
        spacing: 5 * ps.s

        Row {
            spacing: 8 * ps.s
            Rectangle {
                id: dot
                anchors.verticalCenter: parent.verticalCenter
                width: 8 * ps.s
                height: width
                radius: width / 2
                color: ps.tint
                SequentialAnimation on opacity {
                    running: ps.pulse
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) dot.opacity = 1
                    NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ps.text
                color: ps.tint
                font.family: Theme.font
                font.pixelSize: 12.5 * ps.s
                font.weight: Font.Bold
            }
        }
        Text {
            visible: ps.detail.length > 0
            width: parent.width
            elide: Text.ElideRight
            text: ps.detail
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 10 * ps.s
        }
    }
}
