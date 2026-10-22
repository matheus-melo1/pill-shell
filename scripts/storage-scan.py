"""
Storage data for the drawer's Armazenamento route. Read-only: nothing here
deletes anything. Every command prints one JSON line.

  storage-scan.py disks
      physical disks with their partitions (size, fs, label, mountpoint) and,
      for mounted ones, used/free from statvfs.
  storage-scan.py scan [path]
      directory tree of `path` (default /) on its filesystem, from
      `du -x -B1 --max-depth`, as nested {name, path, size, children}; the
      filesystem's used bytes are included so the view can show what the scan
      couldn't read (system dirs without root). Cached per path; pass
      --cached to get the last result instantly when there is one.
  storage-scan.py cleanup
      known reclaimable spots (package/build caches, docker, journal, trash)
      with their size, a description and the command that frees them.
  storage-scan.py big
      largest files on the root filesystem (cached).
"""

import hashlib
import json
import os
import re
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
CACHE = os.environ.get("XDG_CACHE_HOME", HOME + "/.cache") + "/pill-storage"
SCAN_DEPTH_ROOT = 4
SCAN_DEPTH_SUB = 3
BIG_TTL = 1800
MIN_CLEANUP = 50 * 1024 * 1024


def run(cmd, timeout=30, env=None):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                             env=dict(os.environ, LC_ALL="C", **(env or {})))
        return out.stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def cache_path(name):
    os.makedirs(CACHE, exist_ok=True)
    return os.path.join(CACHE, name)


def save(name, obj):
    with open(cache_path(name) + ".tmp", "w") as f:
        json.dump(obj, f, separators=(",", ":"))
    os.replace(cache_path(name) + ".tmp", cache_path(name))


def load(name):
    try:
        with open(cache_path(name)) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def fs_usage(path):
    try:
        st = os.statvfs(path)
    except OSError:
        return None
    total = st.f_blocks * st.f_frsize
    free = st.f_bavail * st.f_frsize
    return {"total": total, "used": total - st.f_bfree * st.f_frsize, "free": free}


# ---- disks ---------------------------------------------------------------

def disks():
    data = json.loads(run(["lsblk", "-J", "-b", "-o",
                           "NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,LABEL,PARTLABEL,TRAN,ROTA"]) or "{}")
    out = []
    for d in data.get("blockdevices", []):
        if d.get("type") != "disk" or d["name"].startswith(("zram", "loop")):
            continue
        parts = []
        for p in d.get("children") or []:
            mounts = [m for m in (p.get("mountpoints") or []) if m]
            mount = mounts[0] if mounts else ""
            part = {
                "name": p["name"],
                "size": int(p["size"]),
                "fs": p.get("fstype") or "",
                "label": p.get("label") or p.get("partlabel") or "",
                "mount": mount,
            }
            if mount:
                u = fs_usage(mount)
                if u:
                    part.update(used=u["used"], free=u["free"])
            parts.append(part)
        out.append({
            "name": d["name"],
            "model": (d.get("model") or "").strip(),
            "size": int(d["size"]),
            "tran": d.get("tran") or "",
            "parts": parts,
        })
    root = fs_usage("/")
    print(json.dumps({"ok": True, "disks": out, "root": root}, separators=(",", ":")))


# ---- scan ----------------------------------------------------------------

def scan(path, cached_only):
    path = os.path.abspath(path)
    key = "scan-" + hashlib.sha1(path.encode()).hexdigest()[:12] + ".json"
    if cached_only:
        c = load(key)
        print(json.dumps(c or {"ok": False, "error": "sem cache"}, separators=(",", ":")))
        return
    depth = SCAN_DEPTH_ROOT if path == "/" else SCAN_DEPTH_SUB
    out = run(["du", "-x", "-B1", "--max-depth=%d" % depth, path], timeout=300)
    sizes = {}
    for line in out.splitlines():
        m = re.match(r"^(\d+)\s+(.*)$", line)
        if m:
            sizes[m.group(2)] = int(m.group(1))
    if path not in sizes:
        print(json.dumps({"ok": False, "error": "não foi possível ler " + path}))
        return

    nodes = {p: {"name": os.path.basename(p) or p, "path": p, "size": s, "children": []}
             for p, s in sizes.items()}
    for p, n in nodes.items():
        if p == path:
            continue
        parent = os.path.dirname(p)
        if parent in nodes:
            nodes[parent]["children"].append(n)
    for n in nodes.values():
        n["children"].sort(key=lambda c: -c["size"])
        n["children"] = n["children"][:60]  # long tails don't fit a treemap anyway
        n["leaf"] = not n["children"]

    fs = fs_usage(path) or {}
    result = {
        "ok": True,
        "path": path,
        "tree": nodes[path],
        "fsUsed": fs.get("used", 0),
        "depth": depth,
        "scannedAt": int(time.time() * 1000),
    }
    save(key, result)
    print(json.dumps(result, separators=(",", ":")))


# ---- cleanup -------------------------------------------------------------

def du_bytes(path):
    out = run(["du", "-s", "-B1", path], timeout=60)
    m = re.match(r"^(\d+)", out)
    return int(m.group(1)) if m else 0


def parse_human(s):
    m = re.match(r"([\d.]+)\s*([KMGT]?)i?B", s.strip(), re.I)
    if not m:
        return 0
    return int(float(m.group(1)) * 1024 ** "BKMGT".index((m.group(2) or "B").upper()))


def cleanup():
    items = []

    def add(key, title, desc, size, cmd, root=False, icon="trash"):
        if size >= MIN_CLEANUP:
            items.append({"key": key, "title": title, "desc": desc, "size": size,
                          "cmd": cmd, "root": root, "icon": icon})

    add("pacman", "Cache de pacotes do pacman",
        "Pacotes baixados em /var/cache/pacman/pkg. Remover tira a opção de downgrade sem baixar de novo.",
        du_bytes("/var/cache/pacman/pkg"), "sudo paccache -rk0", root=True, icon="archive")

    gocache = run(["go", "env", "GOCACHE"], timeout=10).strip()
    if gocache:
        add("go", "Cache de build do Go", "Recompilado sob demanda no próximo build.",
            du_bytes(gocache), "go clean -cache", icon="code")

    add("nuget", "Pacotes do NuGet", "Baixados de novo no próximo restore dos projetos .NET.",
        du_bytes(HOME + "/.nuget/packages"), "dotnet nuget locals all --clear", icon="code")
    add("npm", "Cache do npm", "Baixado de novo quando necessário.",
        du_bytes(HOME + "/.npm/_cacache"), "npm cache clean --force", icon="code")
    for helper in ("paru", "yay"):
        add(helper, "Builds do " + helper, "Clones e pacotes de AUR já compilados em ~/.cache/" + helper + ".",
            du_bytes(HOME + "/.cache/" + helper), "rm -rf ~/.cache/%s/clone" % helper, icon="archive")
    add("pip", "Cache do pip", "Wheels baixados.", du_bytes(HOME + "/.cache/pip"), "pip cache purge", icon="code")
    add("thumbs", "Miniaturas", "Geradas de novo ao abrir as pastas.",
        du_bytes(HOME + "/.cache/thumbnails"), "rm -rf ~/.cache/thumbnails/*", icon="image")
    add("trash", "Lixeira", "Arquivos já apagados.",
        du_bytes(HOME + "/.local/share/Trash"), "gio trash --empty", icon="trash")

    m = re.search(r"take up ([\d.]+\s*[KMGT]?i?B)", run(["journalctl", "--disk-usage"], timeout=10))
    if m and parse_human(m.group(1)) > 300 * 1024 * 1024:
        add("journal", "Logs do systemd (journal)", "Mantém só os 100 MB mais recentes.",
            parse_human(m.group(1)), "sudo journalctl --vacuum-size=100M", root=True, icon="list")

    df = run(["docker", "system", "df", "--format", "{{.Type}}\t{{.Reclaimable}}"], timeout=20)
    reclaim = 0
    for line in df.splitlines():
        parts = line.split("\t")
        if len(parts) == 2:
            reclaim += parse_human(parts[1].split(" ")[0])
    add("docker", "Docker: imagens, containers e volumes sem uso",
        "Remove o que não está em uso por nenhum container ativo (inclui volumes órfãos).",
        reclaim, "docker system prune -a --volumes", icon="archive")

    items.sort(key=lambda i: -i["size"])
    print(json.dumps({"ok": True, "items": items, "total": sum(i["size"] for i in items)},
                     separators=(",", ":")))


# ---- big files -----------------------------------------------------------

def big():
    c = load("big.json")
    if c and time.time() * 1000 - c.get("scannedAt", 0) < BIG_TTL * 1000:
        print(json.dumps(c, separators=(",", ":")))
        return
    out = run(["find", "/", "-xdev", "-type", "f", "-size", "+300M", "-printf", "%s\t%p\n"], timeout=120)
    files = []
    for line in out.splitlines():
        s, _, p = line.partition("\t")
        if s.isdigit():
            files.append({"size": int(s), "path": p})
    files.sort(key=lambda f: -f["size"])
    result = {"ok": True, "files": files[:25], "scannedAt": int(time.time() * 1000)}
    save("big.json", result)
    print(json.dumps(result, separators=(",", ":")))


if __name__ == "__main__":
    cmd = sys.argv[1]
    args = [a for a in sys.argv[2:] if not a.startswith("--")]
    try:
        if cmd == "disks":
            disks()
        elif cmd == "scan":
            scan(args[0] if args else "/", "--cached" in sys.argv)
        elif cmd == "cleanup":
            cleanup()
        elif cmd == "big":
            big()
    except Exception as e:
        print(json.dumps({"ok": False, "error": "%s: %s" % (type(e).__name__, e)}))
