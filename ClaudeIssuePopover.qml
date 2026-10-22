pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "Singletons"

/**
 * Popover that hands a GitHub issue to a Claude Code agent, opened from the
 * Claude button of the issue pane. The host fills it over the pane and calls
 * toggle(trigger, issue) with { url, title, repo, number }.
 *
 * Step one, Destino, lists the Claude sessions open in tmux (account, tmux
 * place, folder, working / free; ones outside tmux or waiting on you are
 * shown but cannot be picked) plus "Novo Claude". Then one of two flows on the
 * same StepTrack:
 *
 *  - an open agent: Enviar previews the message and types it into that
 *    claude (queued if it is mid-turn);
 *  - a new one: Sessão (your tmux sessions, the one whose folders match the
 *    issue's repo suggested, with a search box that filters by name or
 *    folder, Up/Down to move and Enter to pick), Pasta (skipped when the session has only one),
 *    Claude (account, model, effort) and Janela (the new window's name and a
 *    summary), which opens claude there with the issue as its first prompt.
 *
 * Either way it ends on a confirmation with "Ir para o agente/a janela",
 * which switches your open tmux to it and closes the card.
 */
PopShell {
    id: root

    property var issue: null
    property string dest: ""
    property var agent: null
    property var tmuxSession: null
    property string dir: ""
    property string account: "personal"
    property string model: "opus"
    property string effort: "high"
    property string windowName: ""
    property var path: [0, 1]
    property int pos: 0
    property var result: null
    property string query: ""
    property int hl: 0

    readonly property var pageNames: ["Destino", "Enviar", "Sessão", "Pasta", "Claude", "Janela"]
    readonly property var agentList: shown ? Agents.agents() : []
    readonly property string repoName: issue ? issue.repo.split("/").pop().toLowerCase() : ""
    readonly property int page: path[pos]
    readonly property bool working: Agents.busy === "send" || Agents.busy === "new"
    readonly property var effortInfo: ({
        "low": "Pensa pouco e responde rápido.",
        "medium": "Equilíbrio para tarefas do dia a dia.",
        "high": "O padrão: pensa com calma antes de agir.",
        "xhigh": "Pensa bem mais antes de agir, mais lento.",
        "max": "O máximo de raciocínio, o mais lento."
    })

    kicker: "Issue para o Claude"
    subtitle: issue ? issue.repo.split("/").pop() + "  #" + issue.number : ""
    title: issue ? issue.title : ""
    expectH: 420 * s

    function toggle(trigger, data) {
        if (shown && issue && issue.url === data.url)
            hide();
        else
            show(trigger, data);
    }

    function show(trigger, data) {
        place(trigger);
        issue = data;
        dest = "";
        agent = null;
        tmuxSession = null;
        dir = "";
        account = GitHub.defaultAccount(data.url);
        model = GitHub.claudePrefs.model;
        effort = GitHub.claudePrefs.effort;
        windowName = "issue-" + data.number;
        nameField.text = windowName;
        query = "";
        searchField.text = "";
        hl = 0;
        result = null;
        pos = 0;
        path = Agents.agents().some(function(a) { return a.pane.length > 0; }) ? [0, 1] : [0, 2, 3, 4, 5];
        Agents.error = "";
        Agents.refreshTmux();
        shown = true;
    }

    /** "~/x/y" for paths under home. */
    function tilde(p) {
        var home = Quickshell.env("HOME");
        return p.indexOf(home) === 0 ? "~" + p.substring(home.length) : p;
    }

    function base(p) {
        return p.split("/").filter(function(x) { return x.length; }).pop() || p;
    }

    function matchesRepo(p) {
        return repoName.length > 0 && base(p).toLowerCase() === repoName;
    }

    function agentState(a) {
        if (!a.pane.length)
            return { badge: "", tint: Theme.dim, ok: false, note: "fora do tmux" };
        var st = a.session.status;
        if (st === "busy")
            return { badge: "trabalhando", tint: Theme.claude, ok: true, note: "" };
        if (st === "idle")
            return { badge: "livre", tint: Theme.ok, ok: true, note: "" };
        return { badge: "esperando você", tint: Theme.warn, ok: false, note: "responda antes" };
    }

    readonly property var sessionList: {
        var list = Agents.tmuxSessions.slice();
        function score(x) {
            return (x.dirs.some(root.matchesRepo) ? 4 : 0) + (x.attached ? 2 : 0);
        }
        list.sort(function(a, b) { return score(b) - score(a) || b.activity - a.activity; });
        return list;
    }

    /** Sessions whose name or folders hold every word of `query`. */
    readonly property var shownSessions: {
        var words = query.toLowerCase().split(/\s+/).filter(function(w) { return w.length; });
        if (!words.length)
            return sessionList;
        return sessionList.filter(function(x) {
            var hay = (x.name + " " + x.dirs.join(" ")).toLowerCase();
            return words.every(function(w) { return hay.indexOf(w) >= 0; });
        });
    }
    onQueryChanged: hl = 0

    function pickAgent(a) {
        dest = "agent";
        agent = a;
        path = [0, 1];
        advance.restart();
    }

    function pickNew() {
        dest = "new";
        path = tmuxSession && tmuxSession.dirs.length < 2 ? [0, 2, 4, 5] : [0, 2, 3, 4, 5];
        advance.restart();
    }

    function pickSession(x) {
        tmuxSession = x;
        dir = x.dirs.find(matchesRepo) || x.dirs[0] || x.path;
        path = x.dirs.length < 2 ? [0, 2, 4, 5] : [0, 2, 3, 4, 5];
        advance.restart();
    }

    function canAdvance() {
        if (page === 0)
            return dest === "agent" ? agent !== null : dest === "new";
        if (page === 2)
            return tmuxSession !== null;
        if (page === 3)
            return dir.length > 0;
        if (page === 5)
            return windowName.trim().length > 0;
        return true;
    }

    function next() {
        if (!canAdvance() || working)
            return;
        if (pos < path.length - 1) {
            pos++;
            return;
        }
        GitHub.claudePrefs = Object.assign({}, GitHub.claudePrefs, { model: model, effort: effort });
        if (dest === "agent")
            Agents.sendIssue(agent.pane, agent.session.pid, issue.url, issue.title);
        else
            Agents.newAgent(tmuxSession.name, dir, windowName.trim(), account, model, effort, issue.url, issue.title);
    }

    Connections {
        target: Agents
        function onDone(kind, d) {
            if (!root.shown)
                return;
            if (kind === "send")
                root.result = { target: root.agent.pane, text: "Issue enviada para " + root.agent.session.name,
                    detail: d.busy ? "Ele está trabalhando: a mensagem entrou na fila." : root.agent.tmuxSession + "  ›  " + root.agent.windowName,
                    go: "Ir para o agente" };
            else if (kind === "new")
                root.result = { target: d.window, text: "Claude aberto com a issue",
                    detail: root.tmuxSession.name + "  ›  " + root.windowName.trim() + "  ·  " + root.tilde(root.dir), go: "Ir para a janela" };
            else if (kind === "goto")
                root.hide();
        }
    }

    Timer {
        id: advance
        interval: 220
        onTriggered: root.next()
    }

    // Type straight into the page's field once it has slid in.
    onPageChanged: if (page === 2 || page === 5) focusField.restart()
    Timer {
        id: focusField
        interval: Motion.morph
        onTriggered: {
            if (root.page === 2)
                searchField.focusAll();
            else if (root.page === 5)
                nameField.focusAll();
        }
    }

    Item {
        id: views
        width: parent.width
        height: root.result ? donePane.implicitHeight : formPane.implicitHeight

        // ======== form ========
        Column {
            id: formPane
            width: views.width
            spacing: 12 * root.s
            opacity: root.result ? 0 : 1
            visible: opacity > 0.01
            y: root.result ? -8 * root.s : 0
            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
            Behavior on y { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

            StepProgress {
                width: parent.width
                s: root.s
                names: root.path.map(function(p) { return root.pageNames[p]; })
                pos: root.pos
            }

            StepTrack {
                width: parent.width
                path: root.path
                pos: root.pos

                // 0. destination
                StepPage {
                    page: 0
                    spacing: 8 * root.s

                    Text {
                        text: root.agentList.length ? "Claudes abertos" : "Nenhum Claude aberto agora"
                        color: Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 9.5 * root.s
                        font.weight: Font.Bold
                    }

                    PopList {
                        visible: root.agentList.length > 0
                        s: root.s
                        maxHeight: 186
                        Repeater {
                            model: root.agentList
                            PopTile {
                                id: at
                                required property var modelData
                                readonly property var st: root.agentState(modelData)
                                width: parent.width
                                s: root.s
                                title: modelData.session.name || "claude"
                                sub: (modelData.pane.length ? modelData.tmuxSession + " › " + (modelData.windowName || modelData.window) + "  ·  " : "")
                                    + root.tilde(modelData.session.cwd)
                                icon: modelData.session.account === "work" ? "briefcase" : "user"
                                badge: st.badge
                                badgeTint: st.tint
                                available: st.ok
                                note: st.note
                                selected: root.dest === "agent" && root.agent !== null && root.agent.pane === modelData.pane
                                onPicked: root.pickAgent(at.modelData)
                            }
                        }
                    }

                    PopTile {
                        width: parent.width
                        s: root.s
                        title: "Novo Claude"
                        sub: "Numa janela nova de uma sessão do tmux"
                        icon: "plus"
                        selected: root.dest === "new"
                        onPicked: root.pickNew()
                    }
                }

                // 1. send to an open agent
                StepPage {
                    page: 1
                    spacing: 8 * root.s

                    PopStatus {
                        width: parent.width
                        s: root.s
                        tint: root.agent && root.agent.session.status === "busy" ? Theme.claude : Theme.ok
                        text: root.agent ? "Para " + (root.agent.session.name || "claude") : ""
                        detail: root.agent ? root.agent.tmuxSession + "  ›  " + root.agent.windowName + "  ·  " + root.tilde(root.agent.session.cwd) : ""
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: "Vai digitar no Claude: “Leia a issue " + (root.issue ? root.issue.url : "")
                            + " com gh issue view … e me resuma o que precisa ser feito. Ainda não altere nada.”"
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                        lineHeight: 1.1
                    }
                    Text {
                        visible: root.agent !== null && root.agent.session.status === "busy"
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: "Ele está trabalhando agora: a mensagem entra na fila."
                        color: Theme.warn
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                    }
                }

                // 2. tmux session
                StepPage {
                    page: 2
                    spacing: 8 * root.s

                    PopField {
                        id: searchField
                        width: parent.width
                        s: root.s
                        glyph: "探"
                        placeholder: "Buscar sessão ou pasta…"
                        counter: root.query.length ? root.shownSessions.length + "/" + root.sessionList.length : ""
                        onEdited: root.query = text
                        onMoved: (d) => root.hl = Math.max(0, Math.min(root.shownSessions.length - 1, root.hl + d))
                        onAccepted: if (root.shownSessions.length) root.pickSession(root.shownSessions[root.hl])
                    }
                    Text {
                        visible: !Agents.tmuxLoaded || (root.query.length > 0 && root.shownSessions.length === 0)
                        width: parent.width
                        elide: Text.ElideRight
                        text: !Agents.tmuxLoaded ? "Lendo as sessões do tmux…" : "Nenhuma sessão com “" + root.query + "”"
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                    }
                    PopList {
                        id: sessList
                        s: root.s
                        maxHeight: 216
                        Repeater {
                            model: root.shownSessions
                            PopTile {
                                id: stile
                                required property var modelData
                                required property int index
                                width: parent.width
                                focused: searchField.input.activeFocus && root.hl === index
                                onFocusedChanged: if (focused) sessList.ensureVisible(stile)
                                s: root.s
                                tileHeight: 48
                                title: modelData.name
                                sub: root.tilde(modelData.dirs[0] || modelData.path) + "  ·  " + modelData.windows.length
                                    + (modelData.windows.length === 1 ? " janela" : " janelas")
                                icon: "terminal"
                                badge: modelData.dirs.some(root.matchesRepo) ? "sugerida" : (modelData.attached ? "aberta" : "")
                                badgeTint: modelData.dirs.some(root.matchesRepo) ? Theme.claude : Theme.info
                                selected: root.tmuxSession !== null && root.tmuxSession.id === modelData.id
                                onPicked: root.pickSession(stile.modelData)
                            }
                        }
                    }
                }

                // 3. folder inside the session
                StepPage {
                    page: 3
                    spacing: 8 * root.s

                    Repeater {
                        model: root.tmuxSession ? root.tmuxSession.dirs : []
                        PopTile {
                            id: dtile
                            required property string modelData
                            width: parent.width
                            s: root.s
                            tileHeight: 48
                            title: root.base(modelData)
                            sub: root.tilde(modelData)
                            icon: "folder"
                            badge: root.matchesRepo(modelData) ? "repo da issue" : ""
                            selected: root.dir === modelData
                            onPicked: { root.dir = dtile.modelData; advance.restart(); }
                        }
                    }
                }

                // 4. which claude
                StepPage {
                    page: 4
                    spacing: 6 * root.s

                    Repeater {
                        model: [
                            { label: "Conta", options: [{ key: "personal", text: "Pessoal" }, { key: "work", text: "Trabalho" }], prop: "account" },
                            { label: "Modelo", options: Claude.models, prop: "model" },
                            { label: "Effort", options: Claude.efforts, prop: "effort" }
                        ]
                        Column {
                            id: cfg
                            required property var modelData
                            width: parent.width
                            spacing: 5 * root.s
                            bottomPadding: 4 * root.s
                            Text {
                                text: cfg.modelData.label
                                color: Theme.subtle
                                font.family: Theme.font
                                font.pixelSize: 9.5 * root.s
                                font.weight: Font.Bold
                            }
                            PopSegmented {
                                width: parent.width
                                s: root.s
                                options: cfg.modelData.options
                                value: root[cfg.modelData.prop]
                                onPicked: (key) => root[cfg.modelData.prop] = key
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: root.effortInfo[root.effort] || ""
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                    }
                }

                // 5. window name + summary
                StepPage {
                    page: 5
                    spacing: 10 * root.s

                    Text {
                        text: "Nome da janela"
                        color: Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 9.5 * root.s
                        font.weight: Font.Bold
                    }
                    PopField {
                        id: nameField
                        width: parent.width
                        s: root.s
                        placeholder: "issue-123"
                        onEdited: root.windowName = text
                        onAccepted: root.next()
                    }

                    PopSummary {
                        width: parent.width
                        s: root.s
                        chips: [
                            { k: root.path.indexOf(2), t: root.tmuxSession ? root.tmuxSession.name : "" },
                            { k: Math.max(root.path.indexOf(3), root.path.indexOf(2)), t: root.base(root.dir) },
                            { k: root.path.indexOf(4), t: root.account === "work" ? "Trabalho" : "Pessoal" },
                            { k: root.path.indexOf(4), t: Claude.modelName(root.model) + " · " + root.effort }
                        ]
                        onJump: (k) => root.pos = k
                    }
                }
            }

            Text {
                visible: Agents.error.length > 0
                width: parent.width
                wrapMode: Text.Wrap
                text: Agents.error
                color: Theme.danger
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
            }

            Item {
                width: parent.width
                height: 30 * root.s

                PopButton {
                    anchors.left: parent.left
                    s: root.s
                    opacity: root.pos > 0 ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                    text: "Voltar"
                    tint: Theme.subtle
                    onClicked: if (root.pos > 0) root.pos--
                }
                PopButton {
                    anchors.right: parent.right
                    s: root.s
                    readonly property bool last: root.pos === root.path.length - 1
                    primary: last
                    active: root.canAdvance() && !root.working
                    text: !last ? "Continuar"
                        : (root.dest === "agent" ? (Agents.busy === "send" ? "Enviando…" : "Enviar issue")
                            : (Agents.busy === "new" ? "Abrindo…" : "Abrir Claude"))
                    onClicked: root.next()
                }
            }
        }

        // ======== done ========
        Column {
            id: donePane
            width: views.width
            spacing: 12 * root.s
            opacity: root.result ? 1 : 0
            visible: opacity > 0.01
            y: root.result ? 0 : 8 * root.s
            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
            Behavior on y { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

            PopStatus {
                width: parent.width
                s: root.s
                tint: Theme.ok
                text: root.result ? root.result.text : ""
                detail: root.result ? root.result.detail : ""
            }

            Text {
                visible: Agents.error.length > 0
                width: parent.width
                wrapMode: Text.Wrap
                text: Agents.error
                color: Theme.danger
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
            }

            Item {
                width: parent.width
                height: 30 * root.s
                PopButton {
                    anchors.left: parent.left
                    s: root.s
                    text: "Fechar"
                    tint: Theme.subtle
                    onClicked: root.hide()
                }
                PopButton {
                    anchors.right: parent.right
                    s: root.s
                    primary: true
                    active: Agents.busy !== "goto"
                    text: root.result ? root.result.go : ""
                    onClicked: Agents.gotoTarget(root.result.target)
                }
            }
        }
    }
}
