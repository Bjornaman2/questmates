"""Read the baked QuestieDB_Forever.toc (TOC metadata: base64 CBOR rows) into Python dicts.

Get the data: download the newest QuestieDB-*-Forever.zip from https://github.com/Questie/QuestieDB/releases
and unpack it to tools/data/questie/forever/ (so tools/data/questie/forever/QuestieDB/QuestieDB_Forever.toc exists).
Needs: pip install --target tools/pylib cbor2
"""
import sys, os, re, base64
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "pylib"))
import cbor2

DB = os.path.join(HERE, "questie", "forever", "QuestieDB")
LINE = re.compile(r"^## X-(Quest|Npc|Object|Item)-(\d+)-(S|\d+)(?:-(\d+))?: (.*)$")

def load():
    raw = {}      # (kind, id, field) -> value string or {part: str}
    with open(os.path.join(DB, "QuestieDB_Forever.toc"), encoding="utf-8") as f:
        for line in f:
            m = LINE.match(line.rstrip("\n"))
            if not m:
                continue
            kind, eid, field, part, val = m.groups()
            key = (kind, int(eid), field)
            if part is None:
                raw.setdefault(key, {})[0] = val
            else:
                raw.setdefault(key, {})[int(part)] = val
    data = {}
    for (kind, eid, field), parts in raw.items():
        head = parts.get(0)
        if head and re.fullmatch(r"~\d+~", head):
            n = int(head.strip("~"))
            s = "".join(parts[i] for i in range(1, n + 1))
        else:
            s = head
        try:
            v = cbor2.loads(base64.b64decode(s))
        except Exception as e:
            v = ("ERR", str(e))
        ent = data.setdefault(kind, {}).setdefault(eid, {})
        if field == "S":
            if isinstance(v, dict):
                for k, x in v.items():
                    ent[k] = x
            elif isinstance(v, list):
                for i, x in enumerate(v, 1):
                    if x is not None:
                        ent[i] = x
        else:
            ent[int(field)] = v
    return data

if __name__ == "__main__":
    d = load()
    for k in d: print(k, len(d[k]))
    print("Quest 7:", d["Quest"].get(7))
    print("Npc 823:", d["Npc"].get(823))
