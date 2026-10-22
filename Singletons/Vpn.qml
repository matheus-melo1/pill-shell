pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * OpenVPN bridge for the drawer's VPN route. Polls scripts/vpn-status.py
 * (unit state, boot enablement, exit interface, tunnel address, traffic
 * counters, server, one ping) every 15s, or every 2s while `watching` is set
 * by an open view or an action is settling. Down/up rates come from counter
 * deltas between polls.
 *
 * setOn()/setBoot() call systemctl without sudo, so polkit-gnome asks for the
 * password; `authPending` is true while that call is in flight so the drawer
 * can step aside for the dialog. A non-zero exit (cancelled or wrong password)
 * lands in `error` for a few seconds.
 */
Singleton {
    id: root

    readonly property string unit: "openvpn-client@cliente"

    property bool ready: false
    property bool active: false
    property string state: ""
    property bool enabled: false
    property string dev: ""
    property bool tunneled: false
    property string tunIp: ""
    property string server: ""
    property real since: 0
    property var latency: null
    property real rx: 0
    property real tx: 0
    property real rxRate: 0
    property real txRate: 0
    property real lastPoll: 0

    property bool watching: false
    property string pending: ""
    property string error: ""
    readonly property bool authPending: action.running
    readonly property bool transitioning: pending.length > 0 || state === "activating" || state === "deactivating"

    function refresh() {
        if (!proc.running)
            proc.running = true;
    }

    function setOn(on) {
        if (action.running)
            return;
        pending = on ? "on" : "off";
        error = "";
        action.command = ["systemctl", on ? "start" : "stop", root.unit];
        action.running = true;
    }

    function setBoot(on) {
        if (action.running)
            return;
        pending = on ? "boot-on" : "boot-off";
        error = "";
        action.command = ["systemctl", on ? "enable" : "disable", root.unit];
        action.running = true;
    }

    /** "1,2 GB" style byte count. */
    function bytes(n) {
        var u = ["B", "KB", "MB", "GB", "TB"];
        var i = 0;
        while (n >= 1024 && i < u.length - 1) {
            n /= 1024;
            i++;
        }
        return (i === 0 ? Math.round(n) : n.toFixed(n < 10 ? 1 : 0)) + " " + u[i];
    }

    Timer {
        interval: root.watching || root.transitioning ? 2000 : 15000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        id: settle
        interval: 12000
        onTriggered: root.pending = ""
    }

    Timer {
        id: errorClear
        interval: 5000
        onTriggered: root.error = ""
    }

    Process {
        id: action
        onExited: (code) => {
            if (code !== 0) {
                root.pending = "";
                root.error = "Cancelado ou sem permissão";
                errorClear.restart();
            } else {
                settle.restart();
            }
            root.refresh();
        }
    }

    Process {
        id: proc
        command: ["python3", "-I", Quickshell.env("HOME") + "/.config/quickshell/pill/scripts/vpn-status.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                var d;
                try {
                    d = JSON.parse(this.text);
                } catch (e) {
                    return;
                }
                var t = Date.now();
                if (root.lastPoll > 0 && d.rx >= root.rx && d.tx >= root.tx) {
                    var dt = (t - root.lastPoll) / 1000;
                    root.rxRate = (d.rx - root.rx) / dt;
                    root.txRate = (d.tx - root.tx) / dt;
                } else {
                    root.rxRate = 0;
                    root.txRate = 0;
                }
                root.lastPoll = t;
                root.active = d.active;
                root.state = d.state;
                root.enabled = d.enabled;
                root.dev = d.dev;
                root.tunneled = d.tunneled;
                root.tunIp = d.tunIp;
                root.server = d.server;
                root.since = d.since;
                root.latency = d.latency;
                root.rx = d.rx;
                root.tx = d.tx;
                root.ready = true;

                // An action has settled once the unit reaches the asked-for state.
                if ((root.pending === "on" && d.active && d.tunneled)
                        || (root.pending === "off" && !d.active)
                        || (root.pending === "boot-on" && d.enabled)
                        || (root.pending === "boot-off" && !d.enabled))
                    root.pending = "";
            }
        }
    }
}
