pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

/**
 * Progress header for the stepped popovers: one segment per entry of `names`,
 * filled up to `pos` (the current one bright, past ones dimmer) on the morph
 * curve, over "Passo N de M · <name>".
 */
Column {
    id: prog

    property real s: 1
    property var names: []
    property int pos: 0

    spacing: 8 * s

    Row {
        id: segs
        width: parent.width
        spacing: 4 * prog.s
        Repeater {
            model: prog.names.length
            Rectangle {
                id: seg
                required property int index
                width: (segs.width - (prog.names.length - 1) * segs.spacing) / Math.max(1, prog.names.length)
                height: 3 * prog.s
                radius: height / 2
                color: Theme.threadBg
                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    width: seg.index <= prog.pos ? parent.width : 0
                    color: seg.index === prog.pos ? Theme.claude : Qt.alpha(Theme.claude, 0.5)
                    Behavior on width { NumberAnimation { duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve } }
                    Behavior on color { ColorAnimation { duration: Motion.standard } }
                }
            }
        }
    }

    Row {
        spacing: 6 * prog.s
        Text {
            text: "Passo " + (prog.pos + 1) + " de " + prog.names.length
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10 * prog.s
            font.features: { "tnum": 1 }
        }
        Text {
            text: "·"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10 * prog.s
        }
        Text {
            text: prog.names[prog.pos] || ""
            color: Theme.bright
            font.family: Theme.font
            font.pixelSize: 10 * prog.s
            font.weight: Font.Bold
        }
    }
}
