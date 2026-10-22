"""
Hand GitHub issues to Claude Code agents living in tmux, for the pill's issue
pane.

  tmux                                          sessions, windows and folders
  send <pane> <pid> <issue-url> <title>         give the issue to a running claude
  new <session> <dir> <name> <account> <model> <effort> <issue-url> <title>
                                                open a claude on it in a new window
  goto <window-or-pane-id>                      show it in your open tmux

`tmux` lists the sessions (minus the background review one), each with its
windows and the distinct folders its panes are in, active pane first, then
the session's start folder.

`send` types one line into the agent's pane through a bracketed paste and
presses Enter, so Claude takes it as a message (queued if it is mid-turn).
It only does so when the pane really hosts that claude (its pid descends from
the pane's process and its registry entry points at the pane) and the agent
is idle or working, never while it waits on a question or permission prompt,
where keystrokes could pick an option.

`new` opens a window named <name> in <session>, in <dir>, running claude with
the account's config dir, model, effort and the issue as its first prompt;
when claude exits the window drops to a shell like any new tmux window. It is created in the
background; `goto` brings it up.

Prints one JSON line; failures are {"ok": false, "error": ...}.
Env overrides (tests): PILL_AGENT_ACCOUNTS ("name=dir:name=dir"),
PILL_AGENT_CLAUDE.
"""

import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import tmuxnav  # noqa: E402

HOME = os.path.expanduser("~")
REVIEW_SESSION = "claude-reviews"
CLAUDE = os.environ.get("PILL_AGENT_CLAUDE", "claude")
ACCOUNTS = dict(kv.split("=", 1) for kv in os.environ.get(
    "PILL_AGENT_ACCOUNTS", "personal=%s/.claude-personal:work=%s/.claude-work" % (HOME, HOME)).split(":"))
MODELS = {"opus", "sonnet", "haiku", "fable"}
EFFORTS = {"low", "medium", "high", "xhigh", "max"}
SENDABLE = {"idle", "busy"}

ISSUE_URL = re.compile(r"^https://github\.com/[^/]+/[^/]+/issues/\d+$")


class Fail(Exception):
    pass


def tmux(*args, check=True, stdin=None):
    out = subprocess.run(["tmux", *args], capture_output=True, text=True, timeout=10, input=stdin)
    if check and out.returncode != 0:
        msg = (out.stderr or "tmux falhou").strip().splitlines()
        raise Fail(msg[-1] if msg else "tmux falhou")
    return out.stdout


def issue_prompt(url, title):
    named = ' ("%s")' % title.replace("\n", " ").strip() if title.strip() else ""
    return ("Leia a issue %s%s com `gh issue view %s --comments`, incluindo as sub-issues e os PRs ligados, "
            "e me resuma o que precisa ser feito. Ainda não altere nada." % (url, named, url))


def sessions():
    fields = ["session_id", "session_name", "session_path", "session_attached", "session_activity",
              "window_id", "window_index", "window_name", "window_active", "pane_current_path", "pane_active"]
    out = tmux("list-panes", "-a", "-F", "\t".join("#{%s}" % f for f in fields), check=False)
    by = {}
    order = []
    for line in out.splitlines():
        r = dict(zip(fields, line.split("\t")))
        if len(r) != len(fields) or r["session_name"] == REVIEW_SESSION:
            continue
        s = by.get(r["session_id"])
        if s is None:
            s = by[r["session_id"]] = {
                "id": r["session_id"], "name": r["session_name"], "path": r["session_path"],
                "attached": r["session_attached"] != "0", "activity": int(r["session_activity"] or 0),
                "windows": [], "dirs": [], "_active": "",
            }
            order.append(s)
        if not any(w["id"] == r["window_id"] for w in s["windows"]):
            s["windows"].append({"id": r["window_id"], "index": int(r["window_index"]), "name": r["window_name"]})
        path = r["pane_current_path"]
        if r["window_active"] == "1" and r["pane_active"] == "1":
            s["_active"] = path
        if path and path not in s["dirs"]:
            s["dirs"].append(path)
    for s in order:
        dirs = [d for d in [s.pop("_active"), s["path"]] + s["dirs"] if d]
        s["dirs"] = [d for i, d in enumerate(dirs) if d not in dirs[:i] and os.path.isdir(d)]
    return order


def registry(pid):
    for root in ACCOUNTS.values():
        try:
            with open(os.path.join(root, "sessions", "%d.json" % pid)) as f:
                return json.load(f)
        except (OSError, ValueError):
            continue
    return None


def descends(pid, ancestor):
    while pid > 1:
        if pid == ancestor:
            return True
        pid = tmuxnav.parent_pid(pid)
    return False


def send(pane, pid, url, title):
    if not ISSUE_URL.match(url):
        raise Fail("URL de issue inválida")
    pid = int(pid)
    reg = registry(pid)
    if not reg or not str(reg.get("tmux", "")).endswith("." + pane):
        raise Fail("esse Claude não está mais nesse painel do tmux")
    status = reg.get("status") or ""
    if status not in SENDABLE:
        raise Fail("o Claude está esperando uma resposta sua (%s): responda no terminal antes" % (status or "?"))
    info = tmux("display-message", "-p", "-t", pane, "#{pane_pid}\t#{pane_in_mode}", check=False).strip().split("\t")
    if len(info) != 2 or not info[0]:
        raise Fail("painel do tmux não encontrado")
    if not descends(pid, int(info[0])):
        raise Fail("esse painel não roda mais esse Claude")
    if info[1] == "1":
        tmux("send-keys", "-t", pane, "-X", "cancel")
    tmux("load-buffer", "-b", "pill-issue", "-", stdin=issue_prompt(url, title))
    tmux("paste-buffer", "-p", "-d", "-b", "pill-issue", "-t", pane)
    time.sleep(0.3)
    tmux("send-keys", "-t", pane, "Enter")
    return {"pane": pane, "busy": status == "busy"}


def new(session, folder, name, account, model, effort, url, title):
    if not ISSUE_URL.match(url):
        raise Fail("URL de issue inválida")
    if account not in ACCOUNTS:
        raise Fail("conta desconhecida: " + account)
    if model not in MODELS:
        raise Fail("modelo desconhecido: " + model)
    if effort not in EFFORTS:
        raise Fail("effort desconhecido: " + effort)
    name = " ".join(name.split())
    if not name:
        raise Fail("dê um nome para a janela")
    if not os.path.isdir(folder):
        raise Fail("pasta não existe: " + folder)
    target = next((s for s in sessions() if s["name"] == session), None)
    if not target:
        raise Fail("sessão do tmux não encontrada: " + session)
    # sh runs claude, then hands the window over the way tmux opens one
    # (default-command through default-shell, or the bare shell).
    shell = tmux("show-options", "-gv", "default-shell", check=False).strip() or os.environ.get("SHELL", "sh")
    then = tmux("show-options", "-gv", "default-command", check=False).strip()
    script = 'shell="$1"; then="$2"; shift 2; "$@"; [ -n "$then" ] && exec "$shell" -c "$then"; exec "$shell"'
    out = tmux("new-window", "-d", "-P", "-F", "#{window_id}\t#{pane_id}", "-t", target["id"] + ":",
               "-n", name, "-c", folder, "-e", "CLAUDE_CONFIG_DIR=" + ACCOUNTS[account],
               "sh", "-c", script, "pill-agent", shell, then, CLAUDE, "--model", model, "--effort", effort,
               "-n", name, issue_prompt(url, title)).strip().split("\t")
    return {"window": out[0], "pane": out[1] if len(out) > 1 else ""}


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "tmux"
    args = sys.argv[2:]
    if cmd == "tmux" and not args:
        out = {"sessions": sessions()}
    elif cmd == "send" and len(args) == 4:
        out = send(*args)
    elif cmd == "new" and len(args) == 8:
        out = new(*args)
    elif cmd == "goto" and len(args) == 1:
        out = {"client": tmuxnav.goto(args[0])}
    else:
        raise Fail("uso: tmux | send <pane> <pid> <url> <title> | "
                   "new <session> <dir> <name> <account> <model> <effort> <url> <title> | goto <target>")
    print(json.dumps(dict(ok=True, **out), separators=(",", ":")))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e) or e.__class__.__name__}))
        sys.exit(0)
