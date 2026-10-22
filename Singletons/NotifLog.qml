pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Persistent notification history. Every notification the server receives is
 * appended here on arrival (Do-Not-Disturb included, and regardless of how it
 * is later dismissed) and kept in a JSON file under the state dir, so the
 * history survives quickshell restarts. Entries are plain objects, newest
 * first: { id, nid, app, summary, body, icon, image, desktopEntry, urgency,
 * ts }. `nid` + `ts` let a view match an entry to a still-live notification.
 * Retention is `maxEntries` and `maxAgeDays`, pruned on load and on every add;
 * writes are debounced so a burst costs one file write.
 */
Singleton {
    id: root

    readonly property int maxEntries: 500
    readonly property int maxAgeDays: 14

    readonly property var entries: adapter.entries
    readonly property int count: entries.length

    /** Apps with their entry counts, most frequent first. */
    readonly property var apps: {
        var map = {};
        var out = [];
        for (var i = 0; i < entries.length; i++) {
            var e = entries[i];
            if (map[e.app] === undefined) {
                map[e.app] = { app: e.app, count: 0, icon: e.icon };
                out.push(map[e.app]);
            }
            map[e.app].count++;
        }
        out.sort(function(a, b) { return b.count - a.count; });
        return out;
    }

    /**
     * Phone notifications mirrored by KDE Connect (and the daemon's own) belong
     * to the phone route and are personal, so they are never written to disk;
     * prune also drops any that older versions stored. Takes a live
     * notification or a stored entry.
     */
    function isPhone(n) {
        return String(n.desktopEntry || "") === "org.kde.kdeconnect.daemon";
    }

    function prune(list) {
        var cutoff = Date.now() - root.maxAgeDays * 86400000;
        return list.filter(function(e) {
            return e.ts >= cutoff && !root.isPhone(e);
        }).slice(0, root.maxEntries);
    }

    function add(n, icon, ts) {
        if (root.isPhone(n))
            return;
        var img = String(n.image || "");
        var entry = {
            id: ts + "-" + n.id,
            nid: n.id,
            app: (n.appName && n.appName.length) ? n.appName : "System",
            summary: String(n.summary || ""),
            body: String(n.body || ""),
            icon: icon && String(icon).indexOf("image://qsimage") !== 0 ? String(icon) : "",
            image: img.indexOf("/") === 0 || img.indexOf("file://") === 0 ? img : "",
            desktopEntry: String(n.desktopEntry || ""),
            urgency: n.urgency,
            ts: ts
        };
        adapter.entries = root.prune([entry].concat(adapter.entries));
        save.restart();
    }

    function remove(id) {
        adapter.entries = adapter.entries.filter(function(e) { return e.id !== id; });
        save.restart();
    }

    function clearApp(app) {
        adapter.entries = adapter.entries.filter(function(e) { return e.app !== app; });
        save.restart();
    }

    function clear() {
        adapter.entries = [];
        save.restart();
    }

    Timer {
        id: save
        interval: 600
        onTriggered: file.writeAdapter()
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ricelin/notif-history.json"
        blockLoading: true
        printErrors: false

        JsonAdapter {
            id: adapter
            property var entries: []
        }
    }

    Component.onCompleted: {
        var kept = root.prune(adapter.entries || []);
        if (!file.loaded || kept.length !== (adapter.entries || []).length) {
            adapter.entries = kept;
            file.writeAdapter();
        }
    }
}
