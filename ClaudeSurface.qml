pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import "Singletons"

/**
 * CLAUDE CODE surface. Header with the orange Claude mark and a live
 * "N trabalhando" chip. Below, one card per account side by side: account
 * icon and name, a large 5-hour ring with the percentage in its centre and the
 * reset countdown, then a thin weekly bar with its own reset; a stale fetch
 * dims the card and says so. Then the live sessions as cards, busy first:
 * a breathing Claude mark for busy sessions and a pause glyph for idle ones,
 * session name, project folder, account icon and time in the current state.
 * Rings and bars go red past 80%. Exposes `implicitHeight` from its content
 * and docks Ame as a soul at the header mark.
 */
PillSurface {
    id: root

    mTop: 16
    mLeft: 19
    mRight: 19
    mBottom: 16

    implicitHeight: content.implicitHeight

    readonly property point markPoint: {
        void root.width;
        void root.height;
        return mark.mapToItem(root, mark.width / 2, mark.height / 2);
    }

    ameForm: open ? "soul" : "off"
    amePoint: markPoint

    property real now: Date.now()

    Timer {
        interval: 30000
        running: root.open
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }

    function usageColor(pct) {
        return pct >= 80 ? Theme.danger : Theme.claude;
    }

    function folder(cwd) {
        var c = cwd || "";
        if (c === Quickshell.env("HOME"))
            return "~";
        var parts = c.split("/");
        return parts[parts.length - 1] || c;
    }

    component Ring: Item {
        id: ring
        property real value: 0
        property bool known: true
        property real thickness: 6
        readonly property real frac: known ? Math.max(0, Math.min(1, value / 100)) : 0
        readonly property real rad: (width - thickness * root.s) / 2
        property real shown: frac
        Behavior on shown { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: Theme.threadBg
                strokeWidth: ring.thickness * root.s
                fillColor: "transparent"
                PathAngleArc {
                    centerX: ring.width / 2; centerY: ring.height / 2
                    radiusX: ring.rad; radiusY: ring.rad
                    startAngle: 0; sweepAngle: 360
                }
            }
            ShapePath {
                strokeColor: root.usageColor(ring.value)
                strokeWidth: ring.thickness * root.s
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.width / 2; centerY: ring.height / 2
                    radiusX: ring.rad; radiusY: ring.rad
                    startAngle: -90; sweepAngle: 360 * ring.shown
                }
            }
        }
    }

    component IconLabel: Row {
        id: il
        property string icon: ""
        property string text: ""
        property color color: Theme.dim
        property real size: 10
        spacing: 5 * root.s

        GlyphIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: (il.size + 1) * root.s
            height: width
            name: il.icon
            color: il.color
            stroke: 2
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: il.text
            color: il.color
            font.family: Theme.font
            font.pixelSize: il.size * root.s
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
        }
    }

    component AccountCard: Rectangle {
        id: ac
        required property var modelData
        readonly property var a: modelData
        readonly property bool known5: a.five !== null && a.five !== undefined
        readonly property bool known7: a.seven !== null && a.seven !== undefined
        readonly property int five: known5 ? Math.round(a.five) : 0
        readonly property int seven: known7 ? Math.round(a.seven) : 0
        readonly property bool hot: five >= 80

        height: acCol.implicitHeight + 28 * root.s
        radius: 16 * root.s
        border.width: 1
        border.color: hot ? Qt.alpha(Theme.danger, 0.35) : Theme.frameBorder
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.alpha(ac.hot ? Theme.danger : Theme.claude, 0.07) }
            GradientStop { position: 1.0; color: Theme.frameBg }
        }
        opacity: a.stale ? 0.7 : 1

        Column {
            id: acCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14 * root.s
            spacing: 12 * root.s

            Item {
                width: parent.width
                height: 18 * root.s

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7 * root.s

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22 * root.s
                        height: width
                        radius: 7 * root.s
                        color: Qt.alpha(Theme.cream, 0.07)
                        GlyphIcon {
                            anchors.centerIn: parent
                            width: 13 * root.s
                            height: width
                            name: ac.a.name === "work" ? "briefcase" : "user"
                            color: Theme.cream
                            stroke: 2
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ac.a.name === "work" ? "Trabalho" : "Pessoal"
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 11.5 * root.s
                        font.weight: Font.Bold
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: ac.a.stale
                    text: "desatualizado"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 8.5 * root.s
                    font.italic: true
                }
            }

            Row {
                spacing: 14 * root.s

                Ring {
                    width: 72 * root.s
                    height: width
                    value: ac.five
                    known: ac.known5
                    thickness: 6.5

                    Column {
                        anchors.centerIn: parent
                        spacing: -1 * root.s
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: ac.known5 ? ac.five + "%" : "—"
                            color: ac.hot ? Theme.danger : Theme.bright
                            font.family: Theme.font
                            font.pixelSize: 17 * root.s
                            font.weight: Font.Bold
                            font.letterSpacing: -0.5 * root.s
                            font.features: { "tnum": 1 }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "5H"
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 8 * root.s
                            font.weight: Font.Bold
                            font.letterSpacing: 1 * root.s
                        }
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6 * root.s

                    Text {
                        text: "Janela de 5 horas"
                        color: Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                        font.weight: Font.DemiBold
                    }
                    IconLabel {
                        icon: "clock"
                        readonly property string remaining: Claude.until(ac.a.fiveReset, root.now)
                        text: remaining.length ? "reseta em " + remaining : "sem janela ativa"
                        color: Theme.dim
                        size: 9.5
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 6 * root.s

                Item {
                    width: parent.width
                    height: weekLabel.implicitHeight

                    Text {
                        id: weekLabel
                        text: "Semana"
                        color: Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.right: parent.right
                        text: ac.known7 ? ac.seven + "%" : "—"
                        color: ac.seven >= 80 ? Theme.danger : Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 5 * root.s
                    radius: height / 2
                    color: Theme.threadBg

                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, ac.seven / 100))
                        height: parent.height
                        radius: parent.radius
                        color: root.usageColor(ac.seven)
                        Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                    }
                }

                IconLabel {
                    icon: "clock"
                    readonly property string remaining: Claude.until(ac.a.sevenReset, root.now)
                    visible: remaining.length > 0
                    text: "reseta em " + remaining
                    color: Theme.faint
                    size: 9
                }
            }
        }
    }

    component SessionCard: Rectangle {
        id: sc
        required property var modelData
        readonly property var x0: modelData
        readonly property bool busy: x0.status === "busy"

        width: parent ? parent.width : 0
        height: 54 * root.s
        radius: 14 * root.s
        color: busy ? Qt.alpha(Theme.claude, 0.08) : Theme.frameBg
        border.width: 1
        border.color: busy ? Qt.alpha(Theme.claude, 0.32) : Theme.frameBorder

        Rectangle {
            id: badge
            anchors.left: parent.left
            anchors.leftMargin: 11 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 32 * root.s
            height: width
            radius: 10 * root.s
            color: sc.busy ? Qt.alpha(Theme.claude, 0.16) : Qt.alpha(Theme.cream, 0.05)

            GlyphIcon {
                id: badgeIcon
                anchors.centerIn: parent
                width: (sc.busy ? 18 : 12) * root.s
                height: width
                name: sc.busy ? "claude" : "pause"
                color: sc.busy ? Theme.claude : Theme.faint

                SequentialAnimation on opacity {
                    running: sc.busy && root.open
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) badgeIcon.opacity = 1
                    NumberAnimation { to: 0.35; duration: 750; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 750; easing.type: Easing.InOutSine }
                }
                RotationAnimation on rotation {
                    running: sc.busy && root.open
                    from: 0; to: 360
                    duration: 6000
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) badgeIcon.rotation = 0
                }
            }
        }

        Column {
            anchors.left: badge.right
            anchors.leftMargin: 11 * root.s
            anchors.right: meta.left
            anchors.rightMargin: 10 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4 * root.s

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: sc.x0.name || ("pid " + sc.x0.pid)
                color: sc.busy ? Theme.bright : Theme.cream
                font.family: Theme.font
                font.pixelSize: 12.5 * root.s
                font.weight: sc.busy ? Font.Bold : Font.DemiBold
            }
            Row {
                spacing: 10 * root.s
                IconLabel {
                    icon: "folder"
                    text: root.folder(sc.x0.cwd)
                    color: Theme.dim
                    size: 9.5
                }
                IconLabel {
                    icon: sc.x0.account === "work" ? "briefcase" : "user"
                    text: sc.x0.account === "work" ? "trabalho" : "pessoal"
                    color: Theme.faint
                    size: 9.5
                }
            }
        }

        Column {
            id: meta
            anchors.right: parent.right
            anchors.rightMargin: 13 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4 * root.s

            Rectangle {
                anchors.right: parent.right
                width: stText.implicitWidth + 14 * root.s
                height: 17 * root.s
                radius: height / 2
                color: sc.busy ? Qt.alpha(Theme.claude, 0.18) : Qt.alpha(Theme.cream, 0.06)
                Text {
                    id: stText
                    anchors.centerIn: parent
                    text: sc.busy ? "trabalhando" : "ociosa"
                    color: sc.busy ? Theme.claude : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 8.5 * root.s
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.6 * root.s
                }
            }
            IconLabel {
                anchors.right: parent.right
                icon: "clock"
                text: Claude.since(sc.x0.statusSince || sc.x0.startedAt, root.now)
                color: Theme.faint
                size: 9
            }
        }
    }

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        // header
        Item {
            width: parent.width
            height: 26 * root.s

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9 * root.s

                GlyphIcon {
                    id: mark
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20 * root.s
                    height: width
                    name: "claude"
                    color: Theme.claude
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Claude Code"
                    color: Theme.bright
                    font.family: Theme.font
                    font.pixelSize: 14 * root.s
                    font.weight: Font.Bold
                    font.letterSpacing: -0.2 * root.s
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: Claude.total > 0
                width: hdrRow.implicitWidth + 20 * root.s
                height: 22 * root.s
                radius: height / 2
                color: Claude.busy ? Qt.alpha(Theme.claude, 0.15) : Qt.alpha(Theme.cream, 0.06)
                border.width: 1
                border.color: Claude.busy ? Qt.alpha(Theme.claude, 0.35) : Theme.frameBorder

                Row {
                    id: hdrRow
                    anchors.centerIn: parent
                    spacing: 6 * root.s
                    Rectangle {
                        id: hdrDot
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6 * root.s
                        height: width
                        radius: width / 2
                        color: Claude.busy ? Theme.claude : Theme.faint
                        SequentialAnimation on opacity {
                            running: Claude.busy && root.open
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) hdrDot.opacity = 1
                            NumberAnimation { to: 0.25; duration: 700 }
                            NumberAnimation { to: 1; duration: 700 }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Claude.busy ? Claude.busyCount + " trabalhando" : "todas ociosas"
                        color: Claude.busy ? Theme.claude : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 9.5 * root.s
                        font.weight: Font.Bold
                    }
                }
            }
        }

        Item { width: 1; height: 16 * root.s }

        // accounts
        Row {
            id: accRow
            width: parent.width
            spacing: 10 * root.s
            readonly property int n: Math.max(1, Claude.accounts.length)

            Repeater {
                model: Claude.accounts
                AccountCard {
                    width: (accRow.width - accRow.spacing * (accRow.n - 1)) / accRow.n
                }
            }
        }

        Item { width: 1; height: 20 * root.s }

        // sessions header
        Item {
            width: parent.width
            height: 18 * root.s

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Sessões abertas"
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.2 * root.s
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10 * root.s
                IconLabel {
                    icon: "claude"
                    text: Claude.busyCount + ""
                    color: Claude.busy ? Theme.claude : Theme.faint
                    size: 10
                }
                IconLabel {
                    icon: "pause"
                    text: (Claude.total - Claude.busyCount) + ""
                    color: Theme.faint
                    size: 10
                }
            }
        }

        Item { width: 1; height: 10 * root.s }

        Rectangle {
            visible: Claude.total === 0
            width: parent.width
            height: 64 * root.s
            radius: 14 * root.s
            color: "transparent"
            border.width: 1
            border.color: Theme.frameBorder

            IconLabel {
                anchors.centerIn: parent
                icon: "claude"
                text: "Nenhuma sessão aberta"
                color: Theme.faint
                size: 11
            }
        }

        Column {
            width: parent.width
            spacing: 7 * root.s

            Repeater {
                model: Claude.sessions
                SessionCard {}
            }
        }
    }
}
