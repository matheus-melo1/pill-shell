import QtQuick
import QtQuick.Controls as QQC
import "Singletons"

/**
 * 務 quick-add surface: the pill grows into a single input for a new task,
 * so one can be jotted down from anywhere without opening the drawer. Enter
 * adds and closes after a short confirmation; Ctrl+Enter adds and stays open
 * for the next one; Esc closes. Shows how many tasks are pending and docks
 * Ame as a soul at the kanji.
 */
PillSurface {
    id: root

    mTop: 14
    mLeft: 20
    mRight: 20
    mBottom: 12

    property bool justAdded: false

    readonly property point kanjiPoint: {
        void root.width;
        void root.height;
        return kanji.mapToItem(root, kanji.width / 2, kanji.height / 2);
    }

    ameForm: open ? "soul" : "off"
    amePoint: kanjiPoint

    function focusField() { field.forceActiveFocus(); }

    onActiveChanged: if (active) {
        field.text = "";
        justAdded = false;
        Qt.callLater(root.focusField);
    }

    function submit(keepOpen) {
        if (!Todo.add(field.text))
            return;
        field.text = "";
        justAdded = true;
        flash.restart();
        if (!keepOpen)
            closeLater.restart();
    }

    Timer {
        id: flash
        interval: 1400
        onTriggered: root.justAdded = false
    }

    Timer {
        id: closeLater
        interval: 450
        onTriggered: root.requestClose()
    }

    Item {
        id: inputRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 34 * root.s

        Text {
            id: kanji
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "務"
            color: root.justAdded ? Theme.ok : Theme.cream
            font.family: Theme.fontJp
            font.weight: Font.Medium
            font.pixelSize: 18 * root.s
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        QQC.TextField {
            id: field
            anchors.left: kanji.right
            anchors.leftMargin: 12 * root.s
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            background: null
            padding: 0
            placeholderText: "Nova tarefa…"
            placeholderTextColor: Theme.faint
            color: Theme.bright
            selectionColor: Qt.alpha(Theme.info, 0.4)
            font.family: Theme.font
            font.pixelSize: 16 * root.s
            Keys.onPressed: (e) => {
                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    root.submit(e.modifiers & Qt.ControlModifier);
                    e.accepted = true;
                }
            }
        }
    }

    Rectangle {
        id: hair
        anchors.top: inputRow.bottom
        anchors.topMargin: 8 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.hair
    }

    Item {
        anchors.top: hair.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6 * root.s
            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 12 * root.s
                height: width
                name: root.justAdded ? "check" : "checklist"
                color: root.justAdded ? Theme.ok : Theme.faint
                stroke: 2.2
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.justAdded ? "Adicionada" : (Todo.open.length + (Todo.open.length === 1 ? " pendente" : " pendentes"))
                color: root.justAdded ? Theme.ok : Theme.dim
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.DemiBold
            }
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Enter adiciona  ·  Ctrl+Enter mais uma  ·  Esc fecha"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 9.5 * root.s
        }
    }
}
