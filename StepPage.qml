import QtQuick
import "Singletons"

/**
 * One page of a StepTrack: a column of content at `page`, sliding on the morph
 * curve to its place in the track's `path` relative to `pos`.
 */
Item {
    id: pg

    property int page: 0
    property alias spacing: col.spacing
    default property alias content: col.data

    readonly property Item track: parent ? parent.parent : null
    readonly property int at: track ? track.path.indexOf(page) : -1

    width: track ? track.width : 0
    implicitHeight: col.implicitHeight
    height: implicitHeight
    x: track ? (at >= 0 ? at - track.pos : 2) * width : 0
    visible: at >= 0
    Behavior on x { NumberAnimation { duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve } }

    Column {
        id: col
        width: parent.width
        spacing: 10
    }
}
