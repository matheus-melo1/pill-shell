pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Storage data for the drawer's Armazenamento route, from
 * scripts/storage-scan.py (read-only). refresh() reloads the disk map, the
 * root-filesystem tree, the cleanup suggestions and the largest files; the
 * cached tree is shown first so the route opens instantly. subScan(path)
 * fetches a deeper tree for a folder beyond the root scan's depth into
 * `subtrees`. Cleanup commands never run here: runInTerminal() opens them in
 * a kitty window so they are seen (and sudo asked) before anything is freed.
 */
Singleton {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.config/quickshell/pill/scripts/storage-scan.py"

    property var disks: []
    property var rootFs: null
    property var tree: null
    property real fsUsed: 0
    property real scannedAt: 0
    property var cleanup: []
    property real cleanupTotal: 0
    property var bigFiles: []
    property var subtrees: ({})
    property string subScanning: ""
    readonly property bool scanning: scanProc.running || disksProc.running
    readonly property bool busy: scanning || cleanupProc.running || bigProc.running

    function refresh() {
        if (!tree && !cachedProc.running)
            cachedProc.running = true;
        if (!disksProc.running)
            disksProc.running = true;
        if (!scanProc.running)
            scanProc.running = true;
        if (!cleanupProc.running)
            cleanupProc.running = true;
        if (!bigProc.running)
            bigProc.running = true;
    }

    /** Refresh when the data is missing or older than `maxAgeMs`. */
    function refreshIfStale(maxAgeMs) {
        if (!scannedAt || Date.now() - scannedAt > maxAgeMs)
            refresh();
        else if (!disksProc.running)
            disksProc.running = true;
    }

    function subScan(path) {
        if (subProc.running || subtrees[path])
            return;
        subScanning = path;
        subProc.target = path;
        subProc.running = true;
    }

    function runInTerminal(cmd) {
        Quickshell.execDetached(["kitty", "--title", "Limpeza", "--hold", "sh", "-c",
            "echo '$ " + cmd.replace(/'/g, "'\\''") + "'; echo; " + cmd + "; echo; echo '— pronto, pode fechar esta janela —'"]);
    }

    function openFolder(path) {
        Quickshell.execDetached(["xdg-open", path]);
    }

    /** "4,5 GB" style size. */
    function fmt(b) {
        var u = ["B", "KB", "MB", "GB", "TB"];
        var i = 0;
        b = Number(b) || 0;
        while (b >= 1000 && i < u.length - 1) {
            b /= 1024;
            i++;
        }
        var v = i === 0 ? Math.round(b) : (b < 10 ? b.toFixed(1) : Math.round(b));
        return String(v).replace(".", ",") + " " + u[i];
    }

    component JsonProc: Process {
        id: jp
        signal json(var d)
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    if (d.ok)
                        jp.json(d);
                } catch (e) {
                }
            }
        }
    }

    JsonProc {
        id: disksProc
        command: ["python3", "-I", root.script, "disks"]
        onJson: (d) => {
            root.disks = d.disks;
            root.rootFs = d.root;
        }
    }

    JsonProc {
        id: cachedProc
        command: ["python3", "-I", root.script, "scan", "/", "--cached"]
        onJson: (d) => {
            if (!scanProc.running || !root.tree) {
                root.tree = d.tree;
                root.fsUsed = d.fsUsed;
                root.scannedAt = d.scannedAt;
            }
        }
    }

    JsonProc {
        id: scanProc
        command: ["python3", "-I", root.script, "scan", "/"]
        onJson: (d) => {
            root.tree = d.tree;
            root.fsUsed = d.fsUsed;
            root.scannedAt = d.scannedAt;
            root.subtrees = ({});
        }
    }

    JsonProc {
        id: subProc
        property string target: ""
        command: ["python3", "-I", root.script, "scan", target]
        onJson: (d) => {
            var m = Object.assign({}, root.subtrees);
            m[d.path] = d.tree;
            root.subtrees = m;
        }
        onExited: root.subScanning = ""
    }

    JsonProc {
        id: cleanupProc
        command: ["python3", "-I", root.script, "cleanup"]
        onJson: (d) => {
            root.cleanup = d.items;
            root.cleanupTotal = d.total;
        }
    }

    JsonProc {
        id: bigProc
        command: ["python3", "-I", root.script, "big"]
        onJson: (d) => root.bigFiles = d.files
    }
}
