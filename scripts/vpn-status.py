"""
OpenVPN snapshot for the pill drawer. Reads the systemd unit state (active,
enabled for boot, since when), which interface the default route to the
internet leaves through (tun0 means full tunnel), the tunnel address and
traffic counters, the server from the client config when readable, and one
ping round-trip to 1.1.1.1. Needs no privileges. Prints a single JSON line.
"""

import json
import re
import subprocess
import time

UNIT = "openvpn-client@cliente"
CONF = "/etc/openvpn/client/cliente.conf"
TUN = "tun0"


def run(*cmd, timeout=4):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                             env={"LC_ALL": "C", "PATH": "/usr/bin:/bin"})
        return out.stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def unit_props():
    props = {}
    for line in run("systemctl", "show", UNIT, "-p", "ActiveState,SubState,UnitFileState,ActiveEnterTimestampMonotonic").splitlines():
        k, _, v = line.partition("=")
        props[k] = v
    return props


def read_int(path):
    try:
        with open(path) as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return 0


def server():
    try:
        with open(CONF) as f:
            for line in f:
                m = re.match(r"\s*remote\s+(\S+)(?:\s+(\d+))?", line)
                if m:
                    return m.group(1) + (":" + m.group(2) if m.group(2) else "")
    except OSError:
        pass
    return ""


def main():
    p = unit_props()
    active = p.get("ActiveState") == "active"

    route = run("ip", "route", "get", "1.1.1.1")
    m = re.search(r"\bdev (\S+)", route)
    dev = m.group(1) if m else ""

    addr = run("ip", "-4", "-o", "addr", "show", "dev", TUN)
    m = re.search(r"inet (\S+)", addr)
    tun_ip = m.group(1).split("/")[0] if m else ""

    since = 0
    mono = p.get("ActiveEnterTimestampMonotonic", "0")
    if active and mono.isdigit() and int(mono) > 0:
        since = int((time.time() - (time.monotonic() - int(mono) / 1e6)) * 1000)

    ping = run("ping", "-c1", "-W2", "1.1.1.1", timeout=4)
    m = re.search(r"time=([0-9.]+)", ping)

    print(json.dumps({
        "active": active,
        "state": p.get("ActiveState", ""),
        "enabled": p.get("UnitFileState") == "enabled",
        "dev": dev,
        "tunneled": dev == TUN,
        "tunIp": tun_ip,
        "rx": read_int("/sys/class/net/%s/statistics/rx_bytes" % TUN),
        "tx": read_int("/sys/class/net/%s/statistics/tx_bytes" % TUN),
        "since": since,
        "server": server(),
        "latency": float(m.group(1)) if m else None,
    }, separators=(",", ":")))


if __name__ == "__main__":
    main()
