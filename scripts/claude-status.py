"""
Claude Code snapshot for the pill. For each account config dir it lists the
live CLI sessions (registry files under sessions/, filtered to pids that are
still running with the same procStart so orphaned files are dropped) and the
5h / 7d usage limits from the OAuth usage endpoint. Usage is cached per
account for CACHE_TTL seconds so the pill can poll this every few seconds
without hammering the API. The token is never refreshed here (that would
rotate it under the running CLI); a failed fetch keeps the last cached value
and marks it stale. Prints a single JSON line.
"""

import json
import os
import time
import urllib.request

HOME = os.path.expanduser("~")
ACCOUNTS = [("personal", HOME + "/.claude-personal"), ("work", HOME + "/.claude-work")]
CACHE_DIR = os.environ.get("XDG_CACHE_HOME", HOME + "/.cache") + "/pill-claude"
CACHE_TTL = 90
RETRY_TTL = 30
USAGE_URL = "https://api.anthropic.com/api/oauth/usage"


def proc_start(pid):
    try:
        with open("/proc/%d/stat" % pid) as f:
            stat = f.read()
    except OSError:
        return None
    # comm may contain spaces/parens: fields after the last ')' start at field 3
    return stat[stat.rindex(")") + 2:].split()[19]


def sessions(account, root):
    out = []
    d = os.path.join(root, "sessions")
    try:
        names = os.listdir(d)
    except OSError:
        return out
    for n in names:
        if not n.endswith(".json"):
            continue
        try:
            with open(os.path.join(d, n)) as f:
                s = json.load(f)
            pid = int(s["pid"])
        except (OSError, ValueError, KeyError, TypeError):
            continue
        start = proc_start(pid)
        if start is None or (s.get("procStart") and str(s["procStart"]) != start):
            continue
        out.append({
            "account": account,
            "pid": pid,
            "name": s.get("name") or "",
            "cwd": s.get("cwd") or "",
            "status": s.get("status") or "idle",
            "startedAt": s.get("startedAt") or 0,
            "statusSince": s.get("statusUpdatedAt") or s.get("updatedAt") or 0,
            "tmux": s.get("tmux") or "",
        })
    return out


def window(o):
    if not isinstance(o, dict) or o.get("utilization") is None:
        return None, ""
    return float(o["utilization"]), o.get("resets_at") or ""


def fetch_usage(root):
    with open(os.path.join(root, ".credentials.json")) as f:
        oauth = json.load(f)["claudeAiOauth"]
    req = urllib.request.Request(USAGE_URL, headers={
        "Authorization": "Bearer " + oauth["accessToken"],
        "anthropic-beta": "oauth-2025-04-20",
        "Content-Type": "application/json",
    })
    with urllib.request.urlopen(req, timeout=5) as r:
        data = json.load(r)
    five, five_reset = window(data.get("five_hour"))
    seven, seven_reset = window(data.get("seven_day"))
    return {"five": five, "fiveReset": five_reset, "seven": seven, "sevenReset": seven_reset}


def usage(account, root):
    path = os.path.join(CACHE_DIR, "usage-%s.json" % account)
    cached = None
    try:
        with open(path) as f:
            cached = json.load(f)
    except (OSError, ValueError):
        pass
    now = time.time()
    if cached:
        ttl = RETRY_TTL if cached.get("stale") else CACHE_TTL
        if now - cached.get("checkedAt", 0) < ttl:
            return cached
    try:
        fresh = fetch_usage(root)
        fresh["stale"] = False
    except Exception:
        fresh = dict(cached or {"five": None, "fiveReset": "", "seven": None, "sevenReset": ""})
        fresh["stale"] = True
    fresh["checkedAt"] = now
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(fresh, f)
        os.replace(tmp, path)
    except OSError:
        pass
    return fresh


def main():
    all_sessions = []
    accounts = []
    for account, root in ACCOUNTS:
        if not os.path.isdir(root):
            continue
        all_sessions += sessions(account, root)
        u = usage(account, root) if os.path.exists(os.path.join(root, ".credentials.json")) else {}
        accounts.append({
            "name": account,
            "five": u.get("five"),
            "fiveReset": u.get("fiveReset", ""),
            "seven": u.get("seven"),
            "sevenReset": u.get("sevenReset", ""),
            "stale": bool(u.get("stale", True)),
        })
    all_sessions.sort(key=lambda s: (s["status"] != "busy", -s["startedAt"]))
    print(json.dumps({"sessions": all_sessions, "accounts": accounts}, separators=(",", ":")))


if __name__ == "__main__":
    main()
