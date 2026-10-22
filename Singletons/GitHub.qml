pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * GitHub bridge: polls scripts/github-status.py (which talks through the
 * logged-in `gh` CLI) once a minute, and on demand via refresh() when the
 * surface opens. `reviews` are open PRs waiting on the viewer's review,
 * `mine` the viewer's own open PRs with review/mergeable/CI state, `issues`
 * the board issues assigned to the viewer in Ready / In Progress (status,
 * priority, kind, estimate), `runs` the
 * Actions runs queued, running or finished in the last minutes in recently
 * touched repos. A failed fetch keeps the last snapshot and sets `error`.
 * `ciFailing` / `ciRunning` summarise the viewer's PRs and runs for the rest
 * pill dot.
 *
 * Issue detail (scripts/github-issue.py): openIssue(url) loads `detail` (body,
 * comments, sub-issues, linked PRs, board item and field options) and
 * openPr(url) loads a PR (checks, reviews, files, closing issues, merge
 * methods); `detailKind` says which. Edits
 * (setField, comment, setBlocked, close/reopen) run one at a time through
 * `busy`, apply optimistically where it is safe, then reload the detail and
 * the list. `transitions` is the team board's Kanban flow, used to flag moves
 * outside it.
 *
 * Background Claude reviews (scripts/claude-review.py): startClaudeReview()
 * launches an interactive `claude` reviewing a PR in its own window of the
 * tmux session `claudeSession`; it gets the PR link in its prompt and reads
 * the diff straight from GitHub (nothing is cloned). `claudeReviews` mirrors
 * those windows (polled while any exist); claudeReviewFor(url) adds `state`
 * from the live Claude session in that window: starting / busy / idle (done,
 * waiting at the prompt) / dead.
 * `claudePrefs` remembers the last model, effort and output choice.
 * attachClaudeReview() opens no terminal: it switches the tmux client you are
 * using to the review's window and focuses its terminal, emitting
 * claudeAttached on success; failures land in claudeError like launches.
 * clearClaudeReviews() closes every review window at once.
 */
Singleton {
    id: root

    property bool ready: false
    property string error: ""
    property string login: ""
    property string avatar: ""
    property string boardUrl: ""
    property var issues: []
    property int reviewCount: 0
    property var reviews: []
    property var mine: []
    property var runs: []

    readonly property var activeStates: ["queued", "in_progress", "waiting", "requested", "pending"]

    readonly property var inProgress: issues.filter(function(i) { return i.status === "In Progress"; })
    readonly property var readyIssues: issues.filter(function(i) { return i.status === "Ready"; })

    readonly property int runningCount: runs.filter(function(r) { return root.activeStates.indexOf(r.status) >= 0; }).length
    readonly property bool ciRunning: runningCount > 0
        || mine.some(function(p) { return p.ci === "PENDING" || p.ci === "EXPECTED"; })
    readonly property bool ciFailing: mine.some(function(p) { return p.ci === "FAILURE" || p.ci === "ERROR"; })
        || runs.some(function(r) { return r.conclusion === "failure" && root.activeStates.indexOf(r.status) < 0; })

    readonly property string script: Quickshell.env("HOME") + "/.config/quickshell/pill/scripts/github-status.py"

    // ---- issue detail ----
    readonly property string issueScript: Quickshell.env("HOME") + "/.config/quickshell/pill/scripts/github-issue.py"
    readonly property var statusFlow: ["Backlog", "Refinement", "Ready", "In Progress", "In Review", "QA", "Done"]
    readonly property var transitions: ({
        "Backlog": ["Refinement", "Ready"],
        "Refinement": ["Ready", "Backlog"],
        "Ready": ["In Progress"],
        "In Progress": ["In Review", "Backlog", "Refinement"],
        "In Review": ["QA", "In Progress"],
        "QA": ["Done", "In Progress"],
        "Done": []
    })

    property string detailUrl: ""
    property string detailKind: "issue"
    property var detail: null
    property bool detailLoading: false
    property string detailError: ""
    property string busy: ""
    property string actionError: ""
    readonly property bool detailOpen: detailUrl.length > 0
    property var actionQueue: []

    function field(name) {
        return detail && detail.item ? detail.item.fields[name] : undefined;
    }

    function inFlow(from, to) {
        return (transitions[from] || []).indexOf(to) >= 0;
    }

    function openIssue(url) {
        openDetail(url, "issue");
    }

    function openPr(url) {
        openDetail(url, "pr");
    }

    function openDetail(url, kind) {
        if (detailUrl === url && detail)
            return;
        // Clear first: switching the kind while the old detail is still set
        // would hand an issue object to the PR pane (or vice versa).
        detail = null;
        detailKind = kind;
        detailUrl = url;
        detailError = "";
        actionError = "";
        loadDetail();
    }

    function closeDetail() {
        detailUrl = "";
        detail = null;
        detailError = "";
        actionError = "";
    }

    function loadDetail() {
        if (!detailUrl.length)
            return;
        detailLoading = true;
        detailProc.url = detailUrl;
        detailProc.cmd = detailKind === "pr" ? "pr-detail" : "detail";
        detailProc.running = false;
        detailProc.running = true;
    }

    function patchField(name, value) {
        if (!detail || !detail.item)
            return;
        var d = Object.assign({}, detail);
        d.item = { id: detail.item.id, fields: Object.assign({}, detail.item.fields) };
        d.item.fields[name] = value;
        detail = d;
    }

    function run(label, args, stdin) {
        actionQueue = actionQueue.concat([{ label: label, args: args, stdin: stdin || "" }]);
        pump();
    }

    function pump() {
        if (actionProc.running || !actionQueue.length)
            return;
        var a = actionQueue[0];
        actionQueue = actionQueue.slice(1);
        busy = a.label;
        actionError = "";
        actionProc.payload = a.stdin;
        actionProc.command = ["python3", "-I", issueScript].concat(a.args);
        actionProc.running = true;
    }

    function setField(name, value) {
        if (!detail || !detail.item)
            return;
        patchField(name, value);
        run(name, ["set", detail.item.id, name, value === undefined || value === null ? "" : String(value)]);
    }

    function comment(text) {
        if (!detail || !String(text).trim().length)
            return;
        run("comment", ["comment", detail.id], String(text).trim());
    }

    /** Blocking needs a written reason (board rule): it is posted, then the flag set. */
    function setBlocked(on, reason) {
        if (!detail || !detail.item)
            return;
        if (on) {
            if (!String(reason || "").trim().length)
                return;
            run("comment", ["comment", detail.id], "🚧 **Bloqueado:** " + String(reason).trim());
        }
        patchField("Blocked", on ? "Yes" : "No");
        run("Blocked", ["set", detail.item.id, "Blocked", on ? "Yes" : "No"]);
    }

    // ---- pull request actions ----
    function review(event, body) {
        if (detail && detailKind === "pr")
            run("review", ["review", detail.id, event], String(body || "").trim());
    }

    function mergePr(method) {
        if (detail && detailKind === "pr")
            run("merge", ["merge", detail.id, method]);
    }

    function setDraft(on) {
        if (detail && detailKind === "pr")
            run("draft", [on ? "draft" : "ready", detail.id]);
    }

    function closePr() {
        if (detail && detailKind === "pr")
            run("state", ["close-pr", detail.id]);
    }

    function reopenPr() {
        if (detail && detailKind === "pr")
            run("state", ["reopen-pr", detail.id]);
    }

    function closeIssue() {
        if (detail)
            run("state", ["close", detail.id]);
    }

    function reopenIssue() {
        if (detail)
            run("state", ["reopen", detail.id]);
    }

    Process {
        id: detailProc
        property string url: ""
        property string cmd: "detail"
        command: ["python3", "-I", root.issueScript, cmd, url]
        stdout: StdioCollector {
            onStreamFinished: {
                root.detailLoading = false;
                var d;
                try {
                    d = JSON.parse(this.text);
                } catch (e) {
                    root.detailError = "resposta inválida";
                    return;
                }
                if (detailProc.url !== root.detailUrl)
                    return; // a different issue was opened meanwhile
                if (!d.ok) {
                    root.detailError = d.error || "erro";
                    return;
                }
                root.detail = d;
            }
        }
    }

    Process {
        id: actionProc
        property string payload: ""
        stdinEnabled: true
        onRunningChanged: if (running && payload.length) {
            write(payload);
            stdinEnabled = false; // close stdin so the script sees EOF
        }
        stdout: StdioCollector {
            onStreamFinished: {
                var d = {};
                try {
                    d = JSON.parse(this.text);
                } catch (e) {
                    d = { ok: false, error: "resposta inválida" };
                }
                if (!d.ok)
                    root.actionError = d.error || "erro";
                root.busy = "";
                actionProc.stdinEnabled = true;
                if (root.actionQueue.length) {
                    root.pump();
                } else {
                    root.loadDetail();
                    root.refresh();
                }
            }
        }
    }

    // ---- background Claude reviews ----
    readonly property string reviewScript: Quickshell.env("HOME") + "/.config/quickshell/pill/scripts/claude-review.py"
    readonly property string claudeSession: "claude-reviews"
    property var claudeReviews: []
    property string claudeLaunching: ""
    property string claudeError: ""
    property string claudeErrorUrl: ""
    property var claudePrefs: ({ model: "opus", effort: "high", post: false })

    /** Work account for the company orgs, personal for the rest. */
    function defaultAccount(url) {
        var m = /github\.com\/([^\/]+)\//.exec(url || "");
        return m && m[1].toLowerCase().indexOf("tecware") === 0 ? "work" : "personal";
    }

    function claudeReviewFor(url) {
        for (var i = 0; i < claudeReviews.length; i++) {
            var r = claudeReviews[i];
            if (r.url !== url)
                continue;
            // Session registry `tmux` is "session:@window.%pane".
            var sess = Claude.sessions.find(function(x) { return x.tmux.indexOf(":" + r.window + ".") >= 0; });
            return Object.assign({}, r, { state: r.dead ? "dead" : (sess ? (sess.status === "busy" ? "busy" : "idle") : "starting") });
        }
        return null;
    }

    function startClaudeReview(url, account, model, effort, post) {
        if (launchProc.running)
            return;
        claudePrefs = { model: model, effort: effort, post: post };
        claudeLaunching = url;
        claudeError = "";
        launchProc.url = url;
        launchProc.command = ["python3", "-I", reviewScript, "start", url, account, model, effort, post ? "1" : "0"];
        launchProc.running = true;
    }

    function stopClaudeReview(window) {
        stopProc.command = ["python3", "-I", reviewScript, "stop", window];
        stopProc.running = true;
    }

    /** Kills every review window of the session, running ones included. */
    function clearClaudeReviews() {
        if (stopProc.running)
            return;
        stopProc.command = ["python3", "-I", reviewScript, "clear"];
        stopProc.running = true;
    }

    signal claudeAttached(string window)

    function attachClaudeReview(window) {
        if (attachProc.running)
            return;
        var r = claudeReviews.find(function(x) { return x.window === window; });
        attachProc.window = window;
        attachProc.url = r ? r.url : "";
        claudeError = "";
        attachProc.command = ["python3", "-I", reviewScript, "attach", window];
        attachProc.running = true;
    }

    function listClaudeReviews() {
        if (!listProc.running)
            listProc.running = true;
    }

    Timer {
        interval: 4000
        running: root.claudeReviews.length > 0
        repeat: true
        onTriggered: root.listClaudeReviews()
    }

    Process {
        id: listProc
        command: ["python3", "-I", root.reviewScript, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    if (d.ok)
                        root.claudeReviews = d.reviews;
                } catch (e) {}
                // A launch stays "preparing" until its window shows up here.
                if (!launchProc.running)
                    root.claudeLaunching = "";
            }
        }
    }

    Process {
        id: launchProc
        property string url: ""
        stdout: StdioCollector {
            onStreamFinished: {
                var d = {};
                try {
                    d = JSON.parse(this.text);
                } catch (e) {
                    d = { ok: false, error: "resposta inválida" };
                }
                if (!d.ok) {
                    root.claudeError = d.error || "erro";
                    root.claudeErrorUrl = launchProc.url;
                    root.claudeLaunching = "";
                    return;
                }
                // Restart: a list already in flight predates the new window.
                listProc.running = false;
                listProc.running = true;
            }
        }
    }

    Process {
        id: attachProc
        property string window: ""
        property string url: ""
        stdout: StdioCollector {
            onStreamFinished: {
                var d = {};
                try {
                    d = JSON.parse(this.text);
                } catch (e) {
                    d = { ok: false, error: "resposta inválida" };
                }
                if (d.ok) {
                    root.claudeAttached(attachProc.window);
                } else {
                    root.claudeError = d.error || "erro";
                    root.claudeErrorUrl = attachProc.url;
                }
            }
        }
    }

    Process {
        id: stopProc
        stdout: StdioCollector {
            onStreamFinished: root.listClaudeReviews()
        }
    }

    function refresh() {
        if (!proc.running)
            proc.running = true;
        listClaudeReviews();
    }

    /** "3m" / "5h" / "2d" since an ISO timestamp. */
    function since(iso, now) {
        if (!iso)
            return "";
        var sec = Math.max(0, Math.round((now - Date.parse(iso)) / 1000));
        if (sec < 3600)
            return Math.max(1, Math.floor(sec / 60)) + "m";
        if (sec < 86400)
            return Math.floor(sec / 3600) + "h";
        return Math.floor(sec / 86400) + "d";
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: proc
        command: ["python3", "-I", root.script]
        stdout: StdioCollector {
            onStreamFinished: {
                var d;
                try {
                    d = JSON.parse(this.text);
                } catch (e) {
                    root.error = "resposta inválida";
                    return;
                }
                if (!d.ok) {
                    root.error = d.error || "erro";
                    return;
                }
                root.error = "";
                root.login = d.login;
                root.avatar = d.avatar || "";
                root.boardUrl = d.boardUrl || "";
                root.issues = d.issues || [];
                root.reviewCount = d.reviewCount;
                root.reviews = d.reviews;
                root.mine = d.mine;
                root.runs = d.runs;
                root.ready = true;
            }
        }
    }
}
