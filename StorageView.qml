pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import "Singletons"

/**
 * 蔵 ARMAZENAMENTO route of the drawer, laid out for the widened card.
 *
 *  - Disk map: one bar per physical disk, partitions to scale and coloured by
 *    what they are (Linux, Windows, EFI, other) with a legend; mounted ones
 *    fill with their usage. Hover names the partition.
 *  - Linux partition: usage ring (red past 90%) with a ghost arc for where it
 *    would land after the suggested cleanups, free space, and the share of the
 *    top-level folders as a stacked bar.
 *  - Where the space is: a two-level squarified treemap of the current folder
 *    (each tile previews its own subfolders) with a breadcrumb and a hover
 *    status line. Clicking a tile drills in; a folder past the root scan's
 *    depth is scanned on demand. Unreadable bytes and loose files get tiles.
 *  - Cleanups: reclaimable caches with size, share of the total and command;
 *    copy it, or run it in a terminal after a confirming second click.
 *  - Largest files with a size bar; clicking opens the containing folder.
 *
 * Surfaces follow concentric radii: cards are 18 with 14 padding, so inner
 * pieces use 4 to 8.
 */
Item {
    id: root

    property real s: 1
    property bool open: false

    opacity: open ? 1 : 0
    visible: opacity > 0.01
    enabled: open
    Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

    property var crumbs: []
    property string hoverText: ""
    property string confirmKey: ""
    property real now: Date.now()

    readonly property real cardR: 18 * s
    readonly property real pad: 14 * s
    readonly property real innerR: 6 * s

    onOpenChanged: if (open) {
        now = Date.now();
        Storage.refreshIfStale(10 * 60 * 1000);
    }

    Timer {
        interval: 30000
        running: root.open
        repeat: true
        onTriggered: root.now = Date.now()
    }

    Timer {
        id: confirmTimeout
        interval: 3500
        onTriggered: root.confirmKey = ""
    }

    readonly property var palette: ["#e2875f", "#5b9bd5", "#55b97f", "#d8a74a", "#9d84e2", "#d475a9", "#4cbac6", "#9aa3ad"]
    readonly property color linuxColor: "#e2875f"
    readonly property color windowsColor: "#5b9bd5"

    function partKind(p) {
        if (p.mount === "/")
            return { label: "Linux", color: linuxColor };
        if (p.fs === "ntfs")
            return { label: "Windows", color: windowsColor };
        if (p.fs === "vfat")
            return { label: p.mount === "/boot/efi" ? "EFI" : "FAT", color: "#55b97f" };
        if (p.fs === "ext4" || p.fs === "btrfs" || p.fs === "xfs")
            return { label: "Linux", color: "#9d84e2" };
        if (p.fs === "swap")
            return { label: "Swap", color: "#d8a74a" };
        return { label: "Reservada", color: "#6b7280" };
    }

    function findNode(node, path) {
        if (!node)
            return null;
        if (node.path === path)
            return node;
        for (var i = 0; i < node.children.length; i++) {
            var c = node.children[i];
            if (path === c.path || path.indexOf(c.path + "/") === 0)
                return findNode(c, path);
        }
        return null;
    }

    readonly property var current: {
        var path = crumbs.length ? crumbs[crumbs.length - 1] : "/";
        var sub = Storage.subtrees[path];
        var n = findNode(Storage.tree, path);
        if (sub && (!n || n.leaf))
            return sub;
        if (!n) {
            for (var p in Storage.subtrees) {
                var m = findNode(Storage.subtrees[p], path);
                if (m)
                    return m.leaf && Storage.subtrees[path] ? Storage.subtrees[path] : m;
            }
        }
        return n;
    }

    readonly property var tiles: {
        var n = current;
        if (!n)
            return [];
        var out = [];
        var sum = 0;
        n.children.forEach(function(c, i) {
            if (c.size > 0) {
                out.push({ name: c.name, path: c.path, size: c.size, kind: "dir", leaf: c.leaf,
                           children: c.children, color: root.palette[i % root.palette.length] });
                sum += c.size;
            }
        });
        var loose = n.size - sum;
        if (loose > n.size * 0.01)
            out.push({ name: "arquivos soltos", path: n.path, size: loose, kind: "files", children: [], color: "#9aa3ad" });
        if (n.path === "/" && Storage.fsUsed > n.size)
            out.push({ name: "sistema · sem acesso", path: "", size: Storage.fsUsed - n.size, kind: "hidden", children: [], color: "#6b7280" });
        return out;
    }

    /** Squarified treemap layout of `items` into w×h; returns items with x/y/w/h. */
    function squarify(items, w, h) {
        var total = items.reduce(function(a, b) { return a + b.size; }, 0);
        if (total <= 0 || w <= 0 || h <= 0)
            return [];
        var scale = (w * h) / total;
        var rects = [];
        var x = 0, y = 0, rw = w, rh = h;
        var row = [];
        function worst(r, side) {
            var s = r.reduce(function(a, b) { return a + b.area; }, 0);
            var mx = 0, mn = Infinity;
            r.forEach(function(it) { mx = Math.max(mx, it.area); mn = Math.min(mn, it.area); });
            return Math.max(side * side * mx / (s * s), (s * s) / (side * side * mn));
        }
        function layoutRow(r) {
            var s = r.reduce(function(a, b) { return a + b.area; }, 0);
            if (rw >= rh) {
                var colW = s / rh;
                var yy = y;
                r.forEach(function(it) {
                    var hh = it.area / colW;
                    rects.push(Object.assign({}, it.item, { x: x, y: yy, w: colW, h: hh }));
                    yy += hh;
                });
                x += colW;
                rw -= colW;
            } else {
                var rowH = s / rw;
                var xx = x;
                r.forEach(function(it) {
                    var ww = it.area / rowH;
                    rects.push(Object.assign({}, it.item, { x: xx, y: y, w: ww, h: rowH }));
                    xx += ww;
                });
                y += rowH;
                rh -= rowH;
            }
        }
        var queue = items.slice().sort(function(a, b) { return b.size - a.size; })
            .map(function(it) { return { item: it, area: it.size * scale }; });
        while (queue.length) {
            var side = Math.min(rw, rh);
            if (!row.length || worst(row.concat([queue[0]]), side) <= worst(row, side)) {
                row.push(queue.shift());
            } else {
                layoutRow(row);
                row = [];
            }
        }
        if (row.length)
            layoutRow(row);
        return rects;
    }

    /** Children to preview inside a tile, skipping single-folder chains (/home → /home/you). */
    function previewChildren(node) {
        var n = node;
        while (n && n.children && n.children.length === 1)
            n = n.children[0];
        return n && n.children ? n.children.filter(function(c) { return c.size > 0; }) : [];
    }

    function drill(tile) {
        if (tile.kind !== "dir")
            return;
        crumbs = crumbs.concat([tile.path]);
        if (tile.leaf)
            Storage.subScan(tile.path);
    }

    function ago(ms) {
        if (!ms)
            return "nunca";
        var m = Math.floor((now - ms) / 60000);
        return m < 1 ? "agora" : (m < 60 ? "há " + m + " min" : "há " + Math.floor(m / 60) + " h");
    }

    function cleanupColor(icon) {
        return ({ "code": "#5b9bd5", "archive": "#d8a74a", "trash": "#e5534b", "image": "#d475a9", "list": "#9d84e2" })[icon] || "#55b97f";
    }

    // ---- building blocks ----

    component Card: Rectangle {
        id: card
        default property alias content: cardBody.data
        property string title: ""
        property string icon: ""
        property string aside: ""
        property color asideColor: Theme.dim
        radius: root.cardR
        color: Qt.alpha(Theme.cream, 0.035)

        Row {
            id: cardHead
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin: root.pad
            anchors.topMargin: root.pad
            spacing: 8 * root.s
            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 14 * root.s
                height: width
                name: card.icon
                color: Theme.subtle
                stroke: 2
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: card.title
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 11.5 * root.s
                font.weight: Font.DemiBold
            }
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: root.pad
            anchors.verticalCenter: cardHead.verticalCenter
            text: card.aside
            color: card.asideColor
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
            font.weight: Font.DemiBold
        }
        Item {
            id: cardBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: cardHead.bottom
            anchors.bottom: parent.bottom
            anchors.margins: root.pad
            anchors.topMargin: 12 * root.s
        }
    }

    component IconTile: Rectangle {
        id: itile
        property string icon: ""
        property color tint: Theme.subtle
        property real size: 30
        width: size * root.s
        height: width
        radius: root.innerR + 2 * root.s
        color: Qt.alpha(tint, 0.14)
        GlyphIcon {
            anchors.centerIn: parent
            width: itile.width * 0.5
            height: width
            name: itile.icon
            color: itile.tint
            stroke: 1.9
        }
    }

    // ---- header ----
    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 28 * root.s

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * root.s
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "蔵"
                color: Theme.cream
                font.family: Theme.fontJp
                font.weight: Font.Medium
                font.pixelSize: 16 * root.s
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "ARMAZENAMENTO"
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
            spacing: 10 * root.s
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6 * root.s
                Rectangle {
                    id: scanDot
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6 * root.s
                    height: width
                    radius: width / 2
                    color: Storage.scanning ? Theme.warn : Theme.ok
                    SequentialAnimation on opacity {
                        running: Storage.scanning && root.open
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) scanDot.opacity = 1
                        NumberAnimation { to: 0.3; duration: 600 }
                        NumberAnimation { to: 1; duration: 600 }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Storage.scanning ? "analisando…" : "analisado " + root.ago(Storage.scannedAt)
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                }
            }
            GhPill {
                s: root.s
                text: "Atualizar"
                hoverable: !Storage.busy
                enabledLook: !Storage.busy
                onClicked: Storage.refresh()
            }
        }
    }

    // ---- disk map ----
    Card {
        id: diskCard
        anchors.top: header.bottom
        anchors.topMargin: 14 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 76 * root.s + Storage.disks.length * 66 * root.s
        title: "Discos"
        icon: "drive"
        aside: Storage.disks.length ? Storage.fmt(Storage.disks.reduce(function(a, d) { return a + d.size; }, 0)) + " no total" : ""

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 14 * root.s

            Repeater {
                model: Storage.disks
                Item {
                    id: disk
                    required property var modelData
                    width: parent.width
                    height: 52 * root.s

                    IconTile {
                        id: diskIcon
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "drive"
                        size: 38
                    }

                    Item {
                        anchors.left: diskIcon.right
                        anchors.leftMargin: 12 * root.s
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom

                        Text {
                            id: diskName
                            anchors.top: parent.top
                            text: disk.modelData.model || disk.modelData.name
                            color: Theme.cream
                            font.family: Theme.font
                            font.pixelSize: 11.5 * root.s
                            font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.left: diskName.right
                            anchors.leftMargin: 8 * root.s
                            anchors.baseline: diskName.baseline
                            text: disk.modelData.name + (disk.modelData.tran ? " · " + disk.modelData.tran.toUpperCase() : "")
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 10 * root.s
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.baseline: diskName.baseline
                            text: Storage.fmt(disk.modelData.size)
                            color: Theme.subtle
                            font.family: Theme.font
                            font.pixelSize: 11 * root.s
                            font.weight: Font.DemiBold
                        }

                        Row {
                            id: bar
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 28 * root.s
                            spacing: 3 * root.s
                            readonly property real minW: 6 * root.s
                            readonly property var parts: disk.modelData.parts
                            readonly property real avail: width - spacing * (parts.length - 1) - minW * parts.length
                            readonly property real total: parts.reduce(function(a, p) { return a + p.size; }, 0)

                            Repeater {
                                model: bar.parts
                                Rectangle {
                                    id: seg
                                    required property var modelData
                                    readonly property var kind: root.partKind(modelData)
                                    readonly property bool mounted: modelData.used !== undefined
                                    readonly property real frac: mounted ? modelData.used / (modelData.used + modelData.free) : 0
                                    readonly property color fillColor: frac > 0.9 ? "#e5534b" : kind.color
                                    width: bar.minW + bar.avail * modelData.size / bar.total
                                    height: bar.height
                                    radius: root.innerR
                                    color: Qt.alpha(kind.color, segHover.hovered ? 0.24 : 0.14)
                                    clip: true
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    Rectangle {
                                        visible: seg.mounted
                                        width: parent.width * seg.frac
                                        height: parent.height
                                        radius: parent.radius
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: Qt.alpha(seg.fillColor, 0.45) }
                                            GradientStop { position: 1.0; color: Qt.alpha(seg.fillColor, 0.8) }
                                        }
                                    }
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: 2 * root.s
                                        color: seg.kind.color
                                        visible: seg.width > 10 * root.s
                                    }
                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10 * root.s
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6 * root.s
                                        visible: seg.width > 96 * root.s
                                        Text {
                                            text: seg.kind.label + (seg.modelData.mount ? "  " + seg.modelData.mount : "")
                                            color: Theme.bright
                                            font.family: Theme.font
                                            font.pixelSize: 10.5 * root.s
                                            font.weight: Font.Bold
                                        }
                                        Text {
                                            text: Storage.fmt(seg.modelData.size) + (seg.mounted ? " · " + Math.round(seg.frac * 100) + "%" : "")
                                            color: Qt.alpha(Theme.bright, 0.7)
                                            font.family: Theme.font
                                            font.pixelSize: 10 * root.s
                                            font.features: { "tnum": 1 }
                                        }
                                    }
                                    HoverHandler {
                                        id: segHover
                                        onHoveredChanged: root.hoverText = hovered
                                            ? seg.modelData.name + " · " + seg.kind.label + (seg.modelData.fs ? " (" + seg.modelData.fs + ")" : "")
                                              + (seg.modelData.label ? " · “" + seg.modelData.label + "”" : "")
                                              + " · " + Storage.fmt(seg.modelData.size)
                                              + (seg.modelData.mount ? " · montada em " + seg.modelData.mount + ", " + Storage.fmt(seg.modelData.free) + " livres" : " · não montada")
                                            : ""
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // legend
        Row {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            spacing: 14 * root.s
            Repeater {
                model: [
                    { label: "Linux", color: root.linuxColor },
                    { label: "Windows", color: root.windowsColor },
                    { label: "EFI", color: "#55b97f" },
                    { label: "Reservada", color: "#6b7280" },
                    { label: "preenchido = usado", color: Theme.cream, used: true }
                ]
                Row {
                    id: lgItem
                    required property var modelData
                    spacing: 6 * root.s
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10 * root.s
                        height: 10 * root.s
                        radius: 3 * root.s
                        color: lgItem.modelData.used ? "transparent" : Qt.alpha(lgItem.modelData.color, 0.55)
                        border.width: lgItem.modelData.used ? 1.5 * root.s : 0
                        border.color: Qt.alpha(Theme.cream, 0.5)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: lgItem.modelData.label
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                    }
                }
            }
        }
    }

    // ---- left column ----
    Item {
        id: leftCol
        anchors.top: diskCard.bottom
        anchors.topMargin: 14 * root.s
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: (parent.width - 14 * root.s) * 0.6

        Card {
            id: rootCard
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 150 * root.s
            title: "Partição do Linux"
            icon: "drive"
            readonly property real used: Storage.rootFs ? Storage.rootFs.used : 0
            readonly property real free: Storage.rootFs ? Storage.rootFs.free : 0
            readonly property real cap: Math.max(1, used + free)
            // Same figure as df's Use%: ext4's root-reserved blocks don't count as free.
            readonly property real frac: used / cap
            readonly property real afterFrac: Math.max(0, used - Storage.cleanupTotal) / cap
            readonly property color tone: frac > 0.9 ? "#e5534b" : (frac > 0.75 ? Theme.warn : Theme.ok)
            aside: frac > 0.9 ? "pouco espaço livre" : "montada em /"
            asideColor: frac > 0.9 ? "#e5534b" : Theme.dim

            Item {
                id: ring
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 92 * root.s
                height: width
                readonly property real r: width / 2 - 6 * root.s

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: Theme.threadBg
                        strokeWidth: 9 * root.s
                        fillColor: "transparent"
                        PathAngleArc { centerX: ring.width / 2; centerY: ring.height / 2; radiusX: ring.r; radiusY: ring.r; startAngle: 0; sweepAngle: 360 }
                    }
                    ShapePath {
                        strokeColor: Qt.alpha(rootCard.tone, 0.35)
                        strokeWidth: 9 * root.s
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc { centerX: ring.width / 2; centerY: ring.height / 2; radiusX: ring.r; radiusY: ring.r; startAngle: -90; sweepAngle: 360 * rootCard.frac }
                    }
                    // what stays after the suggested cleanups
                    ShapePath {
                        strokeColor: rootCard.tone
                        strokeWidth: 9 * root.s
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc { centerX: ring.width / 2; centerY: ring.height / 2; radiusX: ring.r; radiusY: ring.r; startAngle: -90; sweepAngle: 360 * rootCard.afterFrac }
                    }
                }
                Column {
                    anchors.centerIn: parent
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Math.round(rootCard.frac * 100) + "%"
                        color: Theme.bright
                        font.family: Theme.font
                        font.pixelSize: 20 * root.s
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "usado"
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 9 * root.s
                    }
                }
            }

            Column {
                anchors.left: ring.right
                anchors.leftMargin: 20 * root.s
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9 * root.s

                Row {
                    spacing: 7 * root.s
                    Text {
                        id: freeBig
                        text: Storage.fmt(rootCard.free)
                        color: Theme.bright
                        font.family: Theme.font
                        font.pixelSize: 24 * root.s
                        font.weight: Font.Bold
                        font.letterSpacing: -0.5 * root.s
                    }
                    Text {
                        anchors.baseline: freeBig.baseline
                        text: "livres de " + Storage.fmt(rootCard.cap)
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                    }
                }

                Text {
                    visible: Storage.cleanupTotal > 0
                    text: "Com as limpezas sugeridas: " + Math.round(rootCard.frac * 100) + "% → " + Math.round(rootCard.afterFrac * 100) + "%"
                    color: Theme.ok
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                    font.weight: Font.DemiBold
                }

                Item {
                    width: parent.width
                    height: 8 * root.s
                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: Theme.threadBg
                    }
                    Row {
                        id: comp
                        anchors.fill: parent
                        readonly property var parts: {
                            var t = Storage.tree;
                            if (!t)
                                return [];
                            return t.children.filter(function(c) { return c.size > rootCard.cap * 0.01; })
                                .map(function(c, i) { return { name: c.name, size: c.size, color: root.palette[i % root.palette.length] }; });
                        }
                        Repeater {
                            model: comp.parts
                            Rectangle {
                                required property var modelData
                                required property int index
                                width: comp.width * modelData.size / rootCard.cap
                                height: comp.height
                                radius: index === 0 ? height / 2 : 0
                                color: modelData.color
                            }
                        }
                    }
                }
                Flow {
                    width: parent.width
                    spacing: 12 * root.s
                    Repeater {
                        model: comp.parts
                        Row {
                            id: lg
                            required property var modelData
                            spacing: 5 * root.s
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8 * root.s
                                height: width
                                radius: width / 2
                                color: lg.modelData.color
                            }
                            Text {
                                text: "/" + lg.modelData.name.replace(/^\//, "")
                                color: Theme.subtle
                                font.family: Theme.font
                                font.pixelSize: 10 * root.s
                            }
                            Text {
                                text: Storage.fmt(lg.modelData.size)
                                color: Theme.faint
                                font.family: Theme.font
                                font.pixelSize: 10 * root.s
                                font.features: { "tnum": 1 }
                            }
                        }
                    }
                }
            }
        }

        Card {
            id: mapCard
            anchors.top: rootCard.bottom
            anchors.topMargin: 14 * root.s
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            title: "Onde está o espaço"
            icon: "archive"
            aside: root.current ? Storage.fmt(root.current.size) + " nesta pasta" : ""

            Row {
                id: crumbRow
                width: parent.width
                height: 24 * root.s
                spacing: 2 * root.s

                Repeater {
                    model: ["/"].concat(root.crumbs)
                    Row {
                        id: cr
                        required property string modelData
                        required property int index
                        readonly property bool last: index === root.crumbs.length
                        spacing: 2 * root.s
                        GlyphIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: cr.index > 0
                            width: 10 * root.s
                            height: width
                            name: "chevronDown"
                            rotation: -90
                            color: Theme.faint
                            stroke: 2.4
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: crText.implicitWidth + 16 * root.s
                            height: 24 * root.s
                            radius: root.innerR
                            color: cr.last ? Qt.alpha(Theme.cream, 0.08) : (crArea.containsMouse ? Qt.alpha(Theme.cream, 0.05) : "transparent")
                            Text {
                                id: crText
                                anchors.centerIn: parent
                                text: cr.index === 0 ? "/" : cr.modelData.split("/").pop()
                                color: cr.last ? Theme.bright : Theme.subtle
                                font.family: Theme.font
                                font.pixelSize: 11 * root.s
                                font.weight: cr.last ? Font.DemiBold : Font.Normal
                            }
                            MouseArea {
                                id: crArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !cr.last
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.crumbs = root.crumbs.slice(0, cr.index)
                            }
                        }
                    }
                }
            }

            GhPill {
                anchors.right: parent.right
                anchors.verticalCenter: crumbRow.verticalCenter
                visible: root.crumbs.length > 0
                s: root.s
                text: "abrir pasta"
                onClicked: Storage.openFolder(root.crumbs[root.crumbs.length - 1])
            }

            Item {
                id: map
                anchors.top: crumbRow.bottom
                anchors.topMargin: 10 * root.s
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: statusLine.top
                anchors.bottomMargin: 8 * root.s

                readonly property var rects: root.squarify(root.tiles, width, height)
                readonly property real gap: 3 * root.s

                Repeater {
                    model: map.rects
                    Rectangle {
                        id: tile
                        required property var modelData
                        readonly property var t: modelData
                        readonly property bool clickable: t.kind === "dir"
                        readonly property bool roomy: width > 90 * root.s && height > 56 * root.s
                        readonly property real headH: roomy ? 40 * root.s : 0
                        x: t.x + map.gap / 2
                        y: t.y + map.gap / 2
                        width: Math.max(0, t.w - map.gap)
                        height: Math.max(0, t.h - map.gap)
                        radius: Math.min(root.innerR + 2 * root.s, width / 3, height / 3)
                        clip: true
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.alpha(tile.t.color, tileHover.hovered && tile.clickable ? 0.34 : 0.24) }
                            GradientStop { position: 1.0; color: Qt.alpha(tile.t.color, tileHover.hovered && tile.clickable ? 0.20 : 0.11) }
                        }
                        border.width: tileHover.hovered && tile.clickable ? 1 : 0
                        border.color: Qt.alpha(tile.t.color, 0.8)

                        // second level: this folder's own subfolders
                        Item {
                            id: inner
                            readonly property var items: tile.roomy ? root.previewChildren(tile.t) : []
                            visible: items.length > 1
                            x: 6 * root.s
                            y: tile.headH
                            width: tile.width - 12 * root.s
                            height: tile.height - tile.headH - 6 * root.s
                            readonly property var rects: visible ? root.squarify(items, width, height) : []

                            Repeater {
                                model: inner.rects
                                Rectangle {
                                    id: sub
                                    required property var modelData
                                    x: modelData.x + 1
                                    y: modelData.y + 1
                                    width: Math.max(0, modelData.w - 2)
                                    height: Math.max(0, modelData.h - 2)
                                    radius: Math.min(4 * root.s, width / 3, height / 3)
                                    color: Qt.alpha(tile.t.color, 0.13)
                                    border.width: 1
                                    border.color: Qt.alpha(tile.t.color, 0.22)
                                    Text {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.margins: 5 * root.s
                                        width: parent.width - 10 * root.s
                                        visible: sub.width > 52 * root.s && sub.height > 20 * root.s
                                        elide: Text.ElideRight
                                        text: sub.modelData.name
                                        color: Qt.alpha(Theme.bright, 0.62)
                                        font.family: Theme.font
                                        font.pixelSize: 9.5 * root.s
                                    }
                                }
                            }
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: 9 * root.s
                            width: parent.width - 18 * root.s
                            spacing: 1 * root.s
                            visible: tile.width > 48 * root.s && tile.height > 28 * root.s
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: tile.t.name
                                color: Theme.bright
                                font.family: Theme.font
                                font.pixelSize: (tile.roomy ? 12.5 : 10.5) * root.s
                                font.weight: Font.DemiBold
                                font.italic: tile.t.kind !== "dir"
                            }
                            Text {
                                visible: tile.height > 42 * root.s
                                text: Storage.fmt(tile.t.size) + (root.current && root.current.size ? "  ·  " + Math.round(100 * tile.t.size / root.current.size) + "%" : "")
                                color: Qt.lighter(tile.t.color, 1.35)
                                font.family: Theme.font
                                font.pixelSize: 10 * root.s
                                font.features: { "tnum": 1 }
                            }
                        }

                        HoverHandler {
                            id: tileHover
                            cursorShape: tile.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onHoveredChanged: root.hoverText = hovered
                                ? (tile.t.path || tile.t.name) + " · " + Storage.fmt(tile.t.size)
                                  + (tile.t.kind === "hidden" ? " · pastas do sistema que só o root consegue ler"
                                    : (tile.clickable ? " · clique para entrar" : ""))
                                : ""
                        }
                        TapHandler {
                            enabled: tile.clickable
                            onTapped: root.drill(tile.t)
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    visible: map.rects.length === 0
                    spacing: 6 * root.s
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Storage.subScanning.length ? "Analisando " + Storage.subScanning.split("/").pop() + "…"
                            : (Storage.tree ? "Sem subpastas aqui" : "Analisando o disco…")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 12 * root.s
                    }
                }
            }

            Text {
                id: statusLine
                anchors.bottom: parent.bottom
                width: parent.width
                height: 14 * root.s
                elide: Text.ElideMiddle
                text: root.hoverText.length ? root.hoverText : "Passe o mouse para ver detalhes · clique para entrar na pasta"
                color: root.hoverText.length ? Theme.subtle : Theme.faint
                font.family: Theme.font
                font.pixelSize: 10 * root.s
            }
        }
    }

    // ---- right column ----
    Item {
        anchors.top: leftCol.top
        anchors.left: leftCol.right
        anchors.leftMargin: 14 * root.s
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        Card {
            id: cleanCard
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.min(parent.height * 0.56, 54 * root.s + Math.max(1, Storage.cleanup.length) * 60 * root.s)
            title: "Limpezas sugeridas"
            icon: "trash"
            aside: Storage.cleanupTotal > 0 ? Storage.fmt(Storage.cleanupTotal) + " recuperáveis" : ""
            asideColor: Theme.ok

            Flickable {
                anchors.fill: parent
                contentHeight: cleanCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: cleanCol
                    width: parent.width
                    spacing: 4 * root.s

                    Text {
                        visible: Storage.cleanup.length === 0
                        text: Storage.busy ? "Procurando…" : "Nada relevante para limpar"
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                    }

                    Repeater {
                        model: Storage.cleanup
                        Rectangle {
                            id: cl
                            required property var modelData
                            readonly property bool confirming: root.confirmKey === modelData.key
                            readonly property color tint: root.cleanupColor(modelData.icon)
                            readonly property bool showActions: clHover.hovered || confirming
                            width: cleanCol.width
                            height: 56 * root.s
                            radius: root.innerR + 2 * root.s
                            color: confirming ? Qt.alpha(Theme.warn, 0.08) : (clHover.hovered ? Qt.alpha(Theme.cream, 0.045) : "transparent")
                            Behavior on color { ColorAnimation { duration: 120 } }
                            HoverHandler { id: clHover }

                            IconTile {
                                id: clIcon
                                anchors.left: parent.left
                                anchors.leftMargin: 8 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                icon: cl.modelData.icon
                                tint: cl.tint
                                size: 32
                            }

                            Column {
                                anchors.left: clIcon.right
                                anchors.leftMargin: 11 * root.s
                                anchors.right: clRight.left
                                anchors.rightMargin: 10 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 5 * root.s
                                Row {
                                    spacing: 6 * root.s
                                    Text {
                                        text: cl.modelData.title
                                        color: Theme.cream
                                        font.family: Theme.font
                                        font.pixelSize: 11.5 * root.s
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        visible: cl.modelData.root
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "sudo"
                                        color: Theme.warn
                                        font.family: Theme.font
                                        font.pixelSize: 8.5 * root.s
                                        font.weight: Font.Bold
                                    }
                                }
                                // share of the total recoverable
                                Rectangle {
                                    width: parent.width
                                    height: 4 * root.s
                                    radius: height / 2
                                    color: Theme.threadBg
                                    visible: !cl.showActions
                                    Rectangle {
                                        width: parent.width * cl.modelData.size / Math.max(1, Storage.cleanupTotal)
                                        height: parent.height
                                        radius: parent.radius
                                        color: Qt.alpha(cl.tint, 0.8)
                                    }
                                }
                                Text {
                                    visible: cl.showActions
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: cl.confirming ? "Clique de novo para abrir no terminal" : "$ " + cl.modelData.cmd
                                    color: cl.confirming ? Theme.warn : Theme.subtle
                                    font.family: cl.confirming ? Theme.font : "monospace"
                                    font.pixelSize: 9.5 * root.s
                                }
                            }

                            Item {
                                id: clRight
                                anchors.right: parent.right
                                anchors.rightMargin: 8 * root.s
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 82 * root.s

                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !cl.showActions
                                    text: Storage.fmt(cl.modelData.size)
                                    color: Theme.bright
                                    font.family: Theme.font
                                    font.pixelSize: 12.5 * root.s
                                    font.weight: Font.Bold
                                    font.features: { "tnum": 1 }
                                }

                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: cl.showActions
                                    spacing: 4 * root.s
                                    Repeater {
                                        model: [{ icon: "copy", act: "copy" }, { icon: "terminal", act: "run" }]
                                        Rectangle {
                                            id: ab
                                            required property var modelData
                                            readonly property bool hot: ab.modelData.act === "run" && cl.confirming
                                            width: 30 * root.s
                                            height: width
                                            radius: root.innerR
                                            color: hot ? Qt.alpha(Theme.warn, 0.2) : (abArea.containsMouse ? Qt.alpha(Theme.cream, 0.1) : Qt.alpha(Theme.cream, 0.05))
                                            scale: abArea.pressed ? 0.96 : 1
                                            Behavior on scale { NumberAnimation { duration: 100 } }
                                            GlyphIcon {
                                                anchors.centerIn: parent
                                                width: 14 * root.s
                                                height: width
                                                name: ab.modelData.icon
                                                color: ab.hot ? Theme.warn : (abArea.containsMouse ? Theme.bright : Theme.iconDim)
                                                stroke: 1.9
                                            }
                                            MouseArea {
                                                id: abArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (ab.modelData.act === "copy") {
                                                        Ai.copy(cl.modelData.cmd);
                                                    } else if (cl.confirming) {
                                                        root.confirmKey = "";
                                                        Storage.runInTerminal(cl.modelData.cmd);
                                                    } else {
                                                        root.confirmKey = cl.modelData.key;
                                                        confirmTimeout.restart();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Card {
            anchors.top: cleanCard.bottom
            anchors.topMargin: 14 * root.s
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            title: "Maiores arquivos"
            icon: "image"
            aside: Storage.bigFiles.length ? Storage.bigFiles.length + " acima de 300 MB" : ""

            Flickable {
                anchors.fill: parent
                contentHeight: bigCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: bigCol
                    width: parent.width
                    spacing: 3 * root.s
                    readonly property real maxSize: Storage.bigFiles.length ? Storage.bigFiles[0].size : 1

                    Repeater {
                        model: Storage.bigFiles
                        Rectangle {
                            id: bf
                            required property var modelData
                            readonly property string file: modelData.path.split("/").pop()
                            readonly property string dir: modelData.path.replace(/\/[^/]*$/, "").replace(/^\/home\/[^/]+/, "~")
                            width: bigCol.width
                            height: 40 * root.s
                            radius: root.innerR + 2 * root.s
                            color: bfArea.containsMouse ? Qt.alpha(Theme.cream, 0.045) : "transparent"
                            clip: true

                            // size bar behind the row
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: parent.width * bf.modelData.size / bigCol.maxSize
                                radius: parent.radius
                                color: Qt.alpha(root.linuxColor, 0.07)
                            }

                            Column {
                                anchors.left: parent.left
                                anchors.leftMargin: 10 * root.s
                                anchors.right: bfSize.left
                                anchors.rightMargin: 10 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2 * root.s
                                Text {
                                    width: parent.width
                                    elide: Text.ElideMiddle
                                    text: bf.file
                                    color: bfArea.containsMouse ? Theme.bright : Theme.cream
                                    font.family: Theme.font
                                    font.pixelSize: 11 * root.s
                                    font.weight: Font.Medium
                                }
                                Text {
                                    width: parent.width
                                    elide: Text.ElideMiddle
                                    text: bf.dir
                                    color: Theme.faint
                                    font.family: Theme.font
                                    font.pixelSize: 9.5 * root.s
                                }
                            }
                            Text {
                                id: bfSize
                                anchors.right: parent.right
                                anchors.rightMargin: 10 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                text: Storage.fmt(bf.modelData.size)
                                color: Theme.subtle
                                font.family: Theme.font
                                font.pixelSize: 11 * root.s
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                            }
                            MouseArea {
                                id: bfArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Storage.openFolder(bf.modelData.path.replace(/\/[^/]*$/, ""))
                            }
                        }
                    }
                }
            }
        }
    }
}
