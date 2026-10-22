"""
GitHub snapshot for the pill, through the logged-in `gh` CLI (no token of its
own). One GraphQL call fetches the open PRs waiting on the viewer's review and
the viewer's own open PRs (draft/review/mergeable state plus the head commit's
CI rollup) and the issues assigned to the viewer on the team board whose
Status is one of BOARD_STATUSES (filtered server-side by the project's item
query), with priority, type and estimate. Actions runs are read for the repos the viewer touched recently
(push/PR events in the last day, plus repos of PRs updated in the last three
days), capped at MAX_RUN_REPOS and fetched in parallel; only queued/running
runs and runs that finished in the last RECENT_SEC are kept. Prints a single
JSON line; on failure prints {"ok": false, "error": ...} so the pill can keep
its last snapshot.
"""

import json
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

BOARD_ORG = "Tecware-Bizpik"
BOARD_NUMBER = 4
BOARD_STATUSES = ["In Progress", "Ready"]

MAX_RUN_REPOS = 6
RECENT_SEC = 15 * 60
ACTIVE = {"queued", "in_progress", "waiting", "requested", "pending"}

QUERY = """
query {
  board: organization(login: "%(org)s") {
    projectV2(number: %(number)d) {
      url
      items(first: 60, query: "assignee:@me is:open status:%(statuses)s") {
        nodes {
          status: fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
          prio: fieldValueByName(name: "Priority") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
          kind: fieldValueByName(name: "Tipo") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
          estimate: fieldValueByName(name: "Estimate") { ... on ProjectV2ItemFieldNumberValue { number } }
          content { ... on Issue { title url number updatedAt repository { nameWithOwner } } }
        }
      }
    }
  }
  viewer {
    login avatarUrl
    pullRequests(states: OPEN, first: 20, orderBy: {field: UPDATED_AT, direction: DESC}) {
      nodes {
        title url number isDraft reviewDecision mergeable updatedAt
        repository { nameWithOwner }
        commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
      }
    }
  }
  reviews: search(query: "is:pr is:open review-requested:@me archived:false", type: ISSUE, first: 20) {
    issueCount
    nodes { ... on PullRequest { title url number isDraft createdAt author { login } repository { nameWithOwner } } }
  }
}
""" % {
    "org": BOARD_ORG,
    "number": BOARD_NUMBER,
    "statuses": ",".join('\\"%s\\"' % st if " " in st else st for st in BOARD_STATUSES),
}


def gh(*args, timeout=20):
    out = subprocess.run(["gh", *args], capture_output=True, text=True, timeout=timeout)
    if out.returncode != 0:
        raise RuntimeError((out.stderr or "gh failed").strip().splitlines()[-1])
    return json.loads(out.stdout)


def ts(iso):
    return datetime.fromisoformat(iso.replace("Z", "+00:00"))


def runs_for(repo, now):
    try:
        data = gh("api", "repos/%s/actions/runs?per_page=10" % repo, timeout=15)
    except Exception:
        return []
    out = []
    for r in data.get("workflow_runs", []):
        active = r.get("status") in ACTIVE
        if not active:
            done = r.get("updated_at")
            if not done or (now - ts(done)).total_seconds() > RECENT_SEC:
                continue
        out.append({
            "repo": repo,
            "name": r.get("name") or r.get("display_title") or "",
            "title": r.get("display_title") or "",
            "branch": r.get("head_branch") or "",
            "status": r.get("status") or "",
            "conclusion": r.get("conclusion") or "",
            "url": r.get("html_url") or "",
            "startedAt": r.get("run_started_at") or r.get("created_at") or "",
            "updatedAt": r.get("updated_at") or "",
        })
    return out


def main():
    now = datetime.now(timezone.utc)
    data = gh("api", "graphql", "-f", "query=" + QUERY)["data"]
    login = data["viewer"]["login"]

    reviews = []
    for n in data["reviews"]["nodes"]:
        if not n:
            continue
        reviews.append({
            "repo": n["repository"]["nameWithOwner"],
            "title": n["title"],
            "url": n["url"],
            "number": n["number"],
            "isDraft": n["isDraft"],
            "author": (n.get("author") or {}).get("login", ""),
            "createdAt": n["createdAt"],
        })

    mine = []
    for n in data["viewer"]["pullRequests"]["nodes"]:
        commits = n["commits"]["nodes"]
        rollup = commits[0]["commit"]["statusCheckRollup"] if commits else None
        mine.append({
            "repo": n["repository"]["nameWithOwner"],
            "title": n["title"],
            "url": n["url"],
            "number": n["number"],
            "isDraft": n["isDraft"],
            "review": n["reviewDecision"] or "",
            "mergeable": n["mergeable"] or "",
            "ci": (rollup or {}).get("state", ""),
            "updatedAt": n["updatedAt"],
        })

    board = ((data.get("board") or {}).get("projectV2")) or {}
    issues = []
    for n in (board.get("items") or {}).get("nodes", []):
        c = n.get("content") or {}
        if not c.get("url"):
            continue
        issues.append({
            "status": (n.get("status") or {}).get("name", ""),
            "priority": (n.get("prio") or {}).get("name", ""),
            "kind": (n.get("kind") or {}).get("name", ""),
            "estimate": (n.get("estimate") or {}).get("number"),
            "repo": c["repository"]["nameWithOwner"],
            "title": c["title"],
            "url": c["url"],
            "number": c["number"],
            "updatedAt": c["updatedAt"],
        })
    rank = {st: i for i, st in enumerate(BOARD_STATUSES)}
    issues.sort(key=lambda i: i["updatedAt"], reverse=True)
    issues.sort(key=lambda i: (rank.get(i["status"], 99), i["priority"] or "P9"))

    repos = []
    try:
        events = gh("api", "users/%s/events?per_page=50" % login, timeout=15)
    except Exception:
        events = []
    for e in events:
        if e.get("type") in ("PushEvent", "PullRequestEvent", "CreateEvent") \
                and (now - ts(e["created_at"])) < timedelta(days=1):
            repos.append(e["repo"]["name"])
    for p in mine:
        if (now - ts(p["updatedAt"])) < timedelta(days=3):
            repos.append(p["repo"])
    repos = list(dict.fromkeys(repos))[:MAX_RUN_REPOS]

    runs = []
    with ThreadPoolExecutor(max_workers=MAX_RUN_REPOS) as pool:
        for chunk in pool.map(lambda r: runs_for(r, now), repos):
            runs += chunk
    runs.sort(key=lambda r: r["startedAt"], reverse=True)
    runs.sort(key=lambda r: r["status"] not in ACTIVE)

    print(json.dumps({
        "ok": True,
        "login": login,
        "avatar": data["viewer"]["avatarUrl"],
        "boardUrl": board.get("url", ""),
        "issues": issues,
        "reviewCount": data["reviews"]["issueCount"],
        "reviews": reviews,
        "mine": mine,
        "runs": runs,
    }, separators=(",", ":")))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e)}))
        sys.exit(0)
