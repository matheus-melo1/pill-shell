pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import "Singletons"

/**
 * 務 TAREFAS route of the drawer: the plain to-do list. An add field on top
 * (Enter adds), the open tasks in the user's order, and a collapsible
 * "Concluídas" section with a clear action.
 *
 * A task row has a round check that fills and strikes the text when done,
 * the text (double-click to edit in place, Enter saves, Esc cancels, an empty
 * edit deletes), a drag grip and a hover delete. Reordering drags the grip:
 * the row dims and a line marks where it will land, and the move is
 * committed on release, so the list isn't rebuilt under the pointer.
 */
Item {
    id: root

    property real s: 1
    property bool open: false

    opacity: open ? 1 : 0
    visible: opacity > 0.01
    enabled: open
    Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

    property bool showDone: false
    property string editingId: ""
    property bool confirmClear: false

    // drag state
    property int dragFrom: -1
    property int dragTo: -1

    onOpenChanged: if (open) {
        editingId = "";
        Qt.callLater(function() { addField.forceActiveFocus(); });
    } else {
        confirmClear = false;
    }

    Timer {
        id: clearTimeout
        interval: 3500
        onTriggered: root.confirmClear = false
    }

    function addNow() {
        if (Todo.add(addField.text))
            addField.text = "";
    }

    /** Open-list index whose row the given y (in openCol coords) falls on. */
    function indexAtY(y) {
        var n = openRepeater.count;
        for (var i = 0; i < n; i++) {
            var it = openRepeater.itemAt(i);
            if (it && y < it.y + it.height / 2)
                return i;
        }
        return Math.max(0, n - 1);
    }

    component Check: Rectangle {
        id: ck
        property bool checked: false
        signal toggled()
        width: 20 * root.s
        height: width
        radius: width / 2
        color: checked ? Theme.ok : "transparent"
        border.width: 1.5 * root.s
        border.color: checked ? Theme.ok : (ckArea.containsMouse ? Theme.cream : Theme.faint)
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        GlyphIcon {
            anchors.centerIn: parent
            width: 12 * root.s
            height: width
            name: "check"
            color: Theme.cardBot
            stroke: 2.8
            opacity: ck.checked ? 1 : 0
            scale: ck.checked ? 1 : 0.5
            Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutBack } }
        }
        GlyphIcon {
            anchors.centerIn: parent
            width: 11 * root.s
            height: width
            name: "check"
            color: Theme.faint
            stroke: 2.4
            visible: !ck.checked && ckArea.containsMouse
        }
        MouseArea {
            id: ckArea
            anchors.fill: parent
            anchors.margins: -5 * root.s
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ck.toggled()
        }
    }

    component TaskRow: Item {
        id: row
        required property var modelData
        required property int index
        property bool draggable: true
        readonly property var t: modelData
        readonly property bool editing: root.editingId === t.id
        readonly property bool dragging: draggable && root.dragFrom === index

        width: parent ? parent.width : 0
        height: Math.max(44 * root.s, label.implicitHeight + 24 * root.s)
        opacity: dragging ? 0.35 : 1

        Rectangle {
            anchors.fill: parent
            radius: 12 * root.s
            color: rowHover.hovered || row.editing ? Theme.frameBg : "transparent"
            border.width: row.editing ? 1 : 0
            border.color: Qt.alpha(Theme.cream, 0.2)
        }
        HoverHandler { id: rowHover }

        Check {
            id: check
            anchors.left: parent.left
            anchors.leftMargin: 10 * root.s
            anchors.verticalCenter: parent.verticalCenter
            checked: row.t.done
            onToggled: Todo.toggle(row.t.id)
        }

        Text {
            id: label
            visible: !row.editing
            anchors.left: check.right
            anchors.leftMargin: 12 * root.s
            anchors.right: actions.left
            anchors.rightMargin: 8 * root.s
            anchors.verticalCenter: parent.verticalCenter
            wrapMode: Text.Wrap
            text: row.t.text
            color: row.t.done ? Theme.faint : Theme.cream
            font.family: Theme.font
            font.pixelSize: 13 * root.s
            font.strikeout: row.t.done
            lineHeight: 1.1

            MouseArea {
                anchors.fill: parent
                onDoubleClicked: if (!row.t.done) {
                    root.editingId = row.t.id;
                    Qt.callLater(function() {
                        editor.text = row.t.text;
                        editor.forceActiveFocus();
                        editor.selectAll();
                    });
                }
            }
        }

        QQC.TextField {
            id: editor
            visible: row.editing
            anchors.left: check.right
            anchors.leftMargin: 8 * root.s
            anchors.right: actions.left
            anchors.rightMargin: 8 * root.s
            anchors.verticalCenter: parent.verticalCenter
            background: null
            color: Theme.bright
            selectionColor: Qt.alpha(Theme.info, 0.4)
            font.family: Theme.font
            font.pixelSize: 13 * root.s
            onAccepted: {
                Todo.edit(row.t.id, text);
                root.editingId = "";
                addField.forceActiveFocus();
            }
            Keys.onEscapePressed: (e) => {
                root.editingId = "";
                addField.forceActiveFocus();
                e.accepted = true;
            }
            onActiveFocusChanged: if (!activeFocus && row.editing) {
                Todo.edit(row.t.id, text);
                root.editingId = "";
            }
        }

        Row {
            id: actions
            anchors.right: parent.right
            anchors.rightMargin: 6 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2 * root.s
            opacity: rowHover.hovered && !row.editing ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }

            Rectangle {
                width: 26 * root.s
                height: width
                radius: 8 * root.s
                color: delArea.containsMouse ? Qt.alpha(Theme.danger, 0.16) : "transparent"
                GlyphIcon {
                    anchors.centerIn: parent
                    width: 12 * root.s
                    height: width
                    name: "x"
                    color: delArea.containsMouse ? Theme.danger : Theme.iconDim
                    stroke: 2.2
                }
                MouseArea {
                    id: delArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Todo.remove(row.t.id)
                }
            }

            Item {
                visible: row.draggable
                width: 22 * root.s
                height: 26 * root.s
                GlyphIcon {
                    anchors.centerIn: parent
                    width: 16 * root.s
                    height: width
                    name: "grip"
                    color: gripArea.pressed ? Theme.cream : Theme.faint
                    stroke: 3
                }
                MouseArea {
                    id: gripArea
                    anchors.fill: parent
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    preventStealing: true
                    onPressed: {
                        root.dragFrom = row.index;
                        root.dragTo = row.index;
                    }
                    onPositionChanged: (m) => {
                        var p = mapToItem(openCol, m.x, m.y);
                        root.dragTo = root.indexAtY(p.y);
                    }
                    onReleased: {
                        var from = root.dragFrom, to = root.dragTo;
                        root.dragFrom = -1;
                        root.dragTo = -1;
                        Todo.move(from, to);
                    }
                    onCanceled: {
                        root.dragFrom = -1;
                        root.dragTo = -1;
                    }
                }
            }
        }
    }

    // ---- header ----
    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 24 * root.s

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * root.s
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "務"
                color: Theme.cream
                font.family: Theme.fontJp
                font.weight: Font.Medium
                font.pixelSize: 16 * root.s
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "TAREFAS"
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.DemiBold
                font.letterSpacing: 1.6 * root.s
            }
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: Todo.open.length === 0 ? "tudo feito" : Todo.open.length + (Todo.open.length === 1 ? " pendente" : " pendentes")
            color: Todo.open.length === 0 ? Theme.ok : Theme.dim
            font.family: Theme.font
            font.pixelSize: 10 * root.s
            font.weight: Font.Bold
        }
    }

    // ---- add field ----
    Rectangle {
        id: addBox
        anchors.top: header.bottom
        anchors.topMargin: 16 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 46 * root.s
        radius: 14 * root.s
        color: Theme.frameBg
        border.width: 1
        border.color: addField.activeFocus ? Qt.alpha(Theme.cream, 0.22) : Theme.frameBorder

        GlyphIcon {
            id: plusIcon
            anchors.left: parent.left
            anchors.leftMargin: 14 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 16 * root.s
            height: width
            name: "plus"
            color: addField.activeFocus ? Theme.cream : Theme.faint
            stroke: 2.2
        }
        QQC.TextField {
            id: addField
            anchors.left: plusIcon.right
            anchors.leftMargin: 10 * root.s
            anchors.right: parent.right
            anchors.rightMargin: 14 * root.s
            anchors.verticalCenter: parent.verticalCenter
            background: null
            placeholderText: "Adicionar tarefa…  (Enter)"
            placeholderTextColor: Theme.faint
            color: Theme.bright
            selectionColor: Qt.alpha(Theme.info, 0.4)
            font.family: Theme.font
            font.pixelSize: 13.5 * root.s
            onAccepted: root.addNow()
        }
    }

    // ---- list ----
    Flickable {
        id: list
        anchors.top: addBox.bottom
        anchors.topMargin: 14 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: listCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: root.dragFrom < 0

        Column {
            id: listCol
            width: list.width
            spacing: 4 * root.s

            Item {
                width: parent.width
                height: openCol.implicitHeight

                Column {
                    id: openCol
                    width: parent.width
                    spacing: 2 * root.s

                    Repeater {
                        id: openRepeater
                        model: Todo.open
                        TaskRow {}
                    }
                }

                // insertion marker while dragging
                Rectangle {
                    readonly property var target: root.dragTo >= 0 ? openRepeater.itemAt(root.dragTo) : null
                    visible: root.dragFrom >= 0 && root.dragTo !== root.dragFrom && target !== null
                    x: 8 * root.s
                    width: parent.width - 16 * root.s
                    height: 2 * root.s
                    radius: 1 * root.s
                    color: Theme.info
                    y: !target ? 0 : (root.dragTo > root.dragFrom ? target.y + target.height : target.y) - 1 * root.s
                }
            }

            // empty state
            Column {
                visible: Todo.open.length === 0
                width: parent.width
                topPadding: 40 * root.s
                bottomPadding: 30 * root.s
                spacing: 10 * root.s
                GlyphIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 34 * root.s
                    height: width
                    name: "checklist"
                    color: Theme.faint
                    stroke: 1.5
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Todo.items.length ? "Nada pendente" : "Nenhuma tarefa ainda"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                    font.weight: Font.Medium
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Win+Ctrl+D adiciona pela pill de qualquer lugar"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                }
            }

            // done section
            Item {
                visible: Todo.done.length > 0
                width: parent.width
                height: 34 * root.s

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 6 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6 * root.s
                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 11 * root.s
                        height: width
                        name: "chevronDown"
                        rotation: root.showDone ? 0 : -90
                        color: Theme.dim
                        stroke: 2.4
                        Behavior on rotation { NumberAnimation { duration: Motion.fast } }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Concluídas  " + Todo.done.length
                        color: Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                        font.weight: Font.Bold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1.1 * root.s
                    }
                }
                MouseArea {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * 0.6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showDone = !root.showDone
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 8 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.confirmClear ? "Confirmar?" : "Limpar"
                    color: root.confirmClear ? Theme.danger : (clearArea.containsMouse ? Theme.cream : Theme.dim)
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    MouseArea {
                        id: clearArea
                        anchors.fill: parent
                        anchors.margins: -6 * root.s
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.confirmClear) {
                                root.confirmClear = false;
                                Todo.clearDone();
                            } else {
                                root.confirmClear = true;
                                clearTimeout.restart();
                            }
                        }
                    }
                }
            }

            Column {
                visible: root.showDone
                width: parent.width
                spacing: 2 * root.s
                Repeater {
                    model: root.showDone ? Todo.done : []
                    TaskRow { draggable: false }
                }
            }
        }
    }
}
