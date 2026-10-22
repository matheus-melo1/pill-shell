pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Plain to-do list shared by the drawer's Tarefas route and the pill's
 * quick-add surface. Items are { id, text, done, created, doneAt } kept in
 * list order (open items in the user's order; done items move to the end,
 * newest first) and persisted to a JSON file in the state dir with debounced
 * writes.
 */
Singleton {
    id: root

    readonly property var items: adapter.items
    readonly property var open: items.filter(function(t) { return !t.done; })
    readonly property var done: items.filter(function(t) { return t.done; })
        .sort(function(a, b) { return (b.doneAt || 0) - (a.doneAt || 0); })

    function uid() {
        return Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
    }

    function commit(list) {
        adapter.items = list;
        save.restart();
    }

    /** New tasks go to the end of the open list. */
    function add(text) {
        text = String(text || "").trim();
        if (!text.length)
            return false;
        commit(open.concat([{ id: uid(), text: text, done: false, created: Date.now(), doneAt: 0 }]).concat(done));
        return true;
    }

    function toggle(id) {
        commit(items.map(function(t) {
            return t.id === id ? Object.assign({}, t, { done: !t.done, doneAt: t.done ? 0 : Date.now() }) : t;
        }));
    }

    function edit(id, text) {
        text = String(text || "").trim();
        if (!text.length)
            return remove(id);
        commit(items.map(function(t) { return t.id === id ? Object.assign({}, t, { text: text }) : t; }));
    }

    function remove(id) {
        commit(items.filter(function(t) { return t.id !== id; }));
    }

    /** Move an open task from index `from` to index `to` within the open list. */
    function move(from, to) {
        var o = open.slice();
        if (from < 0 || from >= o.length || to < 0 || to >= o.length || from === to)
            return;
        var t = o.splice(from, 1)[0];
        o.splice(to, 0, t);
        commit(o.concat(done));
    }

    function clearDone() {
        commit(open);
    }

    Timer {
        id: save
        interval: 400
        onTriggered: file.writeAdapter()
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ricelin/todo.json"
        blockLoading: true
        printErrors: false

        JsonAdapter {
            id: adapter
            property var items: []
        }
    }
}
