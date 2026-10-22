"""
PreToolUse hook for the background PR reviews (claude-review.py).

  review-guard.py comment   the review may post one review: a comment or an approval
  review-guard.py none      the review may not write to GitHub at all

The prompt already tells the agent what it may publish; this makes it a hard
rule. It reads the hook payload on stdin and, for Bash calls, blocks (exit 2,
reason on stderr, which Claude sees) anything that requests changes or merges,
and any gh api write (POST/PUT/PATCH/DELETE, fields without -X GET, graphql
mutations), so the only way to publish is `gh pr review --comment|--approve`.
In `none` mode gh pr review/comment and gh issue comment are blocked too.
"""

import json
import re
import sys

ALWAYS = [
    (re.compile(r"\bgh\s+pr\s+review\b[^|;&]*(\s--request-changes\b|\s-r\b)"), "pedir mudanças"),
    (re.compile(r"\bevent[\"']?\s*[=:]\s*[\"']?(APPROVE|REQUEST_CHANGES)\b", re.I),
     "aprovar ou pedir mudanças pela API"),
    (re.compile(r"\bgh\s+pr\s+(merge|close|ready|edit)\b"), "mexer no estado do PR"),
]

NO_POST = [
    (re.compile(r"\bgh\s+(pr|issue)\s+(review|comment)\b"), "publicar no GitHub"),
]

GH_API = re.compile(r"\bgh\s+api\b[^|;&]*")
WRITE_METHOD = re.compile(r"\s(-X|--method)[\s=]*[\"']?(POST|PUT|PATCH|DELETE)\b", re.I)
GET_METHOD = re.compile(r"\s(-X|--method)[\s=]*[\"']?GET\b", re.I)
FIELDS = re.compile(r"\s(-f|-F|--field|--raw-field|--input)\b")


def api_write(cmd):
    """gh api sends POST once it has fields, unless told GET; graphql reads are fine."""
    for m in GH_API.finditer(cmd):
        call = m.group(0)
        if WRITE_METHOD.search(call):
            return True
        if re.search(r"\bgh\s+api\s+graphql\b", call):
            if re.search(r"\bmutation\b", call):
                return True
        elif FIELDS.search(call) and not GET_METHOD.search(call):
            return True
    return False


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "none"
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    if payload.get("tool_name") != "Bash":
        return 0
    cmd = str((payload.get("tool_input") or {}).get("command", ""))
    rules = ALWAYS + (NO_POST if mode != "comment" else [])
    hits = [what for pat, what in rules if pat.search(cmd)]
    if api_write(cmd):
        hits.append("escrever pela API do GitHub")
    if not hits:
        return 0
    allowed = ("um review com gh pr review --approve ou --comment" if mode == "comment"
               else "nada, o resultado fica só no terminal")
    sys.stderr.write("Bloqueado pelo pill: este review não pode %s. Permitido publicar: %s.\n" % (hits[0], allowed))
    return 2


if __name__ == "__main__":
    sys.exit(main())
