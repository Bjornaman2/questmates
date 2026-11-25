import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "pylib"))
from lupa import lua51

ADDON = os.path.join(HERE, "..", "..", "Questmates")
FILES = [l.strip() for l in open(os.path.join(ADDON, "Questmates.toc"), encoding="utf-8-sig") if l.strip().endswith(".lua")]
mock = open(os.path.join(HERE, "mock.lua"), encoding="utf-8-sig").read()
ATLAS = os.environ.get("ATLAS", "0") == "1"
fails = []
SENDER_SEP = os.environ.get("SENDER_SEP", "-")

def client(name, cls):
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()
    g.PLAYER, g.REALM, g.MYCLASS, g.ATLAS_OK = name, "Doomhowl", cls, ATLAS
    L.execute(mock)
    L.execute("NS = {}")
    for fn in FILES:
        src = open(os.path.join(ADDON, fn), encoding="utf-8-sig").read()
        L.execute("local src, name = ...; local f, err = loadstring(src, '@' .. name); assert(f, err); f('Questmates', NS)", src, fn)
    L.execute("FIRE('ADDON_LOADED', 'Questmates')")
    return L

A = client("Bjorn", "MAGE")
B = client("Friend", "PALADIN")
clients = {"Bjorn": A, "Friend": B}

def deliver():
    moved = True
    while moved:
        moved = False
        for name, L in clients.items():
            box = L.globals().OUTBOX
            n = len(box)
            if n == 0: continue
            msgs = [(box[i + 1].prefix, box[i + 1].msg) for i in range(n)]
            L.execute("wipe(OUTBOX)")
            for other, L2 in clients.items():
                if other == name: continue
                for p, m in msgs:
                    L2.globals().FIRE("CHAT_MSG_ADDON", p, m, "PARTY", name + SENDER_SEP + "Doomhowl")
            moved = True

def tick(sec=1.0, steps=10):
    for _ in range(steps):
        for L in clients.values(): L.execute(f"ADVANCE({sec / steps})")
        deliver()

def errors(L, label):
    errs = list(L.execute("return ERRORS").values())
    if errs:
        print(f"!!! ERRORS in {label}:"); [print("   ", e) for e in errs]
        fails.append(label)
        L.execute("wipe(ERRORS)")

def toasts(L):
    return L.execute("""local t = {} for _, f in ipairs(FRAMES) do if f.parent == QuestmatesToastAnchor and f.shown and f.data then
      t[#t+1] = TEXTS(f):gsub('\\n', ' | ') end end return table.concat(t, '\\n')""")

def section(t): print("\n==== " + t + " ====")

A.execute("""LOG = {
 {id=11, title='Kobold Camp Cleanup', level=7, share=true, obj={{text='Kobold Vermin slain', have=3, need=10}}},
 {id=12, title='Princess Must Die!', level=12, share=true, obj={{text='Princess slain', have=0, need=1}}},
}""")
B.execute("""LOG = {
 {id=11, title='Kobold Camp Cleanup', level=7, share=true, obj={{text='Kobold Vermin slain', have=8, need=10}}},
 {id=21, title='The Fargodeep Mine', level=7, share=false, obj={{text='Explore the mine', have=0, need=1}}},
 {id=22, title='Wolves Across the Border', level=6, share=true, obj={{text='Tough Wolf Meat', have=1, need=8}}},
}""")
for L in (A, B): L.globals().FIRE("PLAYER_ENTERING_WORLD")
tick(1)
errors(A, "A login"); errors(B, "B login")

section("B learns a chain before grouping: turns in 30 to Marshal Dughan, accepts 31 from him")
B.execute("NPC='Marshal Dughan'; DETAIL_ID=30; POS={0.42,0.66}")
B.globals().FIRE("QUEST_DETAIL")
B.execute("table.insert(LOG, {id=30, title='A Threat Within', level=5, share=true, obj={}})")
B.globals().FIRE("QUEST_ACCEPTED", 30); tick(1)
B.globals().FIRE("QUEST_COMPLETE")
B.globals().FIRE("QUEST_TURNED_IN", 30, 100, 0)
B.execute("table.remove(LOG); COMPLETED[30]=true")
B.globals().FIRE("QUEST_REMOVED", 30)
B.execute("DETAIL_ID=31")
B.globals().FIRE("QUEST_DETAIL")
B.execute("table.insert(LOG, {id=31, title='Report to Goldshire', level=5, share=true, obj={{text='Talk to the Marshal', have=0, need=1}}})")
B.globals().FIRE("QUEST_ACCEPTED", 31)
tick(2)
print("B knows prev[31] =", B.execute("return QuestmatesDB.know.prev[31]"), " giver:", B.execute("return QuestmatesDB.know.givers[31].npc"))
errors(B, "B chain learning")

section("Group up")
A.execute("GROUP = {{name='Friend', realm='Doomhowl', class='PALADIN'}}")
B.execute("GROUP = {{name='Bjorn', realm='Doomhowl', class='MAGE'}}")
for L in (A, B): L.globals().FIRE("GROUP_ROSTER_UPDATE")
tick(12, 120)
errors(A, "A group"); errors(B, "B group")
print("A toasts:\n" + toasts(A))
print("--- A tracker ---"); print(A.execute("return TEXTS(QuestmatesTracker)"))

section("B makes progress on 22 (focus moves there)")
A.execute("for _,f in ipairs(FRAMES) do if f.parent==QuestmatesToastAnchor then f.data=nil; f.shown=false end end")
B.execute("LOG[3].obj[1].have = 4; FOCUSPOI = 22")
B.globals().FIRE("QUEST_LOG_UPDATE"); tick(3, 30)
print("A toasts:\n" + toasts(A))
A.execute("Questmates:Fire('OPEN')"); tick(1)
print("--- A HOME page ---"); print(A.execute("return TEXTS(QuestmatesJournal)"))
print("A sees B poi:", A.execute("local m = Questmates.mates['Friend-Doomhowl'] return m.poi and (m.poi.id .. ' ' .. m.poi.x) or 'none'"))
print("A sees B spots for 22:", A.execute("local m = Questmates.mates['Friend-Doomhowl'] return m.spots[22] and #m.spots[22] or 0"))
errors(A, "A progress")

section("A opens journal on quest 31 (doesn't have it) -> asks B for the path")
A.execute("Questmates:Fire('OPEN', 'Friend-Doomhowl', 31)")
tick(3, 30)
A.execute("Questmates.journal.refresh()")
print(A.execute("return TEXTS(QuestmatesJournal)"))
print("buttons:", A.execute("local t={} for _,b in ipairs(Questmates.journal.buttons) do if b.shown then t[#t+1]=b:GetText() end end return table.concat(t,' | ')"))
errors(A, "A journal")

section("B suggests 31 to party (Show Party) -> A gets toast; chain travels with it")
A.execute("for _,f in ipairs(FRAMES) do if f.parent==QuestmatesToastAnchor then f.data=nil; f.shown=false end end")
A.execute("QuestmatesDB.know.prev = {}; QuestmatesDB.know.givers[31] = nil; QuestmatesDB.know.givers[30] = nil; Questmates.askedPath = {}")
B.execute("Questmates.suggest(31)")
tick(3, 30)
print("A toasts:\n" + toasts(A))
print("A learned prev[31] =", A.execute("return QuestmatesDB.know.prev[31]"), " giver30:", A.execute("local g = QuestmatesDB.know.givers[30] return g and g.npc"))
A.execute("for _,f in ipairs(FRAMES) do if f.parent==QuestmatesToastAnchor and f.shown and f.data then f.scripts.OnClick(f,'LeftButton') break end end")
tick(1, 10)
print("--- A journal after clicking the toast ---"); print(A.execute("return TEXTS(QuestmatesJournal)"))
errors(A, "A suggest"); errors(B, "B suggest")

section("A: Show on Map for 31 -> map pins")
A.execute("for _,b in ipairs(Questmates.journal.buttons) do if b.shown and b:GetText()=='Show on Map' then b.scripts.OnClick(b) end end")
tick(1, 10)
print("map opened:", A.globals().OPENED_MAP, " pins:", A.execute("local t={} for _,p in ipairs(PINS) do t[#t+1]=p.kind .. (p.d.n and ('#'..p.d.n) or '') .. '@' .. string.format('%.2f,%.2f', p.px or -1, p.py or -1) end return table.concat(t,' ')"))
A.execute("TT = {} for _,p in ipairs(PINS) do if p.kind=='step' then p:OnMouseEnter() break end end")
print("step tooltip:", " / ".join(STR for STR in [A.execute("return STRIP(table.concat(TT, ' / '))")]))
errors(A, "A map")

section("B places a map pin -> A sees 'heading here' and can follow")
A.execute("for _,f in ipairs(FRAMES) do if f.parent==QuestmatesToastAnchor then f.data=nil; f.shown=false end end")
B.execute("USERWP = UiMapPoint.CreateFromCoordinates(1429, 0.55, 0.30)")
B.globals().FIRE("USER_WAYPOINT_UPDATED"); tick(2, 20)
print("A toasts:\n" + toasts(A))
A.execute("Questmates.followDestination('Friend-Doomhowl')")
tick(2, 20)
print("A waypoint:", A.execute("return USERWP and (USERWP.uiMapID .. ' ' .. USERWP.position.x) or 'none'"), " B toasts (should be none from echo):", toasts(B) or "none")
errors(A, "A dest"); errors(B, "B dest")

section("Tooltip on B as seen by A, and on a creature")
A.execute("TT = {}; GameTooltip.GetUnit = function() return 'Friend', 'party1' end; TOOLTIP_CB(GameTooltip)")
print(A.execute("return STRIP(table.concat(TT, ' / '))"))
A.execute("""TT = {}; GameTooltip.GetUnit = function() return 'Kobold', 'mouseover' end
GameTooltip.lines = {1,2}; _G.GameTooltipTextLeft2 = MOCK('FontString'); GameTooltipTextLeft2.text = '  Kobold Vermin slain: 3/10'
TOOLTIP_CB(GameTooltip)""")
print(A.execute("return STRIP(table.concat(TT, ' / '))"))
errors(A, "A tooltip")

section("B finishes + turns in Kobold Camp; Join button")
A.execute("for _,f in ipairs(FRAMES) do if f.parent==QuestmatesToastAnchor then f.data=nil; f.shown=false end end")
B.execute("LOG[1].obj[1].have = 10; FOCUSPOI = 11")
B.globals().FIRE("QUEST_LOG_UPDATE"); tick(2, 20)
print("--- A tracker ---"); print(A.execute("return TEXTS(QuestmatesTracker)"))
B.globals().FIRE("QUEST_COMPLETE")
B.globals().FIRE("QUEST_TURNED_IN", 11, 0, 0)
B.execute("table.remove(LOG, 1); COMPLETED[11] = true")
B.globals().FIRE("QUEST_REMOVED", 11); tick(3, 30)
print("A toasts:\n" + toasts(A))
errors(A, "A turnin"); errors(B, "B turnin")

section("Quest log Show Party button + share request")
A.execute("SELECTED = 12; QuestMapFrame.QuestsFrame.DetailsFrame.scripts.OnShow()")
tick(1)
print("A quest log button shown:", A.execute("for _,f in ipairs(FRAMES) do if f.parent == QuestMapFrame.QuestsFrame.DetailsFrame and f.template=='UIPanelButtonTemplate' then return tostring(f.shown) .. ' qid=' .. tostring(f.qid) end end return 'missing'"))
A.execute("Questmates.askShare('Friend-Doomhowl', 22)"); tick(1)
print("B popup:", B.execute("local p = POPUPS[#POPUPS] return p and (STRIP(p.a) .. ' / ' .. STRIP(p.b) .. ' / ' .. tostring(p.data)) or 'none'"))
errors(A, "A ql"); errors(B, "B ql")

section("Demo mode on a solo client")
S = client("Solo", "MAGE")
clients = {"Solo": S}
S.execute("LOG = {{id=11, title='Kobold Camp Cleanup', level=7, share=true, obj={{text='Kobold Vermin slain', have=3, need=10}}}, {id=12, title='Princess Must Die!', level=12, share=true, obj={}}}")
S.globals().FIRE("PLAYER_ENTERING_WORLD")
S.globals().SlashCmdList.QUESTMATES("demo")
tick(9, 90)
print("--- demo tracker ---"); print(S.execute("return TEXTS(QuestmatesTracker)"))
print("--- demo toasts ---"); print(toasts(S))
S.execute("Questmates:Fire('OPEN')"); tick(1)
print("--- demo HOME page ---"); print(S.execute("return TEXTS(QuestmatesJournal)"))
S.execute("Questmates:Fire('OPEN', Questmates.DEMO, 990001)"); tick(1)
print("--- demo journal ---"); print(S.execute("return TEXTS(QuestmatesJournal)"))
S.execute("Questmates:Fire('SHOW_ON_MAP', 990001)"); tick(1)
for scale in (1, 0.3):
    S.execute(f"CANVAS_SCALE = {scale}; WorldMapFrame.provider:RefreshAllData()")
    print(f"LAYOUT at zoom {scale}:", S.execute("local t={} for _,p in ipairs(PINS) do t[#t+1]=p.kind .. (p.d.label and (\"[\"..p.d.label..\"]\") or \"\") .. string.format(\"@%.0f,%.0f\", (p.px or 0)*1000*(CANVAS_SCALE or 1), (p.py or 0)*667*(CANVAS_SCALE or 1)) .. ((p.label.shown and p.label.text.text) and (\" tag=\" .. STRIP(p.label.text.text)) or \"\") end return table.concat(t,\"\\n  \")"))
# guided trip: click Take me there on the quest page
S.execute("Questmates:Fire('OPEN', Questmates.DEMO, 990001)"); tick(1)
S.execute("for _,f in ipairs(FRAMES) do if f.template=='UIPanelButtonTemplate' and f.shown and f.GetText and f:GetText()=='Take me there' and f.parent ~= QuestmatesJournal then f.scripts.OnClick(f) break end end")
tick(1, 10)
print("GUIDED: map opened", S.globals().OPENED_MAP, " journal shown:", S.execute("return tostring(QuestmatesJournal.shown)"), " target:", S.execute("return Questmates.guideTarget and (Questmates.guideTarget.npc .. ' / ' .. Questmates.guideTarget.title) or 'none'"))
print("GUIDED pins:", S.execute("local c={} for _,p in ipairs(PINS) do c[p.kind]=(c[p.kind] or 0)+1 end local t={} for k,v in pairs(c) do t[#t+1]=k..'='..v end table.sort(t) return table.concat(t,' ')"))
print("GUIDED steps:", S.execute("local t={} for _,p in ipairs(PINS) do if p.kind=='step' then t[#t+1]=p.d.label .. (p.d.next and ' NEXT' or '') .. (p.d.locked and ' LOCKED' or '') end end return table.concat(t,', ')"))
print("LEGEND:", S.execute("local t={} for _,r in ipairs(QuestmatesMapLegend.rows or {}) do if r.shown then t[#t+1]=STRIP(r.text.text) end end return tostring(QuestmatesMapLegend.shown) .. ' :: ' .. table.concat(t,' / ')"))
print("TRAIL rotations:", S.execute("local t={} for _,p in ipairs(PINS) do if p.kind=='trail' then t[#t+1]=string.format('%.2f', p.d.angle) end end return table.concat(t,' ')"))
print("TAKE-ME-THERE buttons on quest page:", S.execute("local n=0 for _,f in ipairs(FRAMES) do if f.template=='UIPanelButtonTemplate' and f.shown and f:GetText()=='Take me there' and f.parent ~= QuestmatesJournal then local p=f while p do if not p.shown then break end p=rawget(p,'parent') end if not p then n=n+1 end end end return n"))
print("GUIDED toasts:", toasts(S))
print("--- steps in journal ---"); S.execute("Questmates:Fire('OPEN', Questmates.DEMO, 990001)"); tick(1)
print(S.execute("return TEXTS(QuestmatesJournal)").split("How to get it")[1][:600])
S.execute("POS = { Questmates.guideTarget and 0 or 0, 0 }")
S.execute("local g = QuestmatesDB.know.givers[990003]; POS = { g.x, g.y }"); tick(2, 20)
print("ARRIVED toasts:", [l for l in toasts(S).split(chr(10)) if "made it" in l], " | target now:", S.execute("return tostring(Questmates.guideTarget)"))
S.execute("CANVAS_SCALE = 1; Questmates.guide(QuestmatesDB.know.givers[990004], {npc='Quartermaster Lewin', title='x'})"); tick(0.5, 5)
print("TRAIL dots at zoom 1:", S.execute("local n=0 for _,p in ipairs(PINS) do if p.kind=='trail' then n=n+1 end end return n"))
S.globals().SlashCmdList.QUESTMATES("options")
print("options opened:", S.globals().OPENED_SETTINGS)
errors(S, "demo")

section("DUNGEON SCENARIO")
clients = {"Bjorn": A, "Friend": B}
for L in (A, B): L.execute("MYLEVEL = 18; wipe(PUSHED and {} or {}); PUSHED = nil")
A.execute("Questmates.Dungeons.setTask(1581)"); tick(2, 20)
print("B task now:", B.execute("local t = QuestmatesDB.task return t and (t.area .. ' by ' .. tostring(t.by)) or 'none'"))
print("B toasts:", [l for l in toasts(B).split(chr(10)) if "dungeon" in l.lower() or "Deadmines" in l])
p = A.execute("local dg = Questmates.Dungeons.get(1581) local p = Questmates.Dungeons.plan(dg) local t = {} for i, s in ipairs(p.stops) do local npc, names, n = Questmates.Dungeons.stopText(s) t[#t+1] = i .. ') ' .. npc .. ' [' .. names .. ']' end return p.total .. ' quests, ready ' .. p.ready .. ', stops: ' .. table.concat(t, ' | ') .. ' ; later ' .. #p.later")
print("A plan:", p)
A.execute("Questmates:Fire('OPEN_DUNGEON', 1581)"); tick(1)
print("--- A dungeon page ---"); print(A.execute("return TEXTS(QuestmatesJournal)").split("DUNGEON")[-1][:1600])
print("--- A tracker ---"); print(A.execute("return TEXTS(QuestmatesTracker)")[:500])
# B accepts a Deadmines-chain quest -> auto share
first = A.execute("local dg = Questmates.Dungeons.get(1581) local p = Questmates.Dungeons.plan(dg) return p.stops[1] and p.stops[1].steps[1] or 0")
print("first step quest:", first, A.execute(f"return Questmates.titleOf({first})"))
B.execute(f"table.insert(LOG, {{id={first}, title=Questmates.titleOf({first}), level=15, share=true, obj={{}}}})")
B.globals().FIRE("QUEST_ACCEPTED", first); tick(4, 40)
print("B pushed (auto-share):", B.globals().PUSHED, " B toasts:", toasts(B).split(chr(10)))
# A gets the quest dialog for it -> auto accept
A.execute(f"DETAIL_ID = {first}"); A.globals().FIRE("QUEST_DETAIL"); tick(1, 10)
print("A auto-accepted:", list(A.execute("return ACCEPTED_Q").values()))
A.execute("Questmates.Dungeons.setTask(nil)"); tick(2, 20)
print("after stop, B task:", B.execute("return tostring(QuestmatesDB.task)"))
errors(A, "A dungeon"); errors(B, "B dungeon")

section("LEARN SCENARIO")
print("Krol'dok in list:", A.execute("local dg = Questmates.Dungeons.byName(\"Krol'dok Stronghold\") return dg and (dg.name .. ' lvl ' .. dg.lo .. '-' .. dg.hi .. ' quests ' .. #dg.quests .. ' for me ' .. #Questmates.Dungeons.questsFor(dg)) or 'MISSING'"))
# a Forever quest under a dungeon header in B's log (not in the database list) + a quest the game tags Dungeon
B.execute("table.insert(LOG, {isHeader=true, title=\"Krol'dok Stronghold\"}); table.insert(LOG, {id=99501, title='Mouldy Secrets', level=41, share=true, obj={}})")
B.execute("table.insert(LOG, {isHeader=true, title='Manor Mistmantle'}); table.insert(LOG, {id=99502, title='The Mistmantle Curse', level=30, share=true, obj={}}); TAGS = {[99502]=81}")
B.globals().FIRE("QUEST_LOG_UPDATE"); tick(4, 40)
print("B learned:", B.execute("local t={} for q, n in pairs(QuestmatesDB.know.dq) do t[#t+1]=q..'='..n end table.sort(t) return table.concat(t,', ')"))
print("A learned (via party):", A.execute("local t={} for q, n in pairs(QuestmatesDB.know.dq) do t[#t+1]=q..'='..n end table.sort(t) return table.concat(t,', ')"))
print("A Manor Mistmantle:", A.execute("local dg = Questmates.Dungeons.byName('Manor Mistmantle') return dg and (dg.name .. ' learned=' .. tostring(dg.learned) .. ' quests ' .. #dg.quests .. ' lvl ' .. dg.lo) or 'MISSING'"))
# A walks into an instance -> entrance learned + shared
A.execute("POS = {0.61, 0.33}"); tick(5, 10)
A.execute("INSTANCE = {name='Manor Mistmantle', kind='party'}"); A.globals().FIRE("PLAYER_ENTERING_WORLD"); tick(3, 30); A.execute("INSTANCE = nil")
print("B entrance for Manor Mistmantle:", B.execute("local e = QuestmatesDB.know.inst['Manor Mistmantle'] return e and (tostring(e.map) .. ' ' .. tostring(e.x) .. ',' .. tostring(e.y)) or 'none'"))
# finished dungeon -> All done, crossed out
A.execute("local dg = Questmates.Dungeons.get(1581) for _, q in ipairs(dg.quests) do COMPLETED[q] = true end")
A.execute("Questmates:Fire('OPEN_DUNGEON', nil)"); tick(1)
txt = A.execute("return TEXTS(QuestmatesJournal)")
print("--- A dungeon list (end) ---"); print(txt[txt.find("All done"):][:400] if "All done" in txt else "NO ALL DONE SECTION")
print("strike lines drawn:", A.execute("local n=0 for _,f in ipairs(FRAMES) do end return #(Questmates.journal.homeDoc.pools.strike or {})"))
A.execute("MYLEVEL = 41; Questmates:Fire('OPEN_DUNGEON', 17780)"); tick(1)
t = A.execute("return TEXTS(QuestmatesJournal)")
print("--- KROLDOK PAGE ---"); print(t[t.find("Krol'dok Stronghold\nLevel"):][:1800])
errors(A, "A learn"); errors(B, "B learn")

section("BLOCKED SCENARIO")
clients = {"Bjorn": A, "Friend": B}
for L in (A, B): L.execute("MYLEVEL = 45; for _, f in ipairs(FRAMES) do if f.parent == QuestmatesToastAnchor then f.data = nil; f.shown = false end end")
B.execute("COMPLETED[94926] = true; table.insert(LOG, {id=94982, title='Eye of Mugg', level=45, share=true, obj={}})")
B.globals().FIRE("QUEST_LOG_UPDATE"); tick(3, 30)
A.execute("Questmates.Dungeons.setTask(17780)"); tick(2, 20)
print("A next action before:", A.execute("local a = Questmates.Dungeons.nextAction(Questmates.Dungeons.get(17780)) return a.kind .. ' ' .. (a.stop and a.stop.giver.npc or '')"))
# Bjorn talks to Demar Brant: he offers other quests but not Eye of Mugg
A.execute("NPC = 'Demar Brant'; GOSSIP_OFFER = {94894}"); A.globals().FIRE("GOSSIP_SHOW"); tick(3, 30)
print("A blocked:", A.execute("local b = Questmates.Offers.blocked(94982) return b and (b.npc .. ' at level ' .. b.level) or 'no'"))
print("A toasts:", [l for l in toasts(A).split(chr(10)) if "offered" in l.lower() or "Next stop" in l])
print("A next action after:", A.execute("local a = Questmates.Dungeons.nextAction(Questmates.Dungeons.get(17780)) return a.kind .. ' ' .. (a.stop and a.stop.giver.npc or '')"))
print("Friend answered:", A.execute("local m = Questmates.mates['Friend-Doomhowl'] local t = {} for q in pairs((m.unlock or {})[94982] or {}) do t[#t+1] = q end return table.concat(t, ',')"))
A.execute("Questmates:Fire('OPEN', nil, 94982)"); tick(1)
txt = A.execute("return TEXTS(QuestmatesJournal)")
i = txt.find("Eye of Mugg\nLevel"); print("--- A quest page ---"); print(txt[i:i+1100])
# Bjorn does Drop the Hammer, turns it in, then gets Eye of Mugg -> link learned
A.execute("table.insert(LOG, {id=94926, title='Drop the Hammer', level=45, share=true, obj={}})"); A.globals().FIRE("QUEST_ACCEPTED", 94926); tick(1)
A.globals().FIRE("QUEST_COMPLETE"); A.globals().FIRE("QUEST_TURNED_IN", 94926, 0, 0)
A.execute("for i, q in ipairs(LOG) do if q.id == 94926 then table.remove(LOG, i) break end end COMPLETED[94926] = true"); tick(5, 50)
A.execute("DETAIL_ID = 94982"); A.globals().FIRE("QUEST_DETAIL"); A.execute("table.insert(LOG, {id=94982, title='Eye of Mugg', level=45, share=true, obj={}})"); A.globals().FIRE("QUEST_ACCEPTED", 94982); tick(3, 30)
print("A learned prev:", A.execute("return tostring(QuestmatesDB.know.prev[94982])"), " B learned prev:", B.execute("return tostring(QuestmatesDB.know.prev[94982])"))
print("path now:", A.execute("local t = {} for _, q in ipairs(Questmates.pathTo(94982)) do t[#t+1] = Questmates.titleOf(q) end return table.concat(t, ' -> ')"))
errors(A, "A blocked"); errors(B, "B blocked")

section("DIRECT WINDOW SCENARIO")
Z = client("Zeke", "MAGE")
clients = {"Zeke": Z}
Z.execute("MYLEVEL = 45; LOG = {{id=94877, title='Saving Sunnyglade', level=40, share=true, obj={{text='Twilight cultist slain', have=3, need=8}}}}")
Z.globals().FIRE("PLAYER_ENTERING_WORLD"); tick(1)
Z.execute("Questmates.Dungeons.setTask(17780)"); tick(1)
Z.execute("NPC = 'Demar Brant'"); Z.globals().FIRE("QUEST_PROGRESS"); tick(2, 20)
print("blocked after direct window:", Z.execute("local b = Questmates.Offers.blocked(94982) return b and b.npc or 'no'"))
Z.execute("Questmates:Fire('OPEN', nil, 94982)"); tick(1)
txt = Z.execute("return TEXTS(QuestmatesJournal)")
i = txt.find("What probably unlocks it"); print(txt[i:i+420])
Z.execute("Questmates:Fire('OPEN_DUNGEON', 17780)"); tick(1)
txt = Z.execute("return TEXTS(QuestmatesJournal)")
i = txt.find("Krol'dok Stronghold\nLevel"); print("--- NEW DUNGEON PAGE ---"); print(txt[i:i+1200])
# fallback link: mark Ranath's quest as not offered by hand
Z.execute("for _, b in ipairs(Questmates.journal.homeDoc.pools.link or {}) do if b.shown and b.text.text:find('offer') then b.scripts.OnClick(b) break end end"); tick(1)
print("after link, next:", Z.execute("local a = Questmates.Dungeons.nextAction(Questmates.Dungeons.get(17780)) return a.kind .. ' ' .. (a.stop and a.stop.giver.npc or (a.qid and Questmates.titleOf(a.qid)) or '')"))
errors(Z, "Z direct")

section("GAME KNOWS SCENARIO")
Y = client("Yara", "MAGE")
clients = {"Yara": Y}
Y.execute("MYLEVEL = 45; LOG = {{id=94877, title='Saving Sunnyglade', level=40, share=true, obj={{text='Twilight cultist slain', have=3, need=8}}}}")
# the server: every quest on Riverglades (2548) you can plainly take is available, plus the chain starts - but NOT Eye of Mugg
Y.execute("""
local list = {}
for qid, r in pairs(Questmates.DData.Q) do
  local st = r[8]
  if st and st[3] == 2548 and qid ~= 94982 and (r[3] or 0) <= 45 and Questmates.questForMe(qid) and not COMPLETED[qid] and qid ~= 94877 then
    list[#list + 1] = { questID = qid, x = st[4], y = st[5] }
  end
end
AVAIL_LINES[2548] = list
""")
Y.globals().FIRE("PLAYER_ENTERING_WORLD"); tick(1)
Y.execute("Questmates.Dungeons.setTask(17780)"); tick(6, 60)
print("game status for Eye of Mugg:", Y.execute("return tostring(Questmates.Offers.status(94982))"), "| map reliable:", Y.execute("local q = Questmates.DQ(94982) return tostring(q[8][3])"))
Y.execute("Questmates:Fire('OPEN_DUNGEON', 17780)"); tick(1)
txt = Y.execute("return TEXTS(QuestmatesJournal)")
i = txt.find("DO THIS NEXT"); print("--- page ---"); print(txt[i:i+900])
# after picking up the other stops, the card should say: finish Saving Sunnyglade (most likely unlocks Eye of Mugg)
print("actions in order:")
for k in range(4):
    a = Y.execute("local a = Questmates.Dungeons.nextAction(Questmates.Dungeons.get(17780)) if a.kind == 'stop' then local n, names = Questmates.Dungeons.stopText(a.stop) return 'stop: ' .. n .. ' - ' .. names elseif a.kind == 'finish' then return 'finish: ' .. Questmates.titleOf(a.qid) .. ' -> ' .. Questmates.titleOf(a.forQuest) .. (a.guessed and ' (most likely)' or '') else return a.kind end")
    print("  ", a)
    if not a.startswith("stop"): break
    Y.execute("local a = Questmates.Dungeons.nextAction(Questmates.Dungeons.get(17780)) for _, qid in ipairs(a.stop.steps) do table.insert(LOG, {id=qid, title=Questmates.titleOf(qid), level=40, share=true, obj={}}) end")
    Y.globals().FIRE("QUEST_LOG_UPDATE"); tick(1, 10)
Y.execute("wipe(PRINTS)"); Y.globals().SlashCmdList.QUESTMATES("why Eye of Mugg")
print("--- WHY OUTPUT ---"); print(Y.execute("return STRIP(table.concat(PRINTS, string.char(10)))"))
Y.execute("NPC = 'Demar Brant'"); Y.globals().FIRE("QUEST_PROGRESS"); tick(1, 10)
print("--- LOG (last 8) ---"); print(Y.execute("local l = QuestmatesDB.debugLog local t = {} for i = math.max(1, #l - 7), #l do t[#t+1] = l[i] end return table.concat(t, string.char(10))"))
errors(Y, "Y game knows")

section("PLAN PAGE")
P = client("Pia", "MAGE")
clients = {"Pia": P}
P.execute("MYLEVEL = 40; LOG = {{id=94886, title='The Western Front', level=44, share=true, obj={{text='Twilight Lieutenant slain', have=0, need=1}}}, {id=94907, title='A Small Favor', level=44, share=true, obj={{text='Ore', have=1, need=5}}}}")
P.execute("POS = {0.66, 0.80}; C_Map.GetBestMapForUnit = function() return 2548 end")
P.globals().FIRE("PLAYER_ENTERING_WORLD"); tick(1)
P.execute("Questmates.Dungeons.setTask(17780)"); tick(1)
P.execute("NPC = 'Demar Brant'"); P.globals().FIRE("QUEST_PROGRESS"); tick(2, 20)
P.execute("Questmates:Fire('OPEN_DUNGEON', 17780)"); tick(1)
txt = P.execute("return TEXTS(QuestmatesJournal)")
i = txt.find("Krol'dok Stronghold\nLevel"); print(txt[i:i+1500])
errors(P, "P plan")

section("NO REALM SCENARIO")
R1 = client("Rowan", "MAGE"); R2 = client("Tilda", "PALADIN")
clients = {"Rowan": R1, "Tilda": R2}
for L in (R1, R2): L.execute("REALM_HIDDEN = true")
R1.execute("LOG = {{id=7, title='Kobold Camp Cleanup', level=2, share=true, obj={{text='Kobold Vermin slain', have=3, need=10}}}}")
R2.execute("LOG = {{id=7, title='Kobold Camp Cleanup', level=2, share=true, obj={{text='Kobold Vermin slain', have=5, need=10}}}, {id=783, title='A Threat Within', level=1, share=true, obj={}}}")
for L in (R1, R2): L.globals().FIRE("PLAYER_ENTERING_WORLD")
tick(1)
# the party list gives no realm (same realm); messages arrive as Name-Doomhowl (deliver() adds it)
R1.execute("GROUP = {{name='Tilda', realm=nil, class='PALADIN'}}")
R2.execute("GROUP = {{name='Rowan', realm=nil, class='MAGE'}}")
for L in (R1, R2): L.globals().FIRE("GROUP_ROSTER_UPDATE")
tick(10, 100)
print("Rowan sees:", R1.execute("local t = {} for _, f in ipairs(Questmates.mateList()) do local m = Questmates.mates[f] t[#t+1] = f .. ' synced=' .. tostring(m and m.synced) .. ' quests=' .. (function() local n = 0 for _ in pairs(m and m.quests or {}) do n = n + 1 end return n end)() end return table.concat(t, ' | ')"))
print("Rowan tracker:", R1.execute("return TEXTS(QuestmatesTracker)").replace(chr(10), " / ")[:200])
R1.execute("Questmates.askShare(Questmates.mateList()[1], 783)"); tick(1, 10)
print("Tilda got share request:", R2.execute("local p = POPUPS[#POPUPS] return p and (STRIP(p.a) .. ' / ' .. tostring(p.data)) or 'none'"))
R2.execute("LOG[1].obj[1].have = 8"); R2.globals().FIRE("QUEST_LOG_UPDATE"); tick(3, 30)
R1.execute("Questmates:Fire('OPEN')"); tick(1)
txt = R1.execute("return TEXTS(QuestmatesJournal)"); i = txt.find("Right now")
print("--- RIGHT NOW PROGRESS ---"); print(txt[i:i+300])
errors(R1, "R1 no realm"); errors(R2, "R2 no realm")

print("\nRESULT:", "FAIL " + ", ".join(fails) if fails else "no Lua errors")
