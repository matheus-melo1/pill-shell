pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Widgets
import "Singletons"

/**
 * Issue detail pane that the drawer slides open beside the GitHub board when
 * a card is clicked. Top bar (repo#n, reload, open in browser, close), title
 * with state, author and ages, then:
 *
 *  - Status as the board's Kanban pipeline: the current step is lit, moves
 *    inside the team flow are one click, moves outside it ask to click again.
 *  - Field controls: Priority segments, Tipo select, Estimate stepper, and a
 *    Blocked switch that demands a written reason (posted as a comment) per
 *    the board rules; Sprint/Marco/Produto read-only.
 *  - Labels, assignees, parent issue, sub-issues with a progress bar, linked
 *    PRs, the Markdown description (collapsible), the latest comments and a
 *    comment box (Ctrl+Enter), plus close / reopen.
 *  - A Claude button in the top bar opening ClaudeIssuePopover, which hands
 *    the issue to an open Claude agent in tmux or to a new one. Escape closes
 *    the popover first (popOpen / closePop for the drawer).
 *
 * All edits go through the GitHub singleton, which applies them
 * optimistically and reloads. Content is laid out at `paneW` regardless of the
 * animated width so it doesn't reflow while the drawer grows.
 */
Item {
    id: root

    property real s: 1
    property real paneW: 540 * s
    signal requestClose()

    clip: true

    readonly property var d: GitHub.detailKind === "issue" ? GitHub.detail : null
    readonly property string status: GitHub.field("Status") || ""
    property string pendingStatus: ""
    property bool showFullBody: false
    readonly property bool popOpen: pop.shown
    function closePop() {
        pop.hide();
    }
    property bool blockOpen: false
    property bool confirmClose: false
    property real now: Date.now()

    onDChanged: {
        pendingStatus = "";
        confirmClose = false;
    }

    Connections {
        target: GitHub
        function onDetailUrlChanged() {
            root.showFullBody = false;
            root.blockOpen = false;
            root.pendingStatus = "";
            pop.hide();
            body.contentY = 0;
            root.now = Date.now();
        }
    }

    function ago(iso) {
        var m = Math.floor((now - Date.parse(iso)) / 60000);
        if (m < 60)
            return Math.max(1, m) + " min";
        if (m < 1440)
            return Math.floor(m / 60) + " h";
        var days = Math.floor(m / 1440);
        return days < 30 ? days + " d" : Qt.formatDate(new Date(iso), "dd/MM/yy");
    }

    function short(st) {
        return { "Refinement": "Refino", "In Progress": "Em progresso", "In Review": "Review" }[st] || st;
    }

    function statusColor(st) {
        return ({
            "Backlog": Theme.dim, "Refinement": "#a371f7", "Ready": Theme.info,
            "In Progress": Theme.warn, "In Review": Theme.claude, "QA": "#db61a2", "Done": Theme.ok
        })[st] || Theme.subtle;
    }

    function prioColor(p) {
        return p === "P0" ? Theme.danger : (p === "P1" ? Theme.warn : (p === "P2" ? Theme.subtle : Theme.dim));
    }

    function moveTo(st) {
        if (st === status || GitHub.busy.length)
            return;
        if (!GitHub.inFlow(status, st) && pendingStatus !== st) {
            pendingStatus = st;
            return;
        }
        pendingStatus = "";
        GitHub.setField("Status", st);
    }

    component Section: GhSection { s: root.s }

    component Avatar: GhAvatar { s: root.s }

    component Pill: GhPill { s: root.s }

    component FieldRow: Item {
        id: fr
        property string label: ""
        default property alias content: frSlot.data
        width: parent ? parent.width : 0
        height: Math.max(30 * root.s, frSlot.childrenRect.height)

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: fr.label
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 11 * root.s
        }
        Item {
            id: frSlot
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: childrenRect.height
        }
    }

    component LinkRow: GhLinkRow { s: root.s }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 18 * root.s
        anchors.bottomMargin: 18 * root.s
        width: 1
        color: Theme.hair
    }

    Item {
        id: inner
        x: 22 * root.s
        y: 0
        width: root.paneW - 44 * root.s
        height: root.height

        // ---- top bar ----
        Item {
            id: topBar
            anchors.top: parent.top
            anchors.topMargin: 20 * root.s
            width: parent.width
            height: 28 * root.s

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * root.s
                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 15 * root.s
                    height: width
                    name: "github"
                    color: Theme.subtle
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.d ? root.d.repo.split("/")[1] + "  #" + root.d.number : "carregando…"
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: GitHub.busy.length > 0 || GitHub.detailLoading
                    text: GitHub.busy.length ? "salvando…" : "atualizando…"
                    color: Theme.warn
                    font.family: Theme.font
                    font.pixelSize: 9.5 * root.s
                    font.italic: true
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2 * root.s

                ClaudeButton {
                    id: aiBtn
                    visible: root.d !== null
                    anchors.verticalCenter: parent.verticalCenter
                    s: root.s
                    size: 28
                    open: pop.shown
                    onClicked: pop.toggle(aiBtn, { url: GitHub.detailUrl, title: root.d.title, repo: root.d.repo, number: root.d.number })
                }

                Repeater {
                    model: [
                        { icon: "retry", act: "reload" },
                        { icon: "send", act: "open" },
                        { icon: "x", act: "close" }
                    ]
                    Rectangle {
                        id: tb
                        required property var modelData
                        width: 28 * root.s
                        height: width
                        radius: 9 * root.s
                        color: tbArea.containsMouse ? Theme.frameBg : "transparent"
                        GlyphIcon {
                            anchors.centerIn: parent
                            width: 13 * root.s
                            height: width
                            name: tb.modelData.icon
                            rotation: tb.modelData.act === "open" ? 45 : 0
                            color: tbArea.containsMouse ? Theme.cream : Theme.iconDim
                            stroke: 2
                        }
                        MouseArea {
                            id: tbArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (tb.modelData.act === "reload")
                                    GitHub.loadDetail();
                                else if (tb.modelData.act === "open")
                                    Qt.openUrlExternally(GitHub.detailUrl);
                                else
                                    root.requestClose();
                            }
                        }
                    }
                }
            }
        }

        // ---- error ----
        Column {
            anchors.centerIn: parent
            visible: !root.d && GitHub.detailError.length > 0
            spacing: 10 * root.s
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Não deu para carregar"
                color: Theme.danger
                font.family: Theme.font
                font.pixelSize: 12 * root.s
                font.weight: Font.DemiBold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(implicitWidth, inner.width)
                wrapMode: Text.Wrap
                text: GitHub.detailError
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
            }
        }

        // ---- loading skeleton ----
        DetailSkeleton {
            visible: !root.d && GitHub.detailError.length === 0
            anchors.top: topBar.bottom
            anchors.topMargin: 12 * root.s
            width: parent.width
            s: root.s
        }

        // ---- body ----
        Flickable {
            id: body
            visible: root.d !== null
            anchors.top: topBar.bottom
            anchors.topMargin: 12 * root.s
            anchors.bottom: composer.top
            anchors.bottomMargin: 10 * root.s
            width: parent.width
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: col
                width: body.width
                spacing: 12 * root.s

                // title
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: root.d ? root.d.title : ""
                    color: Theme.bright
                    font.family: Theme.font
                    font.pixelSize: 17 * root.s
                    font.weight: Font.Bold
                    lineHeight: 1.12
                }

                Row {
                    spacing: 8 * root.s
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property bool isOpen: root.d && root.d.state === "OPEN"
                        width: stRow.implicitWidth + 16 * root.s
                        height: 22 * root.s
                        radius: height / 2
                        color: Qt.alpha(isOpen ? Theme.ok : "#a371f7", 0.16)
                        border.width: 1
                        border.color: Qt.alpha(isOpen ? Theme.ok : "#a371f7", 0.4)
                        Row {
                            id: stRow
                            anchors.centerIn: parent
                            spacing: 5 * root.s
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6 * root.s
                                height: width
                                radius: width / 2
                                color: parent.parent.isOpen ? Theme.ok : "#a371f7"
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.parent.isOpen ? "Aberta" : "Fechada"
                                color: parent.parent.isOpen ? Theme.ok : "#a371f7"
                                font.family: Theme.font
                                font.pixelSize: 10 * root.s
                                font.weight: Font.Bold
                            }
                        }
                    }
                    Avatar {
                        anchors.verticalCenter: parent.verticalCenter
                        src: root.d ? root.d.author.avatarUrl : ""
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.d ? root.d.author.login + " abriu há " + root.ago(root.d.createdAt) + "  ·  atualizada há " + root.ago(root.d.updatedAt) : ""
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                    }
                }

                Rectangle {
                    visible: GitHub.actionError.length > 0
                    width: parent.width
                    height: aeText.implicitHeight + 16 * root.s
                    radius: 10 * root.s
                    color: Qt.alpha(Theme.danger, 0.1)
                    border.width: 1
                    border.color: Qt.alpha(Theme.danger, 0.3)
                    Text {
                        id: aeText
                        anchors.fill: parent
                        anchors.margins: 8 * root.s
                        anchors.leftMargin: 12 * root.s
                        wrapMode: Text.Wrap
                        verticalAlignment: Text.AlignVCenter
                        text: GitHub.actionError
                        color: Theme.danger
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                    }
                }

                // ---- status pipeline ----
                Rectangle {
                    visible: root.d && root.d.item
                    width: parent.width
                    height: stCol.implicitHeight + 24 * root.s
                    radius: 14 * root.s
                    color: Theme.frameBg
                    border.width: 1
                    border.color: Theme.frameBorder

                    Column {
                        id: stCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12 * root.s
                        spacing: 10 * root.s

                        Item {
                            width: parent.width
                            height: 16 * root.s
                            Text {
                                text: "STATUS NO BOARD"
                                color: Theme.subtle
                                font.family: Theme.font
                                font.pixelSize: 9.5 * root.s
                                font.weight: Font.Bold
                                font.letterSpacing: 1.2 * root.s
                            }
                            Text {
                                anchors.right: parent.right
                                text: root.pendingStatus.length
                                    ? "Fora do fluxo do time: clique de novo para mover"
                                    : "Próximos: " + ((GitHub.transitions[root.status] || []).map(root.short).join(", ") || "—")
                                color: root.pendingStatus.length ? Theme.warn : Theme.faint
                                font.family: Theme.font
                                font.pixelSize: 9.5 * root.s
                            }
                        }

                        Flow {
                            width: parent.width
                            spacing: 4 * root.s
                            Repeater {
                                model: GitHub.statusFlow
                                Row {
                                    id: step
                                    required property string modelData
                                    required property int index
                                    readonly property bool current: modelData === root.status
                                    readonly property bool next: GitHub.inFlow(root.status, modelData)
                                    spacing: 4 * root.s
                                    Pill {
                                        text: root.short(step.modelData)
                                        tint: step.current || root.pendingStatus === step.modelData ? root.statusColor(step.modelData) : (step.next ? root.statusColor(step.modelData) : Theme.subtle)
                                        on: step.current || root.pendingStatus === step.modelData
                                        enabledLook: step.current || step.next || root.pendingStatus === step.modelData
                                        hoverable: !step.current && GitHub.busy.length === 0
                                        onClicked: root.moveTo(step.modelData)
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: step.index < GitHub.statusFlow.length - 1
                                        text: "›"
                                        color: Theme.faint
                                        font.pixelSize: 12 * root.s
                                    }
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            visible: text.length > 0
                            text: {
                                var t = root.pendingStatus || "";
                                if (t === "Ready" && !(GitHub.field("Estimate") > 0))
                                    return "Para entrar em Ready o board pede Estimate e critérios de aceite.";
                                if (t === "In Review" && root.d && root.d.prs.length === 0)
                                    return "In Review pede um PR vinculado à issue.";
                                return "";
                            }
                            color: Theme.warn
                            font.family: Theme.font
                            font.pixelSize: 9.5 * root.s
                        }
                    }
                }

                // ---- fields ----
                Column {
                    visible: root.d && root.d.item
                    width: parent.width
                    spacing: 2 * root.s

                    FieldRow {
                        label: "Prioridade"
                        Row {
                            spacing: 4 * root.s
                            Repeater {
                                model: root.d && root.d.options.Priority ? root.d.options.Priority : []
                                Pill {
                                    required property string modelData
                                    text: modelData
                                    tint: root.prioColor(modelData)
                                    on: GitHub.field("Priority") === modelData
                                    onClicked: GitHub.setField("Priority", on ? "" : modelData)
                                }
                            }
                        }
                    }

                    FieldRow {
                        label: "Tipo"
                        Row {
                            spacing: 4 * root.s
                            Pill {
                                id: tipoBtn
                                text: (GitHub.field("Tipo") || "—") + "  ▾"
                                tint: Theme.info
                                on: tipoMenu.visible
                                onClicked: tipoMenu.visible = !tipoMenu.visible
                            }
                        }
                    }

                    Flow {
                        id: tipoMenu
                        visible: false
                        width: parent.width
                        spacing: 4 * root.s
                        layoutDirection: Qt.RightToLeft
                        bottomPadding: 6 * root.s
                        Repeater {
                            model: root.d && root.d.options.Tipo ? root.d.options.Tipo : []
                            Pill {
                                required property string modelData
                                text: modelData
                                tint: Theme.info
                                on: GitHub.field("Tipo") === modelData
                                onClicked: {
                                    GitHub.setField("Tipo", modelData);
                                    tipoMenu.visible = false;
                                }
                            }
                        }
                    }

                    FieldRow {
                        label: "Estimate"
                        Row {
                            spacing: 6 * root.s
                            Pill {
                                text: "−"
                                onClicked: {
                                    var v = Number(GitHub.field("Estimate") || 0);
                                    GitHub.setField("Estimate", v <= 0.5 ? "" : (v <= 1 ? 0.5 : v - 1));
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 52 * root.s
                                horizontalAlignment: Text.AlignHCenter
                                readonly property var v: GitHub.field("Estimate")
                                text: v === undefined || v === null ? "—" : (v % 1 === 0 ? v : Number(v).toFixed(1)) + " pts"
                                color: Theme.cream
                                font.family: Theme.font
                                font.pixelSize: 12 * root.s
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                            }
                            Pill {
                                text: "+"
                                onClicked: {
                                    var v = Number(GitHub.field("Estimate") || 0);
                                    GitHub.setField("Estimate", v < 1 ? (v === 0 ? 0.5 : 1) : v + 1);
                                }
                            }
                        }
                    }

                    FieldRow {
                        label: "Bloqueada"
                        Row {
                            spacing: 6 * root.s
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: GitHub.field("Blocked") === "Yes"
                                text: "🚧 bloqueada"
                                color: Theme.danger
                                font.family: Theme.font
                                font.pixelSize: 10.5 * root.s
                                font.weight: Font.Bold
                            }
                            Rectangle {
                                id: blockSw
                                readonly property bool checked: GitHub.field("Blocked") === "Yes" || root.blockOpen
                                anchors.verticalCenter: parent.verticalCenter
                                width: 40 * root.s
                                height: 22 * root.s
                                radius: height / 2
                                color: checked ? Qt.alpha(Theme.danger, 0.8) : Qt.alpha(Theme.cream, 0.12)
                                Rectangle {
                                    width: parent.height - 6 * root.s
                                    height: width
                                    radius: width / 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: blockSw.checked ? parent.width - width - 3 * root.s : 3 * root.s
                                    color: "#ffffff"
                                    Behavior on x { NumberAnimation { duration: Motion.fast } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (GitHub.field("Blocked") === "Yes")
                                            GitHub.setBlocked(false);
                                        else
                                            root.blockOpen = !root.blockOpen;
                                        if (root.blockOpen)
                                            reason.forceActiveFocus();
                                    }
                                }
                            }
                        }
                    }

                    // reason required to block
                    Rectangle {
                        visible: root.blockOpen
                        width: parent.width
                        height: blockCol.implicitHeight + 20 * root.s
                        radius: 12 * root.s
                        color: Qt.alpha(Theme.danger, 0.07)
                        border.width: 1
                        border.color: Qt.alpha(Theme.danger, 0.3)

                        Column {
                            id: blockCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 10 * root.s
                            spacing: 8 * root.s
                            Text {
                                text: "Motivo do bloqueio (vira comentário na issue)"
                                color: Theme.danger
                                font.family: Theme.font
                                font.pixelSize: 10 * root.s
                                font.weight: Font.Bold
                            }
                            QQC.TextArea {
                                id: reason
                                width: parent.width
                                wrapMode: QQC.TextArea.Wrap
                                placeholderText: "Quem/o quê está bloqueando, o que falta, ETA…"
                                placeholderTextColor: Theme.faint
                                color: Theme.bright
                                background: Rectangle { radius: 8 * root.s; color: Qt.rgba(0, 0, 0, 0.25) }
                                font.family: Theme.font
                                font.pixelSize: 11.5 * root.s
                            }
                            Row {
                                spacing: 6 * root.s
                                layoutDirection: Qt.RightToLeft
                                width: parent.width
                                Pill {
                                    text: "Marcar bloqueada"
                                    tint: Theme.danger
                                    on: reason.text.trim().length > 0
                                    enabledLook: reason.text.trim().length > 0
                                    onClicked: if (reason.text.trim().length) {
                                        GitHub.setBlocked(true, reason.text);
                                        reason.text = "";
                                        root.blockOpen = false;
                                    }
                                }
                                Pill {
                                    text: "Cancelar"
                                    onClicked: {
                                        reason.text = "";
                                        root.blockOpen = false;
                                    }
                                }
                            }
                        }
                    }

                    Repeater {
                        model: ["Sprint", "Marco", "Produto"]
                        FieldRow {
                            id: ro
                            required property string modelData
                            visible: GitHub.field(modelData) !== undefined
                            label: modelData
                            Text {
                                text: String(GitHub.field(ro.modelData) || "")
                                color: Theme.cream
                                font.family: Theme.font
                                font.pixelSize: 11 * root.s
                                font.weight: Font.Medium
                            }
                        }
                    }
                }

                // labels + assignees
                Flow {
                    visible: root.d && (root.d.labels.length > 0 || root.d.assignees.length > 0)
                    width: parent.width
                    spacing: 6 * root.s
                    Repeater {
                        model: root.d ? root.d.assignees : []
                        Rectangle {
                            id: asg
                            required property var modelData
                            width: asgRow.implicitWidth + 14 * root.s
                            height: 24 * root.s
                            radius: height / 2
                            color: Theme.frameBg
                            border.width: 1
                            border.color: Theme.frameBorder
                            Row {
                                id: asgRow
                                anchors.centerIn: parent
                                spacing: 6 * root.s
                                Avatar { anchors.verticalCenter: parent.verticalCenter; src: asg.modelData.avatarUrl; size: 16 }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: asg.modelData.login
                                    color: Theme.cream
                                    font.family: Theme.font
                                    font.pixelSize: 10 * root.s
                                }
                            }
                        }
                    }
                    Repeater {
                        model: root.d ? root.d.labels : []
                        Rectangle {
                            id: lbl
                            required property var modelData
                            readonly property color c: "#" + modelData.color
                            width: lblText.implicitWidth + 16 * root.s
                            height: 24 * root.s
                            radius: height / 2
                            color: Qt.alpha(c, 0.18)
                            border.width: 1
                            border.color: Qt.alpha(c, 0.5)
                            Text {
                                id: lblText
                                anchors.centerIn: parent
                                text: lbl.modelData.name
                                color: Qt.lighter(lbl.c, 1.3)
                                font.family: Theme.font
                                font.pixelSize: 10 * root.s
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }

                // parent / sub-issues / PRs
                Column {
                    visible: root.d && (root.d.parent || root.d.subIssues.length || root.d.prs.length)
                    width: parent.width
                    spacing: 2 * root.s

                    Section { visible: root.d && root.d.parent; text: "Issue pai" }
                    LinkRow {
                        visible: root.d && root.d.parent
                        icon: "back"
                        text: root.d && root.d.parent ? "#" + root.d.parent.number + "  " + root.d.parent.title : ""
                        url: root.d && root.d.parent ? root.d.parent.url : ""
                    }

                    Item {
                        visible: root.d && root.d.subIssues.length > 0
                        width: parent.width
                        height: 26 * root.s
                        Section { text: "Sub-issues"; anchors.verticalCenter: parent.verticalCenter }
                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8 * root.s
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 90 * root.s
                                height: 5 * root.s
                                radius: height / 2
                                color: Theme.threadBg
                                Rectangle {
                                    width: parent.width * (root.d ? root.d.subSummary.percentCompleted / 100 : 0)
                                    height: parent.height
                                    radius: parent.radius
                                    color: Theme.ok
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.d ? root.d.subSummary.completed + "/" + root.d.subSummary.total : ""
                                color: Theme.subtle
                                font.family: Theme.font
                                font.pixelSize: 10 * root.s
                                font.weight: Font.Bold
                            }
                        }
                    }
                    Repeater {
                        model: root.d ? root.d.subIssues : []
                        LinkRow {
                            required property var modelData
                            icon: modelData.state === "OPEN" ? "shield" : "shieldCheck"
                            iconColor: modelData.state === "OPEN" ? Theme.ok : "#a371f7"
                            text: "#" + modelData.number + "  " + modelData.title
                            url: modelData.url
                        }
                    }

                    Section { visible: root.d && root.d.prs.length > 0; text: "Pull requests" }
                    Repeater {
                        model: root.d ? root.d.prs : []
                        LinkRow {
                            required property var modelData
                            icon: "github"
                            iconColor: modelData.state === "MERGED" ? "#a371f7" : (modelData.state === "OPEN" ? Theme.ok : Theme.danger)
                            text: "#" + modelData.number + "  " + modelData.title
                            meta: modelData.isDraft ? "rascunho" : ({ "MERGED": "merged", "OPEN": "aberto", "CLOSED": "fechado" })[modelData.state]
                            metaColor: iconColor
                            url: modelData.url
                        }
                    }
                }

                // description
                Section { text: "Descrição" }
                Item {
                    width: parent.width
                    readonly property real full: descText.implicitHeight
                    readonly property real cap: 360 * root.s
                    height: root.showFullBody || full <= cap ? full : cap
                    clip: true

                    TextEdit {
                        id: descText
                        width: parent.width
                        readOnly: true
                        selectByMouse: true
                        textFormat: TextEdit.MarkdownText
                        wrapMode: TextEdit.Wrap
                        text: root.d ? (root.d.body.length ? root.d.body : "_Sem descrição._") : ""
                        color: Theme.cream
                        selectionColor: Qt.alpha(Theme.info, 0.4)
                        font.family: Theme.font
                        font.pixelSize: 12 * root.s
                        onLinkActivated: (link) => Qt.openUrlExternally(link)
                    }

                    Rectangle {
                        visible: !root.showFullBody && parent.full > parent.cap
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 60 * root.s
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.alpha(Theme.cardBot, 0) }
                            GradientStop { position: 1.0; color: Theme.cardBot }
                        }
                    }
                }
                Pill {
                    visible: descText.implicitHeight > 360 * root.s
                    text: root.showFullBody ? "Mostrar menos" : "Ler descrição inteira"
                    onClicked: root.showFullBody = !root.showFullBody
                }

                // comments
                Section {
                    text: root.d ? "Comentários  " + root.d.commentCount : "Comentários"
                }
                Text {
                    visible: root.d && root.d.comments.length === 0
                    text: "Nenhum comentário ainda"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                }
                Repeater {
                    model: root.d ? root.d.comments : []
                    Rectangle {
                        id: cm
                        required property var modelData
                        width: col.width
                        height: cmCol.implicitHeight + 22 * root.s
                        radius: 12 * root.s
                        color: Theme.frameBg
                        border.width: 1
                        border.color: Theme.frameBorder

                        Column {
                            id: cmCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 11 * root.s
                            spacing: 6 * root.s
                            Row {
                                spacing: 7 * root.s
                                Avatar { anchors.verticalCenter: parent.verticalCenter; src: cm.modelData.author ? cm.modelData.author.avatarUrl : ""; size: 18 }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (cm.modelData.author ? cm.modelData.author.login : "ghost") + "  ·  há " + root.ago(cm.modelData.createdAt)
                                    color: Theme.subtle
                                    font.family: Theme.font
                                    font.pixelSize: 10 * root.s
                                    font.weight: Font.DemiBold
                                }
                            }
                            TextEdit {
                                width: parent.width
                                readOnly: true
                                selectByMouse: true
                                textFormat: TextEdit.MarkdownText
                                wrapMode: TextEdit.Wrap
                                text: cm.modelData.body
                                color: Theme.cream
                                selectionColor: Qt.alpha(Theme.info, 0.4)
                                font.family: Theme.font
                                font.pixelSize: 11.5 * root.s
                                onLinkActivated: (link) => Qt.openUrlExternally(link)
                            }
                        }
                    }
                }

                // close / reopen
                Row {
                    visible: root.d !== null
                    spacing: 6 * root.s
                    topPadding: 4 * root.s
                    bottomPadding: 6 * root.s
                    Pill {
                        readonly property bool isOpen: root.d && root.d.state === "OPEN"
                        text: isOpen ? (root.confirmClose ? "Confirmar: fechar como concluída" : "Fechar issue") : "Reabrir issue"
                        tint: isOpen ? "#a371f7" : Theme.ok
                        on: root.confirmClose
                        onClicked: {
                            if (!isOpen) {
                                GitHub.reopenIssue();
                            } else if (root.confirmClose) {
                                root.confirmClose = false;
                                GitHub.closeIssue();
                            } else {
                                root.confirmClose = true;
                            }
                        }
                    }
                }
            }
        }

        // ---- comment composer ----
        Rectangle {
            id: composer
            visible: root.d !== null
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18 * root.s
            width: parent.width
            height: visible ? Math.min(cmInput.implicitHeight, 120 * root.s) + 46 * root.s : 0
            radius: 14 * root.s
            color: Theme.frameBg
            border.width: 1
            border.color: cmInput.activeFocus ? Qt.alpha(Theme.cream, 0.22) : Theme.frameBorder

            QQC.ScrollView {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8 * root.s
                height: Math.min(cmInput.implicitHeight, 120 * root.s)
                QQC.TextArea {
                    id: cmInput
                    background: null
                    wrapMode: QQC.TextArea.Wrap
                    placeholderText: "Escrever um comentário…  (Ctrl+Enter envia)"
                    placeholderTextColor: Theme.faint
                    color: Theme.bright
                    selectionColor: Qt.alpha(Theme.info, 0.4)
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                    Keys.onPressed: (e) => {
                        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && (e.modifiers & Qt.ControlModifier)) {
                            GitHub.comment(cmInput.text);
                            cmInput.text = "";
                            e.accepted = true;
                        }
                    }
                }
            }

            Row {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 8 * root.s
                spacing: 6 * root.s
                Pill {
                    text: GitHub.busy === "comment" ? "Enviando…" : "Comentar"
                    tint: Theme.ok
                    on: cmInput.text.trim().length > 0
                    enabledLook: cmInput.text.trim().length > 0
                    onClicked: if (cmInput.text.trim().length) {
                        GitHub.comment(cmInput.text);
                        cmInput.text = "";
                    }
                }
            }
        }
    }

    ClaudeIssuePopover {
        id: pop
        anchors.fill: parent
        anchors.rightMargin: 22 * root.s
        z: 100
        s: root.s
    }
}
