"""
Bridge for the drawer's AI chat, speaking the OpenAI-compatible API of the
active provider. The only piece that touches the API key, which lives in
KEY_DIR/<provider>.key (one line, chmod 600) and never passes through QML,
argv or logs. The active provider is $PILL_AI_PROVIDER, else the name in
KEY_DIR/ai-provider, else the first in PROVIDERS that has a key file.

  ai-chat.py chat     reads one JSON line on stdin:
                        {"model": "...", "messages": [{"role", "content",
                         "images": [abs paths]}]}
                      streams the reply as JSON lines on stdout:
                        {"t":"delta","text":"..."}   text as it arrives
                        {"t":"done","model":"...","usage":{...}}
                        {"t":"error","msg":"..."}
  ai-chat.py models   prints {"models":[{id,name,provider,providerName,alias,target,
                      ctx,image,variable,prompt,completion,created}]}
                      from /models, cached for MODELS_TTL seconds.
  ai-chat.py account  prints the OpenRouter balance and free-model quota:
                      {"credits", "usage", "freeUsed", "freeLimit"} ({} for
                      other providers)
  ai-chat.py status   prints {"hasKey", "keyFile", "provider", "label",
                      "defaultModel"}

Images are inlined as base64 data URLs in OpenAI-style content parts.
"""

import base64
import json
import mimetypes
import os
import re
import sys
import time
import urllib.error
import urllib.request

HOME = os.path.expanduser("~")
KEY_DIR = os.environ.get("XDG_DATA_HOME", HOME + "/.local/share") + "/pill"
CACHE = os.environ.get("XDG_CACHE_HOME", HOME + "/.cache") + "/pill-ai"
MODELS_TTL = 6 * 3600
OPENROUTER = "https://openrouter.ai/api/v1"

PROVIDERS = {
    "codecraft": {"label": "CodeCraft", "api": "https://codecraftapi.com/v1",
                  "default": "claude-sonnet-5"},
    "openrouter": {"label": "OpenRouter", "api": OPENROUTER,
                   "default": "anthropic/claude-sonnet-5.5"},
}


def provider():
    name = os.environ.get("PILL_AI_PROVIDER")
    if name in PROVIDERS:
        return name
    try:
        with open(KEY_DIR + "/ai-provider") as f:
            name = f.read().strip()
        if name in PROVIDERS:
            return name
    except OSError:
        pass
    for name in PROVIDERS:
        if os.path.isfile(key_file(name)):
            return name
    return "openrouter"


def key_file(name=None):
    return "%s/%s.key" % (KEY_DIR, name or provider())


API = PROVIDERS[provider()]["api"]


def emit(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def key():
    try:
        with open(key_file()) as f:
            k = f.read().strip()
        return k or None
    except OSError:
        return None


def request(path, body=None, stream=False):
    headers = {
        "Authorization": "Bearer " + (key() or ""),
        "HTTP-Referer": "https://github.com/quickshell-pill",
        "X-Title": "Pill Drawer",
        # Cloudflare in front of some providers 403s urllib's default agent
        "User-Agent": "pill-drawer/1.0",
    }
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    req = urllib.request.Request(API + path, data=data, headers=headers)
    return urllib.request.urlopen(req, timeout=120 if stream else 20)


def api_error(e):
    try:
        payload = json.loads(e.read().decode())
        msg = payload.get("error", {}).get("message") or str(payload)
    except Exception:
        msg = str(e)
    if e.code == 401:
        msg = "Chave inválida ou expirada (401)"
    elif e.code == 402:
        msg = "Sem créditos em %s (402): esse modelo é pago. Escolha um do grupo Grátis ou adicione créditos." % PROVIDERS[provider()]["label"]
    elif e.code == 403 or "insufficient" in msg.lower() or "billing" in msg.lower():
        msg = "%s recusou: %s" % (PROVIDERS[provider()]["label"], msg)
    elif e.code == 429:
        msg = "Limite de requisições atingido (429), tente de novo em instantes"
    return msg


def image_part(path):
    mime = mimetypes.guess_type(path)[0] or "image/png"
    with open(path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    return {"type": "image_url", "image_url": {"url": "data:%s;base64,%s" % (mime, b64)}}


def to_api(messages):
    out = []
    for m in messages:
        imgs = [p for p in (m.get("images") or []) if os.path.isfile(p)]
        if imgs and m["role"] == "user":
            parts = [{"type": "text", "text": m.get("content") or ""}]
            parts += [image_part(p) for p in imgs]
            out.append({"role": "user", "content": parts})
        else:
            out.append({"role": m["role"], "content": m.get("content") or ""})
    return out


def chat():
    if not key():
        emit({"t": "error", "msg": "Nenhuma API key em " + key_file()})
        return
    req = json.loads(sys.stdin.readline())
    body = {"model": req["model"], "messages": to_api(req["messages"]), "stream": True}
    try:
        resp = request("/chat/completions", body, stream=True)
    except urllib.error.HTTPError as e:
        emit({"t": "error", "msg": api_error(e)})
        return
    except Exception as e:
        emit({"t": "error", "msg": "Falha de conexão: %s" % e})
        return

    model, usage = req["model"], None
    for raw in resp:
        line = raw.decode("utf-8", "replace").strip()
        if not line.startswith("data:"):
            continue  # SSE comments (": OPENROUTER PROCESSING") and blanks
        data = line[5:].strip()
        if data == "[DONE]":
            break
        try:
            chunk = json.loads(data)
        except ValueError:
            continue
        if "error" in chunk:
            emit({"t": "error", "msg": chunk["error"].get("message", "erro do provedor")})
            return
        model = chunk.get("model") or model
        usage = chunk.get("usage") or usage
        for choice in chunk.get("choices") or []:
            text = (choice.get("delta") or {}).get("content")
            if text:
                emit({"t": "delta", "text": text})
    emit({"t": "done", "model": model, "usage": usage})


def models():
    path = "%s/models-%s.json" % (CACHE, provider())
    try:
        if time.time() - os.path.getmtime(path) < MODELS_TTL:
            with open(path) as f:
                print(f.read())
            return
    except OSError:
        pass
    try:
        out = openrouter_models() if API == OPENROUTER else plain_models()
    except Exception as e:
        print(json.dumps({"models": [], "error": str(e)}))
        return
    # one label per provider: the vendor most of its model names use
    votes = {}
    for m in out:
        if m["providerName"]:
            v = votes.setdefault(m["provider"], {})
            v[m["providerName"]] = v.get(m["providerName"], 0) + 1
    for m in out:
        v = votes.get(m["provider"])
        m["providerName"] = max(v, key=v.get) if v else m["provider"].replace("-", " ").title()
    text = json.dumps({"models": out}, separators=(",", ":"))
    os.makedirs(CACHE, exist_ok=True)
    with open(path, "w") as f:
        f.write(text)
    print(text)


def openrouter_catalog():
    """OpenRouter's public model list (no key needed), cached."""
    path = CACHE + "/openrouter-catalog.json"
    try:
        if time.time() - os.path.getmtime(path) < MODELS_TTL:
            with open(path) as f:
                return json.load(f)
    except (OSError, ValueError):
        pass
    req = urllib.request.Request(OPENROUTER + "/models", headers={"User-Agent": "pill-drawer/1.0"})
    data = json.load(urllib.request.urlopen(req, timeout=20))["data"]
    os.makedirs(CACHE, exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, separators=(",", ":"))
    return data


def openrouter_models():
    out = []
    for m in openrouter_catalog():
        arch = m.get("architecture") or {}
        if ":batch" in m["id"] or "text" not in (arch.get("output_modalities") or ["text"]):
            continue  # batch variants can't stream; skip models that don't answer in text
        pricing = m.get("pricing") or {}
        prompt = float(pricing.get("prompt") or 0)
        name = m.get("name") or m["id"]
        vendor, _, short = name.partition(": ")
        out.append({
            "id": m["id"],
            "name": short or name,
            "provider": m["id"].lstrip("~").split("/")[0],
            "providerName": vendor if short else "",
            "alias": m["id"].startswith("~"),
            "target": (m.get("alias_target") or {}).get("name", ""),
            "ctx": m.get("context_length") or 0,
            "image": "image" in (arch.get("input_modalities") or []),
            # routers report -1: the price depends on the model they pick
            "variable": prompt < 0,
            "prompt": max(prompt, 0) * 1e6,
            "completion": max(float(pricing.get("completion") or 0), 0) * 1e6,
            "created": m.get("created") or 0,
        })
    return out


# id prefix -> OpenRouter vendor slug, for providers whose ids are bare
VENDORS = [("claude", "anthropic"), ("gpt", "openai"), ("o1", "openai"), ("o3", "openai"),
           ("o4", "openai"), ("gemini", "google"), ("gemma", "google"), ("grok", "x-ai"),
           ("deepseek", "deepseek"), ("qwen", "qwen"), ("glm", "z-ai"), ("kimi", "moonshotai"),
           ("seed", "bytedance-seed"), ("muse", "meta"), ("llama", "meta-llama"),
           ("mistral", "mistralai"), ("minimax", "minimax")]


def natural(s):
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", s)]


def plain_models():
    """Providers whose /models only lists ids: borrow name, context and image
    support from OpenRouter's catalog when the same model is there. Prices are
    the provider's own and unknown here, so they're left out."""
    data = json.load(request("/models"))["data"]
    try:
        catalog = {m["id"].split("/", 1)[-1]: m for m in openrouter_catalog()
                   if not m["id"].startswith("~") and ":" not in m["id"]}
    except Exception:
        catalog = {}
    out = []
    for m in sorted(data, key=lambda m: natural(m["id"])):
        mid = m["id"]
        vendor = next((v for p, v in VENDORS if mid.lower().startswith(p)), mid.split("-")[0])
        ref = catalog.get(mid) or {}
        arch = ref.get("architecture") or {}
        rname = ref.get("name") or ""
        rvendor, _, rshort = rname.partition(": ")
        out.append({
            "id": mid,
            "name": rshort or rname or pretty(mid),
            "provider": vendor,
            "providerName": rvendor if rshort else "",
            "alias": False,
            "target": "",
            "ctx": ref.get("context_length") or 0,
            # unknown when OpenRouter doesn't have it: let the user try
            "image": ("image" in (arch.get("input_modalities") or [])) if ref else None,
            "variable": False,
            "prompt": None,
            "completion": None,
            "created": 0,
        })
    # higher version sorts as newer inside each vendor
    for i, m in enumerate(out):
        m["created"] = i
    return out


def pretty(mid):
    words = []
    for w in mid.replace("_", "-").split("-"):
        if w.lower() in ("gpt", "glm"):
            words.append(w.upper())
        elif re.match(r"^[a-z]\d", w):
            words.append(w.upper())
        else:
            words.append(w[:1].upper() + w[1:])
    return " ".join(words)


def account():
    if API != OPENROUTER or not key():
        print("{}")
        return
    try:
        credits = json.load(request("/credits"))["data"]
        info = json.load(request("/key"))["data"]
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        return
    free = info.get("free_model_daily_requests") or {}
    print(json.dumps({
        "credits": credits.get("total_credits", 0),
        "usage": credits.get("total_usage", 0),
        "freeUsed": free.get("used", 0),
        "freeLimit": free.get("limit", 0),
    }))


def status():
    p = provider()
    print(json.dumps({"hasKey": key() is not None, "keyFile": key_file(), "provider": p,
                      "label": PROVIDERS[p]["label"], "defaultModel": PROVIDERS[p]["default"]}))


if __name__ == "__main__":
    {"chat": chat, "models": models, "account": account, "status": status}[sys.argv[1]]()
