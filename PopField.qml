import QtQuick
import "Singletons"

/**
 * Text field for the stepped popovers: a framed input with an optional
 * leading kanji `glyph`, a `placeholder` and a right-hand `counter`. Emits
 * edited() as the user types, accepted() on Enter and moved(±1) on Up/Down
 * (for list navigation). Set `text` imperatively when resetting: typing
 * replaces any binding on it.
 */
Rectangle {
    id: pf

    property real s: 1
    property alias text: input.text
    property string placeholder: ""
    property string glyph: ""
    property string counter: ""
    readonly property alias input: input
    signal edited()
    signal accepted()
    signal moved(int delta)

    function focusAll() {
        input.forceActiveFocus();
        input.selectAll();
    }

    height: 36 * s
    radius: 10 * s
    color: Theme.frameBg
    border.width: 1
    border.color: input.activeFocus ? Qt.alpha(Theme.claude, 0.6) : Theme.frameBorder
    Behavior on border.color { ColorAnimation { duration: Motion.fast } }

    Text {
        id: lead
        visible: pf.glyph.length > 0
        anchors.left: parent.left
        anchors.leftMargin: 12 * pf.s
        anchors.verticalCenter: parent.verticalCenter
        text: pf.glyph
        color: input.activeFocus ? Theme.claude : Theme.dim
        font.family: Theme.fontJp
        font.weight: Font.Medium
        font.pixelSize: 13 * pf.s
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    TextInput {
        id: input
        anchors.left: lead.right
        anchors.leftMargin: lead.visible ? 9 * pf.s : 0
        anchors.right: count.left
        anchors.rightMargin: 10 * pf.s
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.bright
        selectionColor: Qt.alpha(Theme.claude, 0.4)
        selectByMouse: true
        clip: true
        font.family: Theme.font
        font.pixelSize: 12 * pf.s
        onTextEdited: pf.edited()
        Keys.onReturnPressed: pf.accepted()
        Keys.onEnterPressed: pf.accepted()
        Keys.onUpPressed: pf.moved(-1)
        Keys.onDownPressed: pf.moved(1)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text.length === 0
            text: pf.placeholder
            color: Theme.faint
            font: input.font
        }
    }

    Text {
        id: count
        anchors.right: parent.right
        anchors.rightMargin: 12 * pf.s
        anchors.verticalCenter: parent.verticalCenter
        text: pf.counter
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 10 * pf.s
        font.features: { "tnum": 1 }
    }
}
