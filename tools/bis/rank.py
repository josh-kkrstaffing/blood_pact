#!/usr/bin/env python3
"""Rank pre-raid BiS for every spec from raw/*.txt and write BiSData.lua + ranked.csv.
Method: each guide's top pick = 2 points, each alternative = 1; BiS = most points;
ties go to ForeverSpec's order; score = points / BiS points. Horde versions."""
import re, glob, json, collections, sys

SITES = {"fb": "FrostyBoost", "fs": "ForeverSpec", "cc": "ConquestCapped"}
CLASS_KEY = {"Warrior":"WARRIOR","Paladin":"PALADIN","Hunter":"HUNTER","Rogue":"ROGUE","Priest":"PRIEST",
             "Shaman":"SHAMAN","Mage":"MAGE","Warlock":"WARLOCK","Druid":"DRUID"}
ORDER = ["Head","Neck","Shoulder","Back","Chest","Wrist","Hands","Waist","Legs","Feet","Ring 1","Ring 2",
         "Trinket 1","Trinket 2","Main hand","Off hand","Two-hand","Ranged / Relic"]
INV = {"Head":[1],"Neck":[2],"Shoulder":[3],"Back":[15],"Chest":[5],"Wrist":[9],"Hands":[10],"Waist":[6],"Legs":[7],
       "Feet":[8],"Ring 1":[11,12],"Ring 2":[11,12],"Trinket 1":[13,14],"Trinket 2":[13,14],"Main hand":[16],
       "Off hand":[17],"Two-hand":[16],"Ranged / Relic":[18]}

def canon_slot(s):
    s = s.strip().lower().replace("-", " ")
    if s.startswith("ring") or s.startswith("finger"): return "Ring"
    if s.startswith("trinket"): return "Trinket"
    for k, v in [("head","Head"),("neck","Neck"),("shoulder","Shoulder"),("back","Back"),("chest","Chest"),
                 ("wrist","Wrist"),("hand","Hands"),("waist","Waist"),("leg","Legs"),("feet","Feet"),
                 ("main hand","Main hand"),("off hand","Off hand"),("two hand","Two-hand"),("staff","Two-hand")]:
        if s == k or s == k + "s" or s.startswith(k): 
            if k == "hand" and (s.startswith("main") or s.startswith("off")): continue
            return v
    if s.startswith("main"): return "Main hand"
    if s.startswith("off"): return "Off hand"
    if s in ("ranged","wand","libram","totem","idol","ranged/relic","relic"): return "Ranged / Relic"
    raise SystemExit("unknown slot: " + s)

# Alliance name -> Horde twin. "seen" = the Horde name appears in a guide; others follow the same pattern.
SHOULDER_WORDS = ("Epaulets","Pauldrons","Mantle","Shoulderguards","Spaulders","Shoulderpads")
SEEN_HORDE = set()
def horde(name):
    """returns (horde_name, alliance_name or None, pattern_only)"""
    n = name
    if n.startswith("Sentinel's "): return "Outrider's " + n[11:], n, False
    if n.startswith("Highlander's "): return "Defiler's " + n[13:], n, False
    if n == "Cloak of the Honor Guard": return "Deathguard's Cloak", n, False
    if n.startswith("Stormpike Insignia"): return n.replace("Stormpike", "Frostwolf"), n, False
    if n.startswith("Theramore "):
        rest = n[10:]
        if rest in SHOULDER_WORDS: return "Darkspear " + rest, n, True
        return "Raider " + rest, n, True
    return n, None, False

def clean_item(raw):
    s = raw.strip()
    if s in ("", "-", "–", "none"): return None
    if re.search(r"\(A\)\s*$", s): return None          # Alliance-only, no Horde twin named
    s = re.sub(r"\s*\((H|Horde)\)\s*$", "", s)
    s = re.sub(r"\s*\((needs )?[A-Za-z]+ \d+\)\s*$", "", s)
    return s.strip()

def load():
    data = collections.OrderedDict()   # (class, spec) -> site -> list of (slot, [items], source)
    for path in sorted(glob.glob("raw/*.txt")):
        cur = None
        for line in open(path, encoding="utf-8"):
            line = line.rstrip("\n")
            if not line or line.startswith("#"): continue
            if line.startswith("@"):
                site, cls, specs = line[1:].split("|")
                base = None
                if "~" in specs: specs, base = specs.split("~")
                cur = []
                for spec in specs.split(","):
                    d = data.setdefault((cls, spec.strip()), collections.OrderedDict())
                    rows = collections.OrderedDict()
                    if base:
                        for k, v in data[(cls, base)][site].items(): rows[k] = v
                    d[site] = rows
                    cur.append((site, rows))
                continue
            parts = line.split("|")
            nitems = 2 if cur[0][0] == "fb" else 3
            slot_raw, items, src = parts[0], parts[1:1+nitems], (parts[1+nitems] if len(parts) > 1+nitems else "")
            for site, rows in cur:
                rows[slot_raw.strip()] = (canon_slot(slot_raw), [clean_item(i) for i in items], src.strip())
    return data

def tidy_how(src):
    s = src.strip()
    s = re.sub(r"\s*\(\d+%\)", "", s)
    s = re.sub(r"[^/,:]*?\s*\(A\)\s*/\s*", "", s)             # "X (A) / Y (H)" -> "Y (H)"
    s = re.sub(r"\s*/\s*[^/,]*?\(A\)", "", s)                  # "Y (H) / X (A)" -> "Y (H)"
    s = s.replace(" (H)", "").replace(" (Horde)", "")
    s = re.sub(r"^Frostwolf,", "Frostwolf Clan,", s)
    s = re.sub(r"^Darkspear,", "Darkspear Raiders,", s)
    s = re.sub(r"^Warsong,", "Warsong Outriders,", s)
    s = re.sub(r"^Quest (?!reward)", "Quest: ", s)
    s = re.sub(r"^(Leatherworking|Tailoring|Blacksmithing|Engineering|Enchanting|Alchemy)\b", r"Crafted: \1", s)
    s = s.replace("Pix Xizzix, Stranglethorn Vale", "Vendor: Pix Xizzix (Undermine Trader), Stranglethorn Vale")
    s = re.sub(r"^Exalted with (.*)$", r"\1, Exalted", s)
    return s

def rank_spec(sites, HOW):
    pts = collections.defaultdict(lambda: collections.Counter())   # slot -> item -> points
    guides = collections.defaultdict(lambda: collections.defaultdict(set))
    fsrank = collections.defaultdict(dict)
    twos = set(); allies = {}; pattern = set()
    for site, rows in sites.items():
        for raw_slot, (slot, items, src) in rows.items():
            names = []
            for it in items:
                if not it: names.append(None); continue
                h, a, pat = horde(it)
                if a: allies[h] = a
                if pat and h not in SEEN_HORDE: pattern.add(h)
                names.append(h)
            seen = set()
            pooled = slot in ("Ring", "Trinket")
            both = pooled and site == "fs"            # one ranked line fills two slots
            for i, n in enumerate(names):
                if not n or n in seen: continue
                seen.add(n)
                p = 2 if (i == 0 or (both and i == 1)) else 1
                tgt = slot
                if slot == "Two-hand": twos.add(n)
                pts[tgt][n] += p
                guides[tgt][n].add(site)
                if site == "fs": fsrank[tgt].setdefault(n, i)
            first = next((n for n in names if n), None)
            if first and src:
                HOW.setdefault(first, {})[site] = tidy_how(src)
    return pts, guides, fsrank, twos, allies, pattern

def how_for(name, HOW):
    h = HOW.get(name)
    if not h: return ""
    for site in ("fb", "cc", "fs"):
        if site in h: return h[site]
    return ""

def build(data):
    HOW = {}
    # Horde names that guides print themselves
    for sites in data.values():
        for rows in sites.values():
            for slot, items, src in rows.values():
                for it in items:
                    if it and (it.startswith("Darkspear ") or it.startswith("Raider ") or it.startswith("Outrider's ")
                               or it.startswith("Defiler's ")): SEEN_HORDE.add(it)
    ranked = collections.OrderedDict()
    staged = {}
    for key, sites in data.items():
        staged[key] = rank_spec(sites, HOW)
    for key, (pts, guides, fsrank, twos, allies, pattern) in staged.items():
        sites = data[key]
        def order(slot):
            items = list(pts[slot].items())
            items.sort(key=lambda kv: (-kv[1], fsrank[slot].get(kv[0], 9), kv[0]))
            return items
        has_mh = bool(pts.get("Main hand")) or bool(pts.get("Off hand"))
        slots = []
        def emit(label, items, flags=None):
            if not items: return
            top = items[0][1]
            out = []
            for n, p in items[:4]:
                note = []
                if n in pattern: note.append("Horde name follows the pattern of the confirmed pairs; confirm in game")
                if n == items[0][0] and len(items) > 1 and items[1][1] == p:
                    note.append("Tied with %s on points; ForeverSpec's order breaks the tie" % items[1][0])
                e = {"name": n, "how": how_for(n, HOW), "points": p, "guides": len(guides[flags or label][n]) if (flags or label) in guides else 0,
                     "score": round(p / top, 2), "note": "; ".join(note)}
                if n in allies: e["ally"] = allies[n]
                out.append(e)
            slots.append({"slot": label, "inv": INV[label], "items": out})
        for label in ORDER:
            if label in ("Ring 1", "Ring 2", "Trinket 1", "Trinket 2"):
                pool = order(label.split()[0])
                if not pool: continue
                idx = 0 if label.endswith("1") else 1
                if len(pool) <= idx: continue
                mine = [pool[idx]] + [x for i, x in enumerate(pool) if i > 1]
                top = mine[0][1]
                out = []
                for n, p in mine[:4]:
                    e = {"name": n, "how": how_for(n, HOW), "points": p, "guides": len(guides[label.split()[0]][n]),
                         "score": round(min(1, p / top), 2), "note": ""}
                    if n in allies: e["ally"] = allies[n]
                    out.append(e)
                slots.append({"slot": label, "inv": INV[label], "items": out})
            elif label == "Main hand":
                if not has_mh: continue
                merged = collections.Counter(pts["Main hand"])
                for n, p in pts["Two-hand"].items(): merged[n] += p
                items = sorted(merged.items(), key=lambda kv: (-kv[1], 0 if kv[0] in pts["Main hand"] else 1,
                                                               fsrank["Main hand"].get(kv[0], fsrank["Two-hand"].get(kv[0], 9)), kv[0]))
                top = items[0][1]
                out = []
                for n, p in items[:5]:
                    g = len(guides["Main hand"][n] | guides["Two-hand"][n])
                    e = {"name": n, "how": how_for(n, HOW), "points": p, "guides": g, "score": round(p / top, 2), "note": ""}
                    if n in twos and n not in pts["Main hand"]:
                        e["two"] = True
                        e["note"] = "Two-hander: also covers the off hand"
                    if n in allies: e["ally"] = allies[n]
                    out.append(e)
                slots.append({"slot": "Main hand", "inv": [16], "items": out})
            elif label == "Off hand":
                if has_mh: emit("Off hand", order("Off hand"))
            elif label == "Two-hand":
                if not has_mh: emit("Two-hand", order("Two-hand"))
            else:
                emit(label, order(label))
        ranked[key] = {"guides": [SITES[s] for s in sites], "slots": slots}
    return ranked

# Warlock Demonology and Destruction were ranked earlier from 7 and 6 guides (see the BiS sheet); keep those.
def preset(rows, guides):
    slots = collections.OrderedDict()
    for slot, name, how, p, note in rows:
        slots.setdefault(slot, []).append((name, how, p, note))
    out = []
    for slot, items in slots.items():
        if slot == "Two-hand option": continue
        top = items[0][2]
        its = [{"name": n, "how": h, "points": p, "guides": 0, "score": round(min(1, p / top), 2), "note": note} for n, h, p, note in items]
        if slot == "Main hand" and "Two-hand option" in slots:
            n, h, p, note = slots["Two-hand option"][0]
            its.append({"name": n, "how": h, "points": p, "guides": 0, "score": round(p / top, 2), "two": True,
                        "note": "Two-hander: also covers the off hand"})
        its.sort(key=lambda it: -it["score"])
        out.append({"slot": slot, "inv": INV[slot], "items": its})
    return {"guides": guides, "slots": out}

def lua_str(s): return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

def write_lua(ranked, path, updated):
    by_class = collections.OrderedDict()
    for (cls, spec), r in ranked.items(): by_class.setdefault(cls, collections.OrderedDict())[spec] = r
    L = ["-- Blood Pact: ranked pre-raid BiS lists for every spec. GENERATED by the BiS research script; don't edit by hand.",
         "-- Ranking: each guide's top pick = 2 points, each alternative = 1; most points is BiS; ties go to",
         "-- ForeverSpec's order; score = points / the BiS item's points. Horde versions; 'ally' is the Alliance twin.",
         "-- Raid lists: none yet. Blizzard hasn't published raid loot tables and no guide has raid BiS (Nov 19, 2026).",
         "local _, ns = ...", "ns.BiSData = ns.BiSData or {}", "ns.BiSUpdated = %s" % lua_str(updated), ""]
    for cls, specs in by_class.items():
        L.append("ns.BiSData.%s = {" % CLASS_KEY[cls])
        for spec, r in specs.items():
            L.append("    [%s] = { label = %s, guides = %d, slots = {" % (lua_str(spec), lua_str(spec + " " + cls), len(r["guides"])))
            for s in r["slots"]:
                L.append("        { slot = %s, inv = { %s }, items = {" % (lua_str(s["slot"]), ", ".join(map(str, s["inv"]))))
                for it in s["items"]:
                    f = ["name = " + lua_str(it["name"]), "how = " + lua_str(it["how"] or "Source not listed in the guides"),
                         "score = " + ("%g" % it["score"])]
                    if it.get("ally"): f.append("ally = " + lua_str(it["ally"]))
                    if it.get("two"): f.append("two = true")
                    if it.get("note"): f.append("note = " + lua_str(it["note"]))
                    L.append("            { " + ", ".join(f) + " },")
                L.append("        } },")
            L.append("    } },")
        L.append("}")
        L.append("")
    open(path, "w", encoding="utf-8").write("\n".join(L))

if __name__ == "__main__":
    data = load()
    ranked = build(data)
    presets = json.load(open("presets.json"))
    for spec, p in presets.items():
        ranked[("Warlock", spec)] = preset(p["rows"], p["guides"])
    # stable order: class then spec
    order_cls = list(CLASS_KEY)
    ranked = collections.OrderedDict(sorted(ranked.items(), key=lambda kv: (order_cls.index(kv[0][0]), kv[0][1])))
    write_lua(ranked, "BiSData.lua", "2026-11-19")
    import csv
    with open("ranked.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["Class", "Spec", "Slot", "Rank", "Item", "How to get it", "Guides listing it", "Points", "Score vs BiS", "Notes"])
        for (cls, spec), r in ranked.items():
            for s in r["slots"]:
                for i, it in enumerate(s["items"]):
                    w.writerow([cls, spec, s["slot"], "BiS" if i == 0 else "Alt %d" % i, it["name"], it["how"], it["guides"] or "",
                                it["points"], it["score"], it["note"]])
    n_items = sum(len(s["items"]) for r in ranked.values() for s in r["slots"])
    nohow = sum(1 for r in ranked.values() for s in r["slots"] for it in s["items"] if not it["how"])
    print(len(ranked), "specs,", n_items, "ranked items,", nohow, "without a source")
    for (cls, spec), r in ranked.items():
        print("%-8s %-14s %2d slots  guides: %s" % (cls, spec, len(r["slots"]), ", ".join(r["guides"]) if isinstance(r["guides"][0], str) else r["guides"]))
