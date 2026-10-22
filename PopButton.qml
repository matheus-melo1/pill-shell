import QtQuick
import "Singletons"

/**
 * Button for the stepped popovers: outlined, or filled in `tint` when
 * `primary`. `active: false` dims it and turns clicks off.
 */
Rectangle {
    id: btn

    property real s: 1
    property string text: ""
    property color tint: Theme.claude
    property bool primary: false
    property bool active: true
    signal clicked()

    width: btnText.implicitWidth + 26 * s
    height: 30 * s
    radius: 10 * s
    color: primary ? (btnArea.containsMouse && active ? Qt.lighter(tint, 1.12) : tint)
        : (btnArea.containsMouse && active ? Qt.alpha(tint, 0.12) : "transparent")
    border.width: primary ? 0 : 1
    border.color: btnArea.containsMouse && active ? Qt.alpha(tint, 0.45) : Theme.frameBorder
    opacity: active ? 1 : 0.5
    scale: btnArea.pressed && active ? 0.96 : 1
    Behavior on color { ColorAnimation { duration: Motion.fast } }
    Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
    Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

    Text {
        id: btnText
        anchors.centerIn: parent
        text: btn.text
        color: btn.primary ? Theme.cardBot : (btnArea.containsMouse && btn.active ? Theme.bright : Theme.subtle)
        font.family: Theme.font
        font.pixelSize: 11 * btn.s
        font.weight: btn.primary ? Font.Bold : Font.DemiBold
    }
    MouseArea {
        id: btnArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: btn.active
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
