import QtQuick
import "Singletons"

/**
 * Selectable option tile for the stepped popovers: optional glyph, title with
 * an optional badge chip, a sub line, and a check that pops in when
 * `selected`. `available: false` dims it, drops hover/click and shows `note`
 * where the check would be. `focused` lights it like hover (keyboard
 * navigation).
 */
Rectangle {
    id: tile

    property real s: 1
    property string title: ""
    property string sub: ""
    property string icon: ""
    property color iconTint: Theme.claude
    property string badge: ""
    property color badgeTint: Theme.claude
    property bool selected: false
    property bool available: true
    property string note: ""
    property real tileHeight: 54
    property bool focused: false
    readonly property bool hot: tileArea.containsMouse || focused
    signal picked()

    height: tileHeight * s
    radius: 12 * s
    color: selected ? Qt.alpha(Theme.claude, 0.12) : (hot ? Qt.alpha(Theme.cream, 0.05) : Theme.frameBg)
    border.width: 1
    border.color: selected ? Qt.alpha(Theme.claude, 0.6)
        : (focused ? Qt.alpha(Theme.claude, 0.4) : (hot ? Qt.alpha(Theme.cream, 0.16) : Theme.frameBorder))
    opacity: available ? 1 : 0.45
    scale: tileArea.pressed ? 0.97 : 1
    Behavior on color { ColorAnimation { duration: Motion.fast } }
    Behavior on border.color { ColorAnimation { duration: Motion.fast } }
    Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

    GlyphIcon {
        id: tileIcon
        visible: tile.icon.length > 0
        anchors.left: parent.left
        anchors.leftMargin: 12 * tile.s
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? 15 * tile.s : 0
        height: width
        name: tile.icon
        color: tile.selected ? tile.iconTint : Theme.iconDim
    }

    Column {
        anchors.left: tileIcon.right
        anchors.leftMargin: tile.icon.length > 0 ? 10 * tile.s : 12 * tile.s
        anchors.right: tileEnd.left
        anchors.rightMargin: 6 * tile.s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3 * tile.s

        Row {
            width: parent.width
            spacing: 6 * tile.s
            Text {
                id: titleText
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - (badgeChip.visible ? badgeChip.width + parent.spacing : 0))
                elide: Text.ElideRight
                text: tile.title
                color: tile.selected ? Theme.bright : Theme.cream
                font.family: Theme.font
                font.pixelSize: 12 * tile.s
                font.weight: Font.DemiBold
            }
            Rectangle {
                id: badgeChip
                visible: tile.badge.length > 0
                anchors.verticalCenter: parent.verticalCenter
                width: badgeText.implicitWidth + 10 * tile.s
                height: 15 * tile.s
                radius: height / 2
                color: Qt.alpha(tile.badgeTint, 0.14)
                Text {
                    id: badgeText
                    anchors.centerIn: parent
                    text: tile.badge
                    color: tile.badgeTint
                    font.family: Theme.font
                    font.pixelSize: 8 * tile.s
                    font.weight: Font.Bold
                    font.letterSpacing: 0.4 * tile.s
                    font.capitalization: Font.AllUppercase
                }
            }
        }
        Text {
            visible: tile.sub.length > 0
            width: parent.width
            elide: Text.ElideMiddle
            text: tile.sub
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 9.5 * tile.s
        }
    }

    Item {
        id: tileEnd
        anchors.right: parent.right
        anchors.rightMargin: 10 * tile.s
        anchors.verticalCenter: parent.verticalCenter
        width: tile.available ? 16 * tile.s : noteText.implicitWidth
        height: 16 * tile.s

        Text {
            id: noteText
            visible: !tile.available
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: tile.note
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 9 * tile.s
            font.italic: true
        }

        Rectangle {
            visible: tile.available
            anchors.fill: parent
            radius: width / 2
            color: tile.selected ? Theme.claude : "transparent"
            border.width: tile.selected ? 0 : 1
            border.color: Theme.frameBorder
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            GlyphIcon {
                anchors.centerIn: parent
                width: 10 * tile.s
                height: width
                name: "check"
                stroke: 2.6
                color: Theme.cardBot
                scale: tile.selected ? 1 : 0
                Behavior on scale { NumberAnimation { duration: Motion.standard; easing.type: Easing.OutBack } }
            }
        }
    }

    MouseArea {
        id: tileArea
        anchors.fill: parent
        hoverEnabled: tile.available
        enabled: tile.available
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.picked()
    }
}
