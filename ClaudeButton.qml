import QtQuick
import "Singletons"

/**
 * Claude glyph button that opens the stepped popovers. With a background
 * `job` ({ state }) it takes that state's colour (working / done / dead) and
 * shows a corner dot, pulsing while it runs; `open` keeps it lit while its
 * popover is up. The glyph turns on hover.
 */
Rectangle {
    id: cb

    property real s: 1
    property real size: 26
    property var job: null
    property bool open: false
    signal clicked()

    readonly property color tone: !job ? Theme.claude
        : (job.state === "idle" ? Theme.ok : (job.state === "dead" ? Theme.danger : Theme.claude))
    readonly property bool lit: cbArea.containsMouse || open

    width: size * s
    height: width
    radius: width * 0.31
    color: lit ? Qt.alpha(tone, 0.18) : (job ? Qt.alpha(tone, 0.10) : "transparent")
    border.width: 1
    border.color: lit ? Qt.alpha(tone, 0.55) : (job ? Qt.alpha(tone, 0.32) : Theme.frameBorder)
    scale: cbArea.pressed ? 0.92 : 1
    Behavior on color { ColorAnimation { duration: Motion.fast } }
    Behavior on border.color { ColorAnimation { duration: Motion.fast } }
    Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

    GlyphIcon {
        anchors.centerIn: parent
        width: cb.width * 0.5
        height: width
        name: "claude"
        color: cb.lit || cb.job ? cb.tone : Theme.iconDim
        rotation: cbArea.containsMouse ? 45 : 0
        Behavior on rotation { NumberAnimation { duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve } }
    }

    Rectangle {
        id: dot
        visible: cb.job !== null
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: -2 * cb.s
        width: 6 * cb.s
        height: width
        radius: width / 2
        color: cb.tone
        SequentialAnimation on opacity {
            running: cb.job !== null && (cb.job.state === "busy" || cb.job.state === "starting") && cb.visible
            loops: Animation.Infinite
            onRunningChanged: if (!running) dot.opacity = 1
            NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
        }
    }

    MouseArea {
        id: cbArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: cb.clicked()
    }
}
