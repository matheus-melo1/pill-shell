pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * KDE Connect bridge for the drawer's phone route and the hover pill's phone
 * battery. Polls scripts/phone.py status every 60s, or every 3s while
 * `watching` is set by the open view: device presence/reachability, battery,
 * cellular network and signal (0-4), the privacy switch and the phone's
 * active notifications ({ id, key, app, title, text, icon, dismissable,
 * canReply }). `seenAt` keeps when each notification (by its stable `key`)
 * first showed up, since KDE Connect carries no timestamp.
 *
 * Actions run one at a time through `busy`: dismiss() drops the card
 * optimistically, reply() sends an inline reply, ring() makes the phone ring,
 * sendClipboard() pushes the clipboard, shareFile() opens a kdialog picker.
 * setPrivacy(true) disables the PC-side notifications plugin in kdeconnectd,
 * so phone notifications stop reaching the desktop at all (no toast, no
 * history); the state lives in kdeconnectd and survives a shell restart.
 * Failures land in `error` for a few seconds.
 */
Singleton {
    id: root

    property bool ready: false
    property bool present: false
    property bool reachable: false
    property string name: ""
    property int battery: -1
    property bool charging: false
    property string network: ""
    property int signal: -1
    property bool privacy: false
    property var notifications: []
    property var seenAt: ({})

    property bool watching: false
    property string pending: ""
    property string error: ""
    readonly property bool busy: action.running
    readonly property bool online: present && reachable

    readonly property string script: Quickshell.env("HOME") + "/.config/quickshell/pill/scripts/phone.py"

    function refresh() {
        if (!proc.running)
            proc.running = true;
    }

    function run(kind, args) {
        if (action.running)
            return false;
        pending = kind;
        error = "";
        action.command = ["python3", "-I", root.script].concat(args);
        action.running = true;
        return true;
    }

    function dismiss(id) {
        if (run("dismiss", ["dismiss", id]))
            root.notifications = root.notifications.filter(function(n) { return n.id !== id; });
    }

    function reply(id, text) {
        if (text.trim().length > 0)
            run("reply", ["reply", id, text.trim()]);
    }

    function ring() { run("ring", ["ring"]); }
    function sendClipboard() { run("clipboard", ["clipboard"]); }
    function shareFile() { run("share", ["share-pick"]); }

    function setPrivacy(on) {
        if (run(on ? "privacy-on" : "privacy-off", ["privacy", on ? "on" : "off"]))
            root.privacy = on;
    }

    Timer {
        interval: root.watching ? 3000 : 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        id: errorClear
        interval: 5000
        onTriggered: root.error = ""
    }

    // The phone resends its notifications a moment after the plugin reloads.
    Timer {
        id: resync
        interval: 2500
        onTriggered: root.refresh()
    }

    Process {
        id: action
        stdout: StdioCollector {
            onStreamFinished: {
                var d;
                try {
                    d = JSON.parse(this.text);
                } catch (e) {
                    d = { ok: false, error: "Resposta inválida" };
                }
                if (!d.ok) {
                    root.error = d.error || "Falhou";
                    errorClear.restart();
                }
                if (root.pending === "privacy-off")
                    resync.restart();
                root.pending = "";
                root.refresh();
            }
        }
    }

    Process {
        id: proc
        command: ["python3", "-I", root.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                var d;
                try {
                    d = JSON.parse(this.text);
                } catch (e) {
                    return;
                }
                if (!d.ok)
                    return;
                root.present = d.present;
                root.reachable = !!d.reachable;
                root.name = d.name || "";
                root.battery = d.battery === undefined ? -1 : d.battery;
                root.charging = !!d.charging;
                root.network = d.network || "";
                root.signal = d.signal === undefined ? -1 : d.signal;
                if (!action.running)
                    root.privacy = !!d.privacy;

                var list = d.notifications || [];
                var now = Date.now();
                var seen = {};
                for (var i = 0; i < list.length; i++) {
                    var k = list[i].key;
                    seen[k] = root.seenAt[k] || now;
                    list[i].ts = seen[k];
                }
                list.sort(function(a, b) { return b.ts - a.ts; });
                root.seenAt = seen;
                root.notifications = list;
                root.ready = true;
            }
        }
    }
}
