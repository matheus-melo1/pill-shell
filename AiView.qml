pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import "Singletons"

/**
 * 話 CHAT route of the drawer: a chat with any model of the active provider. Three modes
 * share the body: the conversation, the saved-conversations list and the
 * model picker (searchable, featured providers first, price per million
 * tokens and an image badge).
 *
 * Messages: the user's turns are right-aligned bubbles with image thumbnails;
 * replies render as Markdown split at ``` fences, so code blocks get their own
 * monospace card with the language and a copy button. While streaming, the
 * live text comes from Ai.streamText and the list follows the bottom unless
 * the reader scrolled up. Errors show inline with a retry.
 *
 * Composer: a growing text area (Enter sends, Shift+Enter breaks the line,
 * Ctrl+V with an image on the clipboard attaches it), staged image chips, and
 * buttons for clipboard image, region capture and send/stop. Without an API
 * key the empty state says where to put it.
 */
Item {
    id: root

    property real s: 1
    property bool open: false

    opacity: open ? 1 : 0
    visible: opacity > 0.01
    enabled: open
    Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

    property string mode: "chat"
    property string modelQuery: ""

    // The thread is a ListModel kept in step with Ai.messages, so a new turn
    // adds one delegate instead of rebuilding the whole conversation (which
    // also lets just the new message animate in). Messages at index >=
    // enterFrom were appended while watching and get the enter animation.
    ListModel { id: msgModel }
    property int enterFrom: 0
    property string syncedChat: "-"

    function syncMessages() {
        var n = Ai.messages.length;
        if (Ai.currentId !== syncedChat) {
            // a blank chat getting its first turn animates it; opening a saved one doesn't
            enterFrom = syncedChat === "" ? 0 : n;
            syncedChat = Ai.currentId;
            msgModel.clear();
            thread.follow = true;
            Qt.callLater(thread.jumpEnd);
        }
        while (msgModel.count > n)
            msgModel.remove(msgModel.count - 1);
        while (msgModel.count < n)
            msgModel.append({});
    }

    Connections {
        target: Ai
        function onMessagesChanged() { root.syncMessages(); }
        function onCurrentIdChanged() { root.syncMessages(); }
    }
    Component.onCompleted: syncMessages()

    onOpenChanged: if (open) {
        Ai.refreshStatus();
        if (mode === "chat")
            input.forceActiveFocus();
    }
    onModeChanged: if (mode === "chat" && open) input.forceActiveFocus()

    Connections {
        target: Ai
        function onModelsChanged() {
            if (root.mode === "models" && !root.modelQuery.length)
                Qt.callLater(root.showCurrentModel);
        }
    }

    readonly property var featuredProviders: ["anthropic", "openai", "google", "x-ai", "deepseek", "mistralai", "qwen", "meta-llama", "meta", "moonshotai", "z-ai"]

    // Every chat-capable model, grouped by provider (featured first, then A–Z);
    // inside a group the "Latest" aliases lead, then newest first. Each word of
    // the query must match the name, id or provider.
    readonly property var modelRows: {
        var words = modelQuery.trim().toLowerCase().split(/\s+/).filter(function(w) { return w.length; });
        var list = Ai.models.filter(function(m) {
            var hay = (m.name + " " + m.id + " " + m.providerName).toLowerCase();
            for (var i = 0; i < words.length; i++)
                if (hay.indexOf(words[i]) < 0)
                    return false;
            return true;
        });
        function rank(m) {
            var i = root.featuredProviders.indexOf(m.provider);
            return i < 0 ? 99 : i;
        }
        list = list.map(function(m) {
            var free = Ai.isFree(m);
            return Object.assign({}, m, { free: free, group: free ? "Grátis" : m.providerName });
        });
        list.sort(function(a, b) {
            if (a.free !== b.free) return a.free ? -1 : 1;
            var ra = rank(a), rb = rank(b);
            if (ra !== rb) return ra - rb;
            if (a.providerName !== b.providerName) return a.providerName.localeCompare(b.providerName);
            if (a.alias !== b.alias) return a.alias ? -1 : 1;
            return b.created - a.created;
        });
        return list;
    }

    /** Split a reply into markdown text and fenced code segments. */
    function segments(text) {
        var out = [];
        var re = /```([^\n`]*)\n?([\s\S]*?)(```|$)/g;
        var last = 0;
        var m;
        while ((m = re.exec(text)) !== null) {
            if (m.index > last)
                out.push({ code: false, text: text.slice(last, m.index) });
            out.push({ code: true, lang: m[1].trim(), text: m[2].replace(/\n$/, "") });
            last = re.lastIndex;
            if (m[0].length === 0)
                break;
        }
        if (last < text.length)
            out.push({ code: false, text: text.slice(last) });
        return out.filter(function(sg) { return sg.code || sg.text.trim().length; });
    }

    function price(m) {
        if (m.variable)
            return "variável";
        if (m.prompt === null || m.prompt === undefined)
            return "";
        if (!m.prompt && !m.completion)
            return "grátis";
        return priceOne(m.prompt) + " / " + priceOne(m.completion);
    }

    function ctxLabel(n) {
        return n >= 1e6 ? +(n / 1e6).toFixed(1) + "M ctx" : Math.round(n / 1000) + "k ctx";
    }

    function pickModel(id) {
        Ai.setModel(id);
        mode = "chat";
    }

    /** Open the picker scrolled to the model in use. */
    function showCurrentModel() {
        for (var i = 0; i < modelRows.length; i++)
            if (modelRows[i].id === Ai.model) {
                modelList.currentIndex = i;
                modelList.positionViewAtIndex(i, ListView.Center);
                return;
            }
        modelList.currentIndex = -1;
    }

    function priceOne(v) {
        if (v === 0)
            return "grátis";
        return "$" + (v < 1 ? v.toFixed(2) : v.toFixed(v < 10 ? 1 : 0));
    }

    function sendNow() {
        if (Ai.send(input.text))
            input.text = "";
    }

    component IconButton: Rectangle {
        id: ib
        property string icon: ""
        property string tip: ""
        property bool active: false
        property color tint: Theme.cream
        property real size: 30
        signal clicked()

        width: size * root.s
        height: width
        radius: width / 2.6
        color: active ? Qt.alpha(tint, 0.16) : (ibArea.containsMouse ? Theme.frameBg : "transparent")
        border.width: 1
        border.color: active ? Qt.alpha(tint, 0.35) : (ibArea.containsMouse ? Theme.frameBorder : "transparent")
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }
        scale: ibArea.pressed ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

        GlyphIcon {
            anchors.centerIn: parent
            width: ib.size * 0.5 * root.s
            height: width
            name: ib.icon
            color: ib.active ? ib.tint : (ibArea.containsMouse ? Theme.cream : Theme.iconDim)
            stroke: 1.9
        }

        MouseArea {
            id: ibArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ib.clicked()
        }

        QQC.ToolTip {
            visible: ibArea.containsMouse && ib.tip.length > 0
            delay: 500
            text: ib.tip
        }
    }

    component CodeBlock: Rectangle {
        id: cb
        property string lang: ""
        property string code: ""

        width: parent ? parent.width : 0
        height: cbHead.height + cbText.implicitHeight + 20 * root.s
        radius: 11 * root.s
        color: Qt.rgba(0, 0, 0, 0.35)
        border.width: 1
        border.color: Theme.frameBorder

        Item {
            id: cbHead
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 30 * root.s

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 12 * root.s
                anchors.verticalCenter: parent.verticalCenter
                text: cb.lang || "código"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.8 * root.s
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 10 * root.s
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5 * root.s
                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12 * root.s
                    height: width
                    name: "copy"
                    color: copyArea.containsMouse ? Theme.cream : Theme.dim
                    stroke: 1.9
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "copiar"
                    color: copyArea.containsMouse ? Theme.cream : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 9.5 * root.s
                    font.weight: Font.DemiBold
                }
            }

            MouseArea {
                id: copyArea
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 80 * root.s
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Ai.copy(cb.code)
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: Theme.hair
            }
        }

        TextEdit {
            id: cbText
            anchors.top: cbHead.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 12 * root.s
            anchors.topMargin: 10 * root.s
            text: cb.code
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.WrapAnywhere
            color: Theme.cream
            selectionColor: Qt.alpha(Theme.info, 0.4)
            font.family: "monospace"
            font.pixelSize: 11 * root.s
        }
    }

    component Markdown: TextEdit {
        width: parent ? parent.width : 0
        readOnly: true
        selectByMouse: true
        textFormat: TextEdit.MarkdownText
        wrapMode: TextEdit.Wrap
        color: Theme.cream
        selectionColor: Qt.alpha(Theme.info, 0.4)
        font.family: Theme.font
        font.pixelSize: 12.5 * root.s
        onLinkActivated: (link) => Qt.openUrlExternally(link)
        HoverHandler {
            cursorShape: parent.hoveredLink.length ? Qt.PointingHandCursor : Qt.IBeamCursor
        }
    }

    component Reply: Column {
        id: rp
        property string text: ""
        property string modelId: ""
        property string error: ""
        property bool live: false
        property bool last: false

        width: parent ? parent.width : 0
        spacing: 8 * root.s

        Row {
            spacing: 7 * root.s
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 20 * root.s
                height: width
                radius: 7 * root.s
                color: Qt.alpha(Theme.info, 0.14)
                GlyphIcon {
                    anchors.centerIn: parent
                    width: 11 * root.s
                    height: width
                    name: "chat"
                    color: Theme.info
                    stroke: 2
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Ai.modelName(rp.modelId)
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.Bold
            }
        }

        // segments re-split on every token: index-keyed delegates stay alive
        // and only their text changes, instead of being rebuilt per delta
        readonly property var segs: root.segments(rp.text + (rp.live && rp.text.length ? " ▍" : ""))
        Repeater {
            model: rp.segs.length
            Loader {
                id: seg
                required property int index
                readonly property var modelData: rp.segs[index] || { code: false, text: "" }
                width: rp.width
                sourceComponent: modelData.code ? codeSeg : textSeg
                Component {
                    id: codeSeg
                    CodeBlock { lang: seg.modelData.lang; code: seg.modelData.text }
                }
                Component {
                    id: textSeg
                    Markdown { text: seg.modelData.text }
                }
            }
        }

        // typing indicator before the first token
        Row {
            visible: rp.live && rp.text.length === 0
            spacing: 5 * root.s
            topPadding: 4 * root.s
            Repeater {
                model: 3
                Rectangle {
                    id: dotItem
                    required property int index
                    width: 6 * root.s
                    height: width
                    radius: width / 2
                    color: Theme.subtle
                    opacity: 0.35
                    transform: Translate { id: dotLift }
                    SequentialAnimation {
                        running: rp.live && root.open && rp.text.length === 0
                        loops: Animation.Infinite
                        PauseAnimation { duration: dotItem.index * 140 }
                        ParallelAnimation {
                            NumberAnimation { target: dotLift; property: "y"; to: -4 * root.s; duration: 280; easing.type: Easing.OutCubic }
                            NumberAnimation { target: dotItem; property: "opacity"; to: 1; duration: 280 }
                        }
                        ParallelAnimation {
                            NumberAnimation { target: dotLift; property: "y"; to: 0; duration: 340; easing.type: Easing.InOutCubic }
                            NumberAnimation { target: dotItem; property: "opacity"; to: 0.35; duration: 340 }
                        }
                        PauseAnimation { duration: (2 - dotItem.index) * 140 + 220 }
                    }
                }
            }
        }

        Rectangle {
            visible: rp.error.length > 0
            width: parent.width
            height: errRow.implicitHeight + 18 * root.s
            radius: 10 * root.s
            color: Qt.alpha(Theme.danger, 0.10)
            border.width: 1
            border.color: Qt.alpha(Theme.danger, 0.3)

            Text {
                id: errRow
                anchors.left: parent.left
                anchors.right: retryBtn.left
                anchors.margins: 12 * root.s
                anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.Wrap
                text: rp.error
                color: Theme.danger
                font.family: Theme.font
                font.pixelSize: 11 * root.s
            }
            IconButton {
                id: retryBtn
                visible: rp.last
                anchors.right: parent.right
                anchors.rightMargin: 8 * root.s
                anchors.verticalCenter: parent.verticalCenter
                icon: "retry"
                tip: "Tentar de novo"
                size: 26
                onClicked: Ai.retry()
            }
        }

        Row {
            visible: !rp.live && rp.text.length > 0
            spacing: 4 * root.s
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
            IconButton {
                icon: "copy"
                tip: "Copiar resposta"
                size: 24
                onClicked: Ai.copy(rp.text)
            }
            IconButton {
                visible: rp.last
                icon: "retry"
                tip: "Gerar de novo"
                size: 24
                onClicked: Ai.retry()
            }
        }
    }

    component UserBubble: Item {
        id: ub
        property string text: ""
        property var images: []
        width: parent ? parent.width : 0
        height: ubCol.implicitHeight

        // natural (unwrapped) width of the text, to size the bubble
        Text {
            id: ubMeasure
            visible: false
            text: ub.text
            font.family: Theme.font
            font.pixelSize: 12.5 * root.s
        }

        readonly property real maxText: ub.width * 0.85 - 28 * root.s

        Column {
            id: ubCol
            anchors.right: parent.right
            width: Math.min(ub.width * 0.85, Math.max(ubMeasure.implicitWidth + 28 * root.s, ubImgs.implicitWidth))
            spacing: 6 * root.s

            Flow {
                id: ubImgs
                visible: ub.images.length > 0
                anchors.right: parent.right
                spacing: 6 * root.s
                layoutDirection: Qt.RightToLeft
                Repeater {
                    model: ub.images
                    Rectangle {
                        id: thumb
                        required property string modelData
                        width: 96 * root.s
                        height: 72 * root.s
                        radius: 10 * root.s
                        clip: true
                        color: Theme.tileBg
                        border.width: 1
                        border.color: Theme.frameBorder
                        Image {
                            anchors.fill: parent
                            anchors.margins: 1
                            source: "file://" + thumb.modelData
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 256
                            asynchronous: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Qt.openUrlExternally("file://" + thumb.modelData)
                        }
                    }
                }
            }

            Rectangle {
                visible: ub.text.length > 0
                anchors.right: parent.right
                width: Math.min(ub.maxText, ubMeasure.implicitWidth) + 28 * root.s
                height: ubText.implicitHeight + 20 * root.s
                radius: 16 * root.s
                color: Qt.alpha(Theme.cream, 0.09)
                border.width: 1
                border.color: Qt.alpha(Theme.cream, 0.12)

                TextEdit {
                    id: ubText
                    x: 14 * root.s
                    y: 10 * root.s
                    width: Math.min(ub.maxText, ubMeasure.implicitWidth + 1)
                    text: ub.text
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    color: Theme.bright
                    selectionColor: Qt.alpha(Theme.info, 0.4)
                    font.family: Theme.font
                    font.pixelSize: 12.5 * root.s
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
        height: 30 * root.s

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * root.s

            IconButton {
                visible: root.mode !== "chat"
                anchors.verticalCenter: parent.verticalCenter
                icon: "back"
                tip: "Voltar"
                size: 26
                onClicked: root.mode = "chat"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "話"
                color: Theme.cream
                font.family: Theme.fontJp
                font.weight: Font.Medium
                font.pixelSize: 16 * root.s
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, header.width - 250 * root.s)
                elide: Text.ElideRight
                text: root.mode === "history" ? "CONVERSAS"
                    : (root.mode === "models" ? "MODELO"
                    : (Ai.current ? Ai.current.title : "NOVO CHAT"))
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: (Ai.current && root.mode === "chat" ? 11 : 10) * root.s
                font.weight: Font.DemiBold
                font.letterSpacing: (Ai.current && root.mode === "chat" ? 0 : 1.6) * root.s
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4 * root.s

            // model chip
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(170 * root.s, mcRow.implicitWidth + 20 * root.s)
                height: 26 * root.s
                radius: height / 2
                color: root.mode === "models" ? Qt.alpha(Theme.info, 0.16) : (mcArea.containsMouse ? Theme.frameBg : "transparent")
                border.width: 1
                border.color: root.mode === "models" ? Qt.alpha(Theme.info, 0.35) : Theme.frameBorder

                Row {
                    id: mcRow
                    anchors.centerIn: parent
                    spacing: 5 * root.s
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 130 * root.s)
                        elide: Text.ElideRight
                        text: Ai.modelName(Ai.model)
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                        font.weight: Font.DemiBold
                    }
                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10 * root.s
                        height: width
                        name: "chevronDown"
                        color: Theme.dim
                        stroke: 2.2
                    }
                }
                MouseArea {
                    id: mcArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.mode = root.mode === "models" ? "chat" : "models";
                        if (root.mode === "models") {
                            root.modelQuery = "";
                            modelSearch.text = "";
                            modelSearch.input.forceActiveFocus();
                            root.showCurrentModel();
                        }
                    }
                }
            }

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "list"
                tip: "Conversas"
                active: root.mode === "history"
                tint: Theme.info
                onClicked: root.mode = root.mode === "history" ? "chat" : "history"
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "plus"
                tip: "Nova conversa"
                onClicked: {
                    Ai.newChat();
                    root.mode = "chat";
                    input.forceActiveFocus();
                }
            }
        }
    }

    // ---- chat ----
    Item {
        id: chatPane
        anchors.top: header.bottom
        anchors.topMargin: 12 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        // panes cross-fade with a short rise instead of popping
        readonly property bool current: root.mode === "chat"
        visible: current || opacity > 0.01
        opacity: current ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
        transform: Translate {
            y: root.mode === "chat" ? 0 : 10 * root.s
            Behavior on y { NumberAnimation { duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve } }
        }

        Flickable {
            id: thread
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: composer.top
            anchors.bottomMargin: 10 * root.s
            contentHeight: threadCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            property bool follow: true
            onContentYChanged: if (moving || dragging) follow = contentY + height >= contentHeight - 40 * root.s
            onContentHeightChanged: if (follow) Qt.callLater(scrollEnd)
            function jumpEnd() {
                scrollAnim.stop();
                contentY = Math.max(0, contentHeight - height);
            }
            // glide to the bottom; restarted on every token so it chases the stream
            function scrollEnd() {
                var to = Math.max(0, contentHeight - height);
                if (Math.abs(to - contentY) < 1)
                    return;
                scrollAnim.stop();
                scrollAnim.to = to;
                scrollAnim.start();
            }
            NumberAnimation {
                id: scrollAnim
                target: thread
                property: "contentY"
                duration: Ai.streaming ? 160 : Motion.morph
                easing.type: Motion.easeStandard
            }

            Column {
                id: threadCol
                width: thread.width
                spacing: 18 * root.s
                topPadding: 4 * root.s
                bottomPadding: 8 * root.s

                Repeater {
                    model: msgModel
                    Loader {
                        id: msgItem
                        required property int index
                        readonly property var modelData: Ai.messages[index] || { role: "assistant", content: "" }
                        width: threadCol.width
                        sourceComponent: modelData.role === "user" ? userMsg : botMsg
                        // user turns slide in; a finished reply replaces the live one in place
                        readonly property bool fresh: index >= root.enterFrom && modelData.role === "user"
                        opacity: fresh ? 0 : 1
                        transform: Translate { id: msgLift; y: msgItem.fresh ? 14 * root.s : 0 }
                        Component.onCompleted: if (fresh) msgEnter.start()
                        ParallelAnimation {
                            id: msgEnter
                            NumberAnimation { target: msgItem; property: "opacity"; to: 1; duration: Motion.standard; easing.type: Motion.easeStandard }
                            NumberAnimation { target: msgLift; property: "y"; to: 0; duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve }
                            NumberAnimation { target: msgItem; property: "scale"; from: 0.96; to: 1; duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve }
                        }
                        Component {
                            id: userMsg
                            UserBubble { text: msgItem.modelData.content; images: msgItem.modelData.images || [] }
                        }
                        Component {
                            id: botMsg
                            Reply {
                                text: msgItem.modelData.content
                                modelId: msgItem.modelData.model || Ai.model
                                error: msgItem.modelData.error || ""
                                last: msgItem.index === Ai.messages.length - 1 && !Ai.streaming
                            }
                        }
                    }
                }

                Reply {
                    id: liveReply
                    visible: Ai.streaming && Ai.streamChat === Ai.currentId
                    live: true
                    opacity: 0
                    transform: Translate { id: liveLift }
                    onVisibleChanged: if (visible) liveEnter.restart()
                    ParallelAnimation {
                        id: liveEnter
                        NumberAnimation { target: liveReply; property: "opacity"; from: 0; to: 1; duration: Motion.standard; easing.type: Motion.easeStandard }
                        NumberAnimation { target: liveLift; property: "y"; from: 10 * root.s; to: 0; duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve }
                    }
                    text: Ai.streamText
                    modelId: Ai.model
                }
            }
        }

        // jump to latest
        IconButton {
            anchors.horizontalCenter: thread.horizontalCenter
            anchors.bottom: thread.bottom
            anchors.bottomMargin: 6 * root.s
            readonly property bool wanted: !thread.follow && thread.contentHeight > thread.height
            visible: opacity > 0.01
            opacity: wanted ? 1 : 0
            scale: wanted ? 1 : 0.6
            Behavior on opacity { NumberAnimation { duration: Motion.glide; easing.type: Motion.easeStandard } }
            Behavior on scale { NumberAnimation { duration: Motion.glide; easing.type: Motion.easeStandard } }
            icon: "chevronDown"
            size: 30
            color: Theme.cardTop
            border.color: Theme.frameBorder
            onClicked: {
                thread.follow = true;
                thread.scrollEnd();
            }
        }

        // empty state
        Column {
            id: emptyState
            readonly property bool shown: Ai.messages.length === 0 && !Ai.streaming && root.open
            anchors.centerIn: thread
            visible: opacity > 0.01
            opacity: shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
            transform: Translate {
                y: emptyState.shown ? 0 : -12 * root.s
                Behavior on y { NumberAnimation { duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve } }
            }
            width: thread.width - 40 * root.s
            spacing: 14 * root.s

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                id: emptyIcon
                width: 64 * root.s
                height: width
                radius: 22 * root.s
                color: Qt.alpha(Theme.info, 0.10)
                SequentialAnimation on scale {
                    running: emptyState.visible
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 1.05; duration: 1600; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1.05; to: 1; duration: 1600; easing.type: Easing.InOutSine }
                }
                border.width: 1
                border.color: Qt.alpha(Theme.info, 0.25)
                GlyphIcon {
                    anchors.centerIn: parent
                    width: 28 * root.s
                    height: width
                    name: "chat"
                    color: Theme.info
                    stroke: 1.6
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Pergunte qualquer coisa"
                color: Theme.bright
                font.family: Theme.font
                font.pixelSize: 17 * root.s
                font.weight: Font.Bold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Usando " + Ai.modelName(Ai.model) + " via " + Ai.providerLabel
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11 * root.s
            }

            Rectangle {
                visible: !Ai.hasKey
                width: parent.width
                height: keyCol.implicitHeight + 24 * root.s
                radius: 12 * root.s
                color: Qt.alpha(Theme.warn, 0.08)
                border.width: 1
                border.color: Qt.alpha(Theme.warn, 0.28)

                Column {
                    id: keyCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 14 * root.s
                    spacing: 6 * root.s
                    Text {
                        text: "Falta a API key do " + Ai.providerLabel
                        color: Theme.warn
                        font.family: Theme.font
                        font.pixelSize: 11.5 * root.s
                        font.weight: Font.Bold
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WrapAnywhere
                        text: "Salve a chave (uma linha) em " + Ai.keyFile + " com permissão 600."
                        color: Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                    }
                }
            }

            Flow {
                visible: Ai.hasKey
                width: parent.width
                spacing: 6 * root.s
                Repeater {
                    model: ["Explique este erro", "Resuma um texto", "Escreva um script bash", "Revise meu código"]
                    Rectangle {
                        id: sug
                        required property string modelData
                        required property int index
                        width: sugText.implicitWidth + 22 * root.s
                        height: 28 * root.s
                        radius: height / 2
                        color: sugArea.containsMouse ? Theme.frameBg : "transparent"
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        // staggered entrance each time the empty state appears
                        opacity: 0
                        transform: Translate { id: sugLift; y: 8 * root.s }
                        scale: sugArea.pressed ? 0.96 : 1
                        Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                        Connections {
                            target: emptyState
                            function onShownChanged() {
                                if (emptyState.shown)
                                    sugIn.restart();
                            }
                        }
                        Component.onCompleted: if (emptyState.shown) sugIn.restart()
                        SequentialAnimation {
                            id: sugIn
                            ScriptAction { script: { sug.opacity = 0; sugLift.y = 8 * root.s; } }
                            PauseAnimation { duration: 120 + sug.index * 60 }
                            ParallelAnimation {
                                NumberAnimation { target: sug; property: "opacity"; to: 1; duration: Motion.standard; easing.type: Motion.easeStandard }
                                NumberAnimation { target: sugLift; property: "y"; to: 0; duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve }
                            }
                        }
                        border.width: 1
                        border.color: Theme.frameBorder
                        Text {
                            id: sugText
                            anchors.centerIn: parent
                            text: sug.modelData
                            color: Theme.subtle
                            font.family: Theme.font
                            font.pixelSize: 10.5 * root.s
                        }
                        MouseArea {
                            id: sugArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                input.text = sug.modelData + ": ";
                                input.cursorPosition = input.text.length;
                                input.forceActiveFocus();
                            }
                        }
                    }
                }
            }
        }

        // composer
        Rectangle {
            id: composer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: compCol.implicitHeight + 20 * root.s
            Behavior on height { NumberAnimation { duration: Motion.glide; easing.type: Motion.easeStandard } }
            radius: 18 * root.s
            color: Theme.frameBg
            border.width: 1
            border.color: input.activeFocus ? Qt.alpha(Theme.cream, 0.22) : Theme.frameBorder
            Behavior on border.color { ColorAnimation { duration: Motion.fast } }

            Column {
                id: compCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10 * root.s
                spacing: 8 * root.s

                Flow {
                    visible: Ai.pending.length > 0
                    width: parent.width
                    spacing: 6 * root.s
                    leftPadding: 4 * root.s
                    Repeater {
                        model: Ai.pending
                        Rectangle {
                            id: chip
                            required property string modelData
                            opacity: 0
                            scale: 0.8
                            Component.onCompleted: chipIn.start()
                            ParallelAnimation {
                                id: chipIn
                                NumberAnimation { target: chip; property: "opacity"; to: 1; duration: Motion.standard; easing.type: Motion.easeStandard }
                                NumberAnimation { target: chip; property: "scale"; to: 1; duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve }
                            }
                            width: 64 * root.s
                            height: 48 * root.s
                            radius: 9 * root.s
                            clip: true
                            color: Theme.tileBg
                            border.width: 1
                            border.color: Theme.frameBorder
                            Image {
                                anchors.fill: parent
                                anchors.margins: 1
                                source: "file://" + chip.modelData
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 160
                                asynchronous: true
                            }
                            Rectangle {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 3 * root.s
                                width: 16 * root.s
                                height: width
                                radius: width / 2
                                color: Qt.rgba(0, 0, 0, 0.7)
                                GlyphIcon {
                                    anchors.centerIn: parent
                                    width: 8 * root.s
                                    height: width
                                    name: "x"
                                    color: "#ffffff"
                                    stroke: 2.6
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Ai.removePending(chip.modelData)
                                }
                            }
                        }
                    }
                }

                QQC.ScrollView {
                    width: parent.width
                    height: Math.min(input.implicitHeight, 140 * root.s)

                    QQC.TextArea {
                        id: input
                        leftPadding: 6 * root.s
                        rightPadding: 6 * root.s
                        topPadding: 4 * root.s
                        bottomPadding: 4 * root.s
                        background: null
                        wrapMode: QQC.TextArea.Wrap
                        placeholderText: Ai.hasKey ? "Mensagem…  (Shift+Enter quebra a linha)" : "Configure a API key para começar"
                        placeholderTextColor: Theme.faint
                        color: Theme.bright
                        selectionColor: Qt.alpha(Theme.info, 0.4)
                        font.family: Theme.font
                        font.pixelSize: 13 * root.s

                        Keys.onPressed: (e) => {
                            if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
                                root.sendNow();
                                e.accepted = true;
                            } else if (e.key === Qt.Key_V && (e.modifiers & Qt.ControlModifier) && !(e.modifiers & Qt.ShiftModifier)) {
                                // Attach an image if the clipboard holds one; text pastes as usual.
                                clipProbe.running = true;
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 30 * root.s

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2 * root.s
                        IconButton {
                            icon: "image"
                            tip: "Colar imagem da área de transferência"
                            onClicked: Ai.pasteImage()
                        }
                        IconButton {
                            icon: "crop"
                            tip: "Capturar área da tela"
                            onClicked: Ai.capture()
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            leftPadding: 6 * root.s
                            visible: Ai.notice.length > 0 || (Ai.pending.length > 0 && Ai.modelInfo(Ai.model) && Ai.modelInfo(Ai.model).image === false)
                            text: Ai.notice.length ? Ai.notice : "este modelo não aceita imagens"
                            color: Ai.notice.length ? Theme.ok : Theme.warn
                            font.family: Theme.font
                            font.pixelSize: 10 * root.s
                            font.weight: Font.DemiBold
                        }
                    }

                    Rectangle {
                        id: sendBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property bool canSend: Ai.streaming || input.text.trim().length > 0 || Ai.pending.length > 0
                        width: 32 * root.s
                        height: width
                        radius: width / 2
                        color: Ai.streaming ? Theme.cream : (canSend ? Theme.bright : Qt.alpha(Theme.cream, 0.12))
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        scale: sendArea.pressed ? 0.96 : 1
                        Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

                        // send ⇄ stop: both stay mounted and cross-fade (opacity, scale 0.25→1)
                        GlyphIcon {
                            anchors.centerIn: parent
                            width: 16 * root.s
                            height: width
                            name: "send"
                            color: sendBtn.canSend ? Theme.cardBot : Theme.faint
                            stroke: 2.4
                            opacity: Ai.streaming ? 0 : 1
                            scale: Ai.streaming ? 0.25 : 1
                            Behavior on opacity { NumberAnimation { duration: Motion.glide; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] } }
                            Behavior on scale { NumberAnimation { duration: Motion.glide; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] } }
                        }
                        GlyphIcon {
                            anchors.centerIn: parent
                            width: 12 * root.s
                            height: width
                            name: "stop"
                            color: Theme.cardBot
                            stroke: 2.4
                            opacity: Ai.streaming ? 1 : 0
                            scale: Ai.streaming ? 1 : 0.25
                            Behavior on opacity { NumberAnimation { duration: Motion.glide; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] } }
                            Behavior on scale { NumberAnimation { duration: Motion.glide; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] } }
                        }
                        MouseArea {
                            id: sendArea
                            anchors.fill: parent
                            enabled: sendBtn.canSend
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Ai.streaming ? Ai.stop() : root.sendNow()
                        }
                    }
                }
            }
        }

        Process {
            id: clipProbe
            command: ["sh", "-c", "wl-paste --list-types | grep -q '^image/'"]
            onExited: (code) => { if (code === 0) Ai.pasteImage(); }
        }
    }

    // ---- history ----
    Flickable {
        anchors.top: header.bottom
        anchors.topMargin: 14 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        // panes cross-fade with a short rise instead of popping
        readonly property bool current: root.mode === "history"
        visible: current || opacity > 0.01
        opacity: current ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
        transform: Translate {
            y: root.mode === "history" ? 0 : 10 * root.s
            Behavior on y { NumberAnimation { duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve } }
        }
        contentHeight: histCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: histCol
            width: parent.width
            spacing: 6 * root.s

            Text {
                visible: Ai.chats.length === 0
                topPadding: 20 * root.s
                text: "Nenhuma conversa salva ainda"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 11.5 * root.s
            }

            Repeater {
                model: Ai.chats
                Rectangle {
                    id: hc
                    required property var modelData
                    readonly property bool isCurrent: modelData.id === Ai.currentId
                    width: histCol.width
                    height: 54 * root.s
                    radius: 13 * root.s
                    color: isCurrent ? Qt.alpha(Theme.info, 0.08) : (hcHover.hovered ? Qt.alpha(Theme.cream, 0.06) : Theme.frameBg)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    border.width: 1
                    border.color: isCurrent ? Qt.alpha(Theme.info, 0.3) : Theme.frameBorder

                    HoverHandler { id: hcHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Ai.openChat(hc.modelData.id);
                            root.mode = "chat";
                        }
                    }

                    Rectangle {
                        id: hcIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 12 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30 * root.s
                        height: width
                        radius: 10 * root.s
                        color: Qt.alpha(hc.isCurrent ? Theme.info : Theme.cream, 0.08)
                        GlyphIcon {
                            anchors.centerIn: parent
                            width: 15 * root.s
                            height: width
                            name: "chat"
                            color: hc.isCurrent ? Theme.info : Theme.iconDim
                            stroke: 1.8
                        }
                    }

                    Column {
                        anchors.left: hcIcon.right
                        anchors.leftMargin: 11 * root.s
                        anchors.right: hcDel.left
                        anchors.rightMargin: 8 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3 * root.s
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: hc.modelData.title
                            color: Theme.cream
                            font.family: Theme.font
                            font.pixelSize: 12 * root.s
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: Ai.modelName(hc.modelData.model) + "  ·  " + hc.modelData.messages.length + " msgs  ·  "
                                + Qt.formatDateTime(new Date(hc.modelData.updated), "dd/MM HH:mm")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 9.5 * root.s
                        }
                    }

                    IconButton {
                        id: hcDel
                        anchors.right: parent.right
                        anchors.rightMargin: 10 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        visible: hcHover.hovered
                        icon: "trash"
                        tip: "Apagar conversa"
                        tint: Theme.danger
                        size: 28
                        onClicked: Ai.deleteChat(hc.modelData.id)
                    }
                }
            }
        }
    }

    // ---- model picker ----
    Item {
        anchors.top: header.bottom
        anchors.topMargin: 14 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        // panes cross-fade with a short rise instead of popping
        readonly property bool current: root.mode === "models"
        visible: current || opacity > 0.01
        opacity: current ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
        transform: Translate {
            y: root.mode === "models" ? 0 : 10 * root.s
            Behavior on y { NumberAnimation { duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve } }
        }

        Rectangle {
            id: msBox
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 40 * root.s
            radius: 12 * root.s
            color: Theme.frameBg
            border.width: 1
            border.color: modelSearch.input.activeFocus ? Qt.alpha(Theme.cream, 0.22) : Theme.frameBorder

            SearchField {
                id: modelSearch
                anchors.fill: parent
                anchors.leftMargin: 14 * root.s
                anchors.rightMargin: 14 * root.s
                s: root.s
                kanji: "探"
                placeholder: "Buscar modelo (claude, gpt, gemini…)"
                counterText: Ai.models.length ? root.modelRows.length + "" : "carregando…"
                onTextChanged: {
                    root.modelQuery = text;
                    modelList.currentIndex = text.length && root.modelRows.length ? 0 : -1;
                    modelList.positionViewAtBeginning();
                }
                onMoved: (d) => {
                    var n = modelList.count;
                    if (!n)
                        return;
                    modelList.currentIndex = Math.max(0, Math.min(n - 1, modelList.currentIndex + d));
                    modelList.positionViewAtIndex(modelList.currentIndex, ListView.Contain);
                }
                onAccepted: if (modelList.currentIndex >= 0) root.pickModel(root.modelRows[modelList.currentIndex].id)
                onDismissed: root.mode = "chat"
            }
        }

        // what this account can actually use
        Rectangle {
            id: acctBox
            readonly property real balance: Ai.knowsBalance ? Ai.account.credits - Ai.account.usage : 0
            visible: Ai.knowsBalance
            anchors.top: msBox.bottom
            anchors.topMargin: visible ? 10 * root.s : 0
            anchors.left: parent.left
            anchors.right: parent.right
            height: visible ? acctCol.implicitHeight + 20 * root.s : 0
            radius: 12 * root.s
            color: Qt.alpha(Ai.freeOnly ? Theme.warn : Theme.ok, 0.08)

            Column {
                id: acctCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 12 * root.s
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3 * root.s
                Text {
                    width: parent.width
                    text: Ai.freeOnly ? "Sua conta não tem créditos: use os modelos do grupo Grátis"
                        : "Saldo $" + acctBox.balance.toFixed(2) + ": todos os modelos estão liberados"
                    color: Ai.freeOnly ? Theme.warn : Theme.ok
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                }
                Text {
                    width: parent.width
                    text: "Grátis: " + Ai.account.freeUsed + " de " + Ai.account.freeLimit + " mensagens usadas hoje"
                        + (Ai.freeOnly ? ". Para liberar os outros, adicione créditos em openrouter.ai/credits." : ".")
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    wrapMode: Text.Wrap
                }
            }
        }

        Text {
            id: priceHint
            anchors.top: acctBox.bottom
            anchors.topMargin: 10 * root.s
            anchors.right: parent.right
            text: Ai.provider === "openrouter" ? "preço por 1M tokens · entrada / saída"
                : Ai.models.length + " modelos da " + Ai.providerLabel
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 9 * root.s
        }

        ListView {
            id: modelList
            anchors.top: priceHint.bottom
            anchors.topMargin: 6 * root.s
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: 2 * root.s
            model: root.modelRows
            currentIndex: -1
            highlightMoveDuration: 0
            reuseItems: true
            cacheBuffer: 400 * root.s

            Text {
                anchors.centerIn: parent
                visible: modelList.count === 0
                text: !Ai.models.length ? "carregando modelos…" : "nenhum modelo encontrado"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 11 * root.s
            }

            delegate: Item {
                id: mw
                required property var modelData
                required property int index
                // group header when the group changes (free models first, then providers)
                readonly property bool head: index === 0 || root.modelRows[index - 1].group !== modelData.group
                width: modelList.width
                height: (head ? 30 * root.s : 0) + 46 * root.s

                Text {
                    visible: mw.head
                    anchors.left: parent.left
                    anchors.leftMargin: 12 * root.s
                    y: 12 * root.s
                    text: mw.modelData.group.toUpperCase()
                    color: mw.modelData.free ? Theme.ok : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 9.5 * root.s
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.2 * root.s
                }

            Rectangle {
                id: mr
                readonly property var modelData: mw.modelData
                readonly property bool selected: modelData.id === Ai.model
                readonly property bool active: mw.ListView.isCurrentItem || mrArea.containsMouse
                // paid model on an account without credits: listed, but dimmed
                readonly property bool locked: Ai.freeOnly && !modelData.free
                anchors.bottom: parent.bottom
                width: modelList.width
                height: 46 * root.s
                opacity: locked && !selected ? 0.45 : 1
                radius: 11 * root.s
                color: selected ? Qt.alpha(Theme.info, 0.10) : (active ? Theme.frameBg : "transparent")
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                border.width: 1
                border.color: selected ? Qt.alpha(Theme.info, 0.35) : "transparent"
                scale: mrArea.pressed ? 0.98 : 1
                Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 12 * root.s
                    anchors.right: mrMeta.left
                    anchors.rightMargin: 10 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2 * root.s
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: mr.modelData.name
                        color: mr.selected ? Theme.bright : Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 12 * root.s
                        font.weight: mr.selected ? Font.Bold : Font.Medium
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideMiddle
                        text: (mr.modelData.alias && mr.modelData.target
                                ? "sempre o mais novo → " + mr.modelData.target.replace(/^[^:]+:\s*/, "")
                                : mr.modelData.id)
                            + (mr.modelData.ctx ? "  ·  " + root.ctxLabel(mr.modelData.ctx) : "")
                        color: Theme.faint
                        font.family: mr.modelData.alias ? Theme.font : "monospace"
                        font.pixelSize: 9 * root.s
                    }
                }

                Row {
                    id: mrMeta
                    anchors.right: parent.right
                    anchors.rightMargin: 12 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8 * root.s
                    GlyphIcon {
                        visible: mr.modelData.image === true
                        anchors.verticalCenter: parent.verticalCenter
                        width: 13 * root.s
                        height: width
                        name: "image"
                        color: Theme.dim
                        stroke: 1.8
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: mr.locked ? "precisa de créditos" : root.price(mr.modelData)
                        visible: text.length > 0
                        color: mr.modelData.variable || (!mr.modelData.prompt && !mr.modelData.completion) ? Theme.dim : Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                        font.features: { "tnum": 1 }
                    }
                }

                MouseArea {
                    id: mrArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pickModel(mr.modelData.id)
                }
            }
            }
        }
    }
}
