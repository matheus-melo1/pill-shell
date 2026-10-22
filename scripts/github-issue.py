"""
Issue detail and board edits for the drawer's GitHub route, through the
logged-in `gh` CLI. Every command prints one JSON line; failures print
{"ok": false, "error": ...}.

  github-issue.py detail <issue-url>
      issue, comments, sub-issues, linked PRs and the team-board item with its
      field values, plus the board's editable single-select options.
  github-issue.py set <item-id> <field> <value>
      sets a board field: single-select by option name, Estimate as a number;
      an empty value clears it.
  github-issue.py comment <issue-or-pr-id>      body on stdin
  github-issue.py close <issue-id> | reopen <issue-id>

  github-issue.py pr-detail <pr-url>
      PR, CI checks of the head commit, reviews and pending reviewers, files,
      issues it closes, comments and the repo's allowed merge methods.
  github-issue.py review <pr-id> APPROVE|REQUEST_CHANGES|COMMENT   body on stdin
  github-issue.py merge <pr-id> MERGE|SQUASH|REBASE
  github-issue.py ready <pr-id> | draft <pr-id>
  github-issue.py close-pr <pr-id> | reopen-pr <pr-id>

Board field/option ids are cached for FIELDS_TTL seconds.
"""

import json
import os
import subprocess
import sys
import time

BOARD_ORG = "Tecware-Bizpik"
BOARD_NUMBER = 4
CACHE = os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")) + "/pill-github"
FIELDS_TTL = 3600

DETAIL = """
query($url: URI!) {
  resource(url: $url) {
    ... on Issue {
      id number title url state stateReason body createdAt updatedAt
      author { login avatarUrl }
      repository { nameWithOwner }
      labels(first: 20) { nodes { name color } }
      assignees(first: 10) { nodes { login avatarUrl } }
      parent { number title url state }
      subIssuesSummary { total completed percentCompleted }
      subIssues(first: 30) { nodes { number title url state } }
      closedByPullRequestsReferences(first: 10, includeClosedPrs: true) { nodes { number title url state isDraft } }
      comments(last: 30) { totalCount nodes { id body createdAt author { login avatarUrl } } }
      projectItems(first: 10) { nodes { id project { number }
        fieldValues(first: 30) { nodes {
          ... on ProjectV2ItemFieldSingleSelectValue { name field { ... on ProjectV2FieldCommon { name } } }
          ... on ProjectV2ItemFieldNumberValue { number field { ... on ProjectV2FieldCommon { name } } }
          ... on ProjectV2ItemFieldTextValue { text field { ... on ProjectV2FieldCommon { name } } }
          ... on ProjectV2ItemFieldDateValue { date field { ... on ProjectV2FieldCommon { name } } }
          ... on ProjectV2ItemFieldIterationValue { title field { ... on ProjectV2FieldCommon { name } } }
        } } } }
    }
  }
}
"""

PR_DETAIL = """
query($url: URI!) {
  resource(url: $url) {
    ... on PullRequest {
      id number title url state isDraft body createdAt updatedAt viewerDidAuthor
      mergeable mergeStateStatus reviewDecision additions deletions changedFiles
      headRefName baseRefName
      author { login avatarUrl }
      repository { nameWithOwner mergeCommitAllowed squashMergeAllowed rebaseMergeAllowed }
      labels(first: 20) { nodes { name color } }
      reviewRequests(first: 10) { nodes { requestedReviewer { ... on User { login avatarUrl } ... on Team { name } } } }
      latestOpinionatedReviews(first: 10) { nodes { state submittedAt author { login avatarUrl } } }
      commits(last: 1) { nodes { commit { oid statusCheckRollup { state contexts(first: 50) { nodes {
        ... on CheckRun { name status conclusion detailsUrl }
        ... on StatusContext { context state targetUrl } } } } } } }
      files(first: 40) { totalCount nodes { path additions deletions changeType } }
      closingIssuesReferences(first: 10) { nodes { number title url state } }
      comments(last: 30) { totalCount nodes { id body createdAt author { login avatarUrl } } }
    }
  }
}
"""

FIELDS = """
query {
  organization(login: "%s") { projectV2(number: %d) { id
    fields(first: 50) { nodes {
      ... on ProjectV2FieldCommon { id name dataType }
      ... on ProjectV2SingleSelectField { options { id name color } }
    } }
  } }
}
""" % (BOARD_ORG, BOARD_NUMBER)


class Fail(Exception):
    pass


def gql(query, **vars):
    # The request goes as JSON on stdin so variables keep their types (gh's -F
    # sends floats as strings, which a Float! variable rejects).
    out = subprocess.run(["gh", "api", "graphql", "--input", "-"],
                         input=json.dumps({"query": query, "variables": vars}),
                         capture_output=True, text=True, timeout=25)
    try:
        data = json.loads(out.stdout or "{}")
    except ValueError:
        data = {}
    if data.get("errors"):
        raise Fail(data["errors"][0].get("message", "erro do GitHub"))
    if out.returncode != 0:
        raise Fail((out.stderr or "gh falhou").strip().splitlines()[-1])
    return data["data"]


def board():
    path = CACHE + "/fields.json"
    try:
        if time.time() - os.path.getmtime(path) < FIELDS_TTL:
            with open(path) as f:
                return json.load(f)
    except (OSError, ValueError):
        pass
    p = gql(FIELDS)["organization"]["projectV2"]
    out = {"id": p["id"], "fields": {}}
    for f in p["fields"]["nodes"]:
        if f and f.get("id"):
            out["fields"][f["name"]] = {
                "id": f["id"],
                "type": f["dataType"],
                "options": f.get("options") or [],
            }
    os.makedirs(CACHE, exist_ok=True)
    with open(path, "w") as f:
        json.dump(out, f)
    return out


def detail(url):
    i = gql(DETAIL, url=url)["resource"]
    if not i:
        raise Fail("Issue não encontrada")
    item = None
    for it in i["projectItems"]["nodes"]:
        if it["project"]["number"] == BOARD_NUMBER:
            fields = {}
            for v in it["fieldValues"]["nodes"]:
                if not v or not v.get("field"):
                    continue
                val = next((v[k] for k in ("name", "number", "text", "date", "title") if k in v), None)
                fields[v["field"]["name"]] = val
            item = {"id": it["id"], "fields": fields}
    b = board()
    options = {name: [o["name"] for o in f["options"]]
               for name, f in b["fields"].items() if f["type"] == "SINGLE_SELECT"}
    return {
        "ok": True,
        "id": i["id"],
        "number": i["number"],
        "title": i["title"],
        "url": i["url"],
        "state": i["state"],
        "stateReason": i.get("stateReason") or "",
        "body": i["body"] or "",
        "createdAt": i["createdAt"],
        "updatedAt": i["updatedAt"],
        "author": i["author"] or {"login": "ghost", "avatarUrl": ""},
        "repo": i["repository"]["nameWithOwner"],
        "labels": i["labels"]["nodes"],
        "assignees": i["assignees"]["nodes"],
        "parent": i["parent"],
        "subSummary": i["subIssuesSummary"],
        "subIssues": i["subIssues"]["nodes"],
        "prs": i["closedByPullRequestsReferences"]["nodes"],
        "commentCount": i["comments"]["totalCount"],
        "comments": i["comments"]["nodes"],
        "item": item,
        "options": options,
    }


def set_field(item_id, name, value):
    b = board()
    f = b["fields"].get(name)
    if not f:
        raise Fail("Campo desconhecido: " + name)
    if value == "":
        gql("""mutation($p: ID!, $i: ID!, $f: ID!) {
            clearProjectV2ItemFieldValue(input: {projectId: $p, itemId: $i, fieldId: $f}) { clientMutationId } }""",
            p=b["id"], i=item_id, f=f["id"])
        return {"ok": True}
    if f["type"] == "SINGLE_SELECT":
        opt = next((o for o in f["options"] if o["name"] == value), None)
        if not opt:
            raise Fail("Opção inválida para %s: %s" % (name, value))
        gql("""mutation($p: ID!, $i: ID!, $f: ID!, $o: String!) {
            updateProjectV2ItemFieldValue(input: {projectId: $p, itemId: $i, fieldId: $f,
              value: {singleSelectOptionId: $o}}) { clientMutationId } }""",
            p=b["id"], i=item_id, f=f["id"], o=opt["id"])
    elif f["type"] == "NUMBER":
        gql("""mutation($p: ID!, $i: ID!, $f: ID!, $n: Float!) {
            updateProjectV2ItemFieldValue(input: {projectId: $p, itemId: $i, fieldId: $f,
              value: {number: $n}}) { clientMutationId } }""",
            p=b["id"], i=item_id, f=f["id"], n=float(value))
    else:
        raise Fail("Campo %s não é editável aqui" % name)
    return {"ok": True}


def comment(issue_id):
    body = sys.stdin.read().strip()
    if not body:
        raise Fail("Comentário vazio")
    gql("""mutation($s: ID!, $b: String!) {
        addComment(input: {subjectId: $s, body: $b}) { clientMutationId } }""", s=issue_id, b=body)
    return {"ok": True}


def close(issue_id):
    gql("""mutation($i: ID!) { closeIssue(input: {issueId: $i, stateReason: COMPLETED}) { clientMutationId } }""", i=issue_id)
    return {"ok": True}


def reopen(issue_id):
    gql("""mutation($i: ID!) { reopenIssue(input: {issueId: $i}) { clientMutationId } }""", i=issue_id)
    return {"ok": True}


def check_state(c):
    """Normalise a CheckRun / StatusContext to success|failure|pending|neutral."""
    if "context" in c:
        st = (c.get("state") or "").upper()
        return {"SUCCESS": "success", "FAILURE": "failure", "ERROR": "failure"}.get(st, "pending")
    if (c.get("status") or "").upper() != "COMPLETED":
        return "pending"
    concl = (c.get("conclusion") or "").upper()
    if concl == "SUCCESS":
        return "success"
    if concl in ("FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE"):
        return "failure"
    return "neutral"


def pr_detail(url):
    p = gql(PR_DETAIL, url=url)["resource"]
    if not p:
        raise Fail("PR não encontrado")
    commit = p["commits"]["nodes"][0]["commit"] if p["commits"]["nodes"] else {}
    rollup = commit.get("statusCheckRollup") or {}
    checks = []
    for c in ((rollup.get("contexts") or {}).get("nodes") or []):
        if not c:
            continue
        checks.append({
            "name": c.get("name") or c.get("context") or "check",
            "state": check_state(c),
            "url": c.get("detailsUrl") or c.get("targetUrl") or "",
        })
    order = {"failure": 0, "pending": 1, "neutral": 2, "success": 3}
    checks.sort(key=lambda c: order[c["state"]])
    requested = []
    for n in p["reviewRequests"]["nodes"]:
        r = n.get("requestedReviewer") or {}
        if r:
            requested.append({"login": r.get("login") or r.get("name") or "?", "avatarUrl": r.get("avatarUrl") or ""})
    repo = p["repository"]
    methods = [m for m, ok in (("SQUASH", repo["squashMergeAllowed"]), ("MERGE", repo["mergeCommitAllowed"]),
                               ("REBASE", repo["rebaseMergeAllowed"])) if ok]
    return {
        "ok": True,
        "kind": "pr",
        "id": p["id"],
        "number": p["number"],
        "title": p["title"],
        "url": p["url"],
        "state": p["state"],
        "isDraft": p["isDraft"],
        "mine": p["viewerDidAuthor"],
        "body": p["body"] or "",
        "createdAt": p["createdAt"],
        "updatedAt": p["updatedAt"],
        "author": p["author"] or {"login": "ghost", "avatarUrl": ""},
        "repo": repo["nameWithOwner"],
        "head": p["headRefName"],
        "base": p["baseRefName"],
        "mergeable": p["mergeable"],
        "mergeState": p["mergeStateStatus"],
        "reviewDecision": p["reviewDecision"] or "",
        "additions": p["additions"],
        "deletions": p["deletions"],
        "changedFiles": p["changedFiles"],
        "labels": p["labels"]["nodes"],
        "reviews": p["latestOpinionatedReviews"]["nodes"],
        "requested": requested,
        "ci": rollup.get("state") or "",
        "checks": checks,
        "files": p["files"]["nodes"],
        "fileCount": p["files"]["totalCount"],
        "closes": p["closingIssuesReferences"]["nodes"],
        "commentCount": p["comments"]["totalCount"],
        "comments": p["comments"]["nodes"],
        "mergeMethods": methods,
    }


def review(pr_id, event):
    if event not in ("APPROVE", "REQUEST_CHANGES", "COMMENT"):
        raise Fail("Tipo de review inválido")
    body = sys.stdin.read().strip()
    if event != "APPROVE" and not body:
        raise Fail("Esse tipo de review precisa de um comentário")
    gql("""mutation($p: ID!, $e: PullRequestReviewEvent!, $b: String) {
        addPullRequestReview(input: {pullRequestId: $p, event: $e, body: $b}) { clientMutationId } }""",
        p=pr_id, e=event, b=body or None)
    return {"ok": True}


def merge(pr_id, method):
    if method not in ("MERGE", "SQUASH", "REBASE"):
        raise Fail("Método de merge inválido")
    gql("""mutation($p: ID!, $m: PullRequestMergeMethod!) {
        mergePullRequest(input: {pullRequestId: $p, mergeMethod: $m}) { clientMutationId } }""", p=pr_id, m=method)
    return {"ok": True}


def ready(pr_id):
    gql("""mutation($p: ID!) { markPullRequestReadyForReview(input: {pullRequestId: $p}) { clientMutationId } }""", p=pr_id)
    return {"ok": True}


def draft(pr_id):
    gql("""mutation($p: ID!) { convertPullRequestToDraft(input: {pullRequestId: $p}) { clientMutationId } }""", p=pr_id)
    return {"ok": True}


def close_pr(pr_id):
    gql("""mutation($p: ID!) { closePullRequest(input: {pullRequestId: $p}) { clientMutationId } }""", p=pr_id)
    return {"ok": True}


def reopen_pr(pr_id):
    gql("""mutation($p: ID!) { reopenPullRequest(input: {pullRequestId: $p}) { clientMutationId } }""", p=pr_id)
    return {"ok": True}


if __name__ == "__main__":
    cmd, args = sys.argv[1], sys.argv[2:]
    try:
        result = {"detail": detail, "set": set_field, "comment": comment,
                  "close": close, "reopen": reopen, "pr-detail": pr_detail,
                  "review": review, "merge": merge, "ready": ready, "draft": draft,
                  "close-pr": close_pr, "reopen-pr": reopen_pr}[cmd](*args)
    except Fail as e:
        result = {"ok": False, "error": str(e)}
    except Exception as e:
        result = {"ok": False, "error": "%s: %s" % (type(e).__name__, e)}
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
