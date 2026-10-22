pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

/**
 * Summary strip for the last step of a stepped popover: one chip per entry of
 * `chips` ({ k, t }); clicking a chip emits jump(k) so the owner can go back
 * to the step that set it.
 */
Rectangle {
    id: sum

    property real s: 1
    property var chips: []
    signal jump(int k)

    height: flow.implicitHeight + 16 * s
    radius: 10 * s
    color: Qt.rgba(0, 0, 0, 0.22)

    Flow {
        id: flow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 10 * sum.s
        anchors.rightMargin: 10 * sum.s
        spacing: 6 * sum.s

        Repeater {
            model: sum.chips
            Rectangle {
                id: chip
                required property var modelData
                width: Math.min(chipText.implicitWidth + 14 * sum.s, flow.width)
                height: 20 * sum.s
                radius: height / 2
                color: chipArea.containsMouse ? Qt.alpha(Theme.claude, 0.16) : Theme.frameBg
                border.width: 1
                border.color: Theme.frameBorder
                Text {
                    id: chipText
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, flow.width - 14 * sum.s)
                    elide: Text.ElideMiddle
                    text: chip.modelData.t
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 9.5 * sum.s
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    id: chipArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sum.jump(chip.modelData.k)
                }
            }
        }
    }
}
