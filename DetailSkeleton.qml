pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

/**
 * Loading placeholder for the GitHub detail panes, shaped like the real
 * layout: title, state/author row, status card, field rows, chips and
 * description lines, all sharing one shimmer phase.
 */
Column {
    id: skeleton

    property real s: 1
    spacing: 12 * skeleton.s

    // One sweep phase shared by every block so the shine moves together.
    property real phase: 0
    NumberAnimation on phase {
        running: skeleton.visible
        from: 0; to: 1
        duration: 1300
        loops: Animation.Infinite
        easing.type: Easing.InOutQuad
    }

    component SkBone: Bone {
        s: skeleton.s
        phase: skeleton.phase
    }

    // title (two lines)
    SkBone { w: 0.92; height: 18 * skeleton.s }
    SkBone { w: 0.58; height: 18 * skeleton.s }

    // state chip, avatar, meta
    Row {
        spacing: 8 * skeleton.s
        SkBone { width: 70 * skeleton.s; height: 22 * skeleton.s; radius: 11 * skeleton.s }
        SkBone { width: 20 * skeleton.s; height: 20 * skeleton.s; radius: 10 * skeleton.s }
        SkBone { width: 220 * skeleton.s; height: 12 * skeleton.s; anchors.verticalCenter: parent.verticalCenter }
    }

    // status card
    Rectangle {
        width: parent.width
        height: 96 * skeleton.s
        radius: 14 * skeleton.s
        color: Theme.frameBg
        border.width: 1
        border.color: Theme.frameBorder

        Column {
            anchors.fill: parent
            anchors.margins: 12 * skeleton.s
            spacing: 14 * skeleton.s
            SkBone { w: 0.32; height: 10 * skeleton.s }
            Row {
                spacing: 8 * skeleton.s
                Repeater {
                    model: [62, 54, 50, 96, 58, 34, 46]
                    SkBone {
                        required property int modelData
                        width: modelData * skeleton.s
                        height: 24 * skeleton.s
                        radius: 12 * skeleton.s
                    }
                }
            }
        }
    }

    // field rows
    Repeater {
        model: [[0.2, 0.3], [0.12, 0.16], [0.16, 0.24], [0.2, 0.1]]
        Item {
            id: fieldRow
            required property var modelData
            width: skeleton.width
            height: 30 * skeleton.s
            SkBone {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: skeleton.width * fieldRow.modelData[0]
            }
            SkBone {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: skeleton.width * fieldRow.modelData[1]
                height: 22 * skeleton.s
                radius: 11 * skeleton.s
            }
        }
    }

    // labels / assignees
    Row {
        spacing: 6 * skeleton.s
        SkBone { width: 104 * skeleton.s; height: 24 * skeleton.s; radius: 12 * skeleton.s }
        SkBone { width: 44 * skeleton.s; height: 24 * skeleton.s; radius: 12 * skeleton.s }
    }

    // description
    SkBone { w: 0.18; height: 10 * skeleton.s }
    Repeater {
        model: [1, 0.96, 0.88, 0.94, 0.7, 0.9, 0.82, 0.45]
        SkBone {
            required property real modelData
            w: modelData
        }
    }
}
