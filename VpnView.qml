pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import "Singletons"

/**
 * 盾 VPN route of the drawer. A hero card with a shield badge (glowing when the
 * tunnel is up, a spinning arc while the unit is changing state), a headline,
 * the exit route and a large switch that starts/stops the OpenVPN unit
 * (polkit asks for the password). Below it four stat tiles (latency, uptime,
 * download, upload with live rates), a detail list (server, tunnel address,
 * exit interface, unit) with the start-on-boot switch, and a note explaining
 * the full-tunnel cost while it is on. Sets Vpn.watching while open so the
 * numbers poll fast.
 */
Item {
    id: root

    property real s: 1
    property bool open: false

    opacity: open ? 1 : 0
    visible: opacity > 0.01
    enabled: open
    Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

    // Only the open view asserts this, so a closed drawer on another monitor
    // can't switch the fast poll back off.
    Binding {
        target: Vpn
        property: "watching"
        value: true
        when: root.open
    }

    property real now: Date.now()
    Timer {
        interval: 1000
        running: root.open && Vpn.active
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }

    readonly property bool on: Vpn.active
    readonly property bool busy: Vpn.transitioning
    readonly property color tone: busy ? Theme.warn : (on ? Theme.ok : Theme.faint)

    function uptime() {
        if (!Vpn.active || Vpn.since <= 0)
            return "—";
        var sec = Math.max(0, Math.floor((now - Vpn.since) / 1000));
        var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), x = sec % 60;
        if (h > 0)
            return h + "h " + (m < 10 ? "0" : "") + m + "m";
        return m + "m " + (x < 10 ? "0" : "") + x + "s";
    }

    function latencyColor(ms) {
        if (ms === null || ms === undefined)
            return Theme.faint;
        return ms < 60 ? Theme.ok : (ms < 150 ? Theme.warn : Theme.danger);
    }

    component Switch: Rectangle {
        id: sw
        property bool checked: false
        property bool busy: false
        property real k: 1
        signal toggled()

        width: 50 * root.s * k
        height: 28 * root.s * k
        radius: height / 2
        color: checked ? Qt.alpha(Theme.ok, 0.85) : Qt.alpha(Theme.cream, 0.12)
        border.width: 1
        border.color: checked ? Qt.alpha(Theme.ok, 0.9) : Theme.frameBorder
        opacity: busy ? 0.6 : 1
        Behavior on color { ColorAnimation { duration: Motion.standard } }

        Rectangle {
            width: sw.height - 6 * root.s * sw.k
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: sw.checked ? sw.width - width - 3 * root.s * sw.k : 3 * root.s * sw.k
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

    component StatTile: Rectangle {
        id: tile
        property string label: ""
        property string value: ""
        property string sub: ""
        property color accent: Theme.cream
        property string icon: ""

        height: 74 * root.s
        radius: 14 * root.s
        color: Theme.frameBg
        border.width: 1
        border.color: Theme.frameBorder

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 14 * root.s
            anchors.right: parent.right
            anchors.rightMargin: 12 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4 * root.s

            Text {
                text: tile.label
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 9 * root.s
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.1 * root.s
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: tile.value
                color: tile.accent
                font.family: Theme.font
                font.pixelSize: 19 * root.s
                font.weight: Font.Bold
                font.letterSpacing: -0.4 * root.s
                font.features: { "tnum": 1 }
            }
            Text {
                visible: tile.sub.length > 0
                text: tile.sub
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.features: { "tnum": 1 }
            }
        }
    }

    component DetailRow: Item {
        id: dr
        property string label: ""
        property string value: ""
        property bool mono: false
        width: parent ? parent.width : 0
        height: 30 * root.s

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: dr.label
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 11 * root.s
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: dr.value
            color: Theme.cream
            font.family: dr.mono ? "monospace" : Theme.font
            font.pixelSize: (dr.mono ? 10.5 : 11.5) * root.s
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
        }
    }

    Column {
        anchors.fill: parent
        spacing: 0

        // header
        Item {
            width: parent.width
            height: 24 * root.s

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * root.s
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "盾"
                    color: Theme.cream
                    font.family: Theme.fontJp
                    font.weight: Font.Medium
                    font.pixelSize: 16 * root.s
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "VPN"
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
                width: stateText.implicitWidth + 22 * root.s
                height: 20 * root.s
                radius: height / 2
                color: Qt.alpha(root.tone, 0.13)
                border.width: 1
                border.color: Qt.alpha(root.tone, 0.3)

                Row {
                    anchors.centerIn: parent
                    spacing: 6 * root.s
                    Rectangle {
                        id: stateDot
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6 * root.s
                        height: width
                        radius: width / 2
                        color: root.tone
                        SequentialAnimation on opacity {
                            running: root.busy && root.open
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) stateDot.opacity = 1
                            NumberAnimation { to: 0.25; duration: 600 }
                            NumberAnimation { to: 1; duration: 600 }
                        }
                    }
                    Text {
                        id: stateText
                        anchors.verticalCenter: parent.verticalCenter
                        text: Vpn.authPending ? "aguardando senha"
                            : (root.busy ? (Vpn.pending === "off" ? "desligando" : "conectando")
                            : (root.on ? "ligada" : "desligada"))
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

        Item { width: 1; height: 18 * root.s }

        // hero
        Rectangle {
            id: hero
            width: parent.width
            height: 132 * root.s
            radius: 18 * root.s
            border.width: 1
            border.color: root.on ? Qt.alpha(Theme.ok, 0.28) : Theme.frameBorder
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: root.on ? Qt.alpha(Theme.ok, 0.10) : Theme.frameBg }
                GradientStop { position: 1.0; color: Theme.frameBg }
            }
            Behavior on border.color { ColorAnimation { duration: Motion.standard } }

            Item {
                id: badge
                anchors.left: parent.left
                anchors.leftMargin: 22 * root.s
                anchors.verticalCenter: parent.verticalCenter
                width: 76 * root.s
                height: width

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width
                    height: width
                    radius: width / 2
                    color: Qt.alpha(root.tone, root.on ? 0.14 : 0.08)
                    border.width: 1
                    border.color: Qt.alpha(root.tone, 0.35)
                    Behavior on color { ColorAnimation { duration: Motion.standard } }
                }

                // breathing halo while connected
                Rectangle {
                    id: halo
                    anchors.centerIn: parent
                    width: parent.width
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 2 * root.s
                    border.color: Theme.ok
                    visible: root.on && !root.busy
                    property real p: 0
                    scale: 1 + p * 0.28
                    opacity: (1 - p) * 0.5
                    NumberAnimation on p {
                        running: halo.visible && root.open
                        from: 0; to: 1
                        duration: 2200
                        loops: Animation.Infinite
                        easing.type: Easing.OutCubic
                    }
                }

                // spinner while changing state
                Shape {
                    id: spinner
                    anchors.fill: parent
                    visible: root.busy
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: Theme.warn
                        strokeWidth: 2.5 * root.s
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: spinner.width / 2; centerY: spinner.height / 2
                            radiusX: spinner.width / 2 - 2 * root.s; radiusY: radiusX
                            startAngle: 0; sweepAngle: 90
                        }
                    }
                    RotationAnimation on rotation {
                        running: spinner.visible && root.open
                        from: 0; to: 360
                        duration: 1000
                        loops: Animation.Infinite
                    }
                }

                GlyphIcon {
                    anchors.centerIn: parent
                    width: 34 * root.s
                    height: 34 * root.s
                    name: root.on ? "shieldCheck" : "shield"
                    color: root.on ? Theme.ok : Theme.subtle
                    stroke: 1.6
                }
            }

            Column {
                anchors.left: badge.right
                anchors.leftMargin: 20 * root.s
                anchors.right: bigSwitch.left
                anchors.rightMargin: 16 * root.s
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5 * root.s

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.busy ? (Vpn.pending === "off" ? "Desligando…" : "Conectando…")
                        : (root.on ? "Protegida" : "Desconectada")
                    color: Theme.bright
                    font.family: Theme.font
                    font.pixelSize: 22 * root.s
                    font.weight: Font.Bold
                    font.letterSpacing: -0.5 * root.s
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: root.on
                        ? (Vpn.tunneled ? "Todo o tráfego sai pela AWS · Virgínia (us-east-1)" : "Túnel ativo, internet saindo direto")
                        : "Internet saindo direto por " + (Vpn.dev || "—")
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                    lineHeight: 1.1
                }
                Text {
                    visible: Vpn.error.length > 0
                    text: Vpn.error
                    color: Theme.danger
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                }
            }

            Switch {
                id: bigSwitch
                anchors.right: parent.right
                anchors.rightMargin: 22 * root.s
                anchors.verticalCenter: parent.verticalCenter
                k: 1.15
                checked: Vpn.pending === "on" || (Vpn.pending !== "off" && root.on)
                busy: Vpn.authPending
                onToggled: Vpn.setOn(!checked)
            }
        }

        Item { width: 1; height: 14 * root.s }

        // stats
        Grid {
            id: grid
            width: parent.width
            columns: 2
            columnSpacing: 10 * root.s
            rowSpacing: 10 * root.s
            readonly property real tileW: (width - columnSpacing) / 2

            StatTile {
                width: grid.tileW
                label: "Latência"
                value: Vpn.latency === null ? "—" : Math.round(Vpn.latency) + " ms"
                sub: "até 1.1.1.1"
                accent: root.latencyColor(Vpn.latency)
            }
            StatTile {
                width: grid.tileW
                label: "Conectada há"
                value: root.uptime()
                sub: root.on ? "desde " + Qt.formatTime(new Date(Vpn.since), "HH:mm") : ""
            }
            StatTile {
                width: grid.tileW
                label: "↓ Download"
                value: root.on ? Vpn.bytes(Vpn.rxRate) + "/s" : "—"
                sub: root.on ? Vpn.bytes(Vpn.rx) + " no total" : ""
            }
            StatTile {
                width: grid.tileW
                label: "↑ Upload"
                value: root.on ? Vpn.bytes(Vpn.txRate) + "/s" : "—"
                sub: root.on ? Vpn.bytes(Vpn.tx) + " no total" : ""
            }
        }

        Item { width: 1; height: 18 * root.s }

        Text {
            text: "Detalhes"
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 9.5 * root.s
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2 * root.s
        }

        Item { width: 1; height: 6 * root.s }

        DetailRow { label: "Servidor"; value: Vpn.server || "—"; mono: true }
        Rectangle { width: parent.width; height: 1; color: Theme.hair }
        DetailRow { label: "IP no túnel"; value: Vpn.tunIp || "—"; mono: true }
        Rectangle { width: parent.width; height: 1; color: Theme.hair }
        DetailRow { label: "Saída para a internet"; value: Vpn.dev || "—"; mono: true }
        Rectangle { width: parent.width; height: 1; color: Theme.hair }
        DetailRow { label: "Serviço"; value: Vpn.unit; mono: true }
        Rectangle { width: parent.width; height: 1; color: Theme.hair }

        Item {
            width: parent.width
            height: 46 * root.s

            Column {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2 * root.s
                Text {
                    text: "Ligar junto com o sistema"
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 11.5 * root.s
                    font.weight: Font.Medium
                }
                Text {
                    text: Vpn.enabled ? "Sobe automaticamente no boot" : "Fica desligada até você ligar"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 9.5 * root.s
                }
            }

            Switch {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                k: 0.85
                checked: Vpn.pending === "boot-on" || (Vpn.pending !== "boot-off" && Vpn.enabled)
                busy: Vpn.authPending
                onToggled: Vpn.setBoot(!checked)
            }
        }

        Item { width: 1; height: 14 * root.s }

        Rectangle {
            visible: root.on && Vpn.tunneled
            width: parent.width
            height: note.implicitHeight + 24 * root.s
            radius: 12 * root.s
            color: Qt.alpha(Theme.warn, 0.07)
            border.width: 1
            border.color: Qt.alpha(Theme.warn, 0.22)

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 1
                anchors.verticalCenter: parent.verticalCenter
                width: 2.5 * root.s
                height: parent.height - 20 * root.s
                radius: width / 2
                color: Theme.warn
            }

            Text {
                id: note
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 16 * root.s
                anchors.rightMargin: 14 * root.s
                wrapMode: Text.Wrap
                text: "Full tunnel: a navegação toda passa pela Virgínia, então a latência sobe (~130 ms) e o DNS fica lento. Só é necessária para acessar as redes 10.0.0.0/16 e 10.200.0.0/16."
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                lineHeight: 1.15
            }
        }
    }
}
