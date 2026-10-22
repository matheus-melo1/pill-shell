pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * AI chat state for the drawer, talking to the active OpenAI-compatible
 * provider (CodeCraft, OpenRouter…) through scripts/ai-chat.py, the only
 * place the API key is read. A saved model the provider doesn't list falls
 * back to the provider's default. Conversations are
 * persisted in the state dir as { id, title, model, created, updated,
 * messages: [{ role, content, images, ts, model, error }] }, newest first,
 * with debounced writes. send() appends the user turn and streams the reply:
 * deltas accumulate in `streamText` (cheap to bind while it grows) and are
 * folded into the conversation when the stream ends, errors or is stopped.
 *
 * Images are staged in `pending` as files under the state dir, from the
 * clipboard (pasteImage) or a region capture (capture); `capturing` is set
 * while slurp runs so the drawer can get out of the way.
 */
Singleton {
    id: root

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ricelin"
    readonly property string imageDir: stateDir + "/ai-images"
    readonly property string script: Quickshell.env("HOME") + "/.config/quickshell/pill/scripts/ai-chat.py"
    // without credits only free models answer: OpenRouter's free router picks one
    readonly property string defaultModel: freeOnly ? "openrouter/free" : (providerDefault || "claude-sonnet-5")

    readonly property var chats: adapter.chats
    readonly property string currentId: adapter.currentId
    readonly property string model: adapter.model && (!models.length || modelInfo(adapter.model)) ? adapter.model : defaultModel
    readonly property var current: {
        for (var i = 0; i < chats.length; i++)
            if (chats[i].id === currentId)
                return chats[i];
        return null;
    }
    readonly property var messages: current ? current.messages : []

    property bool hasKey: false
    property string keyFile: ""
    property string provider: ""
    property string providerLabel: "IA"
    property string providerDefault: ""
    /** OpenRouter balance: { credits, usage, freeUsed, freeLimit }, {} elsewhere. */
    property var account: ({})
    readonly property bool knowsBalance: account.credits !== undefined
    readonly property bool freeOnly: knowsBalance && account.credits - account.usage <= 0

    function isFree(m) {
        return !!m && !m.variable && m.prompt === 0 && m.completion === 0;
    }
    property var models: []
    property bool streaming: false
    property string streamText: ""
    property string streamChat: ""
    property var pending: []
    property bool capturing: false
    property string notice: ""

    function uid() {
        return Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
    }

    function modelInfo(id) {
        for (var i = 0; i < models.length; i++)
            if (models[i].id === id)
                return models[i];
        return null;
    }

    function modelName(id) {
        var m = modelInfo(id);
        if (m)
            return m.name.replace(/^[^:]+:\s*/, "");
        return id.split("/").pop();
    }

    function refreshStatus() {
        statusProc.running = true;
        accountProc.running = true;
        if (!models.length && !modelsProc.running)
            modelsProc.running = true;
    }

    function setModel(id) {
        adapter.model = id;
        if (current)
            patch(current.id, { model: id });
        save.restart();
    }

    function patch(id, fields) {
        adapter.chats = adapter.chats.map(function(c) {
            return c.id === id ? Object.assign({}, c, fields) : c;
        });
        save.restart();
    }

    function newChat() {
        if (streaming)
            stop();
        adapter.currentId = "";
        clearPending();
        save.restart();
    }

    function openChat(id) {
        if (streaming)
            stop();
        adapter.currentId = id;
        save.restart();
    }

    function deleteChat(id) {
        var doomed = adapter.chats.filter(function(c) { return c.id === id; });
        var paths = [];
        if (doomed.length)
            doomed[0].messages.forEach(function(m) { paths = paths.concat(m.images || []); });
        if (paths.length)
            Quickshell.execDetached(["rm", "-f"].concat(paths));
        adapter.chats = adapter.chats.filter(function(c) { return c.id !== id; });
        if (adapter.currentId === id)
            adapter.currentId = "";
        save.restart();
    }

    function send(text) {
        text = String(text || "").trim();
        if (streaming || (!text.length && !pending.length))
            return false;
        var now = Date.now();
        var msg = { role: "user", content: text, images: pending.slice(), ts: now };
        var chat = current;
        if (!chat) {
            chat = {
                id: uid(),
                title: (text || "Imagem").replace(/\s+/g, " ").slice(0, 60),
                model: model,
                created: now,
                updated: now,
                messages: []
            };
            adapter.chats = [chat].concat(adapter.chats);
            adapter.currentId = chat.id;
        }
        var msgs = chat.messages.concat([msg]);
        // Move the chat to the top as the most recently used.
        adapter.chats = [Object.assign({}, chat, { messages: msgs, updated: now, model: model })]
            .concat(adapter.chats.filter(function(c) { return c.id !== chat.id; }));
        pending = [];
        save.restart();
        startStream(chat.id, msgs);
        return true;
    }

    /** Re-ask the last user turn, dropping a failed or unwanted reply after it. */
    function retry() {
        if (streaming || !current)
            return;
        var msgs = current.messages.slice();
        while (msgs.length && msgs[msgs.length - 1].role !== "user")
            msgs.pop();
        if (!msgs.length)
            return;
        patch(current.id, { messages: msgs });
        startStream(current.id, msgs);
    }

    function startStream(chatId, msgs) {
        streamChat = chatId;
        streamText = "";
        streaming = true;
        chatProc.pendingError = "";
        chatProc.doneModel = "";
        chatProc.payload = JSON.stringify({
            model: model,
            messages: msgs.map(function(m) {
                return { role: m.role, content: m.content, images: m.images || [] };
            })
        }) + "\n";
        chatProc.running = true;
    }

    function finish(error) {
        var text = streamText;
        var id = streamChat;
        streaming = false;
        streamText = "";
        streamChat = "";
        var chat = null;
        for (var i = 0; i < adapter.chats.length; i++)
            if (adapter.chats[i].id === id)
                chat = adapter.chats[i];
        if (!chat)
            return;
        var msgs = chat.messages.slice();
        if (text.length || error)
            msgs.push({
                role: "assistant",
                content: text,
                ts: Date.now(),
                model: chatProc.doneModel || model,
                error: error || ""
            });
        patch(id, { messages: msgs, updated: Date.now() });
    }

    function stop() {
        if (chatProc.running) {
            chatProc.stopped = true;
            chatProc.signal(15);
        }
    }

    function clearPending() {
        if (pending.length)
            Quickshell.execDetached(["rm", "-f"].concat(pending));
        pending = [];
    }

    function removePending(path) {
        Quickshell.execDetached(["rm", "-f", path]);
        pending = pending.filter(function(p) { return p !== path; });
    }

    function pasteImage() {
        if (imgProc.running)
            return;
        imgProc.target = imageDir + "/" + uid() + ".png";
        imgProc.command = ["sh", "-c",
            "wl-paste --list-types | grep -q '^image/' || exit 3; mkdir -p \"$(dirname \"$1\")\"; wl-paste --type image/png > \"$1\" && [ -s \"$1\" ]",
            "_", imgProc.target];
        imgProc.running = true;
    }

    function capture() {
        if (imgProc.running)
            return;
        capturing = true;
        imgProc.target = imageDir + "/" + uid() + ".png";
        // Short delay so the drawer has slid away before slurp freezes the frame.
        // stdin must be /dev/null: with a pipe on stdin slurp waits there for
        // predefined boxes and never shows the selection.
        imgProc.command = ["sh", "-c",
            "sleep 0.35; mkdir -p \"$(dirname \"$1\")\"; g=$(slurp < /dev/null) || exit 4; grim -g \"$g\" \"$1\"",
            "_", imgProc.target];
        imgProc.running = true;
    }

    /** Abort a region capture (slurp exits non-zero, which clears `capturing`). */
    function cancelCapture() {
        if (capturing)
            Quickshell.execDetached(["pkill", "-x", "slurp"]);
    }

    function copy(text) {
        Quickshell.execDetached(["wl-copy", "--", text]);
        notice = "Copiado";
        noticeTimer.restart();
    }

    Timer {
        id: noticeTimer
        interval: 1600
        onTriggered: root.notice = ""
    }

    Timer {
        id: save
        interval: 500
        onTriggered: file.writeAdapter()
    }

    Process {
        id: chatProc
        property string payload: ""
        property string pendingError: ""
        property string doneModel: ""
        property bool stopped: false
        command: ["python3", "-I", root.script, "chat"]
        stdinEnabled: true
        onRunningChanged: if (running) write(payload)
        stdout: SplitParser {
            onRead: (line) => {
                var ev;
                try {
                    ev = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (ev.t === "delta")
                    root.streamText += ev.text;
                else if (ev.t === "error")
                    chatProc.pendingError = ev.msg;
                else if (ev.t === "done")
                    chatProc.doneModel = ev.model || "";
            }
        }
        onExited: (code) => {
            var err = chatProc.pendingError;
            if (!err && chatProc.stopped)
                err = "";
            else if (!err && code !== 0)
                err = "O processo terminou com erro (" + code + ")";
            chatProc.stopped = false;
            root.finish(err);
            accountProc.running = true;
        }
    }

    Process {
        id: imgProc
        property string target: ""
        onExited: (code) => {
            root.capturing = false;
            if (code === 0)
                root.pending = root.pending.concat([imgProc.target]);
            else if (code === 3) {
                root.notice = "Nenhuma imagem na área de transferência";
                noticeTimer.restart();
            }
        }
    }

    Process {
        id: accountProc
        command: ["python3", "-I", root.script, "account"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    if (!d.error)
                        root.account = d;
                } catch (e) {
                }
            }
        }
    }

    Process {
        id: statusProc
        command: ["python3", "-I", root.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    root.hasKey = d.hasKey;
                    root.keyFile = d.keyFile;
                    root.providerLabel = d.label;
                    root.providerDefault = d.defaultModel;
                    if (d.provider !== root.provider) {
                        root.provider = d.provider;
                        root.models = [];
                        modelsProc.running = true;
                    }
                } catch (e) {
                }
            }
        }
    }

    Process {
        id: modelsProc
        command: ["python3", "-I", root.script, "models"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.models = JSON.parse(this.text).models || [];
                } catch (e) {
                }
            }
        }
    }

    FileView {
        id: file
        path: root.stateDir + "/ai-chats.json"
        blockLoading: true
        printErrors: false

        JsonAdapter {
            id: adapter
            property var chats: []
            property string currentId: ""
            property string model: ""
        }
    }

    Component.onCompleted: refreshStatus()
}
