pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "Singletons"

/**
 * 報 NOTIFICATIONS route of the drawer: the persistent history from NotifLog.
 * A header with the Do-Not-Disturb switch and a two-step "clear" button, a
 * search field (summary, body and app), a scrollable strip of app filter chips
 * with counts, then the entries grouped by day (Hoje / Ontem / weekday date).
 * Each card shows the app icon, app and time, the summary and a two-line body
 * that expands on demand; cards still live on the server carry a dot and
 * clicking one fires its default action, any card focuses the app's window.
 * A hover ✕ deletes one entry. Only the first `shown` entries are built, with a
 * "load more" at the end. Marks live notifications seen while open.
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

    property string query: ""
    property string appFilter: ""
    property int shown: 80
    property bool confirmClear: false
    property var expanded: ({})
    property real now: Date.now()

    onOpenChanged: if (open) {
        now = Date.now();
        Notifs.markAllSeen();
        search.input.forceActiveFocus();
    } else {
        confirmClear = false;
    }

    Timer {
        interval: 30000
        running: root.open
        repeat: true
        onTriggered: root.now = Date.now()
    }

    Timer {
        id: clearTimeout
        interval: 3500
        onTriggered: root.confirmClear = false
    }

    readonly property var filtered: {
        var q = query.trim().toLowerCase();
        var out = [];
        var all = NotifLog.entries;
        for (var i = 0; i < all.length; i++) {
            var e = all[i];
            if (appFilter.length && e.app !== appFilter)
                continue;
            if (q.length && (e.summary + " " + e.body + " " + e.app).toLowerCase().indexOf(q) < 0)
                continue;
            out.push(e);
        }
        return out;
    }

    /** The first `shown` filtered entries split into day sections. */
    readonly property var days: {
        var out = [];
        var cur = null;
        var list = filtered.slice(0, shown);
        for (var i = 0; i < list.length; i++) {
            var label = dayLabel(list[i].ts);
            if (!cur || cur.label !== label) {
                cur = { label: label, items: [] };
                out.push(cur);
            }
            cur.items.push(list[i]);
        }
        return out;
    }

    function dayLabel(ts) {
        var d = new Date(ts);
        var t = new Date(now);
        var start = new Date(t.getFullYear(), t.getMonth(), t.getDate()).getTime();
        if (ts >= start)
            return "Hoje";
        if (ts >= start - 86400000)
            return "Ontem";
        return Qt.locale("pt_BR").toString(d, "ddd, d 'de' MMM");
    }

    function timeLabel(ts) {
        var m = Math.floor((now - ts) / 60000);
        if (m < 1)
            return "agora";
        if (m < 60)
            return m + " min";
        return Qt.formatTime(new Date(ts), "HH:mm");
    }

    function plain(t) {
        return String(t || "").replace(/<[^>]*>/g, "").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").trim();
    }

    function liveFor(e) {
        var l = Notifs.tracked;
        for (var i = 0; i < l.length; i++)
            if (l[i].id === e.nid && Notifs.arrivalMs[l[i].id] === e.ts)
                return l[i];
        return null;
    }

    function activate(e) {
        var live = liveFor(e);
        Notifs.activateEntry({
            n: live || { desktopEntry: e.desktopEntry, appName: e.app, actions: [] },
            items: live ? [live] : []
        });
        root.requestClose();
    }

    function toggleExpanded(id) {
        var x = Object.assign({}, expanded);
        x[id] = !x[id];
        expanded = x;
    }

    component IconTile: Rectangle {
        id: it
        property string icon: ""
        property string image: ""
        property string app: ""
        property real size: 30

        width: size * root.s
        height: width
        radius: 9 * root.s
        color: Theme.tileBg
        border.width: 1
        border.color: Theme.frameBorder

        Image {
            id: itImg
            anchors.fill: parent
            anchors.margins: it.image.length ? 0 : 5 * root.s
            source: it.image.length ? it.image : it.icon
            sourceSize.width: 64
            sourceSize.height: 64
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            visible: status === Image.Ready
        }

        Text {
            anchors.centerIn: parent
            visible: !itImg.visible
            text: (it.app || "?").charAt(0).toUpperCase()
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: it.size * 0.42 * root.s
            font.weight: Font.Bold
        }
    }

    component HeaderButton: Rectangle {
        id: hb
        property string text: ""
        property string icon: ""
        property bool active: false
        property color tint: Theme.subtle
        signal clicked()

        width: hbRow.implicitWidth + 20 * root.s
        height: 24 * root.s
        radius: height / 2
        color: active ? Qt.alpha(tint, 0.16) : (hbArea.containsMouse ? Theme.frameBg : "transparent")
        border.width: 1
        border.color: active ? Qt.alpha(tint, 0.35) : Theme.frameBorder
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        Row {
            id: hbRow
            anchors.centerIn: parent
            spacing: 6 * root.s
            GlyphIcon {
                visible: hb.icon.length > 0
                anchors.verticalCenter: parent.verticalCenter
                width: 12 * root.s
                height: 12 * root.s
                name: hb.icon
                color: hb.active ? hb.tint : Theme.iconDim
                stroke: 2
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: hb.text
                color: hb.active ? hb.tint : Theme.subtle
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.weight: Font.Bold
            }
        }

        MouseArea {
            id: hbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: hb.clicked()
        }
    }

    component FilterChip: Rectangle {
        id: fc
        property string label: ""
        property int count: 0
        property string icon: ""
        property bool selected: false
        signal clicked()

        width: fcRow.implicitWidth + 18 * root.s
        height: 28 * root.s
        radius: height / 2
        color: selected ? Qt.alpha(Theme.cream, 0.12) : (fcArea.containsMouse ? Theme.frameBg : "transparent")
        border.width: 1
        border.color: selected ? Qt.alpha(Theme.cream, 0.3) : Theme.frameBorder
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        Row {
            id: fcRow
            anchors.centerIn: parent
            spacing: 6 * root.s

            Image {
                visible: fc.icon.length > 0 && status === Image.Ready
                anchors.verticalCenter: parent.verticalCenter
                width: 14 * root.s
                height: 14 * root.s
                source: fc.icon
                sourceSize.width: 32
                sourceSize.height: 32
                asynchronous: true
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: fc.label
                color: fc.selected ? Theme.bright : Theme.cream
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
                font.weight: fc.selected ? Font.DemiBold : Font.Medium
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: fc.count
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.weight: Font.Bold
                font.features: { "tnum": 1 }
            }
        }

        MouseArea {
            id: fcArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: fc.clicked()
        }
    }

    component EntryCard: Rectangle {
        id: card
        required property var modelData
        readonly property var e: modelData
        readonly property bool live: root.liveFor(e) !== null
        readonly property bool critical: e.urgency === 2
        readonly property bool isExpanded: root.expanded[e.id] === true
        readonly property string bodyText: root.plain(e.body)

        width: parent ? parent.width : 0
        height: cardCol.implicitHeight + 24 * root.s
        radius: 13 * root.s
        color: cardHover.hovered ? Qt.alpha(Theme.cream, 0.06) : Theme.frameBg
        border.width: 1
        border.color: critical ? Qt.alpha(Theme.danger, 0.4) : (cardHover.hovered ? Qt.alpha(Theme.cream, 0.14) : Theme.frameBorder)
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        HoverHandler { id: cardHover }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activate(card.e)
        }

        Rectangle {
            visible: card.critical
            anchors.left: parent.left
            anchors.leftMargin: 1
            anchors.verticalCenter: parent.verticalCenter
            width: 2.5 * root.s
            height: parent.height - 22 * root.s
            radius: width / 2
            color: Theme.danger
        }

        IconTile {
            id: tile
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin: 13 * root.s
            anchors.topMargin: 12 * root.s
            icon: card.e.icon
            image: card.e.image
            app: card.e.app
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

                Row {
                    anchors.left: parent.left
                    anchors.right: timeText.left
                    anchors.rightMargin: 8 * root.s
                    spacing: 6 * root.s

                    Rectangle {
                        visible: card.live
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6 * root.s
                        height: width
                        radius: width / 2
                        color: Theme.info
                    }
                    Text {
                        id: appText
                        text: card.e.app
                        color: Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 9.5 * root.s
                        font.weight: Font.Bold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.8 * root.s
                    }
                }

                Text {
                    id: timeText
                    anchors.right: parent.right
                    visible: !cardHover.hovered
                    text: root.timeLabel(card.e.ts)
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 9.5 * root.s
                    font.features: { "tnum": 1 }
                }

                // delete, shown on hover in place of the time
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: cardHover.hovered
                    width: 20 * root.s
                    height: width
                    radius: width / 2
                    color: delArea.containsMouse ? Qt.alpha(Theme.danger, 0.18) : Theme.frameBg
                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 10 * root.s
                        height: 10 * root.s
                        name: "x"
                        color: delArea.containsMouse ? Theme.danger : Theme.iconDim
                        stroke: 2.4
                    }
                    MouseArea {
                        id: delArea
                        anchors.fill: parent
                        anchors.margins: -4 * root.s
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: NotifLog.remove(card.e.id)
                    }
                }
            }

            Text {
                width: parent.width
                visible: text.length > 0
                text: root.plain(card.e.summary)
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: cardHover.hovered ? Theme.bright : Theme.cream
                font.family: Theme.font
                font.pixelSize: 12.5 * root.s
                font.weight: Font.DemiBold
            }

            Text {
                id: bodyLabel
                width: parent.width
                visible: card.bodyText.length > 0
                text: card.bodyText
                wrapMode: Text.Wrap
                maximumLineCount: card.isExpanded ? 40 : 2
                elide: Text.ElideRight
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
                    onClicked: root.toggleExpanded(card.e.id)
                }
            }
        }
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
                text: "報"
                color: Theme.cream
                font.family: Theme.fontJp
                font.weight: Font.Medium
                font.pixelSize: 16 * root.s
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "NOTIFICAÇÕES"
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
            spacing: 6 * root.s

            HeaderButton {
                text: "Não perturbe"
                icon: "dnd"
                active: Flags.dnd
                tint: Theme.warn
                onClicked: Flags.dnd = !Flags.dnd
            }
            HeaderButton {
                visible: NotifLog.count > 0
                text: root.confirmClear ? "Confirmar?" : "Limpar"
                icon: "trash"
                active: root.confirmClear
                tint: Theme.danger
                onClicked: {
                    if (root.confirmClear) {
                        root.confirmClear = false;
                        if (root.appFilter.length)
                            NotifLog.clearApp(root.appFilter);
                        else
                            NotifLog.clear();
                        root.appFilter = "";
                    } else {
                        root.confirmClear = true;
                        clearTimeout.restart();
                    }
                }
            }
        }
    }

    // search
    Rectangle {
        id: searchBox
        anchors.top: header.bottom
        anchors.topMargin: 16 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 40 * root.s
        radius: 12 * root.s
        color: Theme.frameBg
        border.width: 1
        border.color: search.input.activeFocus ? Qt.alpha(Theme.cream, 0.22) : Theme.frameBorder

        SearchField {
            id: search
            anchors.fill: parent
            anchors.leftMargin: 14 * root.s
            anchors.rightMargin: 14 * root.s
            s: root.s
            kanji: "探"
            placeholder: "Buscar nas notificações"
            counterText: root.query.length || root.appFilter.length ? root.filtered.length + " de " + NotifLog.count : NotifLog.count + ""
            onTextChanged: {
                root.query = text;
                root.shown = 80;
            }
            onDismissed: {
                if (text.length)
                    text = "";
                else
                    root.requestClose();
            }
        }
    }

    // app filters
    Flickable {
        id: chips
        anchors.top: searchBox.bottom
        anchors.topMargin: 12 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 28 * root.s
        visible: NotifLog.apps.length > 1
        contentWidth: chipRow.implicitWidth
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick

        Row {
            id: chipRow
            spacing: 6 * root.s

            FilterChip {
                label: "Todas"
                count: NotifLog.count
                selected: root.appFilter === ""
                onClicked: {
                    root.appFilter = "";
                    root.shown = 80;
                }
            }
            Repeater {
                model: NotifLog.apps
                FilterChip {
                    required property var modelData
                    label: modelData.app
                    count: modelData.count
                    icon: modelData.icon
                    selected: root.appFilter === modelData.app
                    onClicked: {
                        root.appFilter = selected ? "" : modelData.app;
                        root.shown = 80;
                    }
                }
            }
        }

        WheelHandler {
            orientation: Qt.Vertical
            onWheel: (ev) => {
                chips.contentX = Math.max(0, Math.min(chips.contentWidth - chips.width, chips.contentX - ev.angleDelta.y));
            }
        }
    }

    // list
    Flickable {
        id: list
        anchors.top: chips.visible ? chips.bottom : searchBox.bottom
        anchors.topMargin: 14 * root.s
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
                model: root.days

                Column {
                    id: daySec
                    required property var modelData
                    width: listCol.width
                    spacing: 8 * root.s
                    topPadding: 4 * root.s

                    Row {
                        spacing: 8 * root.s
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: daySec.modelData.label
                            color: Theme.cream
                            font.family: Theme.font
                            font.pixelSize: 10 * root.s
                            font.weight: Font.Bold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 1.2 * root.s
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: daySec.modelData.items.length
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 9.5 * root.s
                            font.weight: Font.Bold
                        }
                    }

                    Repeater {
                        model: daySec.modelData.items
                        EntryCard {}
                    }
                }
            }

            Text {
                visible: root.filtered.length > root.shown
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: 6 * root.s
                bottomPadding: 6 * root.s
                text: "Carregar mais " + Math.min(80, root.filtered.length - root.shown)
                color: loadArea.containsMouse ? Theme.cream : Theme.dim
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
                font.weight: Font.DemiBold

                MouseArea {
                    id: loadArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.shown += 80
                }
            }

            Text {
                visible: root.filtered.length > 0
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: 8 * root.s
                bottomPadding: 4 * root.s
                text: "Guardadas por " + NotifLog.maxAgeDays + " dias · até " + NotifLog.maxEntries
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 9 * root.s
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

    // empty state
    Column {
        anchors.centerIn: list
        visible: root.filtered.length === 0
        spacing: 10 * root.s

        GlyphIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 34 * root.s
            height: 34 * root.s
            name: "inbox"
            color: Theme.faint
            stroke: 1.4
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: NotifLog.count === 0 ? "Nenhuma notificação ainda" : "Nada encontrado"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 12 * root.s
            font.weight: Font.Medium
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: NotifLog.count === 0
            text: "Tudo que chegar fica guardado aqui"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10 * root.s
        }
    }
}
