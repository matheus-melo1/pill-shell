pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import "Singletons"

/**
 * Pull request detail pane, the PR counterpart of IssueDetail, opened from the
 * Review and Meus PRs tabs. Top bar, title with state (open / draft / merged /
 * closed), author and ages, then:
 *
 *  - Branches (head → base) with a copy of `gh pr checkout N`, and the diff
 *    size as +/−, file count and a five-square bar.
 *  - A merge card that reads mergeStateStatus in plain words. For the
 *    viewer's own PR it offers merge (method segments, confirm on a second
 *    click), ready-for-review / back to draft, and close / reopen; for
 *    someone else's it offers Approve, Request changes and Comment reviews,
 *    the last two requiring text.
 *  - CI checks of the head commit (failures first, each opens its run),
 *    reviews with their verdicts plus pending reviewers, issues the PR closes
 *    (open in this pane), changed files, the Markdown description, comments
 *    and a comment box (Ctrl+Enter).
 *  - A Claude button in the top bar (open PRs) opening the same stepped
 *    ClaudeReviewPopover as the list rows, tinted by the review's state.
 *    While a background review of the PR exists, a card with its live state,
 *    "Abrir no tmux" (switches your open tmux to its window) and a
 *    confirm-to-stop. Escape closes the popover
 *    first (popOpen / closePop for the drawer).
 */
Item {
    id: root

    property real s: 1
    property real paneW: 540 * s
    signal requestClose()

    clip: true

    readonly property var d: GitHub.detailKind === "pr" ? GitHub.detail : null
    readonly property bool isOpen: d !== null && d.state === "OPEN"
    property string mergeMethod: ""
    property bool confirmMerge: false
    property bool confirmClose: false
    property string reviewMode: ""
    property bool showFullBody: false
    property bool showAllFiles: false
    property real now: Date.now()
    property bool confirmStop: false

    readonly property var job: d ? GitHub.claudeReviewFor(GitHub.detailUrl) : null
    readonly property bool popOpen: pop.shown
    function closePop() {
        pop.hide();
    }

    onDChanged: {
        confirmMerge = false;
        confirmClose = false;
        if (d && d.mergeMethods.indexOf(mergeMethod) < 0)
            mergeMethod = d.mergeMethods[0] || "";
    }

    Connections {
        target: GitHub
        function onDetailUrlChanged() {
            root.showFullBody = false;
            root.showAllFiles = false;
            root.reviewMode = "";
            root.confirmStop = false;
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

    readonly property var stateInfo: {
        if (!d)
            return { text: "", color: Theme.dim };
        if (d.state === "MERGED")
            return { text: "Merged", color: "#a371f7" };
        if (d.state === "CLOSED")
            return { text: "Fechado", color: Theme.danger };
        if (d.isDraft)
            return { text: "Rascunho", color: Theme.subtle };
        return { text: "Aberto", color: Theme.ok };
    }

    /** mergeStateStatus in plain words, with a tone. */
    readonly property var mergeInfo: {
        if (!d)
            return { text: "", color: Theme.dim };
        if (d.state === "MERGED")
            return { text: "Já foi feito o merge deste PR", color: "#a371f7" };
        if (d.state === "CLOSED")
            return { text: "PR fechado sem merge", color: Theme.danger };
        if (d.mergeable === "CONFLICTING" || d.mergeState === "DIRTY")
            return { text: "Conflitos com " + d.base + ": resolva antes do merge", color: Theme.danger };
        return ({
            "CLEAN": { text: "Pronto para merge", color: Theme.ok },
            "HAS_HOOKS": { text: "Pronto para merge (com hooks)", color: Theme.ok },
            "UNSTABLE": { text: "Mergeável, mas há checks falhando", color: Theme.warn },
            "BLOCKED": { text: d.reviewDecision === "REVIEW_REQUIRED" ? "Bloqueado: falta review aprovado"
                : (d.reviewDecision === "CHANGES_REQUESTED" ? "Bloqueado: pediram mudanças" : "Bloqueado pelas regras da branch"), color: Theme.warn },
            "BEHIND": { text: "Desatualizado com " + d.base, color: Theme.warn },
            "DRAFT": { text: "Rascunho: marque como pronto para revisar", color: Theme.subtle }
        })[d.mergeState] || { text: "Calculando estado do merge…", color: Theme.dim };
    }

    function checkColor(st) {
        return st === "success" ? Theme.ok : (st === "failure" ? Theme.danger : (st === "pending" ? Theme.warn : Theme.faint));
    }

    function reviewInfo(st) {
        return ({
            "APPROVED": { text: "aprovou", color: Theme.ok },
            "CHANGES_REQUESTED": { text: "pediu mudanças", color: Theme.danger },
            "COMMENTED": { text: "comentou", color: Theme.subtle },
            "DISMISSED": { text: "dispensado", color: Theme.faint }
        })[st] || { text: st.toLowerCase(), color: Theme.subtle };
    }

    readonly property var checkCounts: {
        var c = { success: 0, failure: 0, pending: 0, neutral: 0 };
        if (d)
            d.checks.forEach(function(x) { c[x.state]++; });
        return c;
    }

    component Section: GhSection { s: root.s }
    component Avatar: GhAvatar { s: root.s }
    component Pill: GhPill { s: root.s }
    component LinkRow: GhLinkRow { s: root.s }

    component Card: Rectangle {
        default property alias content: cardCol.data
        property alias spacing: cardCol.spacing
        width: parent ? parent.width : 0
        height: cardCol.implicitHeight + 24 * root.s
        radius: 14 * root.s
        color: Theme.frameBg
        border.width: 1
        border.color: Theme.frameBorder

        Column {
            id: cardCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12 * root.s
            spacing: 10 * root.s
        }
    }

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
                    text: root.d ? root.d.repo.split("/")[1] + "  PR #" + root.d.number : "carregando…"
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

                // Claude review: opens the stepped popover for this PR.
                ClaudeButton {
                    id: aiBtn
                    visible: root.isOpen
                    anchors.verticalCenter: parent.verticalCenter
                    s: root.s
                    size: 28
                    job: root.job
                    open: pop.shown
                    onClicked: if (root.d) pop.toggle(aiBtn, { url: GitHub.detailUrl, title: root.d.title, repo: root.d.repo, number: root.d.number })
                }

                Repeater {
                    model: [{ icon: "retry", act: "reload" }, { icon: "send", act: "open" }, { icon: "x", act: "close" }]
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
                        width: stLabel.implicitWidth + 26 * root.s
                        height: 22 * root.s
                        radius: height / 2
                        color: Qt.alpha(root.stateInfo.color, 0.16)
                        border.width: 1
                        border.color: Qt.alpha(root.stateInfo.color, 0.4)
                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: 9 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6 * root.s
                            height: width
                            radius: width / 2
                            color: root.stateInfo.color
                        }
                        Text {
                            id: stLabel
                            anchors.right: parent.right
                            anchors.rightMargin: 8 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.stateInfo.text
                            color: root.stateInfo.color
                            font.family: Theme.font
                            font.pixelSize: 10 * root.s
                            font.weight: Font.Bold
                        }
                    }
                    Avatar {
                        anchors.verticalCenter: parent.verticalCenter
                        src: root.d ? root.d.author.avatarUrl : ""
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.d ? root.d.author.login + " abriu há " + root.ago(root.d.createdAt) + "  ·  atualizado há " + root.ago(root.d.updatedAt) : ""
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                    }
                }

                // branches + diff size
                Row {
                    spacing: 6 * root.s
                    Repeater {
                        model: root.d ? [root.d.head, "→", root.d.base] : []
                        Rectangle {
                            id: br
                            required property string modelData
                            readonly property bool arrow: modelData === "→"
                            anchors.verticalCenter: parent.verticalCenter
                            width: brText.implicitWidth + (arrow ? 0 : 16 * root.s)
                            height: 22 * root.s
                            radius: 7 * root.s
                            color: arrow ? "transparent" : Qt.alpha(Theme.info, 0.10)
                            Text {
                                id: brText
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth, 190 * root.s)
                                elide: Text.ElideMiddle
                                text: br.modelData
                                color: br.arrow ? Theme.faint : Theme.info
                                font.family: br.arrow ? Theme.font : "monospace"
                                font.pixelSize: 10.5 * root.s
                            }
                        }
                    }
                    Pill {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "copiar checkout"
                        onClicked: if (root.d) Ai.copy("gh pr checkout " + root.d.number + " -R " + root.d.repo)
                    }
                }

                Row {
                    visible: root.d !== null
                    spacing: 10 * root.s
                    Text {
                        text: root.d ? "+" + root.d.additions : ""
                        color: Theme.ok
                        font.family: Theme.font
                        font.pixelSize: 12 * root.s
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                    }
                    Text {
                        text: root.d ? "−" + root.d.deletions : ""
                        color: Theme.danger
                        font.family: Theme.font
                        font.pixelSize: 12 * root.s
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2 * root.s
                        Repeater {
                            model: 5
                            Rectangle {
                                required property int index
                                readonly property real total: root.d ? root.d.additions + root.d.deletions : 0
                                readonly property int greens: total > 0 ? Math.round(5 * root.d.additions / total) : 0
                                width: 9 * root.s
                                height: width
                                radius: 2 * root.s
                                color: total === 0 ? Theme.threadBg : (index < greens ? Theme.ok : Theme.danger)
                            }
                        }
                    }
                    Text {
                        text: root.d ? root.d.changedFiles + (root.d.changedFiles === 1 ? " arquivo" : " arquivos") : ""
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
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

                // ---- merge / review card ----
                Card {
                    Row {
                        spacing: 8 * root.s
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8 * root.s
                            height: width
                            radius: width / 2
                            color: root.mergeInfo.color
                        }
                        Text {
                            text: root.mergeInfo.text
                            color: root.mergeInfo.color
                            font.family: Theme.font
                            font.pixelSize: 12 * root.s
                            font.weight: Font.Bold
                        }
                    }

                    // own PR: merge controls
                    Column {
                        visible: root.d && root.d.mine && root.isOpen
                        width: parent.width
                        spacing: 8 * root.s

                        Row {
                            visible: root.d && !root.d.isDraft
                            spacing: 6 * root.s
                            Repeater {
                                model: root.d ? root.d.mergeMethods : []
                                Pill {
                                    required property string modelData
                                    text: ({ "SQUASH": "Squash", "MERGE": "Merge commit", "REBASE": "Rebase" })[modelData]
                                    tint: Theme.info
                                    on: root.mergeMethod === modelData
                                    onClicked: {
                                        root.mergeMethod = modelData;
                                        root.confirmMerge = false;
                                    }
                                }
                            }
                        }

                        Row {
                            spacing: 6 * root.s
                            Pill {
                                visible: root.d && !root.d.isDraft
                                text: root.confirmMerge ? "Confirmar merge em " + (root.d ? root.d.base : "") : "Fazer merge"
                                tint: Theme.ok
                                on: true
                                enabledLook: root.d && root.d.mergeable !== "CONFLICTING"
                                hoverable: root.d && root.d.mergeable !== "CONFLICTING" && GitHub.busy.length === 0
                                onClicked: {
                                    if (root.confirmMerge) {
                                        root.confirmMerge = false;
                                        GitHub.mergePr(root.mergeMethod);
                                    } else {
                                        root.confirmMerge = true;
                                    }
                                }
                            }
                            Pill {
                                text: root.d && root.d.isDraft ? "Marcar como pronto" : "Voltar para rascunho"
                                tint: root.d && root.d.isDraft ? Theme.ok : Theme.subtle
                                on: root.d && root.d.isDraft
                                onClicked: GitHub.setDraft(!root.d.isDraft)
                            }
                            Pill {
                                text: root.confirmClose ? "Confirmar: fechar PR" : "Fechar PR"
                                tint: Theme.danger
                                on: root.confirmClose
                                onClicked: {
                                    if (root.confirmClose) {
                                        root.confirmClose = false;
                                        GitHub.closePr();
                                    } else {
                                        root.confirmClose = true;
                                    }
                                }
                            }
                        }
                    }

                    // someone else's PR: review actions
                    Column {
                        visible: root.d && !root.d.mine && root.isOpen
                        width: parent.width
                        spacing: 8 * root.s

                        Row {
                            spacing: 6 * root.s
                            Pill {
                                text: "✓ Aprovar"
                                tint: Theme.ok
                                on: root.reviewMode === "APPROVE"
                                onClicked: root.reviewMode = root.reviewMode === "APPROVE" ? "" : "APPROVE"
                            }
                            Pill {
                                text: "Pedir mudanças"
                                tint: Theme.danger
                                on: root.reviewMode === "REQUEST_CHANGES"
                                onClicked: root.reviewMode = root.reviewMode === "REQUEST_CHANGES" ? "" : "REQUEST_CHANGES"
                            }
                            Pill {
                                text: "Comentar review"
                                tint: Theme.info
                                on: root.reviewMode === "COMMENT"
                                onClicked: root.reviewMode = root.reviewMode === "COMMENT" ? "" : "COMMENT"
                            }
                        }

                        Rectangle {
                            visible: root.reviewMode.length > 0
                            width: parent.width
                            height: rvCol.implicitHeight + 16 * root.s
                            radius: 10 * root.s
                            color: Qt.rgba(0, 0, 0, 0.22)

                            Column {
                                id: rvCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 8 * root.s
                                spacing: 6 * root.s
                                QQC.TextArea {
                                    id: rvText
                                    width: parent.width
                                    wrapMode: QQC.TextArea.Wrap
                                    background: null
                                    placeholderText: root.reviewMode === "APPROVE" ? "Comentário opcional…" : "O que precisa mudar / o que comentar (obrigatório)"
                                    placeholderTextColor: Theme.faint
                                    color: Theme.bright
                                    font.family: Theme.font
                                    font.pixelSize: 11.5 * root.s
                                }
                                Row {
                                    width: parent.width
                                    layoutDirection: Qt.RightToLeft
                                    readonly property bool canSend: root.reviewMode === "APPROVE" || rvText.text.trim().length > 0
                                    Pill {
                                        text: ({ "APPROVE": "Enviar aprovação", "REQUEST_CHANGES": "Enviar pedido de mudanças", "COMMENT": "Enviar review" })[root.reviewMode] || ""
                                        tint: root.reviewMode === "REQUEST_CHANGES" ? Theme.danger : (root.reviewMode === "APPROVE" ? Theme.ok : Theme.info)
                                        on: parent.canSend
                                        enabledLook: parent.canSend
                                        onClicked: if (parent.canSend) {
                                            GitHub.review(root.reviewMode, rvText.text);
                                            rvText.text = "";
                                            root.reviewMode = "";
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Pill {
                        visible: root.d && root.d.state === "CLOSED"
                        text: "Reabrir PR"
                        tint: Theme.ok
                        onClicked: GitHub.reopenPr()
                    }
                }

                // ---- background Claude review ----
                Card {
                    id: cr
                    visible: job !== null
                    readonly property var job: root.job
                    readonly property var stateInfo: !job ? null : ({
                        "starting": { text: "Abrindo a sessão…", color: Theme.warn },
                        "busy": { text: "Claude revisando…", color: Theme.claude },
                        "idle": { text: "Review pronto, esperando você no terminal", color: Theme.ok },
                        "dead": { text: "A sessão encerrou", color: Theme.danger }
                    })[job.state]

                    Item {
                        width: parent.width
                        height: 18 * root.s
                        Section { text: "Review com Claude"; topPadding: 0; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "tmux: " + GitHub.claudeSession
                            color: Theme.faint
                            font.family: "monospace"
                            font.pixelSize: 9.5 * root.s
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 8 * root.s

                        Row {
                            spacing: 8 * root.s
                            Rectangle {
                                id: crDot
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8 * root.s
                                height: width
                                radius: width / 2
                                color: cr.stateInfo ? cr.stateInfo.color : Theme.faint
                                SequentialAnimation on opacity {
                                    running: cr.job !== null && (cr.job.state === "busy" || cr.job.state === "starting") && root.visible
                                    loops: Animation.Infinite
                                    onRunningChanged: if (!running) crDot.opacity = 1
                                    NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                                }
                            }
                            Text {
                                text: cr.stateInfo ? cr.stateInfo.text : ""
                                color: cr.stateInfo ? cr.stateInfo.color : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 12 * root.s
                                font.weight: Font.Bold
                            }
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: !cr.job ? "" : (cr.job.account === "work" ? "trabalho" : "pessoal") + "  ·  " + cr.job.model
                                + "  ·  " + cr.job.effort + "  ·  " + (cr.job.post ? "publica no PR" : "só no terminal")
                                + "  ·  há " + root.ago(new Date(cr.job.started).toISOString())
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 10.5 * root.s
                        }
                        Text {
                            visible: GitHub.claudeError.length > 0 && GitHub.claudeErrorUrl === GitHub.detailUrl
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: GitHub.claudeError
                            color: Theme.danger
                            font.family: Theme.font
                            font.pixelSize: 10.5 * root.s
                        }
                        Row {
                            spacing: 6 * root.s
                            Pill {
                                text: "Abrir no tmux"
                                tint: Theme.claude
                                on: true
                                onClicked: GitHub.attachClaudeReview(cr.job.window)
                            }
                            Pill {
                                text: root.confirmStop ? "Confirmar: encerrar" : (cr.job && cr.job.state === "dead" ? "Limpar" : "Encerrar")
                                tint: Theme.danger
                                on: root.confirmStop
                                onClicked: {
                                    if (root.confirmStop || cr.job.state === "dead") {
                                        root.confirmStop = false;
                                        GitHub.stopClaudeReview(cr.job.window);
                                    } else {
                                        root.confirmStop = true;
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- checks ----
                Card {
                    visible: root.d && root.d.checks.length > 0
                    spacing: 4 * root.s

                    Item {
                        width: parent.width
                        height: 18 * root.s
                        Section { text: "Checks"; topPadding: 0; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.checkCounts.success + "/" + (root.d ? root.d.checks.length : 0) + " passaram"
                                + (root.checkCounts.failure ? "  ·  " + root.checkCounts.failure + " falharam" : "")
                                + (root.checkCounts.pending ? "  ·  " + root.checkCounts.pending + " rodando" : "")
                            color: root.checkCounts.failure ? Theme.danger : (root.checkCounts.pending ? Theme.warn : Theme.ok)
                            font.family: Theme.font
                            font.pixelSize: 10 * root.s
                            font.weight: Font.DemiBold
                        }
                    }

                    Repeater {
                        model: root.d ? root.d.checks : []
                        Rectangle {
                            id: ck
                            required property var modelData
                            width: parent.width
                            height: 28 * root.s
                            radius: 8 * root.s
                            color: ckArea.containsMouse ? Qt.alpha(Theme.cream, 0.05) : "transparent"

                            Rectangle {
                                id: ckDot
                                anchors.left: parent.left
                                anchors.leftMargin: 6 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8 * root.s
                                height: width
                                radius: width / 2
                                color: root.checkColor(ck.modelData.state)
                                SequentialAnimation on opacity {
                                    running: ck.modelData.state === "pending" && root.visible
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.3; duration: 600 }
                                    NumberAnimation { to: 1; duration: 600 }
                                }
                            }
                            Text {
                                anchors.left: ckDot.right
                                anchors.leftMargin: 10 * root.s
                                anchors.right: ckState.left
                                anchors.rightMargin: 8 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: ck.modelData.name
                                color: ckArea.containsMouse ? Theme.bright : Theme.cream
                                font.family: Theme.font
                                font.pixelSize: 11.5 * root.s
                            }
                            Text {
                                id: ckState
                                anchors.right: parent.right
                                anchors.rightMargin: 6 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                text: ({ "success": "passou", "failure": "falhou", "pending": "rodando", "neutral": "neutro" })[ck.modelData.state]
                                color: root.checkColor(ck.modelData.state)
                                font.family: Theme.font
                                font.pixelSize: 9 * root.s
                                font.weight: Font.Bold
                                font.capitalization: Font.AllUppercase
                            }
                            MouseArea {
                                id: ckArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (ck.modelData.url) Qt.openUrlExternally(ck.modelData.url)
                            }
                        }
                    }
                }

                // ---- reviews ----
                Column {
                    visible: root.d && (root.d.reviews.length > 0 || root.d.requested.length > 0)
                    width: parent.width
                    spacing: 6 * root.s

                    Section { text: "Reviews" }
                    Repeater {
                        model: root.d ? root.d.reviews : []
                        Row {
                            id: rv
                            required property var modelData
                            readonly property var info: root.reviewInfo(modelData.state)
                            spacing: 8 * root.s
                            Avatar { anchors.verticalCenter: parent.verticalCenter; src: rv.modelData.author ? rv.modelData.author.avatarUrl : "" }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: rv.modelData.author ? rv.modelData.author.login : "ghost"
                                color: Theme.cream
                                font.family: Theme.font
                                font.pixelSize: 11.5 * root.s
                                font.weight: Font.DemiBold
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: rv.info.text + (rv.modelData.submittedAt ? "  ·  há " + root.ago(rv.modelData.submittedAt) : "")
                                color: rv.info.color
                                font.family: Theme.font
                                font.pixelSize: 10.5 * root.s
                            }
                        }
                    }
                    Repeater {
                        model: root.d ? root.d.requested : []
                        Row {
                            id: rq
                            required property var modelData
                            spacing: 8 * root.s
                            Avatar { anchors.verticalCenter: parent.verticalCenter; src: rq.modelData.avatarUrl }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: rq.modelData.login
                                color: Theme.cream
                                font.family: Theme.font
                                font.pixelSize: 11.5 * root.s
                                font.weight: Font.DemiBold
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "review pendente"
                                color: Theme.warn
                                font.family: Theme.font
                                font.pixelSize: 10.5 * root.s
                            }
                        }
                    }
                }

                // labels
                Flow {
                    visible: root.d && root.d.labels.length > 0
                    width: parent.width
                    spacing: 6 * root.s
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

                // closes issues (open in this pane)
                Column {
                    visible: root.d && root.d.closes.length > 0
                    width: parent.width
                    spacing: 2 * root.s
                    Section { text: "Fecha as issues" }
                    Repeater {
                        model: root.d ? root.d.closes : []
                        LinkRow {
                            required property var modelData
                            icon: modelData.state === "OPEN" ? "shield" : "shieldCheck"
                            iconColor: modelData.state === "OPEN" ? Theme.ok : "#a371f7"
                            text: "#" + modelData.number + "  " + modelData.title
                            meta: "abrir"
                            external: false
                            onClicked: GitHub.openIssue(modelData.url)
                        }
                    }
                }

                // files
                Column {
                    visible: root.d && root.d.files.length > 0
                    width: parent.width
                    spacing: 2 * root.s
                    Section { text: root.d ? "Arquivos  " + root.d.fileCount : "Arquivos" }
                    Repeater {
                        model: root.d ? root.d.files.slice(0, root.showAllFiles ? root.d.files.length : 8) : []
                        Item {
                            id: fl
                            required property var modelData
                            width: parent.width
                            height: 24 * root.s
                            Rectangle {
                                id: flType
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16 * root.s
                                height: width
                                radius: 4 * root.s
                                readonly property string t: ({ "ADDED": "A", "DELETED": "D", "RENAMED": "R", "COPIED": "C" })[fl.modelData.changeType] || "M"
                                readonly property color c: t === "A" ? Theme.ok : (t === "D" ? Theme.danger : (t === "R" ? Theme.info : Theme.warn))
                                color: Qt.alpha(c, 0.16)
                                Text {
                                    anchors.centerIn: parent
                                    text: flType.t
                                    color: flType.c
                                    font.family: "monospace"
                                    font.pixelSize: 9 * root.s
                                    font.weight: Font.Bold
                                }
                            }
                            Text {
                                anchors.left: flType.right
                                anchors.leftMargin: 8 * root.s
                                anchors.right: flStat.left
                                anchors.rightMargin: 8 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideLeft
                                text: fl.modelData.path
                                color: Theme.cream
                                font.family: "monospace"
                                font.pixelSize: 10 * root.s
                            }
                            Row {
                                id: flStat
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6 * root.s
                                Text {
                                    text: "+" + fl.modelData.additions
                                    color: Theme.ok
                                    font.family: Theme.font
                                    font.pixelSize: 10 * root.s
                                    font.features: { "tnum": 1 }
                                }
                                Text {
                                    text: "−" + fl.modelData.deletions
                                    color: Theme.danger
                                    font.family: Theme.font
                                    font.pixelSize: 10 * root.s
                                    font.features: { "tnum": 1 }
                                }
                            }
                        }
                    }
                    Pill {
                        visible: root.d && root.d.files.length > 8
                        text: root.showAllFiles ? "Mostrar menos" : "Ver todos os " + (root.d ? root.d.files.length : 0)
                        onClicked: root.showAllFiles = !root.showAllFiles
                    }
                }

                // description
                Section { text: "Descrição" }
                Item {
                    width: parent.width
                    readonly property real full: descText.implicitHeight
                    readonly property real cap: 320 * root.s
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
                    visible: descText.implicitHeight > 320 * root.s
                    text: root.showFullBody ? "Mostrar menos" : "Ler descrição inteira"
                    onClicked: root.showFullBody = !root.showFullBody
                }

                // comments
                Section { text: root.d ? "Comentários  " + root.d.commentCount : "Comentários" }
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
                Item { width: 1; height: 4 * root.s }
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
                    placeholderText: "Comentar no PR…  (Ctrl+Enter envia)"
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

            Pill {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 8 * root.s
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

    ClaudeReviewPopover {
        id: pop
        anchors.fill: parent
        anchors.rightMargin: 22 * root.s
        z: 100
        s: root.s
    }
}
