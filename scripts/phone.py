"""
KDE Connect bridge for the pill drawer's phone route, over the session bus
(dbus-python). The device is the first paired one, preferring a reachable
device, so no id is hard-coded.

  phone.py status          one JSON line: device, battery, cellular signal,
                           notification privacy and the phone's active
                           notifications (app, title, text, icon, dismissable,
                           whether it takes an inline reply)
  phone.py dismiss ID      dismiss a phone notification
  phone.py reply ID TEXT   inline reply to a notification that supports it
  phone.py ring            make the phone ring (find my phone)
  phone.py clipboard       push this computer's clipboard to the phone
  phone.py share-pick      pick a file with kdialog and send it to the phone
  phone.py privacy on|off  on = stop receiving phone notifications on this
                           computer (the PC-side notifications plugin is
                           disabled in kdeconnectd, so nothing reaches the
                           desktop, the toast or the history); off reloads
                           the plugins so the phone resends what is active

Every command prints {"ok": true} or {"ok": false, "error": ...}; status
failures let the pill keep its last snapshot.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

import dbus

SERVICE = "org.kde.kdeconnect"
ROOT = "/modules/kdeconnect"
IFACE = "org.kde.kdeconnect"
NOTIF_PLUGIN = "kdeconnect_notifications"


def out(obj):
    print(json.dumps(obj, ensure_ascii=False))


def prop(bus, path, iface, name, default=None):
    try:
        obj = bus.get_object(SERVICE, path)
        return dbus.Interface(obj, "org.freedesktop.DBus.Properties").Get(iface, name)
    except dbus.DBusException:
        return default


def call(bus, path, iface, method, *args):
    obj = bus.get_object(SERVICE, path)
    return getattr(dbus.Interface(obj, iface), method)(*args)


def pick_device(bus):
    """Path of the paired device to use, reachable first, or None."""
    ids = [str(i) for i in call(bus, ROOT, IFACE + ".daemon", "devices", False, True)]
    if not ids:
        return None
    for i in ids:
        if prop(bus, f"{ROOT}/devices/{i}", IFACE + ".device", "isReachable", False):
            return f"{ROOT}/devices/{i}"
    return f"{ROOT}/devices/{ids[0]}"


def notifications(bus, dev):
    base = dev + "/notifications"
    try:
        ids = [str(i) for i in call(bus, base, IFACE + ".device.notifications", "activeNotifications")]
    except dbus.DBusException:
        return []
    iface = IFACE + ".device.notifications.notification"
    items = []
    for nid in ids:
        path = f"{base}/{nid}"
        try:
            p = dbus.Interface(bus.get_object(SERVICE, path), "org.freedesktop.DBus.Properties").GetAll(iface)
        except dbus.DBusException:
            continue
        # The icon payload lands after the notification; an empty file would
        # fail to decode and stay cached, so report it only once it has data.
        icon = str(p.get("iconPath", "")) if p.get("hasIcon", False) else ""
        try:
            if icon and os.path.getsize(icon) == 0:
                icon = ""
        except OSError:
            icon = ""
        items.append({
            "id": nid,
            "key": str(p.get("internalId", nid)),
            "app": str(p.get("appName", "")),
            "title": str(p.get("title", "")),
            "text": str(p.get("text", "")),
            "icon": icon,
            "dismissable": bool(p.get("dismissable", False)),
            "canReply": len(str(p.get("replyId", ""))) > 0,
        })
    return items


def status(bus):
    dev = pick_device(bus)
    if dev is None:
        out({"ok": True, "present": False})
        return
    d = IFACE + ".device"
    reachable = bool(prop(bus, dev, d, "isReachable", False))
    privacy = not bool(call(bus, dev, d, "isPluginEnabled", NOTIF_PLUGIN))
    snap = {
        "ok": True,
        "present": True,
        "reachable": reachable,
        "name": str(prop(bus, dev, d, "name", "")),
        "privacy": privacy,
        "battery": -1,
        "charging": False,
        "network": "",
        "signal": -1,
        "notifications": [],
    }
    if reachable:
        snap["battery"] = int(prop(bus, dev + "/battery", d + ".battery", "charge", -1))
        snap["charging"] = bool(prop(bus, dev + "/battery", d + ".battery", "isCharging", False))
        snap["network"] = str(prop(bus, dev + "/connectivity_report", d + ".connectivity_report", "cellularNetworkType", ""))
        snap["signal"] = int(prop(bus, dev + "/connectivity_report", d + ".connectivity_report", "cellularNetworkStrength", -1))
        if not privacy:
            snap["notifications"] = notifications(bus, dev)
    out(snap)


def act(bus, cmd, args):
    dev = pick_device(bus)
    if dev is None:
        raise RuntimeError("Nenhum celular pareado")
    d = IFACE + ".device"
    if cmd == "dismiss":
        call(bus, f"{dev}/notifications/{args[0]}", d + ".notifications.notification", "dismiss")
    elif cmd == "reply":
        call(bus, f"{dev}/notifications/{args[0]}", d + ".notifications.notification", "sendReply", args[1])
    elif cmd == "ring":
        call(bus, dev + "/findmyphone", d + ".findmyphone", "ring")
    elif cmd == "clipboard":
        call(bus, dev + "/clipboard", d + ".clipboard", "sendClipboard")
    elif cmd == "share-pick":
        r = subprocess.run(["kdialog", "--title", "Enviar para o celular", "--getopenfilename", os.path.expanduser("~")],
                           capture_output=True, text=True)
        path = r.stdout.strip()
        if r.returncode != 0 or not path:
            out({"ok": True, "cancelled": True})
            return
        call(bus, dev + "/share", d + ".share", "shareUrl", Path(path).as_uri())
    elif cmd == "privacy":
        off = args[0] != "on"
        call(bus, dev, d, "setPluginEnabled", NOTIF_PLUGIN, off)
        if off:
            # A re-enabled plugin only asks the phone for its current
            # notifications on load; they come back flagged silent (no popup).
            call(bus, dev, d, "reloadPlugins")
    else:
        raise RuntimeError("comando desconhecido: " + cmd)
    out({"ok": True})


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    try:
        bus = dbus.SessionBus()
        if cmd == "status":
            status(bus)
        else:
            act(bus, cmd, sys.argv[2:])
    except (dbus.DBusException, RuntimeError, IndexError, OSError) as e:
        msg = e.get_dbus_message() if isinstance(e, dbus.DBusException) else str(e)
        out({"ok": False, "error": msg or type(e).__name__})


if __name__ == "__main__":
    main()
