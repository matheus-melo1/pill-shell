pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

/**
 * 電 PHONE route of the drawer, fed by KDE Connect through Phone. A hero card
 * with the device name, battery (bar, percent, charging) and cellular network
 * with signal bars; the privacy card whose switch stops phone notifications
 * from reaching this computer at all (for presentations); three quick actions
 * (ring the phone, send a file, send the clipboard); then the phone's active
 * notifications, newest first. A card dismisses on its hover ✕ when the phone
 * allows it and opens an inline reply field when the app supports replies.
 * Sets Phone.watching while open so it polls fast. Sending a file closes the
 * drawer first, since the picker opens below this overlay.
 */
Item {
    id: root

    property real s: 1
    property bool open: false

    signal requestClose()

    opacity: open ? 1 : 0
    visible: opacity > 0.01
    enabled: open
    Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

    // Only the open view asserts this, so a closed drawer on another monitor
    // can't switch the fast poll back off.
    Binding {
        target: Phone
        property: "watching"
        value: true
        when: root.open
    }

    property string replying: ""
    property var expanded: ({})
    property real now: Date.now()

    onOpenChanged: if (open) {
        now = Date.now();
        Phone.refresh();
    } else {
        replying = "";
    }

    Timer {
        interval: 30000
        running: root.open
        repeat: true
        onTriggered: root.now = Date.now()
    }

    readonly property color tone: !Phone.online ? Theme.faint : (Phone.privacy ? Theme.warn : Theme.ok)
    readonly property color batteryTone: Phone.charging ? Theme.ok : (Phone.battery >= 0 && Phone.battery <= 15 ? Theme.danger : Theme.cream)

    function timeLabel(ts) {
        var m = Math.floor((now - ts) / 60000);
        if (m < 1)
            return "agora";
        if (m < 60)
            return m + " min";
        return Qt.formatTime(new Date(ts), "HH:mm");
    }

    function toggleExpanded(key) {
        var x = Object.assign({}, expanded);
        x[key] = !x[key];
        expanded = x;
    }

    component Switch: Rectangle {
        id: sw
        property bool checked: false
        property bool busy: false
        property color onColor: Theme.ok
        signal toggled()

        width: 50 * root.s
        height: 28 * root.s
        radius: height / 2
        color: checked ? Qt.alpha(onColor, 0.85) : Qt.alpha(Theme.cream, 0.12)
        border.width: 1
        border.color: checked ? Qt.alpha(onColor, 0.9) : Theme.frameBorder
        opacity: busy ? 0.6 : 1
        Behavior on color { ColorAnimation { duration: Motion.standard } }

        Rectangle {
            width: sw.height - 6 * root.s
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: sw.checked ? sw.width - width - 3 * root.s : 3 * root.s
            color: sw.checked ? "#ffffff" : Theme.cream
            Behavior on x { NumberAnimation { duration: Motion.standard; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -6 * root.s
            enabled: !sw.busy
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.toggled()
        }
    }

    component ActionTile: Rectangle {
        id: at
        property string icon: ""
        property string label: ""
        property bool working: false
        signal clicked()

        height: 64 * root.s
        radius: 14 * root.s
        color: atArea.containsMouse && enabled ? Qt.alpha(Theme.cream, 0.07) : Theme.frameBg
        border.width: 1
        border.color: atArea.containsMouse && enabled ? Qt.alpha(Theme.cream, 0.16) : Theme.frameBorder
        opacity: enabled ? 1 : 0.4
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        Column {
            anchors.centerIn: parent
            spacing: 7 * root.s

            GlyphIcon {
                id: atIcon
                anchors.horizontalCenter: parent.horizontalCenter
                width: 20 * root.s
                height: 20 * root.s
                name: at.icon
                color: atArea.containsMouse && at.enabled ? Theme.bright : Theme.iconDim
                stroke: 1.7

                SequentialAnimation on opacity {
                    running: at.working
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) atIcon.opacity = 1
                    NumberAnimation { to: 0.3; duration: 500 }
                    NumberAnimation { to: 1; duration: 500 }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: at.label
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.DemiBold
            }
        }

        MouseArea {
            id: atArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: at.clicked()
        }
    }

    component NotifCard: Rectangle {
        id: card
        required property var modelData
        readonly property var n: modelData
        readonly property bool isExpanded: root.expanded[n.key] === true
        readonly property bool isReplying: root.replying === n.id

        width: parent ? parent.width : 0
        height: cardCol.implicitHeight + 24 * root.s
        radius: 13 * root.s
        color: cardHover.hovered ? Qt.alpha(Theme.cream, 0.06) : Theme.frameBg
        border.width: 1
        border.color: card.isReplying ? Qt.alpha(Theme.cream, 0.22)
            : (cardHover.hovered ? Qt.alpha(Theme.cream, 0.14) : Theme.frameBorder)
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        HoverHandler { id: cardHover }

        Rectangle {
            id: tile
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin: 13 * root.s
            anchors.topMargin: 12 * root.s
            width: 30 * root.s
            height: width
            radius: 9 * root.s
            color: Theme.tileBg
            border.width: 1
            border.color: Theme.frameBorder

            Image {
                id: tileImg
                anchors.fill: parent
                anchors.margins: 4 * root.s
                source: card.n.icon.length ? "file://" + card.n.icon : ""
                sourceSize.width: 64
                sourceSize.height: 64
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                visible: status === Image.Ready
            }
            Text {
                anchors.centerIn: parent
                visible: !tileImg.visible
                text: (card.n.app || "?").charAt(0).toUpperCase()
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 12.5 * root.s
                font.weight: Font.Bold
            }
        }

        Column {
            id: cardCol
            anchors.left: tile.right
            anchors.leftMargin: 12 * root.s
            anchors.right: parent.right
            anchors.rightMargin: 14 * root.s
            anchors.top: parent.top
            anchors.topMargin: 12 * root.s
            spacing: 4 * root.s

            Item {
                width: parent.width
                height: appText.implicitHeight

                Text {
                    id: appText
                    anchors.left: parent.left
                    anchors.right: tools.left
                    anchors.rightMargin: 8 * root.s
                    elide: Text.ElideRight
                    text: card.n.app
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 9.5 * root.s
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.8 * root.s
                }

                Text {
                    anchors.right: parent.right
                    visible: !cardHover.hovered
                    text: root.timeLabel(card.n.ts)
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 9.5 * root.s
                    font.features: { "tnum": 1 }
                }

                // reply / dismiss, shown on hover in place of the time
                Row {
                    id: tools
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: cardHover.hovered
                    spacing: 6 * root.s

                    Repeater {
                        model: [
                            { key: "reply", icon: "chat", show: card.n.canReply, tint: Theme.info },
                            { key: "dismiss", icon: "x", show: card.n.dismissable, tint: Theme.danger }
                        ]

                        Rectangle {
                            id: toolBtn
                            required property var modelData
                            visible: modelData.show
                            width: 20 * root.s
                            height: width
                            radius: width / 2
                            color: toolArea.containsMouse ? Qt.alpha(modelData.tint, 0.18) : Theme.frameBg
                            GlyphIcon {
                                anchors.centerIn: parent
                                width: (toolBtn.modelData.key === "dismiss" ? 10 : 11) * root.s
                                height: width
                                name: toolBtn.modelData.icon
                                color: toolArea.containsMouse ? toolBtn.modelData.tint : Theme.iconDim
                                stroke: toolBtn.modelData.key === "dismiss" ? 2.4 : 2
                            }
                            MouseArea {
                                id: toolArea
                                anchors.fill: parent
                                anchors.margins: -4 * root.s
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (toolBtn.modelData.key === "dismiss") {
                                        Phone.dismiss(card.n.id);
                                    } else {
                                        root.replying = card.isReplying ? "" : card.n.id;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                visible: text.length > 0
                text: card.n.title
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                textFormat: Text.PlainText
                color: cardHover.hovered ? Theme.bright : Theme.cream
                font.family: Theme.font
                font.pixelSize: 12.5 * root.s
                font.weight: Font.DemiBold
            }

            Text {
                id: bodyLabel
                width: parent.width
                visible: text.length > 0
                text: card.n.text
                wrapMode: Text.Wrap
                maximumLineCount: card.isExpanded ? 40 : 3
                elide: Text.ElideRight
                textFormat: Text.PlainText
                lineHeight: 1.12
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 11 * root.s
            }

            Text {
                visible: bodyLabel.truncated || card.isExpanded
                text: card.isExpanded ? "mostrar menos" : "mostrar mais"
                color: moreArea.containsMouse ? Theme.cream : Theme.dim
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.weight: Font.DemiBold

                MouseArea {
                    id: moreArea
                    anchors.fill: parent
                    anchors.margins: -4 * root.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleExpanded(card.n.key)
                }
            }

            Item {
                width: 1
                height: 4 * root.s
                visible: card.isReplying
            }

            Rectangle {
                visible: card.isReplying
                width: parent.width
                height: 38 * root.s
                radius: 10 * root.s
                color: Theme.tileBg
                border.width: 1
                border.color: replyField.input.activeFocus ? Qt.alpha(Theme.cream, 0.22) : Theme.frameBorder

                SearchField {
                    id: replyField
                    anchors.fill: parent
                    anchors.leftMargin: 12 * root.s
                    anchors.rightMargin: 12 * root.s
                    s: root.s * 0.85
                    kanji: "返"
                    placeholder: "Responder em " + card.n.app
                    counterText: "enter ↵"
                    onAccepted: {
                        Phone.reply(card.n.id, text);
                        text = "";
                        root.replying = "";
                    }
                    onDismissed: root.replying = ""
                }
            }
        }

        onIsReplyingChanged: if (isReplying) replyField.input.forceActiveFocus()
    }

    // header
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
                text: "電"
                color: Theme.cream
                font.family: Theme.fontJp
                font.weight: Font.Medium
                font.pixelSize: 16 * root.s
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "CELULAR"
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.DemiBold
                font.letterSpacing: 1.6 * root.s
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: stateRow.implicitWidth + 22 * root.s
            height: 20 * root.s
            radius: height / 2
            color: Qt.alpha(root.tone, 0.13)
            border.width: 1
            border.color: Qt.alpha(root.tone, 0.3)

            Row {
                id: stateRow
                anchors.centerIn: parent
                spacing: 6 * root.s
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6 * root.s
                    height: width
                    radius: width / 2
                    color: root.tone
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: !Phone.present ? "sem celular"
                        : (!Phone.reachable ? "fora de alcance"
                        : (Phone.privacy ? "modo privado" : "conectado"))
                    color: root.tone
                    font.family: Theme.font
                    font.pixelSize: 8.5 * root.s
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1 * root.s
                }
            }
        }
    }

    // hero
    Rectangle {
        id: hero
        anchors.top: header.bottom
        anchors.topMargin: 18 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 104 * root.s
        radius: 18 * root.s
        color: Theme.frameBg
        border.width: 1
        border.color: Theme.frameBorder

        Rectangle {
            id: badge
            anchors.left: parent.left
            anchors.leftMargin: 20 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 60 * root.s
            height: width
            radius: width / 2
            color: Qt.alpha(root.tone, Phone.online ? 0.12 : 0.06)
            border.width: 1
            border.color: Qt.alpha(root.tone, 0.32)
            Behavior on color { ColorAnimation { duration: Motion.standard } }

            GlyphIcon {
                anchors.centerIn: parent
                width: 28 * root.s
                height: 28 * root.s
                name: "phone"
                color: Phone.online ? Theme.cream : Theme.faint
                stroke: 1.6
            }
        }

        Column {
            anchors.left: badge.right
            anchors.leftMargin: 18 * root.s
            anchors.right: parent.right
            anchors.rightMargin: 20 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * root.s

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: Phone.present ? Phone.name : "Nenhum celular pareado"
                color: Theme.bright
                font.family: Theme.font
                font.pixelSize: 20 * root.s
                font.weight: Font.Bold
                font.letterSpacing: -0.4 * root.s
            }

            // battery + network
            Row {
                visible: Phone.online
                spacing: 16 * root.s

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8 * root.s

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 64 * root.s
                        height: 7 * root.s
                        radius: height / 2
                        color: Theme.threadBg

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, Phone.battery / 100))
                            height: parent.height
                            radius: parent.radius
                            color: root.batteryTone
                            Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (Phone.battery >= 0 ? Phone.battery + "%" : "—") + (Phone.charging ? " · carregando" : "")
                        color: root.batteryTone
                        font.family: Theme.font
                        font.pixelSize: 12 * root.s
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                    }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Phone.signal >= 0
                    width: 1
                    height: 14 * root.s
                    color: Theme.hair
                }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Phone.signal >= 0
                    spacing: 7 * root.s

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2 * root.s
                        Repeater {
                            model: 4
                            Rectangle {
                                required property int index
                                anchors.bottom: parent.bottom
                                width: 3 * root.s
                                height: (4 + index * 2.5) * root.s
                                radius: 1 * root.s
                                color: index < Phone.signal ? Theme.cream : Theme.threadBg
                            }
                        }
                    }
                    Text {
                        id: netText
                        anchors.verticalCenter: parent.verticalCenter
                        text: Phone.network || "sem rede"
                        color: Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 12 * root.s
                        font.weight: Font.DemiBold
                    }
                }
            }

            Text {
                visible: !Phone.online
                width: parent.width
                wrapMode: Text.Wrap
                text: Phone.present
                    ? "O celular não está na mesma rede ou o app está fechado"
                    : "Abra o KDE Connect no Android e pareie com este computador"
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 11 * root.s
            }
        }
    }

    // privacy
    Rectangle {
        id: privacyCard
        anchors.top: hero.bottom
        anchors.topMargin: 12 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 62 * root.s
        radius: 14 * root.s
        enabled: Phone.online
        opacity: enabled ? 1 : 0.4
        color: Phone.privacy ? Qt.alpha(Theme.warn, 0.08) : Theme.frameBg
        border.width: 1
        border.color: Phone.privacy ? Qt.alpha(Theme.warn, 0.3) : Theme.frameBorder
        Behavior on color { ColorAnimation { duration: Motion.standard } }

        GlyphIcon {
            id: privIcon
            anchors.left: parent.left
            anchors.leftMargin: 16 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 20 * root.s
            height: 20 * root.s
            name: Phone.privacy ? "eyeOff" : "awake"
            color: Phone.privacy ? Theme.warn : Theme.iconDim
            stroke: 1.7
        }

        Column {
            anchors.left: privIcon.right
            anchors.leftMargin: 14 * root.s
            anchors.right: privSwitch.left
            anchors.rightMargin: 12 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2 * root.s
            Text {
                text: "Modo privado"
                color: Phone.privacy ? Theme.warn : Theme.cream
                font.family: Theme.font
                font.pixelSize: 12 * root.s
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: Phone.privacy
                    ? "Notificações do celular bloqueadas neste computador"
                    : "Para apresentações: nada do celular aparece na tela"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
            }
        }

        Switch {
            id: privSwitch
            anchors.right: parent.right
            anchors.rightMargin: 16 * root.s
            anchors.verticalCenter: parent.verticalCenter
            checked: Phone.privacy
            busy: Phone.pending.indexOf("privacy") === 0
            onColor: Theme.warn
            onToggled: Phone.setPrivacy(!checked)
        }
    }

    // quick actions
    Row {
        id: actions
        anchors.top: privacyCard.bottom
        anchors.topMargin: 12 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 10 * root.s
        readonly property real tileW: (width - 2 * spacing) / 3

        ActionTile {
            width: actions.tileW
            icon: "phoneRing"
            label: "Tocar"
            enabled: Phone.online && !Phone.busy
            working: Phone.pending === "ring"
            onClicked: Phone.ring()
        }
        ActionTile {
            width: actions.tileW
            icon: "folder"
            label: "Enviar arquivo"
            enabled: Phone.online && !Phone.busy
            working: Phone.pending === "share"
            onClicked: {
                Phone.shareFile();
                root.requestClose();
            }
        }
        ActionTile {
            width: actions.tileW
            icon: "copy"
            label: "Enviar copiado"
            enabled: Phone.online && !Phone.busy
            working: Phone.pending === "clipboard"
            onClicked: Phone.sendClipboard()
        }
    }

    Text {
        id: errorText
        anchors.top: actions.bottom
        anchors.topMargin: 8 * root.s
        anchors.horizontalCenter: parent.horizontalCenter
        visible: Phone.error.length > 0
        text: Phone.error
        color: Theme.danger
        font.family: Theme.font
        font.pixelSize: 10 * root.s
        font.weight: Font.DemiBold
    }

    // notifications
    Row {
        id: listHeader
        anchors.top: errorText.visible ? errorText.bottom : actions.bottom
        anchors.topMargin: 18 * root.s
        anchors.left: parent.left
        spacing: 8 * root.s

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Notificações"
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 9.5 * root.s
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2 * root.s
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: Phone.notifications.length > 0
            text: Phone.notifications.length
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 9.5 * root.s
            font.weight: Font.Bold
        }
    }

    Flickable {
        id: list
        anchors.top: listHeader.bottom
        anchors.topMargin: 10 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: listCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: listCol
            width: list.width
            spacing: 8 * root.s

            Repeater {
                model: Phone.online && !Phone.privacy ? Phone.notifications : []
                NotifCard {}
            }
        }

        Rectangle {
            parent: list
            z: 2
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 30 * root.s
            visible: list.contentY + list.height < list.contentHeight - 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.alpha(Theme.cardBot, 0) }
                GradientStop { position: 1.0; color: Theme.cardBot }
            }
        }
    }

    WheelScroller {
        anchors.fill: list
        s: root.s
        flick: list
    }

    // empty state
    Column {
        anchors.centerIn: list
        visible: !Phone.online || Phone.privacy || Phone.notifications.length === 0
        spacing: 10 * root.s

        GlyphIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 34 * root.s
            height: 34 * root.s
            name: Phone.privacy ? "eyeOff" : "inbox"
            color: Phone.privacy ? Qt.alpha(Theme.warn, 0.7) : Theme.faint
            stroke: 1.4
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: !Phone.online ? "Celular desconectado"
                : (Phone.privacy ? "Modo privado ligado" : "Nada no celular")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 12 * root.s
            font.weight: Font.Medium
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: Phone.online
            text: Phone.privacy ? "Desligue para voltar a receber as notificações" : "As notificações do celular aparecem aqui"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10 * root.s
        }
    }
}
