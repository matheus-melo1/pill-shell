"""
Shared tmux navigation for the pill scripts. goto(target) shows a window or
pane (an "@N" / "%N" id) in the terminal you are using: it never opens a
terminal, it switches the most recently active tmux client to the target's
session, selects the window (and pane), then focuses that client's terminal
window in Hyprland (best effort). With no client attached it raises, saying
how to attach.
"""

import json
import subprocess


class NavError(Exception):
    pass


def tmux(*args, check=True):
    out = subprocess.run(["tmux", *args], capture_output=True, text=True, timeout=10)
    if check and out.returncode != 0:
        msg = (out.stderr or "tmux falhou").strip().splitlines()
        raise NavError(msg[-1] if msg else "tmux falhou")
    return out.stdout


def parent_pid(pid):
    try:
        with open("/proc/%d/stat" % pid) as f:
            stat = f.read()
    except OSError:
        return 0
    return int(stat[stat.rindex(")") + 2:].split()[1])


def focus_terminal(pid):
    """Focus the Hyprland window whose process is an ancestor of `pid`."""
    out = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=5)
    owners = {c["pid"] for c in json.loads(out.stdout)}
    while pid > 1 and pid not in owners:
        pid = parent_pid(pid)
    if pid > 1:
        subprocess.run(["hyprctl", "dispatch", "focuswindow", "pid:%d" % pid],
                       capture_output=True, timeout=5)


def goto(target, attach_hint="tmux attach"):
    session = tmux("display-message", "-p", "-t", target, "#{session_id}", check=False).strip()
    if not session:
        raise NavError("janela não encontrada no tmux")
    out = tmux("list-clients", "-F", "#{client_activity}\t#{client_name}\t#{client_pid}", check=False)
    clients = [line.split("\t") for line in out.splitlines() if line.count("\t") == 2]
    if not clients:
        raise NavError("nenhum tmux aberto: rode " + attach_hint)
    _, name, pid = max(clients, key=lambda c: int(c[0] or 0))
    tmux("select-window", "-t", target)
    if target.startswith("%"):
        tmux("select-pane", "-t", target)
    tmux("switch-client", "-c", name, "-t", session)
    try:
        focus_terminal(int(pid))
    except Exception:
        pass
    return name
