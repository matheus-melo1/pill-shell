pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "Singletons"

/**
 * Popover card for the GitHub panes (Claude review / issue handoff). Fill it
 * over the host; place(trigger) hangs the card under the trigger (above when
 * `expectH` does not fit), right-aligned to it, and it scales in from that
 * corner on the morph curve. Header: a tinted `icon`, `kicker` and
 * `subtitle`, a close button, then `title` (two lines) and the owner's content
 * (the default property). The card snaps to size when it opens and morphs its
 * height afterwards, clipping content while it does. A press outside calls
 * hide(); the owner routes Escape to it too.
 */
Item {
    id: shell

    property real s: 1
    property bool shown: false
    property bool below: true
    property real anchorX: 0
    property real anchorTop: 0
    property real anchorBottom: 0

    property string icon: "claude"
    property color tint: Theme.claude
    property string kicker: ""
    property string subtitle: ""
    property string title: ""
    property real cardWidth: 324 * s
    property real expectH: 360 * s

    default property alias content: body.data

    visible: card.opacity > 0.01

    function place(trigger) {
        var p = trigger.mapToItem(shell, 0, 0);
        anchorX = p.x + trigger.width;
        anchorTop = p.y;
        anchorBottom = p.y + trigger.height;
        below = anchorBottom + expectH < height;
    }

    function hide() {
        shown = false;
    }

    MouseArea {
        anchors.fill: parent
        enabled: shell.shown
        acceptedButtons: Qt.AllButtons
        onPressed: shell.hide()
    }

    Rectangle {
        id: card
        width: shell.cardWidth
        height: col.implicitHeight + 32 * shell.s
        x: Math.max(0, Math.min(shell.width - width, shell.anchorX - width))
        y: shell.below ? Math.min(shell.anchorBottom + 8 * shell.s, shell.height - height)
            : Math.max(0, shell.anchorTop - 8 * shell.s - height)
        radius: 18 * shell.s
        border.width: 1
        border.color: Qt.rgba(0.88, 0.88, 0.88, 0.12)
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.cardTop }
            GradientStop { position: 1.0; color: Theme.cardBot }
        }

        opacity: shell.shown ? 1 : 0
        scale: shell.shown ? 1 : 0.92
        transformOrigin: shell.below ? Item.TopRight : Item.BottomRight
        Behavior on opacity { NumberAnimation { duration: Motion.glide; easing.type: Motion.easeStandard } }
        Behavior on scale { NumberAnimation { duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve } }
        // Snap to size on open; morph only between steps / views.
        Behavior on height {
            enabled: shell.shown && card.opacity > 0.99
            NumberAnimation { duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowBlur: 0.9
            shadowVerticalOffset: 6 * shell.s
        }

        // swallow presses so the backdrop does not close the card
        MouseArea { anchors.fill: parent }

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 1
            anchors.leftMargin: 14 * shell.s
            anchors.rightMargin: 14 * shell.s
            height: 1
            color: Theme.sheen
        }

        // Clips the content while the card's height morphs.
        Item {
            anchors.fill: parent
            anchors.margins: 1
            clip: true

            Column {
                id: col
                x: 15 * shell.s
                y: 15 * shell.s
                width: card.width - 32 * shell.s
                spacing: 12 * shell.s

                Item {
                    width: parent.width
                    height: 30 * shell.s

                    Rectangle {
                        id: hdrIcon
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30 * shell.s
                        height: width
                        radius: 10 * shell.s
                        color: Qt.alpha(shell.tint, 0.14)
                        GlyphIcon {
                            anchors.centerIn: parent
                            width: 15 * shell.s
                            height: width
                            name: shell.icon
                            color: shell.tint
                        }
                    }
                    Column {
                        anchors.left: hdrIcon.right
                        anchors.leftMargin: 10 * shell.s
                        anchors.right: closeBtn.left
                        anchors.rightMargin: 8 * shell.s
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2 * shell.s
                        Text {
                            text: shell.kicker
                            color: Theme.subtle
                            font.family: Theme.font
                            font.pixelSize: 9 * shell.s
                            font.weight: Font.Bold
                            font.letterSpacing: 1.2 * shell.s
                            font.capitalization: Font.AllUppercase
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: shell.subtitle
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 10 * shell.s
                            font.features: { "tnum": 1 }
                        }
                    }
                    Rectangle {
                        id: closeBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26 * shell.s
                        height: width
                        radius: 8 * shell.s
                        color: closeArea.containsMouse ? Theme.frameBg : "transparent"
                        GlyphIcon {
                            anchors.centerIn: parent
                            width: 12 * shell.s
                            height: width
                            name: "x"
                            stroke: 2
                            color: closeArea.containsMouse ? Theme.cream : Theme.iconDim
                        }
                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: shell.hide()
                        }
                    }
                }

                Text {
                    visible: shell.title.length > 0
                    width: parent.width
                    text: shell.title
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    lineHeight: 1.12
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 12 * shell.s
                    font.weight: Font.Medium
                }

                Item {
                    id: body
                    width: parent.width
                    height: childrenRect.height
                }
            }
        }
    }
}
