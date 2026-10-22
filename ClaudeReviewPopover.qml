pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

/**
 * Popover that launches a background Claude review of one PR, opened from the
 * Claude button of a GitHub list row or of the PR pane. The host fills it over
 * its surface and calls toggle(trigger, pr) with { url, title, repo, number }.
 *
 * A four-step form on a StepTrack: Conta (personal / work, the org's default
 * flagged), Modelo, Esforço (what each level means) and Saída (terminal only
 * or a review on the PR: approve when clean, else comment; with a summary whose chips jump back to their step).
 * Picking a tile advances on its own; Voltar / Continuar walk the steps.
 *
 * Once the review exists (or while it is being prepared) the card shows its
 * live state instead, with "Abrir no tmux" (switches your open tmux to the
 * review's window, closing the card once it did) and a confirm-to-stop; a dead
 * session can be cleared, which brings the form back.
 */
PopShell {
    id: root

    property var pr: null
    property int step: 0
    property string account: "personal"
    property string model: "opus"
    property string effort: "high"
    property bool post: false
    property bool confirmStop: false
    property real now: Date.now()

    readonly property var job: pr ? GitHub.claudeReviewFor(pr.url) : null
    readonly property bool hasJob: job !== null
    readonly property bool launching: pr !== null && GitHub.claudeLaunching === pr.url
    readonly property string err: pr && GitHub.claudeErrorUrl === pr.url ? GitHub.claudeError : ""
    readonly property bool statusView: hasJob || launching
    readonly property var stepNames: ["Conta", "Modelo", "Esforço", "Saída"]
    readonly property var effortInfo: ({
        "low": "Passada rápida: só os achados óbvios e de alta confiança.",
        "medium": "Bom para PRs pequenos ou de rotina.",
        "high": "O padrão: cobre bem a maioria dos PRs.",
        "xhigh": "Mais minucioso, olha mais a fundo e demora mais.",
        "max": "Tudo o que encontrar, inclusive achados incertos."
    })

    kicker: "Review com Claude"
    subtitle: pr ? pr.repo.split("/").pop() + "  #" + pr.number : ""
    title: pr ? pr.title : ""

    onHasJobChanged: if (!hasJob) {
        step = 0;
        confirmStop = false;
    }
    onShownChanged: if (!shown) confirmStop = false

    function toggle(trigger, data) {
        if (shown && pr && pr.url === data.url)
            hide();
        else
            show(trigger, data);
    }

    function show(trigger, data) {
        place(trigger);
        pr = data;
        step = 0;
        account = GitHub.defaultAccount(data.url);
        model = GitHub.claudePrefs.model;
        effort = GitHub.claudePrefs.effort;
        post = GitHub.claudePrefs.post;
        confirmStop = false;
        now = Date.now();
        if (GitHub.claudeErrorUrl === data.url)
            GitHub.claudeError = "";
        shown = true;
    }

    function next() {
        if (step < stepNames.length - 1)
            step++;
        else if (!launching)
            GitHub.startClaudeReview(pr.url, account, model, effort, post);
    }

    Connections {
        target: GitHub
        function onClaudeAttached(window) {
            if (root.job && root.job.window === window)
                root.hide();
        }
    }

    /** Pick-then-advance: the tile lights first, then the track slides. */
    Timer {
        id: advance
        interval: 220
        onTriggered: root.next()
    }

    Timer {
        interval: 30000
        running: root.shown
        repeat: true
        onTriggered: root.now = Date.now()
    }

    Item {
        id: views
        width: parent.width
        height: root.statusView ? statusPane.implicitHeight : formPane.implicitHeight

        // ======== form ========
        Column {
            id: formPane
            width: views.width
            spacing: 12 * root.s
            opacity: root.statusView ? 0 : 1
            visible: opacity > 0.01
            y: root.statusView ? -8 * root.s : 0
            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
            Behavior on y { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

            StepProgress {
                width: parent.width
                s: root.s
                names: root.stepNames
                pos: root.step
            }

            StepTrack {
                width: parent.width
                path: [0, 1, 2, 3]
                pos: root.step

                StepPage {
                    page: 0
                    spacing: 8 * root.s
                    Repeater {
                        model: [{ key: "personal", text: "Pessoal", sub: "~/.claude-personal", icon: "user" },
                            { key: "work", text: "Trabalho", sub: "~/.claude-work", icon: "briefcase" }]
                        PopTile {
                            required property var modelData
                            width: parent.width
                            s: root.s
                            title: modelData.text
                            sub: modelData.sub
                            icon: modelData.icon
                            badge: root.pr && GitHub.defaultAccount(root.pr.url) === modelData.key ? "sugerida" : ""
                            selected: root.account === modelData.key
                            onPicked: { root.account = modelData.key; advance.restart(); }
                        }
                    }
                }

                StepPage {
                    page: 1
                    Grid {
                        width: parent.width
                        columns: 2
                        spacing: 8 * root.s
                        Repeater {
                            model: Claude.models
                            PopTile {
                                required property var modelData
                                width: (parent.width - 8 * root.s) / 2
                                s: root.s
                                title: modelData.text
                                sub: modelData.sub
                                selected: root.model === modelData.key
                                onPicked: { root.model = modelData.key; advance.restart(); }
                            }
                        }
                    }
                }

                StepPage {
                    page: 2
                    PopSegmented {
                        width: parent.width
                        s: root.s
                        options: Claude.efforts
                        value: root.effort
                        onPicked: (key) => root.effort = key
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: root.effortInfo[root.effort] || ""
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                        lineHeight: 1.1
                    }
                }

                StepPage {
                    page: 3
                    Grid {
                        width: parent.width
                        columns: 2
                        spacing: 8 * root.s
                        PopTile {
                            width: (parent.width - 8 * root.s) / 2
                            s: root.s
                            title: "Só terminal"
                            sub: "Fica no tmux"
                            icon: "terminal"
                            selected: !root.post
                            onPicked: root.post = false
                        }
                        PopTile {
                            width: (parent.width - 8 * root.s) / 2
                            s: root.s
                            title: "Publicar"
                            sub: "Comenta ou aprova"
                            icon: "chat"
                            selected: root.post
                            onPicked: root.post = true
                        }
                    }

                    PopSummary {
                        width: parent.width
                        s: root.s
                        chips: [
                            { k: 0, t: root.account === "work" ? "Trabalho" : "Pessoal" },
                            { k: 1, t: Claude.modelName(root.model) },
                            { k: 2, t: "effort " + root.effort },
                            { k: 3, t: root.post ? "publica no PR" : "só terminal" }
                        ]
                        onJump: (k) => root.step = k
                    }

                    Text {
                        visible: root.post
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: "Vai como review seu no PR: aprova se não houver blocker nem major, senão só comenta."
                        color: Theme.warn
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                    }

                    Text {
                        visible: root.err.length > 0
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: root.err
                        color: Theme.danger
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                    }
                }
            }

            Item {
                width: parent.width
                height: 30 * root.s

                PopButton {
                    anchors.left: parent.left
                    s: root.s
                    opacity: root.step > 0 ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                    text: "Voltar"
                    tint: Theme.subtle
                    onClicked: if (root.step > 0) root.step--
                }
                PopButton {
                    anchors.right: parent.right
                    s: root.s
                    primary: root.step === root.stepNames.length - 1
                    text: root.step < root.stepNames.length - 1 ? "Continuar" : "Iniciar review"
                    active: !root.launching
                    onClicked: root.next()
                }
            }
        }

        // ======== status ========
        Column {
            id: statusPane
            width: views.width
            spacing: 12 * root.s
            opacity: root.statusView ? 1 : 0
            visible: opacity > 0.01
            y: root.statusView ? 0 : 8 * root.s
            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
            Behavior on y { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

            readonly property string st: root.job ? root.job.state : "preparing"
            readonly property var info: ({
                "preparing": { text: "Preparando o review…", color: Theme.warn },
                "starting": { text: "Abrindo a sessão…", color: Theme.warn },
                "busy": { text: "Claude revisando…", color: Theme.claude },
                "idle": { text: "Review pronto", color: Theme.ok },
                "dead": { text: "A sessão encerrou", color: Theme.danger }
            })[st]

            PopStatus {
                width: parent.width
                s: root.s
                text: statusPane.info.text
                tint: statusPane.info.color
                pulse: root.shown && ["preparing", "starting", "busy"].indexOf(statusPane.st) >= 0
                detail: root.job
                    ? (root.job.account === "work" ? "Trabalho" : "Pessoal") + "  ·  " + root.job.model + "  ·  " + root.job.effort
                        + "  ·  " + (root.job.post ? "publica no PR" : "só terminal") + "  ·  " + GitHub.since(new Date(root.job.started).toISOString(), root.now)
                    : "Lendo o PR no GitHub e abrindo a janela no tmux"
            }

            Text {
                visible: root.err.length > 0
                width: parent.width
                wrapMode: Text.Wrap
                text: root.err
                color: Theme.danger
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
            }

            Text {
                width: parent.width
                text: "tmux: " + GitHub.claudeSession
                color: Theme.faint
                font.family: "monospace"
                font.pixelSize: 9.5 * root.s
            }

            Item {
                width: parent.width
                height: 30 * root.s

                PopButton {
                    anchors.left: parent.left
                    s: root.s
                    visible: root.hasJob
                    text: root.confirmStop ? "Confirmar" : (root.job && root.job.state === "dead" ? "Limpar" : "Encerrar")
                    tint: Theme.danger
                    onClicked: {
                        if (root.confirmStop || root.job.state === "dead") {
                            root.confirmStop = false;
                            GitHub.stopClaudeReview(root.job.window);
                        } else {
                            root.confirmStop = true;
                        }
                    }
                }
                PopButton {
                    anchors.right: parent.right
                    s: root.s
                    primary: true
                    active: root.hasJob
                    text: "Abrir no tmux"
                    onClicked: GitHub.attachClaudeReview(root.job.window)
                }
            }
        }
    }
}
