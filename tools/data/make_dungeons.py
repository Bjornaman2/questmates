"""Build Questmates' DungeonData.lua from the WoW Forever QuestieDB."""
import os, re, sys
from qdb import load, DB

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Questmates", "QuestData.lua")
d = load()
Q, N, O, I = d["Quest"], d["Npc"], d["Object"], d["Item"]

def s(v):
    return v.decode("utf-8") if isinstance(v, bytes) else v

def ids(v):
    if isinstance(v, dict):
        return [x for _, x in sorted(v.items())]
    return [x for x in (v or []) if x is not None]

def triple(v):
    if isinstance(v, dict):
        return [v.get(1), v.get(2), v.get(3)]
    v = list(v or [])
    return v + [None] * (3 - len(v))

# areaId -> uiMapId (main table + overrides)
a2u = {}
txt = open(os.path.join(DB, "support", "Forever", "Zones", "areaIdToUiMapId.lua"), encoding="utf-8").read()
for blk in re.findall(r"= \[\[return \{(.*?)\}\]\]", txt, re.S):
    for a, u in re.findall(r"\[(\d+)\]\s*=\s*(\d+)", blk):
        a2u[int(a)] = int(u)

SKIP = {2257, 2917, 2918, 2597, 3277, 3358}          # tram, halls, battlegrounds
RAIDS = {1977, 2159, 2677, 2717, 3428, 3429, 3456}
dtxt = open(os.path.join(DB, "support", "Forever", "Zones", "dungeons.lua"), encoding="utf-8").read()
dungeons = {}
for m in re.finditer(r'\[(\d+)\] = \{"([^"]+)",(nil|\{[\d,]*\}),(\d+),\{(.*?)\}\},?\s*(?:--.*)?$', dtxt, re.M):
    area, name, alts, parent, locs = int(m.group(1)), m.group(2), m.group(3), int(m.group(4)), m.group(5)
    if area in SKIP:
        continue
    alt = [int(x) for x in re.findall(r"\d+", alts)] if alts != "nil" else []
    entrances = []
    for z, x, y in re.findall(r"\{\s*(\d+),\s*([\d.]+),\s*([\d.]+)\s*\}", locs):
        u = a2u.get(int(z))
        if u and u not in (0,):
            entrances.append((u, float(x) / 100, float(y) / 100))
    dungeons[area] = {"name": name, "ids": {area, *alt}, "raid": area in RAIDS, "entrances": entrances, "quests": []}

# WoW Forever dungeons the QuestieDB dungeon table doesn't list yet (their quests are in the data, untagged).
# Questmates also learns dungeons from the game (quest log headers, instances you enter).
EXTRA = {
    17780: {"name": "Krol'dok Stronghold", "quests": [94969, 94973, 94980, 95056]},
}
for area, e in EXTRA.items():
    dungeons.setdefault(area, {"name": e["name"], "ids": {area}, "raid": False, "entrances": [], "quests": []})
    dungeons[area]["quests"].extend(q for q in e["quests"] if q in Q)

area_to_dungeon = {i: a for a, dg in dungeons.items() for i in dg["ids"]}

def place_of_spawns(spawns):
    if not isinstance(spawns, dict):
        return None
    for zone, pts in spawns.items():
        u = a2u.get(int(zone))
        if u and pts:
            p = pts[0]
            if p and p[0] is not None and p[0] >= 0:
                return (u, round(p[0] / 100, 4), round(p[1] / 100, 4))
    return None

def starter(q):
    npcs, objs, items = (ids(x) for x in triple(q.get(2)))
    for nid in npcs:
        n = N.get(nid)
        if n:
            return {"kind": "npc", "name": s(n.get(1)) or "?", "place": place_of_spawns(n.get(7)), "fac": s(n.get(13)) or ""}
    for oid in objs:
        o = O.get(oid)
        if o:
            pl = None
            for v in o.values():
                if isinstance(v, dict) and v and all(isinstance(k, int) for k in v):
                    pl = place_of_spawns(v)
                    if pl: break
            return {"kind": "obj", "name": s(o.get(1)) or "?", "place": pl, "fac": ""}
    for iid in items:
        it = I.get(iid)
        return {"kind": "item", "name": s(it.get(1)) if it else "an item", "place": None, "fac": ""}
    return None

def finisher(q):
    """(name, (uiMapID, x, y) or None) of the NPC you turn the quest in to"""
    for nid in ids(triple(q.get(3))[0]):
        n = N.get(nid)
        if n:
            return s(n.get(1)), place_of_spawns(n.get(7))
    return None, None

for qid, q in Q.items():
    z = q.get(17)
    if z in area_to_dungeon and q.get(1) and not ((q.get(24) or 0) & 1):
        dungeons[area_to_dungeon[z]]["quests"].append(qid)

# every quest (catch-up paths and quest givers for all of them, not only dungeon quests)
# WoW Forever's newest quests often have no zone in the database. A quest with no (or a Forever-only) zone
# whose objective names a dungeon ("...from the Twilight's Hammer in Krol'dok Stronghold") belongs to it.
added_by_text = {}
for qid, q in Q.items():
    z = q.get(17)
    if not q.get(1) or ((q.get(24) or 0) & 1) or qid < 90000:   # only WoW Forever's own new quests
        continue
    if z and z in area_to_dungeon:
        continue
    if z and 0 < z < 16000:
        continue
    text = " ".join(s(x) or "" for x in ids(q.get(8))) + " " + (s(q.get(1)) or "")
    for area, dg in dungeons.items():
        if dg["name"] and dg["name"] in text and qid not in dg["quests"] and (dg["quests"] or area in EXTRA):
            dg["quests"].append(qid)
            added_by_text.setdefault(dg["name"], []).append((qid, s(q.get(1))))
            break
for name, qs in sorted(added_by_text.items()):
    print("  by objective text:", name, "+", len(qs), [n for _, n in qs][:8])

need = set(qid for qid, q in Q.items() if q.get(1))
def add(qid, depth=0):
    if qid in need or qid not in Q or depth > 12:
        return
    need.add(qid)
    q = Q[qid]
    for p in ids(q.get(12)) + ids(q.get(13)):
        add(abs(p), depth + 1)
for dg in dungeons.values():
    for qid in dg["quests"]:
        add(qid)

def L(v):
    return '"' + str(v).replace("\\", "\\\\").replace('"', '\\"') + '"'

lines = [
    "-- Questmates / QuestData.lua",
    "-- GENERATED from QuestieDB (Forever flavor, GPL-3.0, https://github.com/Questie/QuestieDB) by make_dungeons.py.",
    "-- Every WoW Forever quest: quest giver (position in WoW Forever's own map frame), prerequisites, and the dungeons.",
    "-- Q[id] = { name, level, minLevel, raceMask, classMask, preAll, preAny, starter, finisherName, finisherPlace }",
    "-- finisherPlace = { uiMapID, x, y } of the NPC you turn the quest in to",
    "-- starter = { kind ('npc'|'obj'|'item'), name, uiMapID, x, y, friendlyTo ('A'|'H'|'AH'|'') }",
    "local _, QM = ...",
    "QM.DData = {}",
    "local Q = {}",
    "QM.DData.Q = Q",
]
missing_place = 0
for qid in sorted(need):
    q = Q[qid]
    st = starter(q)
    if st:
        pl = st["place"]
        if st["kind"] != "item" and not pl:
            missing_place += 1
        sts = "{%s,%s,%s,%s,%s,%s}" % (L(st["kind"]), L(st["name"]), pl[0] if pl else "nil",
                                      pl[1] if pl else "nil", pl[2] if pl else "nil", L(st["fac"]))
    else:
        sts = "nil"
    pa = [abs(x) for x in ids(q.get(12))]
    py_ = [abs(x) for x in ids(q.get(13))]
    fin, fpl = finisher(q)
    lines.append("Q[%d]={%s,%d,%d,%d,%d,%s,%s,%s,%s,%s}" % (
        qid, L(s(q.get(1))), q.get(5) or 0, q.get(4) or 0, (q.get(6) or 0), q.get(7) or 0,
        "{" + ",".join(map(str, pa)) + "}" if pa else "nil",
        "{" + ",".join(map(str, py_)) + "}" if py_ else "nil",
        sts, L(fin) if fin else "nil",
        "{%d,%s,%s}" % fpl if fpl else "nil"))

dl = []
for area, dg in dungeons.items():
    if not dg["quests"]:
        continue
    levels = sorted(Q[x].get(5) or 0 for x in dg["quests"] if (Q[x].get(5) or 0) > 0)
    lo, hi = (levels[0], levels[-1]) if levels else (0, 0)
    dl.append((levels[len(levels) // 2] if levels else 99, area, dg, lo, hi))
dl.sort()
lines.append("-- dungeons, easiest first: { area, name, isRaid, minQuestLevel, maxQuestLevel, entrances {{uiMapID,x,y}}, quests, zoneUiMapID }")
lines.append("QM.DData.D = {")
for _, area, dg, lo, hi in dl:
    ents = ",".join("{%d,%s,%s}" % (u, round(x, 4), round(y, 4)) for u, x, y in dg["entrances"])
    zone = a2u.get(area) or "nil"   # the zone the dungeon sits in (its door when the exact spot isn't known)
    lines.append("  {%d,%s,%s,%d,%d,{%s},{%s},%s}," % (area, L(dg["name"]), "true" if dg["raid"] else "false", lo, hi, ents,
                                                    ",".join(map(str, sorted(dg["quests"]))), zone))
lines.append("}")
open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
print("dungeons:", len(dl), " quests described:", len(need), " starters without position:", missing_place, " bytes:", os.path.getsize(OUT))
for _, area, dg, lo, hi in dl:
    print(f"  {dg['name']:<28} {'RAID ' if dg['raid'] else '     '}lvl {lo:>2}-{hi:<2}  quests {len(dg['quests']):>3}  entrances {len(dg['entrances'])}")
