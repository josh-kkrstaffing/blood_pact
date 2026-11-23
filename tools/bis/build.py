#!/usr/bin/env python3
"""Build Modules/BiSData.lua from tools/bis/wowhead.txt (rows copied from Wowhead's WoW Forever guides).

Score rule (Blood Pact's own, the guides give labels not numbers):
  any label with "BiS" or the overview-table pick = 1, Great = 0.75, Good = 0.5, Option / Situational = 0.25,
  then divided by the best label in that slot so the first row is always 1.
Specs with no readable guide list keep their old auto-ranked list from tools/bis/legacy/ and are flagged.
"""
import collections, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CLASSES = ["WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"]
SPECS = {
    "WARRIOR": ["Arms", "Fury", "Protection"], "PALADIN": ["Holy", "Protection", "Retribution"],
    "HUNTER": ["Beast Mastery", "Marksmanship", "Survival"], "ROGUE": ["Assassination", "Combat", "Subtlety"],
    "PRIEST": ["Discipline", "Holy", "Shadow"], "SHAMAN": ["Elemental", "Enhancement", "Restoration"],
    "MAGE": ["Arcane", "Fire", "Frost"], "WARLOCK": ["Affliction", "Demonology", "Destruction"],
    "DRUID": ["Balance", "Feral (Bear)", "Feral (Cat)", "Restoration"],
}
CLASS_NAME = {"WARRIOR": "Warrior", "PALADIN": "Paladin", "HUNTER": "Hunter", "ROGUE": "Rogue", "PRIEST": "Priest",
              "SHAMAN": "Shaman", "MAGE": "Mage", "WARLOCK": "Warlock", "DRUID": "Druid"}
LEGACY_WHY = {
    ("WARRIOR", "Fury"): "Wowhead's Fury list could not be read yet",
    ("PALADIN", "Retribution"): "Wowhead has not published a Retribution pre-raid list yet",
    ("ROGUE", "Assassination"): "Wowhead has not published an Assassination pre-raid list yet",
    ("PRIEST", "Discipline"): "Wowhead has not published a Discipline pre-raid list yet",
}
ARMOR = ["Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet"]
INV = {"Head": [1], "Neck": [2], "Shoulder": [3], "Back": [15], "Chest": [5], "Wrist": [9], "Hands": [10], "Waist": [6],
       "Legs": [7], "Feet": [8], "Ring 1": [11, 12], "Ring 2": [11, 12], "Trinket 1": [13, 14], "Trinket 2": [13, 14],
       "Main hand": [16], "Off hand": [17], "Two-hand": [16], "Ranged / Relic": [18]}
CANON = {"hand": "Hands", "hands": "Hands", "shoulders": "Shoulder", "main hand": "Main hand", "off hand": "Off hand",
         "two-hand": "Two-hand", "ranged": "Ranged / Relic", "wand": "Ranged / Relic", "relic": "Ranged / Relic",
         "idol": "Ranged / Relic", "totem": "Ranged / Relic", "libram": "Ranged / Relic"}


def weight(label):
    l = label.lower()
    if "bis" in l or l == "set": return 1.0
    if "great" in l: return 0.75
    if "good" in l: return 0.5
    return 0.25


def note_for(label):
    m = re.search(r"\((.+)\)", label)
    words = m.group(1) if m else re.sub(r"(?i)\b(bis|great|good|option|optional)\b", "", label).strip(" ,")
    return words[:1].upper() + words[1:] if words else ""


def parse_item(raw):
    """'A=B' -> other faction's name; 'X of {P,Q}' -> either suffix counts."""
    name, also = raw.strip(), []
    if "=" in name:
        name, other = [x.strip() for x in name.split("=", 1)]
        also.append(other)
    m = re.match(r"(.+ of )\{(.+)\}$", name)
    if m:
        opts = [o.strip() for o in m.group(2).split(",")]
        name = m.group(1) + opts[0]
        also += [m.group(1) + o for o in opts[1:]]
    return name, also


def load(path):
    specs, cur = collections.OrderedDict(), None
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        line = line.rstrip("\n")
        if not line.strip() or line.startswith("#"): continue
        if line.startswith("@"):
            cls, key, label, author, updated, url = line[1:].split("|")
            cur = specs[(cls, key)] = {"label": label, "by": author, "asof": updated, "url": url,
                                       "rows": collections.OrderedDict()}
            continue
        parts = line.split("|")
        if len(parts) != 4 or cur is None: sys.exit("%s:%d bad row: %s" % (path, n, line))
        slot, label, item, how = [p.strip() for p in parts]
        slot = CANON.get(slot.lower(), slot)
        name, also = parse_item(item)
        rows = cur["rows"].setdefault(slot, [])
        if any(r["name"] == name for r in rows): continue
        rows.append({"name": name, "also": also, "how": how, "w": weight(label), "note": note_for(label)})
    return specs


def scored(rows, limit=4):
    rows = sorted(rows, key=lambda r: -r["w"])[:limit]          # stable: page order inside a rank
    top = rows[0]["w"]
    return [dict(r, score=round(min(1.0, r["w"] / top), 2)) for r in rows]


def pair(rows, which):
    """Rings and trinkets: slot 1 leads with the best pick, slot 2 with the second; the rest back both up."""
    rows = sorted(rows, key=lambda r: -r["w"])
    if len(rows) <= which: return None
    return scored([rows[which]] + rows[2:], 4)


def build_spec(spec):
    R, slots = spec["rows"], []
    def add(label, items):
        if items: slots.append({"slot": label, "inv": INV[label], "items": items})
    for s in ARMOR:
        add(s, scored(R[s]) if s in R else None)
    for s in ("Ring", "Trinket"):
        if s in R:
            add(s + " 1", pair(R[s], 0)); add(s + " 2", pair(R[s], 1))
    one, two = R.get("Main hand", []), R.get("Two-hand", [])
    if one or "Off hand" in R:
        merged = [dict(r) for r in one]
        for r in two:
            if not any(m["name"] == r["name"] for m in merged):
                merged.append(dict(r, two=True, note=("Two-hander: also covers the off hand" + ("; " + r["note"] if r["note"] else ""))))
        add("Main hand", scored(merged, 5))
        add("Off hand", scored(R["Off hand"]) if "Off hand" in R else None)
    elif two:
        add("Two-hand", scored(two))
    add("Ranged / Relic", scored(R["Ranged / Relic"]) if "Ranged / Relic" in R else None)
    return slots


def q(s): return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    specs = load(os.path.join(HERE, "wowhead.txt"))
    today = sys.argv[1] if len(sys.argv) > 1 else max(s["asof"] for s in specs.values())
    L = ["-- Blood Pact: pre-raid BiS lists for every spec. GENERATED by tools/bis/build.py; don't edit by hand.",
         "-- Source: the named authors' WoW Forever class guides on Wowhead (see list.by / list.url), read " + today + ".",
         "-- Score: a guide's BiS picks = 1, Great = 0.75, Good = 0.5, Option = 0.25, relative to the slot's best.",
         "-- Horde names first; 'also' lists the other faction's name or another accepted random suffix.",
         "-- list.old = no readable guide list yet, so the earlier auto-ranked list is kept and flagged.",
         "local _, ns = ...", "ns.BiSData = ns.BiSData or {}", "ns.BiSUpdated = " + q(today), ""]
    counts = collections.Counter()
    for cls in CLASSES:
        L.append("ns.BiSData.%s = {" % cls)
        for key in SPECS[cls]:
            if (cls, key) in specs:
                sp = specs[(cls, key)]
                slots = build_spec(sp)
                if not 16 <= len(slots) <= 17: sys.exit("%s %s has %d slots" % (cls, key, len(slots)))
                L.append("    [%s] = { label = %s, guides = 1, by = %s, asof = %s, url = %s, slots = {"
                         % (q(key), q(sp["label"]), q(sp["by"]), q(sp["asof"]), q(sp["url"])))
                for s in slots:
                    L.append("        { slot = %s, inv = { %s }, items = {" % (q(s["slot"]), ", ".join(map(str, s["inv"]))))
                    for it in s["items"]:
                        f = ["name = " + q(it["name"]), "how = " + q(it["how"]), "score = %g" % it["score"]]
                        if it["also"]:
                            f.append("ally = " + q(it["also"][0]))
                            if len(it["also"]) > 1: f.append("also = { " + ", ".join(q(a) for a in it["also"][1:]) + " }")
                        if it.get("two"): f.append("two = true")
                        if it["note"]: f.append("note = " + q(it["note"]))
                        L.append("            { " + ", ".join(f) + " },")
                    L.append("        } },")
                L.append("    } },")
                counts["wowhead"] += 1
            else:
                body = open(os.path.join(HERE, "legacy", "%s_%s.lua" % (cls, key)), encoding="utf-8").read().rstrip("\n")
                L.append("    [%s] = { label = %s, guides = 1, old = %s, slots = {"
                         % (q(key), q(key + " " + CLASS_NAME[cls]), q(LEGACY_WHY[(cls, key)])))
                L.append(body)
                L.append("    } },")
                counts["old"] += 1
        L.append("}")
        L.append("")
    open(os.path.join(ROOT, "Modules", "BiSData.lua"), "w", encoding="utf-8").write("\n".join(L))
    print("wrote BiSData.lua:", dict(counts), "updated", today)


if __name__ == "__main__":
    main()
