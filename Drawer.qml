import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "Singletons"

/**
 * Right-edge drawer for one monitor. A full-screen transparent Overlay layer
 * that stays mapped for the session (mapping it on demand would trigger the
 * compositor's own layersIn slide, from the top), holding a floating card that slides in from the right edge with the pill's
 * morph curve, over a faint backdrop. While closed the input mask is empty so
 * every click reaches the windows below; while open the whole layer takes
 * input, a backdrop press or Escape closes, and keyboard focus is exclusive.
 *
 * The card is a vertical nav rail plus a content area. Each entry of `routes`
 * is one integration view; `route` (driven by shell.qml) picks which is shown
 * and the rail asks for another through requestRoute(). Adding an integration
 * is one entry in `routes` and one view in the content area.
 *
 * While Vpn.authPending (polkit is asking for a password) the drawer steps
 * aside: the backdrop clears, input shrinks to the card and keyboard focus is
 * released, so the system dialog can be reached.
 */
PanelWindow {
    id: drawer

    required property var modelData
    property bool open: false
    property string route: "github"
    readonly property real s: modelData ? modelData.height / 1080 : 1
    readonly property real gap: 10 * s
    readonly property real railW: 66 * s
    // Some routes grow the card leftwards: GitHub to show an issue/PR beside
    // the board, Armazenamento for its two-column dashboard.
    readonly property real detailW: 560 * s
    readonly property real storageW: 520 * s
    // Depends on the route only, never on `open`: shrinking while sliding out
    // made the dashboard relayout every frame. While hidden it snaps.
    property real extraW: route === "storage" ? storageW
        : (route === "github" && GitHub.detailOpen ? detailW : 0)
    Behavior on extraW {
        enabled: drawer.slide > 0.01
        NumberAnimation { duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve }
    }
    readonly property real cardW: 580 * s + railW + extraW
    readonly property bool yielding: open && Vpn.authPending
    // Slid away (but still "open") while the AI chat captures a screen region.
    readonly property bool shown: open && !Ai.capturing

    readonly property var routes: [
        { key: "github", label: "GitHub", icon: "github" },
        { key: "vpn", label: "VPN", icon: "shield" },
        { key: "notifs", label: "Notifs", icon: "inbox" },
        { key: "todo", label: "Tarefas", icon: "checklist" },
        { key: "storage", label: "Disco", icon: "drive" },
        { key: "phone", label: "Celular", icon: "phone" },
        { key: "ai", label: "Chat", icon: "chat" }
    ]

    /** Live status dot for a rail entry; transparent hides it. */
    function routeTint(key) {
        switch (key) {
        case "github":
            return GitHub.ciFailing ? Theme.danger : (GitHub.reviewCount > 0 ? Theme.claude : "transparent");
        case "vpn":
            return Vpn.transitioning ? Theme.warn : (Vpn.active ? Theme.ok : "transparent");
        case "notifs":
            return Notifs.unread > 0 ? Theme.info : "transparent";
        case "phone":
            return Phone.online && Phone.privacy ? Theme.warn : "transparent";
        case "ai":
            return Ai.streaming ? Theme.info : "transparent";
        default:
            return "transparent";
        }
    }

    signal requestClose()
    signal requestRoute(string name)

    /** Slide progress, 0 parked off-screen and 1 fully in. */
    property real slide: shown ? 1 : 0
    Behavior on slide {
        NumberAnimation {
            duration: Motion.morph
            easing.type: Motion.easeMorph
            easing.bezierCurve: Motion.morphCurve
        }
    }

    screen: modelData
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown && !yielding ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "pill-drawer"

    anchors { top: true; bottom: true; left: true; right: true }

    mask: !shown ? emptyRegion : (yielding ? cardRegion : fullRegion)
    Region { id: emptyRegion }
    Region { id: cardRegion; item: card }
    Region {
        id: fullRegion
        width: drawer.width
        height: drawer.height
    }

    Rectangle {
        anchors.fill: parent
        visible: drawer.slide > 0.001
        color: Qt.rgba(0, 0, 0, (drawer.yielding ? 0 : 0.22) * drawer.slide)
        Behavior on color { ColorAnimation { duration: Motion.standard } }
    }

    MouseArea {
        anchors.fill: parent
        enabled: drawer.open
        acceptedButtons: Qt.AllButtons
        onPressed: drawer.requestClose()
    }

    FocusScope {
        id: focusScope
        anchors.fill: parent
        focus: drawer.open
        Keys.onEscapePressed: {
            if (drawer.route === "github" && gh.popOpen)
                gh.closePop();
            else if (drawer.route === "github" && prDetail.popOpen)
                prDetail.closePop();
            else if (drawer.route === "github" && issueDetail.popOpen)
                issueDetail.closePop();
            else if (drawer.route === "github" && GitHub.detailOpen)
                GitHub.closeDetail();
            else
                drawer.requestClose();
        }

        Rectangle {
            id: card
            visible: drawer.slide > 0.001
            width: drawer.cardW
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: drawer.gap
            anchors.bottomMargin: drawer.gap
            x: parent.width + drawer.gap - (width + 2 * drawer.gap) * drawer.slide
            radius: 22 * drawer.s
            border.width: 1
            border.color: Theme.border
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.cardTop }
                GradientStop { position: 1.0; color: Theme.cardBot }
            }

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, Theme.shadowOpacity)
                shadowBlur: 0.8
                shadowHorizontalOffset: -3 * drawer.s
            }

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 1
                anchors.leftMargin: card.radius * 0.6
                anchors.rightMargin: card.radius * 0.6
                height: 1
                color: Theme.sheen
            }

            // Swallow presses on the card so they don't reach the backdrop.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }

            // nav rail
            Item {
                id: rail
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                width: drawer.railW

                Column {
                    anchors.top: parent.top
                    anchors.topMargin: 18 * drawer.s
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6 * drawer.s

                    Repeater {
                        model: drawer.routes

                        Item {
                            id: navItem
                            required property var modelData
                            readonly property bool selected: drawer.route === modelData.key
                            width: 50 * drawer.s
                            height: 54 * drawer.s

                            Rectangle {
                                anchors.fill: parent
                                radius: 14 * drawer.s
                                color: navItem.selected ? Theme.frameBg
                                    : (navArea.containsMouse ? Qt.alpha(Theme.frameBg, 0.5) : "transparent")
                                border.width: 1
                                border.color: navItem.selected ? Theme.frameBorder : "transparent"
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.leftMargin: -8 * drawer.s
                                anchors.verticalCenter: parent.verticalCenter
                                width: 3 * drawer.s
                                height: navItem.selected ? 22 * drawer.s : 0
                                radius: width / 2
                                color: Theme.cream
                                Behavior on height { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 5 * drawer.s

                                Item {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 19 * drawer.s
                                    height: 19 * drawer.s

                                    GlyphIcon {
                                        anchors.fill: parent
                                        name: navItem.modelData.icon === "shield" && Vpn.active ? "shieldCheck" : navItem.modelData.icon
                                        color: navItem.selected || navArea.containsMouse ? Theme.cream : Theme.iconDim
                                        stroke: 1.7
                                    }

                                    // live status dot per route
                                    Rectangle {
                                        readonly property color tint: drawer.routeTint(navItem.modelData.key)
                                        visible: tint.a > 0
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.rightMargin: -3 * drawer.s
                                        anchors.topMargin: -2 * drawer.s
                                        width: 7 * drawer.s
                                        height: width
                                        radius: width / 2
                                        color: tint
                                        border.width: 1.5 * drawer.s
                                        border.color: Theme.cardTop
                                    }
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: navItem.modelData.label
                                    color: navItem.selected ? Theme.cream : Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: 8 * drawer.s
                                    font.weight: Font.Bold
                                    font.capitalization: Font.AllUppercase
                                    font.letterSpacing: 0.6 * drawer.s
                                }
                            }

                            MouseArea {
                                id: navArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: drawer.requestRoute(navItem.modelData.key)
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: 18 * drawer.s
                    anchors.bottomMargin: 18 * drawer.s
                    width: 1
                    color: Theme.hair
                }
            }

            // content
            Item {
                id: pane
                clip: true
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: rail.right
                anchors.right: parent.right

                GitHubSurface {
                    id: gh
                    anchors.topMargin: 22 * drawer.s
                    anchors.leftMargin: 22 * drawer.s
                    anchors.rightMargin: 22 * drawer.s + drawer.extraW
                    anchors.bottomMargin: 18 * drawer.s
                    s: drawer.s
                    open: drawer.open && drawer.route === "github"
                    morphCloseness: 1
                    maxBody: height - 116 * drawer.s
                    onRequestClose: drawer.requestClose()
                }

                IssueDetail {
                    id: issueDetail
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    width: drawer.extraW
                    visible: width > 1 && drawer.route === "github" && GitHub.detailKind === "issue"
                    s: drawer.s
                    paneW: drawer.detailW
                    onRequestClose: GitHub.closeDetail()
                }

                PrDetail {
                    id: prDetail
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    width: drawer.extraW
                    visible: width > 1 && drawer.route === "github" && GitHub.detailKind === "pr"
                    s: drawer.s
                    paneW: drawer.detailW
                    onRequestClose: GitHub.closeDetail()
                }

                // Laid out at its final width and pinned right, so the card's
                // width animation clips it instead of relayouting the treemap.
                StorageView {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    anchors.topMargin: 22 * drawer.s
                    anchors.rightMargin: 22 * drawer.s
                    anchors.bottomMargin: 18 * drawer.s
                    width: 580 * drawer.s + drawer.storageW - 44 * drawer.s
                    s: drawer.s
                    open: drawer.open && drawer.route === "storage"
                }

                TodoView {
                    anchors.fill: parent
                    anchors.topMargin: 22 * drawer.s
                    anchors.leftMargin: 22 * drawer.s
                    anchors.rightMargin: 22 * drawer.s
                    anchors.bottomMargin: 18 * drawer.s
                    s: drawer.s
                    open: drawer.open && drawer.route === "todo"
                }

                AiView {
                    anchors.fill: parent
                    anchors.topMargin: 20 * drawer.s
                    anchors.leftMargin: 20 * drawer.s
                    anchors.rightMargin: 20 * drawer.s
                    anchors.bottomMargin: 16 * drawer.s
                    s: drawer.s
                    open: drawer.open && drawer.route === "ai"
                }

                NotificationsView {
                    anchors.fill: parent
                    anchors.topMargin: 22 * drawer.s
                    anchors.leftMargin: 22 * drawer.s
                    anchors.rightMargin: 22 * drawer.s
                    anchors.bottomMargin: 18 * drawer.s
                    s: drawer.s
                    open: drawer.open && drawer.route === "notifs"
                    onRequestClose: drawer.requestClose()
                }

                VpnView {
                    anchors.fill: parent
                    anchors.topMargin: 22 * drawer.s
                    anchors.leftMargin: 22 * drawer.s
                    anchors.rightMargin: 22 * drawer.s
                    anchors.bottomMargin: 18 * drawer.s
                    s: drawer.s
                    open: drawer.open && drawer.route === "vpn"
                }

                PhoneView {
                    anchors.fill: parent
                    anchors.topMargin: 22 * drawer.s
                    anchors.leftMargin: 22 * drawer.s
                    anchors.rightMargin: 22 * drawer.s
                    anchors.bottomMargin: 18 * drawer.s
                    s: drawer.s
                    open: drawer.open && drawer.route === "phone"
                    onRequestClose: drawer.requestClose()
                }
            }
        }
    }

    onShownChanged: if (shown) focusScope.forceActiveFocus()
    // Drop an open issue/PR only after the card has slid away, so the width
    // doesn't animate during the exit.
    onOpenChanged: if (!open && GitHub.detailOpen) closeDetailLater.restart()
    Timer {
        id: closeDetailLater
        interval: Motion.morph + 50
        onTriggered: if (!drawer.open) GitHub.closeDetail()
    }
}
