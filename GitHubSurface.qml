pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import "Singletons"

/**
 * 源 GITHUB surface. A header (kanji, avatar, login) over a strip of four stat
 * tiles that double as tabs: Issues, Review, PRs and Actions, each with its
 * count and an accent dot. The selected tab fills the body:
 *
 *  - Issues: a two-column board of the viewer's assigned issues in In Progress
 *    and Ready. Cards carry repo#n, the title (type prefixes like "[Story]"
 *    stripped, since the type is a chip), priority/type chips and the
 *    estimate, with a status-coloured edge.
 *  - Review / PRs / Actions: rows with a status dot, title, sub line and tag.
 *    A Review row with a background Claude review shows its state as the tag.
 *    Review and PR rows end in a Claude button that opens the stepped
 *    ClaudeReviewPopover for that PR; the button takes the review's state
 *    colour (pulsing while it runs). Escape closes the popover first.
 *    Under those two lists, while the claude-reviews tmux session has review
 *    windows, a footer counts them and "Limpar janelas" closes them all
 *    (asking to confirm when some are still running).
 *
 * Until the first snapshot lands, tab counts, board columns and list rows
 * show shimmering skeletons shaped like the real cards.
 *
 * Bodies scroll past `maxBody`. Every card/row opens its URL in the browser and
 * closes the surface; opening the surface triggers a refresh. Exposes
 * `implicitHeight` from its content and docks Ame as a soul at the kanji.
 */
PillSurface {
    id: root

    mTop: 16
    mLeft: 19
    mRight: 19
    mBottom: 16

    implicitHeight: content.implicitHeight

    property string tab: "issues"
    property real maxBody: 372 * s

    readonly property bool loading: !GitHub.ready
    property real skelPhase: 0
    NumberAnimation on skelPhase {
        running: root.loading && root.open
        from: 0; to: 1
        duration: 1300
        loops: Animation.Infinite
        easing.type: Easing.InOutQuad
    }

    component SkBone: Bone {
        s: root.s
        phase: root.skelPhase
    }

    /** Placeholder shaped like an IssueCard. */
    component SkeletonCard: Rectangle {
        width: parent ? parent.width : 0
        height: skCol.implicitHeight + 22 * root.s
        radius: 11 * root.s
        color: Theme.frameBg
        border.width: 1
        border.color: Theme.frameBorder

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 1
            anchors.verticalCenter: parent.verticalCenter
            width: 2.5 * root.s
            height: parent.height - 22 * root.s
            radius: width / 2
            color: Qt.alpha(Theme.cream, 0.08)
        }

        Column {
            id: skCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 14 * root.s
            anchors.rightMargin: 12 * root.s
            anchors.topMargin: 11 * root.s
            spacing: 8 * root.s

            Item {
                width: parent.width
                height: 10 * root.s
                SkBone { width: parent.width * 0.42; height: 10 * root.s }
                SkBone { anchors.right: parent.right; width: 30 * root.s; height: 10 * root.s }
            }
            SkBone { w: 0.94; height: 12 * root.s }
            SkBone { w: 0.62; height: 12 * root.s }
            Row {
                spacing: 5 * root.s
                SkBone { width: 26 * root.s; height: 17 * root.s; radius: 8.5 * root.s }
                SkBone { width: 44 * root.s; height: 17 * root.s; radius: 8.5 * root.s }
            }
        }
    }

    /** Placeholder shaped like an EntryRow. */
    component SkeletonRow: Item {
        width: parent ? parent.width : 0
        height: 38 * root.s

        SkBone {
            anchors.left: parent.left
            anchors.leftMargin: 10 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 7 * root.s
            height: width
            radius: width / 2
        }
        Column {
            anchors.left: parent.left
            anchors.leftMargin: 28 * root.s
            anchors.right: parent.right
            anchors.rightMargin: 90 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6 * root.s
            SkBone { w: 0.85; height: 11 * root.s }
            SkBone { w: 0.45; height: 8 * root.s }
        }
        SkBone {
            anchors.right: parent.right
            anchors.rightMargin: 10 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 62 * root.s
            height: 17 * root.s
            radius: 8.5 * root.s
        }
    }

    readonly property point kanjiPoint: {
        void root.width;
        void root.height;
        return kanji.mapToItem(root, kanji.width / 2, kanji.height / 2);
    }

    ameForm: open ? "soul" : "off"
    amePoint: kanjiPoint

    property real now: Date.now()

    // Two-step "Limpar janelas" while any review is still running.
    property bool confirmClear: false

    /** Review windows in the tmux session and how many are still working. */
    readonly property var reviewWindows: {
        var all = GitHub.claudeReviews;
        var running = 0;
        for (var i = 0; i < all.length; i++) {
            var j = GitHub.claudeReviewFor(all[i].url);
            if (j && (j.state === "busy" || j.state === "starting"))
                running++;
        }
        return { total: all.length, running: running };
    }
    onReviewWindowsChanged: if (reviewWindows.running === 0) confirmClear = false

    onOpenChanged: if (open) {
        now = Date.now();
        GitHub.refresh();
        GitHub.listClaudeReviews();
    } else {
        pop.hide();
        confirmClear = false;
    }
    onTabChanged: {
        pop.hide();
        confirmClear = false;
    }

    Timer {
        running: root.confirmClear
        interval: 4000
        onTriggered: root.confirmClear = false
    }

    readonly property bool popOpen: pop.shown
    function closePop() {
        pop.hide();
    }

    function jobColor(job) {
        if (!job)
            return Theme.claude;
        return job.state === "idle" ? Theme.ok : (job.state === "dead" ? Theme.danger : Theme.claude);
    }

    Timer {
        interval: 30000
        running: root.open
        repeat: true
        onTriggered: root.now = Date.now()
    }

    function go(url) {
        if (!url)
            return;
        Qt.openUrlExternally(url);
        root.requestClose();
    }

    function shortRepo(full) {
        var i = full.indexOf("/");
        return i >= 0 ? full.substring(i + 1) : full;
    }

    /** Drop leading "[Story]" / "[Task]"-style tags; the type shows as a chip. */
    function cleanTitle(t) {
        return t.replace(/\s*\[(story|task|feature|bug|epic|spike|incidente|qa)\]\s*/ig, " ").trim();
    }

    function prioColor(p) {
        if (p === "P0")
            return Theme.danger;
        if (p === "P1")
            return Theme.warn;
        return Theme.subtle;
    }

    function ciColor(state) {
        if (state === "SUCCESS")
            return Theme.ok;
        if (state === "FAILURE" || state === "ERROR")
            return Theme.danger;
        if (state === "PENDING" || state === "EXPECTED")
            return Theme.warn;
        return Theme.faint;
    }

    function prTag(p) {
        if (p.isDraft)
            return { text: "rascunho", color: Theme.dim };
        if (p.mergeable === "CONFLICTING")
            return { text: "conflito", color: Theme.danger };
        if (p.review === "CHANGES_REQUESTED")
            return { text: "mudanças", color: Theme.warn };
        if (p.review === "APPROVED")
            return { text: "aprovado", color: Theme.ok };
        return { text: "esperando", color: Theme.dim };
    }

    function runColor(r) {
        if (GitHub.activeStates.indexOf(r.status) >= 0)
            return Theme.warn;
        if (r.conclusion === "success")
            return Theme.ok;
        if (r.conclusion === "failure")
            return Theme.danger;
        return Theme.faint;
    }

    component PulseDot: Rectangle {
        id: pd
        property bool pulse: false
        width: 7 * root.s
        height: width
        radius: width / 2

        SequentialAnimation on opacity {
            running: pd.pulse && root.open
            loops: Animation.Infinite
            onRunningChanged: if (!running) pd.opacity = 1
            NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
        }
    }

    component Chip: Rectangle {
        id: chip
        property string text: ""
        property color tint: Theme.subtle
        visible: text.length > 0
        width: chipText.implicitWidth + 12 * root.s
        height: 17 * root.s
        radius: height / 2
        color: Qt.alpha(tint, 0.13)
        border.width: 1
        border.color: Qt.alpha(tint, 0.28)

        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.text
            color: chip.tint
            font.family: Theme.font
            font.pixelSize: 8.5 * root.s
            font.weight: Font.Bold
            font.letterSpacing: 0.4 * root.s
        }
    }

    component StatTab: Rectangle {
        id: st
        property string key: ""
        property string label: ""
        property int count: 0
        property color accent: Theme.subtle
        property bool pulse: false
        readonly property bool selected: root.tab === key

        height: 58 * root.s
        radius: 12 * root.s
        color: selected ? Theme.frameBg : (stArea.containsMouse ? Qt.alpha(Theme.frameBg, 0.5) : "transparent")
        border.width: 1
        border.color: selected ? Theme.frameBorder : "transparent"
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 13 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3 * root.s

            SkBone {
                visible: root.loading
                width: 28 * root.s
                height: 21 * root.s
                radius: 6 * root.s
            }
            Text {
                visible: !root.loading
                text: st.count
                color: st.selected ? Theme.bright : (st.count > 0 ? Theme.cream : Theme.faint)
                font.family: Theme.font
                font.pixelSize: 21 * root.s
                font.weight: Font.Bold
                font.letterSpacing: -0.5 * root.s
                font.features: { "tnum": 1 }
            }
            Row {
                spacing: 6 * root.s
                PulseDot {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 5 * root.s
                    color: st.count > 0 ? st.accent : Theme.faint
                    pulse: st.pulse
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: st.label
                    color: st.selected ? Theme.cream : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 9 * root.s
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.1 * root.s
                }
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 7 * root.s
            anchors.right: parent.right
            anchors.rightMargin: 13 * root.s
            width: st.selected ? 16 * root.s : 0
            height: 2 * root.s
            radius: 1 * root.s
            color: st.accent
            Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
        }

        MouseArea {
            id: stArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.tab = st.key
        }
    }

    component IssueCard: Rectangle {
        id: card
        required property var modelData
        property color edge: Theme.info

        width: parent ? parent.width : 0
        height: cardCol.implicitHeight + 22 * root.s
        radius: 11 * root.s
        readonly property bool selected: GitHub.detailUrl === modelData.url
        color: selected ? Qt.alpha(card.edge, 0.10) : (cardArea.containsMouse ? Qt.alpha(Theme.cream, 0.06) : Theme.frameBg)
        border.width: 1
        border.color: selected ? Qt.alpha(card.edge, 0.7) : (cardArea.containsMouse ? Qt.alpha(card.edge, 0.45) : Theme.frameBorder)
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 1
            anchors.verticalCenter: parent.verticalCenter
            width: 2.5 * root.s
            height: parent.height - 22 * root.s
            radius: width / 2
            color: card.edge
        }

        Column {
            id: cardCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 14 * root.s
            anchors.rightMargin: 12 * root.s
            anchors.topMargin: 11 * root.s
            spacing: 6 * root.s

            Item {
                width: parent.width
                height: repoText.implicitHeight

                Text {
                    id: repoText
                    anchors.left: parent.left
                    anchors.right: estText.left
                    anchors.rightMargin: 8 * root.s
                    elide: Text.ElideRight
                    text: root.shortRepo(card.modelData.repo) + "  #" + card.modelData.number
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 9.5 * root.s
                    font.weight: Font.Medium
                    font.features: { "tnum": 1 }
                }
                Text {
                    id: estText
                    anchors.right: parent.right
                    visible: card.modelData.estimate !== null && card.modelData.estimate !== undefined
                    text: (card.modelData.estimate % 1 === 0 ? card.modelData.estimate : Number(card.modelData.estimate).toFixed(1)) + " pts"
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 9.5 * root.s
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
            }

            Text {
                width: parent.width
                text: root.cleanTitle(card.modelData.title)
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                lineHeight: 1.12
                color: cardArea.containsMouse ? Theme.bright : Theme.cream
                font.family: Theme.font
                font.pixelSize: 12 * root.s
                font.weight: Font.Medium
            }

            Row {
                spacing: 5 * root.s
                Chip { text: card.modelData.priority; tint: root.prioColor(card.modelData.priority) }
                Chip { text: card.modelData.kind; tint: Theme.subtle }
            }
        }

        MouseArea {
            id: cardArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            // Opens the detail pane beside the board instead of the browser.
            onClicked: GitHub.openIssue(card.modelData.url)
        }
    }

    component BoardColumn: Column {
        id: bc
        property string label: ""
        property color accent: Theme.info
        property bool pulse: false
        property var items: []
        property int skeletons: 3
        property real bodyHeight: 0
        readonly property real listHeight: list.implicitHeight

        spacing: 10 * root.s

        Item {
            width: parent.width
            height: 18 * root.s

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7 * root.s
                PulseDot {
                    anchors.verticalCenter: parent.verticalCenter
                    color: bc.accent
                    pulse: bc.pulse
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: bc.label
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 9.5 * root.s
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.2 * root.s
                }
            }
            Rectangle {
                visible: !root.loading
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(height, countText.implicitWidth + 10 * root.s)
                height: 16 * root.s
                radius: height / 2
                color: Qt.alpha(bc.accent, 0.14)
                Text {
                    id: countText
                    anchors.centerIn: parent
                    text: bc.items.length
                    color: bc.accent
                    font.family: Theme.font
                    font.pixelSize: 9 * root.s
                    font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                }
            }
        }

        Flickable {
            id: bcFlick
            width: parent.width
            height: bc.bodyHeight
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Rectangle {
                parent: bcFlick
                z: 2
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 34 * root.s
                visible: bcFlick.contentY + bcFlick.height < bcFlick.contentHeight - 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.alpha(Theme.cardBot, 0) }
                    GradientStop { position: 1.0; color: Theme.cardBot }
                }
            }

            Column {
                id: list
                width: parent.width
                spacing: 8 * root.s

                Repeater {
                    model: root.loading ? bc.skeletons : 0
                    SkeletonCard {}
                }

                Rectangle {
                    visible: !root.loading && bc.items.length === 0
                    width: parent.width
                    height: 64 * root.s
                    radius: 11 * root.s
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.frameBorder
                    Text {
                        anchors.centerIn: parent
                        text: "Nada aqui"
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                    }
                }

                Repeater {
                    model: bc.items
                    IssueCard { edge: bc.accent }
                }
            }
        }
    }

    component EntryRow: Item {
        id: entry
        width: parent ? parent.width : 0
        height: 38 * root.s

        property string title: ""
        property string sub: ""
        property string tag: ""
        property color tagColor: Theme.dim
        property color dotColor: Theme.faint
        property bool pulse: false
        property string url: ""
        // PR rows open the detail pane; other rows go to the browser.
        property bool pr: false
        readonly property bool selected: pr && GitHub.detailUrl === url
        // Claude review button at the right edge (PR rows).
        property bool claude: false
        property string repo: ""
        property int number: 0
        readonly property var job: claude ? GitHub.claudeReviewFor(url) : null
        readonly property bool popHere: pop.shown && pop.pr !== null && pop.pr.url === url

        Rectangle {
            anchors.fill: parent
            radius: 10 * root.s
            color: entry.selected ? Qt.alpha(Theme.info, 0.10) : Theme.frameBg
            border.width: entry.selected ? 1 : 0
            border.color: Qt.alpha(Theme.info, 0.5)
            opacity: entryArea.containsMouse || aiBtn.lit || entry.selected || entry.popHere ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }

        PulseDot {
            id: entryDot
            anchors.left: parent.left
            anchors.leftMargin: 10 * root.s
            anchors.verticalCenter: parent.verticalCenter
            color: entry.dotColor
            pulse: entry.pulse
        }

        Column {
            anchors.left: entryDot.right
            anchors.leftMargin: 11 * root.s
            anchors.right: entryTag.left
            anchors.rightMargin: 10 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2 * root.s

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: entry.title
                color: entryArea.containsMouse ? Theme.bright : Theme.cream
                font.family: Theme.font
                font.pixelSize: 12 * root.s
                font.weight: Font.Medium
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: entry.sub
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.features: { "tnum": 1 }
            }
        }

        Chip {
            id: entryTag
            anchors.right: entry.claude ? aiBtn.left : parent.right
            anchors.rightMargin: entry.claude ? 8 * root.s : 10 * root.s
            anchors.verticalCenter: parent.verticalCenter
            text: entry.tag
            tint: entry.tagColor
        }

        MouseArea {
            id: entryArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: entry.pr ? GitHub.openPr(entry.url) : root.go(entry.url)
        }

        ClaudeButton {
            id: aiBtn
            visible: entry.claude
            anchors.right: parent.right
            anchors.rightMargin: 6 * root.s
            anchors.verticalCenter: parent.verticalCenter
            s: root.s
            job: entry.job
            open: entry.popHere
            onClicked: pop.toggle(aiBtn, { url: entry.url, title: entry.title, repo: entry.repo, number: entry.number })
        }
    }

    component ListBody: Flickable {
        id: lb
        default property alias rows: lbCol.data
        property string emptyText: ""
        property bool empty: false
        property bool loading: root.loading

        width: parent ? parent.width : 0
        contentHeight: lbCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: lbCol
            parent: lb.contentItem
            width: lb.width
            spacing: 2 * root.s

            Repeater {
                model: lb.loading ? 5 : 0
                SkeletonRow {}
            }

            Text {
                visible: lb.empty
                topPadding: 8 * root.s
                bottomPadding: 8 * root.s
                leftPadding: 10 * root.s
                text: lb.emptyText
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 11 * root.s
            }
        }
    }

    component FooterLink: Text {
        id: fl
        property string url: ""
        text: ""
        color: flArea.containsMouse ? Theme.cream : Theme.dim
        font.family: Theme.font
        font.pixelSize: 9.5 * root.s
        font.weight: Font.DemiBold

        MouseArea {
            id: flArea
            anchors.fill: parent
            anchors.margins: -4 * root.s
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.go(fl.url)
        }
    }

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        Item {
            width: parent.width
            height: 24 * root.s

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * root.s

                Text {
                    id: kanji
                    anchors.verticalCenter: parent.verticalCenter
                    text: "源"
                    color: Theme.cream
                    font.family: Theme.fontJp
                    font.weight: Font.Medium
                    font.pixelSize: 16 * root.s
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "GITHUB"
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.6 * root.s
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * root.s

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: GitHub.error.length > 0 ? "erro: " + GitHub.error : (GitHub.login ? "@" + GitHub.login : "carregando…")
                    width: Math.min(implicitWidth, root.width * 0.5)
                    elide: Text.ElideRight
                    color: GitHub.error.length > 0 ? Theme.danger : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                }

                ClippingRectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: GitHub.avatar.length > 0
                    width: 22 * root.s
                    height: width
                    radius: width / 2
                    color: Theme.tileBg
                    border.width: 1
                    border.color: Theme.frameBorder

                    Image {
                        anchors.fill: parent
                        source: GitHub.avatar.length > 0 ? GitHub.avatar + "&s=64" : ""
                        sourceSize.width: 64
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                    }
                }
            }
        }

        Row {
            id: tabs
            width: parent.width
            topPadding: 14 * root.s
            bottomPadding: 16 * root.s
            spacing: 8 * root.s
            readonly property real tileW: (width - 3 * spacing) / 4

            StatTab {
                width: tabs.tileW
                key: "issues"
                label: "Issues"
                count: GitHub.issues.length
                accent: GitHub.inProgress.length > 0 ? Theme.warn : Theme.info
            }
            StatTab {
                width: tabs.tileW
                key: "review"
                label: "Review"
                count: GitHub.reviewCount
                accent: Theme.claude
            }
            StatTab {
                width: tabs.tileW
                key: "prs"
                label: "Meus PRs"
                count: GitHub.mine.length
                accent: GitHub.ciFailing ? Theme.danger : Theme.ok
            }
            StatTab {
                width: tabs.tileW
                key: "actions"
                label: "Actions"
                count: GitHub.runningCount
                accent: Theme.warn
                pulse: GitHub.runningCount > 0
            }
        }

        // Issues: In Progress | Ready board
        Item {
            id: board
            visible: root.tab === "issues"
            width: parent.width
            readonly property real gap: 14 * root.s
            readonly property real bodyH: Math.min(root.maxBody - 28 * root.s,
                Math.max(colProgress.listHeight, colReady.listHeight))
            height: visible ? colProgress.implicitHeight + boardFooter.height : 0

            BoardColumn {
                id: colProgress
                anchors.left: parent.left
                width: (parent.width - board.gap) / 2
                label: "Em progresso"
                skeletons: 2
                accent: Theme.warn
                pulse: items.length > 0
                items: GitHub.inProgress
                bodyHeight: board.bodyH
            }
            BoardColumn {
                id: colReady
                anchors.right: parent.right
                width: (parent.width - board.gap) / 2
                label: "Ready"
                skeletons: 4
                accent: Theme.info
                items: GitHub.readyIssues
                bodyHeight: board.bodyH
            }

            Item {
                id: boardFooter
                anchors.top: colProgress.bottom
                width: parent.width
                height: 28 * root.s
                FooterLink {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    text: "Abrir board ↗"
                    url: GitHub.boardUrl
                }
            }
        }

        ListBody {
            visible: root.tab === "review"
            height: visible ? Math.min(root.maxBody, contentHeight) : 0
            empty: GitHub.ready && GitHub.reviews.length === 0
            emptyText: "Nada esperando sua review"

            Repeater {
                model: GitHub.reviews
                EntryRow {
                    required property var modelData
                    title: modelData.title
                    sub: root.shortRepo(modelData.repo) + "  #" + modelData.number + "  ·  " + modelData.author + "  ·  " + GitHub.since(modelData.createdAt, root.now)
                    tag: job ? ({ "starting": "claude…", "busy": "claude revisando", "idle": "claude pronto", "dead": "claude parou" })[job.state]
                        : (modelData.isDraft ? "rascunho" : "")
                    tagColor: job ? root.jobColor(job) : Theme.dim
                    pulse: job !== null && (job.state === "busy" || job.state === "starting")
                    dotColor: Theme.claude
                    url: modelData.url
                    pr: true
                    claude: true
                    repo: modelData.repo
                    number: modelData.number
                }
            }
        }

        ListBody {
            visible: root.tab === "prs"
            height: visible ? Math.min(root.maxBody, contentHeight) : 0
            empty: GitHub.ready && GitHub.mine.length === 0
            emptyText: "Nenhum PR aberto"

            Repeater {
                model: GitHub.mine
                EntryRow {
                    required property var modelData
                    readonly property var tagInfo: root.prTag(modelData)
                    title: modelData.title
                    sub: root.shortRepo(modelData.repo) + "  #" + modelData.number + "  ·  " + GitHub.since(modelData.updatedAt, root.now)
                    tag: tagInfo.text
                    tagColor: tagInfo.color
                    dotColor: root.ciColor(modelData.ci)
                    pulse: modelData.ci === "PENDING" || modelData.ci === "EXPECTED"
                    url: modelData.url
                    pr: true
                    claude: true
                    repo: modelData.repo
                    number: modelData.number
                }
            }
        }

        // Review windows left in the claude-reviews tmux session.
        Item {
            visible: (root.tab === "review" || root.tab === "prs") && root.reviewWindows.total > 0
            width: parent.width
            height: visible ? 36 * root.s : 0

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10 * root.s
                anchors.right: clearBtn.left
                anchors.rightMargin: 10 * root.s
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5 * root.s
                elide: Text.ElideRight
                text: {
                    var w = root.reviewWindows;
                    var t = w.total + (w.total === 1 ? " janela" : " janelas") + " em tmux: " + GitHub.claudeSession;
                    return w.running > 0 ? t + "  ·  " + w.running + " rodando" : t;
                }
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.features: { "tnum": 1 }
            }

            GhPill {
                id: clearBtn
                s: root.s
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                text: root.confirmClear
                    ? "Confirmar: encerrar " + root.reviewWindows.running + " rodando"
                    : "Limpar janelas"
                tint: Theme.danger
                on: root.confirmClear
                onClicked: {
                    if (root.reviewWindows.running > 0 && !root.confirmClear) {
                        root.confirmClear = true;
                        return;
                    }
                    root.confirmClear = false;
                    GitHub.clearClaudeReviews();
                }
            }
        }

        ListBody {
            visible: root.tab === "actions"
            height: visible ? Math.min(root.maxBody, contentHeight) : 0
            empty: GitHub.ready && GitHub.runs.length === 0
            emptyText: "Nada rodando agora"

            Repeater {
                model: GitHub.runs
                EntryRow {
                    required property var modelData
                    readonly property bool active: GitHub.activeStates.indexOf(modelData.status) >= 0
                    title: modelData.name + (modelData.title && modelData.title !== modelData.name ? " — " + modelData.title : "")
                    sub: root.shortRepo(modelData.repo) + "  ·  " + modelData.branch + "  ·  " + GitHub.since(modelData.startedAt, root.now)
                    tag: active ? (modelData.status === "in_progress" ? "rodando" : "na fila")
                        : (modelData.conclusion === "success" ? "passou" : (modelData.conclusion === "failure" ? "falhou" : modelData.conclusion))
                    tagColor: root.runColor(modelData)
                    dotColor: root.runColor(modelData)
                    pulse: active
                    url: modelData.url
                }
            }
        }
    }

    ClaudeReviewPopover {
        id: pop
        anchors.fill: parent
        z: 100
        s: root.s
    }
}
