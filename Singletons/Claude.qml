pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Claude Code bridge: polls scripts/claude-status.py every few seconds for the
 * live CLI sessions of each account (personal/work config dirs) and their 5h /
 * 7d usage limits. The script caches the usage API itself, so the poll here is
 * cheap. `sessions` arrive busy-first; each is { account, pid, name, cwd,
 * status, startedAt, statusSince, tmux }. `accounts` is one entry per config
 * dir: { name, five, fiveReset, seven, sevenReset, stale } with utilization in
 * percent (null when unknown). `peakFive` is the highest 5h usage across
 * accounts, which is what the rest pill shows. `models` / `efforts` are the
 * CLI choices the GitHub popovers offer when launching a claude.
 */
Singleton {
    id: root

    property var sessions: []
    property var accounts: []

    readonly property int total: sessions.length
    readonly property int busyCount: sessions.filter(function(x) { return x.status === "busy"; }).length
    readonly property bool busy: busyCount > 0

    readonly property var peakAccount: {
        var best = null;
        for (var i = 0; i < accounts.length; i++) {
            var a = accounts[i];
            if (a.five !== null && a.five !== undefined && (best === null || a.five > best.five))
                best = a;
        }
        return best;
    }
    readonly property int peakFive: peakAccount ? Math.round(peakAccount.five) : -1
    readonly property bool hot: peakFive >= 80

    readonly property var models: [
        { key: "opus", text: "Opus", sub: "Mais profundo" },
        { key: "sonnet", text: "Sonnet", sub: "Equilibrado" },
        { key: "haiku", text: "Haiku", sub: "Rápido e leve" },
        { key: "fable", text: "Fable", sub: "Fable 5.1" }
    ]
    readonly property var efforts: ["low", "medium", "high", "xhigh", "max"].map(function(e) { return { key: e, text: e }; })

    function modelName(key) {
        return (models.find(function(m) { return m.key === key; }) || { text: key }).text;
    }

    readonly property string script: Quickshell.env("HOME") + "/.config/quickshell/pill/scripts/claude-status.py"

    /**
     * "2h13m" / "13m" / "3d4h" until an ISO timestamp; empty when unknown or
     * past. `now` is passed in so callers re-evaluate on their own clock.
     */
    function until(iso, now) {
        if (!iso)
            return "";
        var sec = Math.round((Date.parse(iso) - now) / 1000);
        if (!(sec > 0))
            return "";
        var d = Math.floor(sec / 86400);
        var h = Math.floor((sec % 86400) / 3600);
        var m = Math.floor((sec % 3600) / 60);
        if (d > 0)
            return d + "d" + (h > 0 ? h + "h" : "");
        if (h > 0)
            return h + "h" + (m < 10 ? "0" : "") + m + "m";
        return Math.max(1, m) + "m";
    }

    /** "45m" / "3h" / "2d" since an epoch-ms timestamp. */
    function since(ms, now) {
        var sec = Math.max(0, Math.round((now - ms) / 1000));
        if (sec < 3600)
            return Math.max(1, Math.floor(sec / 60)) + "m";
        if (sec < 86400)
            return Math.floor(sec / 3600) + "h";
        return Math.floor(sec / 86400) + "d";
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!proc.running) proc.running = true
    }

    Process {
        id: proc
        command: ["python3", "-I", root.script]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    root.sessions = d.sessions || [];
                    root.accounts = d.accounts || [];
                } catch (e) {
                }
            }
        }
    }
}
