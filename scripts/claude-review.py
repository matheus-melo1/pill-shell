"""
Background Claude Code reviews of pull requests, for the pill's PR pane.

  start <pr-url> <account> <model> <effort> <post>   launch a review
  list                                               live review windows
  stop <window-id>                                   kill one
  clear                                              kill every review window
  attach <window-id>                                 show it in your open tmux

Each review runs as an interactive `claude` in its own window of the tmux
session SESSION (created detached, with a plain shell window so it survives
between reviews), so it keeps going in the background and can be attached to
at any time. The window carries @pill_* user options (PR url, account, model,
effort...), which makes tmux itself the record of what is running: `list`
just reads them back.

Nothing is cloned or checked out: claude starts in the fixed, empty RUN_DIR,
which `start` marks as trusted in the account's .claude.json beforehand (so
the workspace-trust question never comes up), and its prompt carries the PR
link. It reads the PR straight from GitHub with
`gh pr view/diff <url>` and `gh api .../contents/<path>?ref=<head sha>` for
whole files and the repo's own conventions.

`attach` never opens a terminal: tmuxnav.goto switches the tmux client you
are using to the review's window and focuses its terminal.

`account` picks the config dir (~/.claude-personal or ~/.claude-work);
`model`/`effort` go to the CLI and `effort` also sets how deep the review
digs; `post` 1 publishes its findings as one review on the PR, an approval
when nothing blocker or major turned up and a comment otherwise; 0 keeps
everything in the terminal. The prompt says so, and review-guard.py runs as a
PreToolUse hook to enforce it: no review ever requests changes or merges, and
with post 0 nothing is written to GitHub. Prints one JSON line; failures are
{"ok": false, "error": ...}.

Env overrides (tests): PILL_REVIEW_SESSION, PILL_REVIEW_RUN_DIR,
PILL_REVIEW_CLAUDE.
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
SESSION = os.environ.get("PILL_REVIEW_SESSION", "claude-reviews")
RUN_DIR = os.environ.get("PILL_REVIEW_RUN_DIR",
                         os.environ.get("XDG_CACHE_HOME", HOME + "/.cache") + "/pill-reviews/run")
CLAUDE = os.environ.get("PILL_REVIEW_CLAUDE", "claude")

ACCOUNTS = {"personal": HOME + "/.claude-personal", "work": HOME + "/.claude-work"}
MODELS = {"opus", "sonnet", "haiku", "fable"}
EFFORTS = {"low", "medium", "high", "xhigh", "max"}
PERMISSION_MODE = "auto"
GUARD = os.path.join(os.path.dirname(os.path.realpath(__file__)), "review-guard.py")

DEPTH = {
    "low": "Passada rápida: aponte só problemas óbvios e de alta confiança.",
    "medium": "Revise o diff com cuidado; aponte só o que tiver boa confiança.",
    "high": "Revise com profundidade: leia o contexto dos arquivos tocados quando precisar.",
    "xhigh": "Seja minucioso: siga chamadas e usos fora do diff para confirmar cada achado.",
    "max": "Seja exaustivo: reporte tudo o que encontrar, inclusive achados incertos (marque-os como tal).",
}

PR_URL = re.compile(r"^https://github\.com/([^/]+)/([^/]+)/pull/(\d+)")
OPTS = ["url", "repo", "number", "account", "model", "effort", "post", "started"]


class Fail(Exception):
    pass


def run(args, timeout=60, check=True):
    out = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if check and out.returncode != 0:
        msg = (out.stderr or out.stdout or "%s falhou" % args[0]).strip().splitlines()
        raise Fail(msg[-1] if msg else "%s falhou" % args[0])
    return out.stdout


def tmux(*args, check=True):
    return run(["tmux", *args], timeout=10, check=check)


def windows():
    """Live review windows of SESSION as dicts of their @pill_* options."""
    fmt = "\t".join(["#{window_id}", "#{pane_dead}"] + ["#{@pill_%s}" % o for o in OPTS])
    out = tmux("list-windows", "-t", "=" + SESSION, "-F", fmt, check=False)
    res = []
    for line in out.splitlines():
        f = line.split("\t")
        if len(f) != 2 + len(OPTS) or not f[2]:
            continue
        w = dict(zip(OPTS, f[2:]))
        w["window"] = f[0]
        w["dead"] = f[1] == "1"
        w["number"] = int(w["number"] or 0)
        w["post"] = w["post"] == "1"
        w["started"] = int(w["started"] or 0)
        res.append(w)
    return res


def ensure_session():
    if subprocess.run(["tmux", "has-session", "-t", "=" + SESSION], capture_output=True).returncode == 0:
        return
    tmux("new-session", "-d", "-s", SESSION, "-n", "home", "-c", HOME)


def ensure_trusted(config_dir):
    """Accept the workspace-trust question for RUN_DIR before claude asks it.

    Several reviews launched together would each stop on it otherwise. Only
    writes when the flag is missing, atomically, so claude's own writes to the
    file are never clobbered with stale data for long.
    """
    path = os.path.join(config_dir, ".claude.json")
    try:
        with open(path) as f:
            cfg = json.load(f)
    except (OSError, ValueError):
        return
    projects = cfg.setdefault("projects", {})
    entry = projects.setdefault(RUN_DIR, {})
    if entry.get("hasTrustDialogAccepted") is True:
        return
    entry["hasTrustDialogAccepted"] = True
    tmp = path + ".pill-tmp"
    with open(tmp, "w") as f:
        json.dump(cfg, f, indent=2)
    os.chmod(tmp, os.stat(path).st_mode & 0o777)
    os.replace(tmp, path)


def guard_settings(post):
    hook = {"type": "command", "command": "python3 %s %s" % (GUARD, "comment" if post else "none")}
    return json.dumps({"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [hook]}]}})


def prompt(url, repo, number, pr, effort, post):
    head = pr["headRefOid"]
    lines = [
        "Faça o code review do PR %s" % url,
        "",
        "%s#%d: \"%s\" (%s -> %s, head %s)." % (repo, number, pr["title"], pr["headRefName"], pr["baseRefName"], head[:10]),
        "Trabalhe direto pelo GitHub, sem clonar nem baixar o repo:",
        "- gh pr view %s --comments   (descrição, discussão)" % url,
        "- gh pr diff %s              (o diff)" % url,
        "- gh api 'repos/%s/contents/<caminho>?ref=%s' -H 'Accept: application/vnd.github.raw'"
        "   (arquivo inteiro na versão do PR, quando o diff não bastar)" % (repo, head),
        "Antes de concluir, leia pelo gh api (na ref do PR) o CLAUDE.md / AGENTS.md e as skills do repo "
        "(.agents/skills, .claude/skills) e confira se o código segue esses padrões: checks verdes não provam aderência.",
        "Profundidade: " + DEPTH[effort],
        "Foque em bugs de correção, segurança, regressões e quebras do padrão do repo. Liste os achados por severidade "
        "(blocker / major / nit) com arquivo:linha e o porquê, e feche com um veredito curto. Escreva em português.",
    ]
    if post:
        lines.append("Ao terminar, publique os achados no PR como um único review, com o veredito no corpo:")
        lines.append("- sem nenhum blocker nem major (só nits ou nada): APROVE, "
                     "gh pr review %s --approve --body-file <arquivo>" % url)
        lines.append("- com algum blocker ou major: só comente, "
                     "gh pr review %s --comment --body-file <arquivo>" % url)
        lines.append("Nunca peça mudanças (--request-changes) nem faça merge. Se o GitHub recusar a aprovação "
                     "(por exemplo, PR seu), publique o mesmo corpo com --comment.")
    else:
        lines.append("NÃO publique nada no GitHub (nada de gh pr review / gh pr comment / escrita pela API): "
                     "o resultado fica só neste terminal.")
    return "\n".join(lines)


def start(url, account, model, effort, post):
    m = PR_URL.match(url)
    if not m:
        raise Fail("URL de PR inválida")
    if account not in ACCOUNTS:
        raise Fail("conta desconhecida: " + account)
    if model not in MODELS:
        raise Fail("modelo desconhecido: " + model)
    if effort not in EFFORTS:
        raise Fail("effort desconhecido: " + effort)
    owner, name, number = m.group(1), m.group(2), int(m.group(3))
    repo = owner + "/" + name
    url = "https://github.com/%s/pull/%d" % (repo, number)
    post = post == "1"

    for w in windows():
        if w["url"] == url:
            if not w["dead"]:
                raise Fail("já tem um review rodando para este PR")
            # A finished-and-dead window for this PR is replaced by the new run.
            tmux("kill-window", "-t", w["window"], check=False)

    pr = json.loads(run(["gh", "pr", "view", url, "--json",
                         "title,state,baseRefName,headRefName,headRefOid"], timeout=30))
    if pr.get("state") != "OPEN":
        raise Fail("o PR não está aberto")

    os.makedirs(RUN_DIR, exist_ok=True)
    ensure_trusted(ACCOUNTS[account])
    label = "%s#%d" % (name, number)
    argv = [CLAUDE, "--model", model, "--effort", effort, "-n", "review " + label,
            "--permission-mode", PERMISSION_MODE, "--settings", guard_settings(post),
            prompt(url, repo, number, pr, effort, post)]

    ensure_session()
    win = tmux("new-window", "-d", "-P", "-F", "#{window_id}", "-t", "=" + SESSION + ":",
               "-n", label, "-c", RUN_DIR, "-e", "CLAUDE_CONFIG_DIR=" + ACCOUNTS[account], *argv).strip()
    # A window whose claude dies (bad model, auth) stays to show why; claude
    # takes far longer to boot than this call.
    tmux("set-option", "-w", "-t", win, "remain-on-exit", "on")
    opts = {"url": url, "repo": repo, "number": number, "account": account, "model": model,
            "effort": effort, "post": "1" if post else "0", "started": int(time.time() * 1000)}
    for k, v in opts.items():
        tmux("set-option", "-w", "-t", win, "@pill_" + k, str(v))
    return {"window": win, "name": "review " + label}


def stop(window):
    if not any(w["window"] == window for w in windows()):
        raise Fail("review não encontrado")
    tmux("kill-window", "-t", window, check=False)
    return {}


def clear():
    """Kill every review window (running ones too); the plain shell window stays."""
    ws = windows()
    for w in ws:
        tmux("kill-window", "-t", w["window"], check=False)
    return {"cleared": len(ws)}


def attach(window):
    if not any(w["window"] == window for w in windows()):
        raise Fail("review não encontrado")
    return {"client": tmuxnav.goto(window, "tmux attach -t " + SESSION)}


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    if cmd == "start" and len(sys.argv) == 7:
        out = start(*sys.argv[2:7])
    elif cmd == "stop" and len(sys.argv) == 3:
        out = stop(sys.argv[2])
    elif cmd == "attach" and len(sys.argv) == 3:
        out = attach(sys.argv[2])
    elif cmd == "clear" and len(sys.argv) == 2:
        out = clear()
    elif cmd == "list":
        out = {"reviews": windows()}
    else:
        raise Fail("uso: start <url> <account> <model> <effort> <post> | stop <window> | clear | attach <window> | list")
    print(json.dumps(dict(ok=True, **out), separators=(",", ":")))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e) or e.__class__.__name__}))
        sys.exit(0)
