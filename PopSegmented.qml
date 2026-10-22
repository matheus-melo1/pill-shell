pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

/**
 * Segmented control for the stepped popovers: equal cells for `options`
 * ({ key, text }), a highlight that slides to `value` on the morph curve, and
 * picked(key) on click.
 */
Rectangle {
    id: seg

    property real s: 1
    property var options: []
    property string value: ""
    signal picked(string key)

    readonly property int index: Math.max(0, options.findIndex(function(o) { return o.key === seg.value; }))
    readonly property real cellW: options.length ? (width - 6 * s) / options.length : 0

    height: 34 * s
    radius: 11 * s
    color: Theme.frameBg
    border.width: 1
    border.color: Theme.frameBorder

    Rectangle {
        visible: seg.options.some(function(o) { return o.key === seg.value; })
        x: 3 * seg.s + seg.index * seg.cellW
        y: 3 * seg.s
        width: seg.cellW
        height: parent.height - 6 * seg.s
        radius: 8 * seg.s
        color: Qt.alpha(Theme.claude, 0.18)
        border.width: 1
        border.color: Qt.alpha(Theme.claude, 0.55)
        Behavior on x { NumberAnimation { duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve } }
    }

    Row {
        x: 3 * seg.s
        anchors.verticalCenter: parent.verticalCenter
        Repeater {
            model: seg.options
            Item {
                id: cell
                required property var modelData
                readonly property bool on: seg.value === modelData.key
                width: seg.cellW
                height: 28 * seg.s
                Text {
                    anchors.centerIn: parent
                    text: cell.modelData.text
                    color: cell.on ? Theme.claude : (cellArea.containsMouse ? Theme.bright : Theme.subtle)
                    font.family: Theme.font
                    font.pixelSize: 10.5 * seg.s
                    font.weight: cell.on ? Font.Bold : Font.DemiBold
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
                MouseArea {
                    id: cellArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.picked(cell.modelData.key)
                }
            }
        }
    }
}
