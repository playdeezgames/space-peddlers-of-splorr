#!/usr/bin/env python3
"""Generate src/game/rsrc_gen.odin from the original Space Trader resources.

Reads reference/rsrc/Merchant.rsrc (the Constructor resource fork, Mac resource
map format) and reference/MerchantRsc.h (the Constructor header: names and
object attributes). Python stdlib only. Run from the repo root:

    python3 -I tools/gen_rsrc.py

Text is decoded as cp1252 (Palm OS character set) and written as UTF-8.
"""
import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RSRC = os.path.join(ROOT, "reference", "rsrc", "Merchant.rsrc")
HDR = os.path.join(ROOT, "reference", "MerchantRsc.h")
GFX = os.path.join(ROOT, "reference", "MerchantGraphics.h")
OUT = os.path.join(ROOT, "src", "game", "rsrc_gen.odin")


def load_rsrc(path):
    d = open(path, "rb").read()
    doff, moff, _dlen, mlen = struct.unpack(">IIII", d[:16])
    m = d[moff:moff + mlen]
    tl, _nl = struct.unpack(">HH", m[24:28])
    n = struct.unpack(">H", m[tl:tl + 2])[0] + 1
    res = {}
    for i in range(n):
        t, c, o = struct.unpack(">4sHH", m[tl + 2 + i * 8:tl + 10 + i * 8])
        t = t.decode("mac_roman")
        for j in range(c + 1):
            rid, _no, a = struct.unpack(">hhI", m[tl + o + j * 12:tl + o + j * 12 + 8])
            off = a & 0xFFFFFF
            ln = struct.unpack(">I", d[doff + off:doff + off + 4])[0]
            res[(t, rid)] = d[doff + off + 4:doff + off + 4 + ln]
    return res


def cstr(b, pos):
    end = b.index(b"\0", pos)
    return b[pos:end].decode("cp1252"), end + 1


def u16(b, pos):
    return struct.unpack(">H", b[pos:pos + 2])[0]


def s16(b, pos):
    return struct.unpack(">h", b[pos:pos + 2])[0]


def parse_header(path):
    """Return (defines in order, attrs by name, section type by name)."""
    defines = []
    attrs = {}
    section = {}
    cur = None
    for line in open(path, encoding="cp1252"):
        line = line.rstrip("\r\n")
        m = re.match(r"//\s*Resource: (\S+) (\d+)", line)
        if m:
            cur = m.group(1)
            continue
        m = re.match(r"#define\s+(\w+)\s+(-?\d+)\s*(?://\s*(.*))?$", line)
        if not m:
            continue
        name, val, comment = m.group(1), int(m.group(2)), m.group(3) or ""
        defines.append((name, val))
        section[name] = cur
        a = {}
        cm = re.match(r"\((.*)\)\s*$", comment)
        if cm:
            for part in cm.group(1).split(", "):
                if " = " in part:
                    k, v = part.split(" = ", 1)
                    a[k.strip()] = v.strip()
        attrs[name] = a
    return defines, attrs, section


def odin_str(s):
    out = ['"']
    for ch in s:
        if ch == '"':
            out.append('\\"')
        elif ch == "\\":
            out.append("\\\\")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ord(ch) < 32:
            out.append("\\x%02x" % ord(ch))
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


FONTS = {"Standard": "Standard", "Bold": "Bold", "Large": "Large", "Symbol": "Symbol",
         "Symbol 11": "Symbol", "Symbol 7": "Symbol", "LED": "Standard", "Large Bold": "Large_Bold"}
KINDS = {"tTTL": "Title", "tLBL": "Label", "tBTN": "Button", "tFLD": "Field", "tCBX": "Checkbox",
         "tLST": "List", "tPUT": "Popup_Trigger", "tPUL": "Popup_List", "tGDT": "Gadget",
         "tFBM": "Bitmap", "tGSI": "Graffiti", "tREP": "Repeat_Button", "tPBN": "Push_Button",
         "tSLT": "Selector"}
ALERT_TYPES = ["Information", "Confirmation", "Warning", "Error"]


def main():
    res = load_rsrc(RSRC)
    defines, attrs, section = parse_header(HDR)
    gfx_defines, _ga, _gs = parse_header(GFX)
    by_id_in_form = {}  # (form id, object id) -> name
    form_of_name = {}
    cur_form = None
    for name, val in defines:
        if section[name] == "tFRM":
            if name.endswith("Form") and attrs[name].get("Width") is not None and "Modal" in attrs[name]:
                cur_form = val
            else:
                by_id_in_form[(cur_form, val)] = name
                form_of_name[name] = cur_form

    unknown = set()
    objs = []
    forms = []
    pool = []
    for (t, fid) in sorted(k for k in res if k[0] == "tFRM"):
        b = res[(t, fid)]
        x, y, w, h = s16(b, 0), s16(b, 2), s16(b, 4), s16(b, 6)
        modal = u16(b, 10) != 0
        help_id, menu_id, def_btn = u16(b, 20), u16(b, 22), u16(b, 24)
        count = u16(b, 30)
        title = ""
        first = len(objs)
        for i in range(count):
            oid = u16(b, 32 + i * 6)
            okind = b[34 + i * 6:38 + i * 6].decode("mac_roman")
            ob = res.get((okind, oid))
            name = by_id_in_form.get((fid, oid), "")
            a = attrs.get(name, {})
            o = {"kind": KINDS.get(okind), "id": oid, "x": 0, "y": 0, "w": 0, "h": 0, "font": "Standard",
                 "text": "", "usable": True, "frame": True, "bold_frame": False, "editable": False,
                 "max_chars": 0, "numeric": False, "group": 0, "selected": False, "items_first": 0,
                 "items_count": 0, "visible_items": 0, "popup_list": 0, "bitmap": 0, "name": name}
            if o["kind"] is None:
                unknown.add(okind)
                continue
            if okind == "tTTL":
                title, _ = cstr(ob, 0)
                continue
            if okind in ("tGSI", "tPUL"):
                if okind == "tPUL":
                    o["id"] = u16(ob, 0)
                    o["popup_list"] = u16(ob, 2)
                else:
                    o["x"], o["y"] = s16(ob, 0), s16(ob, 2)
                objs.append(o)
                continue
            if okind == "tFBM":
                o["x"], o["y"], o["bitmap"] = s16(ob, 0), s16(ob, 2), u16(ob, 4)
                o["usable"] = u16(ob, 6) != 0
                o["id"] = o["bitmap"]
                objs.append(o)
                continue
            # objects that start with id x y [w h]
            o["id"] = u16(ob, 0)
            o["x"], o["y"] = s16(ob, 2), s16(ob, 4)
            if okind == "tLBL":
                o["usable"] = u16(ob, 6) != 0
                o["font"] = ["Standard", "Bold", "Large", "Symbol", "Symbol", "Symbol", "LED", "Large_Bold"][ob[8]] if ob[8] < 8 else "Standard"
                o["text"], _ = cstr(ob, 9)
            else:
                o["w"], o["h"] = s16(ob, 6), s16(ob, 8)
                if okind in ("tBTN", "tREP", "tPBN", "tSLT"):
                    o["usable"] = u16(ob, 10) != 0
                    o["frame"] = a.get("Frame", "1") == "1"
                    o["bold_frame"] = a.get("Non-bold Frame", "1") == "0"
                    o["group"] = int(a.get("Group ID", "0"))
                    fnt = ob[18]
                    o["font"] = ["Standard", "Bold", "Large", "Symbol", "Symbol", "Symbol", "LED", "Large_Bold"][fnt] if fnt < 8 else "Standard"
                    o["text"], _ = cstr(ob, 19)
                elif okind == "tCBX":
                    o["usable"] = u16(ob, 10) != 0
                    o["selected"] = u16(ob, 12) != 0
                    o["group"] = int(a.get("Group ID", "0"))
                    o["text"], _ = cstr(ob, 16)
                elif okind == "tPUT":
                    o["usable"] = u16(ob, 10) != 0
                    o["text"], _ = cstr(ob, 15)
                elif okind == "tFLD":
                    o["usable"] = a.get("Usable", "1") == "1"
                    o["editable"] = a.get("Editable", "1") == "1"
                    o["max_chars"] = int(a.get("Max Characters", "0"))
                    o["numeric"] = a.get("Numeric", "0") == "1"
                    o["font"] = FONTS.get(a.get("Font", "Standard"), "Standard")
                elif okind == "tLST":
                    o["usable"] = a.get("Usable", "1") == "1"
                    # id x y w, two flag words, visible items, item count, items
                    o["h"] = 0
                    o["visible_items"] = u16(ob, 12)
                    n_items = u16(ob, 14)
                    o["h"] = o["visible_items"] * 11
                    pos = 16
                    o["items_first"] = len(pool)
                    for _ in range(n_items):
                        s, pos = cstr(ob, pos)
                        pool.append(s)
                    o["items_count"] = n_items
                    o["font"] = FONTS.get(a.get("Font", "Standard"), "Standard")
                elif okind == "tGDT":
                    o["usable"] = u16(ob, 10) != 0
            if "Font" in a and okind != "tLBL":
                o["font"] = FONTS.get(a["Font"], o["font"])
            if "Usable" in a:
                o["usable"] = a["Usable"] == "1"
            objs.append(o)
        forms.append({"id": fid, "x": x, "y": y, "w": w, "h": h, "modal": modal, "help": help_id,
                      "menu": menu_id, "default": def_btn, "title": title, "first": first,
                      "count": len(objs) - first})

    alerts = []
    for (t, aid) in sorted(k for k in res if k[0] == "Talt"):
        b = res[(t, aid)]
        atype, help_id, nbtn, dbtn = u16(b, 0), u16(b, 2), u16(b, 4), u16(b, 6)
        pos = 8
        title, pos = cstr(b, pos)
        msg, pos = cstr(b, pos)
        first = len(pool)
        for _ in range(nbtn):
            s, pos = cstr(b, pos)
            pool.append(s)
        alerts.append({"id": aid, "type": ALERT_TYPES[atype] if atype < 4 else "Information", "help": help_id,
                       "default": dbtn, "title": title, "msg": msg, "first": first, "count": nbtn})

    strings = []
    for (t, sid) in sorted(k for k in res if k[0] == "tSTR"):
        s, _ = cstr(res[(t, sid)] + b"\0", 0)
        strings.append((sid, s))

    stls = []
    for (t, sid) in sorted(k for k in res if k[0] == "tSTL"):
        b = res[(t, sid)]
        prefix, pos = cstr(b, 0)
        n = u16(b, pos)
        pos += 2
        first = len(pool)
        for _ in range(n):
            s, pos = cstr(b, pos)
            pool.append(prefix + s)
        stls.append((sid, first, n))

    menus = []
    for (t, mid) in sorted(k for k in res if k[0] == "MENU"):
        b = res[(t, mid)]
        pos = 14
        tlen = b[pos]
        title = b[pos + 1:pos + 1 + tlen].decode("cp1252")
        pos += 1 + tlen
        items = []
        while pos < len(b):
            ln = b[pos]
            if ln == 0:
                break
            text = b[pos + 1:pos + 1 + ln].decode("cp1252")
            pos += 1 + ln
            key = chr(b[pos + 1]) if b[pos + 1] else ""
            pos += 4
            items.append((text, key))
        menus.append((mid, title, items))
    mbars = []
    for (t, bid) in sorted(k for k in res if k[0] == "MBAR"):
        b = res[(t, bid)]
        n = u16(b, 0)
        mbars.append((bid, [u16(b, 2 + i * 2) for i in range(n)]))

    if unknown:
        print("unknown object kinds:", sorted(unknown), file=sys.stderr)
        sys.exit(1)

    L = []
    L.append("// GENERATED by tools/gen_rsrc.py from reference/rsrc/Merchant.rsrc and")
    L.append("// reference/MerchantRsc.h (Space Trader 1.2.2, Pieter Spronck, GPL). Do not edit.")
    L.append("package game")
    L.append("")
    seen = set()
    for name, val in defines + gfx_defines:
        if name in seen:
            continue
        seen.add(name)
        L.append("%s :: %d" % (name, val))
    L.append("")
    L.append("RSRC_POOL := [?]string{")
    for s in pool:
        L.append("\t%s," % odin_str(s))
    L.append("}")
    L.append("")
    L.append("OBJ_DEFS := [?]Obj_Def{")
    for o in objs:
        L.append("\t{kind=.%s, id=%d, x=%d, y=%d, w=%d, h=%d, font=.%s, text=%s, usable=%s, frame=%s, bold_frame=%s, "
                 "editable=%s, max_chars=%d, numeric=%s, group=%d, selected=%s, items_first=%d, items_count=%d, "
                 "visible_items=%d, popup_list=%d, bitmap=%d}, // %s" % (
                     o["kind"], o["id"], o["x"], o["y"], o["w"], o["h"], o["font"], odin_str(o["text"]),
                     str(o["usable"]).lower(), str(o["frame"]).lower(), str(o["bold_frame"]).lower(),
                     str(o["editable"]).lower(), o["max_chars"], str(o["numeric"]).lower(), o["group"],
                     str(o["selected"]).lower(), o["items_first"], o["items_count"], o["visible_items"],
                     o["popup_list"], o["bitmap"], o["name"]))
    L.append("}")
    L.append("")
    L.append("FORM_DEFS := [?]Form_Def{")
    for f in forms:
        L.append("\t{id=%d, x=%d, y=%d, w=%d, h=%d, modal=%s, help_id=%d, menu_id=%d, default_button=%d, title=%s, first=%d, count=%d}," % (
            f["id"], f["x"], f["y"], f["w"], f["h"], str(f["modal"]).lower(), f["help"], f["menu"], f["default"],
            odin_str(f["title"]), f["first"], f["count"]))
    L.append("}")
    L.append("")
    L.append("ALERT_DEFS := [?]Alert_Def{")
    for a in alerts:
        L.append("\t{id=%d, kind=.%s, help_id=%d, default_button=%d, title=%s, message=%s, first=%d, count=%d}," % (
            a["id"], a["type"], a["help"], a["default"], odin_str(a["title"]), odin_str(a["msg"]), a["first"], a["count"]))
    L.append("}")
    L.append("")
    L.append("STRING_DEFS := [?]String_Def{")
    for sid, s in strings:
        L.append("\t{id=%d, text=%s}," % (sid, odin_str(s)))
    L.append("}")
    L.append("")
    L.append("STRING_LIST_DEFS := [?]String_List_Def{")
    for sid, first, n in stls:
        L.append("\t{id=%d, first=%d, count=%d}," % (sid, first, n))
    L.append("}")
    L.append("")
    L.append("MENU_ITEM_DEFS := [?]Menu_Item_Def{")
    mitems = []
    for mid, title, items in menus:
        start = len(mitems)
        for text, key in items:
            mitems.append((text, key))
            L.append("\t{text=%s, key=%s}," % (odin_str(text), "'%s'" % key if key else "0"))
        menus[menus.index((mid, title, items))] = (mid, title, start, len(items))
    L.append("}")
    L.append("")
    L.append("MENU_DEFS := [?]Menu_Def{")
    for mid, title, start, n in menus:
        L.append("\t{id=%d, title=%s, first=%d, count=%d}," % (mid, odin_str(title), start, n))
    L.append("}")
    L.append("")
    L.append("MENU_BAR_DEFS := [?]Menu_Bar_Def{")
    for bid, ms in mbars:
        L.append("\t{id=%d, menus={%s}, count=%d}," % (bid, ", ".join(str(x) for x in ms + [0] * (4 - len(ms))), len(ms)))
    L.append("}")
    L.append("")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "w", encoding="utf-8").write("\n".join(L))
    print("wrote %s: %d forms, %d objects, %d alerts, %d strings, %d string lists, %d menus" % (
        os.path.relpath(OUT, ROOT), len(forms), len(objs), len(alerts), len(strings), len(stls), len(menus)))


if __name__ == "__main__":
    main()
