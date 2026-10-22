pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Bridge to scripts/claude-agent.py, which hands a GitHub issue to a Claude
 * Code agent in tmux. `tmuxSessions` (refreshTmux) lists your sessions, each
 * { id, name, path, attached, activity, windows: [{ id, index, name }], dirs }
 * with `dirs` the folders its panes are in, active one first.
 *
 * sendIssue() types the issue into a running claude's pane; newAgent() opens
 * a window in a session/folder running a fresh claude on it; gotoTarget()
 * switches the tmux you are using to a window or pane. One action runs at a
 * time through `busy` ("send" / "new" / "goto"); each ends in done(kind,
 * result) or sets `error`.
 *
 * agents() lists the live Claude sessions (from the Claude singleton) that sit
 * in a tmux pane, minus background reviews, with their tmux place resolved:
 * { session (the Claude one), pane, window, tmuxSession, windowName }.
 */
Singleton {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.config/quickshell/pill/scripts/claude-agent.py"
    property var tmuxSessions: []
    property bool tmuxLoaded: false
    property string busy: ""
    property string error: ""
    signal done(string kind, var result)

    function refreshTmux() {
        if (!tmuxProc.running)
            tmuxProc.running = true;
    }

    function windowName(windowId) {
        for (var i = 0; i < tmuxSessions.length; i++) {
            var w = tmuxSessions[i].windows.find(function(x) { return x.id === windowId; });
            if (w)
                return w.index + ":" + w.name;
        }
        return "";
    }

    /** Claude sessions living in a tmux pane, background reviews left out. */
    function agents() {
        var out = [];
        Claude.sessions.forEach(function(x) {
            // "session:@window.%pane"; session names cannot hold ":" or ".".
            var m = /^(.*):(@\d+)\.(%\d+)$/.exec(x.tmux || "");
            if (m && m[1] === GitHub.claudeSession)
                return;
            out.push({
                session: x,
                tmuxSession: m ? m[1] : "",
                window: m ? m[2] : "",
                pane: m ? m[3] : "",
                windowName: m ? root.windowName(m[2]) : ""
            });
        });
        return out;
    }

    function sendIssue(pane, pid, url, title) {
        act("send", ["send", pane, String(pid), url, title || ""]);
    }

    function newAgent(session, dir, name, account, model, effort, url, title) {
        act("new", ["new", session, dir, name, account, model, effort, url, title || ""]);
    }

    function gotoTarget(target) {
        act("goto", ["goto", target]);
    }

    function act(kind, args) {
        if (actProc.running)
            return;
        busy = kind;
        error = "";
        actProc.kind = kind;
        actProc.command = ["python3", "-I", script].concat(args);
        actProc.running = true;
    }

    Process {
        id: tmuxProc
        command: ["python3", "-I", root.script, "tmux"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    if (d.ok) {
                        root.tmuxSessions = d.sessions;
                        root.tmuxLoaded = true;
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: actProc
        property string kind: ""
        stdout: StdioCollector {
            onStreamFinished: {
                var d = {};
                try {
                    d = JSON.parse(this.text);
                } catch (e) {
                    d = { ok: false, error: "resposta inválida" };
                }
                var kind = actProc.kind;
                root.busy = "";
                if (!d.ok) {
                    root.error = d.error || "erro";
                    return;
                }
                if (kind === "new")
                    root.refreshTmux();
                root.done(kind, d);
            }
        }
    }
}
