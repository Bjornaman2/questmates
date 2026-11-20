-- Questmates / Dungeons.lua
-- Every dungeon's quests (from QuestData.lua), and "get ready for a dungeon" as a party task:
--   * pick a dungeon -> everyone in the party with Questmates gets the same task
--   * Questmates plans the trip: quest givers grouped by place, nearest first, prerequisites first (in order)
--   * "Take me there" guides you stop by stop; after each stop it says where to go next
--   * quests you accept for it are shared with the party automatically, and the ones your friends share
--     with you are accepted automatically (both can be switched off)

local _, QM = ...
local W, C = QM.W, QM.C
local D = {}
QM.Dungeons = D

---------------------------------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------------------------------

-- The list = the quest database's dungeons + what the game teaches us while playing:
--   * a quest that sits under a dungeon's name in a quest log (or that the game tags Dungeon / Raid)
--   * an instance someone in the party walked into (its name, and where they stood just before = the entrance)
-- Learned facts are shared with the party ("Y" / "N" messages) and kept account-wide.
local list, byArea, dirty = nil, nil, true
local function norm(n) return n and n:lower():gsub("^the ", ""):gsub("[%s%p]", "") end

local function build()
  if list and not dirty then return end
  dirty = false
  list, byArea = {}, {}
  local byName = {}
  for _, r in ipairs((QM.DData and QM.DData.D) or {}) do
    local qs = {}
    for i, q in ipairs(r[7]) do qs[i] = q end
    local dg = { area = r[1], name = r[2], raid = r[3], lo = r[4], hi = r[5], entrances = r[6], quests = qs }
    list[#list + 1] = dg
    byArea[dg.area] = dg
    byName[norm(dg.name)] = dg
  end
  local K = QM.K()
  local function ensure(name, kind)
    local key = norm(name)
    local dg = byName[key]
    if not dg then
      dg = { area = "L:" .. name, name = name, raid = (kind == "raid"), lo = 0, hi = 0, entrances = {}, quests = {}, learned = true }
      list[#list + 1] = dg
      byArea[dg.area] = dg
      byName[key] = dg
    end
    return dg
  end
  for name, e in pairs(K.inst or {}) do
    local dg = ensure(name, e.kind)
    if #dg.entrances == 0 and e.map and e.x then dg.entrances = { { e.map, e.x, e.y } } end
    dg.learnedEntrance = true
  end
  for qid, name in pairs(K.dq or {}) do
    local dg = ensure(name)
    local has = false
    for _, q in ipairs(dg.quests) do if q == qid then has = true break end end
    if not has then dg.quests[#dg.quests + 1] = qid end
  end
  -- levels for learned dungeons come from their quests
  for _, dg in ipairs(list) do
    if dg.lo == 0 then
      for _, q in ipairs(dg.quests) do
        local _, lvl = QM.titleOf(q)
        if lvl and lvl > 0 then
          dg.lo = (dg.lo == 0) and lvl or math.min(dg.lo, lvl)
          dg.hi = math.max(dg.hi, lvl)
        end
      end
    end
  end
  table.sort(list, function(a, b)
    if (a.lo == 0) ~= (b.lo == 0) then return b.lo == 0 end
    if a.lo ~= b.lo then return a.lo < b.lo end
    return a.name < b.name
  end)
end

function D.all() build(); return list end
function D.get(area) build(); return area and byArea[area] end
function D.byName(name)
  build()
  local key = norm(name)
  for _, dg in ipairs(list) do if norm(dg.name) == key then return dg end end
end
QM:On("LEARNED", function() dirty = true; QM:Changed() end)

-- Is this quest (in your log) a dungeon quest? Its log header is a dungeon's name, or the game tags it so.
local DUNGEON_TAGS = { [81] = "party", [62] = "raid", [88] = "raid", [89] = "raid" }
local function tagKind(id)
  if not (C_QuestLog.GetQuestTagInfo) then return nil end
  local ok, info = pcall(C_QuestLog.GetQuestTagInfo, id)
  if not ok or type(info) ~= "table" then return nil end
  local k = DUNGEON_TAGS[QM.safe(info.tagID) or 0]
  if k then return k end
  local name = QM.safe(info.tagName)
  if name == (DUNGEON or "Dungeon") then return "party" end
  if name == (RAID or "Raid") then return "raid" end
end

local function learnFromLog()
  local K = QM.K()
  for id, q in pairs(QM.me.quests) do
    local h = q.header
    if h and h ~= "" and K.dq[id] ~= h then
      local known = D.byName(h)
      local kind = (not known) and tagKind(id) or nil
      local inDB = known and not known.learned and (function() for _, x in ipairs(known.quests) do if x == id then return true end end end)()
      if (known and not inDB) or kind then
        K.dq[id] = h
        if kind and not K.inst[h] then K.inst[h] = { kind = kind } end
        dirty = true
        QM.send(table.concat({ "Y", id, QM.clean(h, 60) }, QM.SEP), "y" .. id)
      end
    end
  end
end

-- Instances: remember where you stood outside, so the first time you enter one we know its entrance.
local lastOutdoor
C_Timer.NewTicker(4, function()
  local inInst = IsInInstance and IsInInstance()
  if not inInst then
    local map, x, y = QM.playerPos()
    if map and x then lastOutdoor = { map = map, x = x, y = y, t = GetTime() } end
  end
end)
QM:On("ENTERED_WORLD", function()
  C_Timer.After(1, function()
    local inInst, kind = false, nil
    if IsInInstance then inInst, kind = IsInInstance() end
    if not inInst or not (kind == "party" or kind == "raid") then return end
    local name = GetInstanceInfo and QM.safe((GetInstanceInfo()))
    if not name or name == "" then return end
    local K = QM.K()
    local e = K.inst[name] or {}
    e.kind = kind
    if not e.x and lastOutdoor and GetTime() - lastOutdoor.t < 180 then
      e.map, e.x, e.y = lastOutdoor.map, lastOutdoor.x, lastOutdoor.y
    end
    K.inst[name] = e
    dirty = true
    if e.x then
      QM.send(table.concat({ "N", QM.clean(name, 60), kind, e.map, string.format("%.4f", e.x), string.format("%.4f", e.y) }, QM.SEP), "n" .. name)
    end
    QM:Changed()
  end)
end)

local learnPending = false
QM:On("UPDATE", function()
  if learnPending then return end
  learnPending = true
  C_Timer.After(1, function() learnPending = false; pcall(learnFromLog) end)
end)
-- The dungeon's quests your character can ever take (race, class, faction).
function D.questsFor(dg)
  local out = {}
  for _, id in ipairs(dg.quests) do if QM.questForMe(id) then out[#out + 1] = id end end
  return out
end

local function myLevel() return UnitLevel("player") or 1 end

-- What a dungeon quest needs from you right now.
--   have / done / ready (go get it) / chain (an earlier quest first) / finish (finish one in your log first)
--   level (you're too low for the next step) / item (starts from an item) / unknown (start not known)
function D.state(id)
  if QM.me.quests[id] then return "have" end
  if QM.completedByMe(id) then return "done" end
  local s = QM.nextStep(id)
  if s.kind == "finish" then return "finish", s end
  if QM.minLevelOf(s.qid) > myLevel() then return "level", s end
  local g = s.giver
  if g and g.item then return "item", s end
  -- in the database but with no quest giver: picked up inside the dungeon (an escort, something you find)
  if not g and s.qid == id and QM.DQ(id) and not QM.DQ(id)[8] then return "inside", s end
  if not (g and g.map and g.x) then return "unknown", s end
  if s.qid ~= id then return "chain", s end
  return "ready", s
end

-- All quests that are part of getting a dungeon's quests (its quests + everything leading to them).
local chainCache = {}
function D.chainSet(dg)
  local c = chainCache[dg.area]
  if c and GetTime() - c.t < 5 then return c.set end
  local set = {}
  for _, id in ipairs(D.questsFor(dg)) do
    for _, q in ipairs(QM.pathTo(id)) do set[q] = true end
  end
  chainCache[dg.area] = { t = GetTime(), set = set }
  return set
end

-- The trip: stops grouped by place (one NPC can give several quests), nearest first.
function D.plan(dg)
  local p = { stops = {}, finish = {}, later = {}, inside = {}, have = {}, done = {}, total = 0 }
  local byKey = {}
  for _, id in ipairs(D.questsFor(dg)) do
    p.total = p.total + 1
    local st, s = D.state(id)
    if st == "have" then p.have[#p.have + 1] = id
    elseif st == "done" then p.done[#p.done + 1] = id
    elseif st == "ready" or st == "chain" then
      local g = s.giver
      local key = (g.npc or "?") .. ":" .. g.map .. ":" .. math.floor(g.x * 50) .. ":" .. math.floor(g.y * 50)
      local stop = byKey[key]
      if not stop then
        stop = { giver = g, steps = {}, stepSet = {}, forQuests = {}, dist = QM.distanceTo(g.map, g.x, g.y) }
        byKey[key] = stop
        p.stops[#p.stops + 1] = stop
      end
      if not stop.stepSet[s.qid] then stop.stepSet[s.qid] = true; stop.steps[#stop.steps + 1] = s.qid end
      stop.forQuests[#stop.forQuests + 1] = id
    elseif st == "finish" then
      p.finish[#p.finish + 1] = { id = id, step = s }
    elseif st == "inside" or (st == "item" and s.qid == id) then
      p.inside[#p.inside + 1] = id
    else
      p.later[#p.later + 1] = { id = id, state = st, step = s }
    end
  end
  table.sort(p.stops, function(a, b)
    if (a.dist ~= nil) ~= (b.dist ~= nil) then return a.dist ~= nil end
    if a.dist and b.dist and a.dist ~= b.dist then return a.dist < b.dist end
    return (a.giver.npc or "") < (b.giver.npc or "")
  end)
  p.ready = #p.have + #p.done
  return p
end

-- How many of a dungeon's quests a party member has right now.
function D.mateCount(dg, full)
  local m = QM.mates[full]
  if not (m and m.synced) then return nil end
  local n = 0
  for _, id in ipairs(dg.quests) do if m.quests[id] then n = n + 1 end end
  return n
end

-- Is the dungeon a good fit for your level?
function D.fits(dg)
  local L = myLevel()
  return dg.hi >= L - 2 and dg.lo <= L + 3
end

function D.entrance(dg)
  local e = dg.entrances[1]
  if not e then return nil end
  return { map = e[1], x = e[2], y = e[3], npc = dg.name .. " entrance" }
end

---------------------------------------------------------------------------------------------------
-- The party task
---------------------------------------------------------------------------------------------------

function D.task() return QM.DB and QM.DB.task and D.get(QM.DB.task.area) end

local lastAnnounced
function D.setTask(area, from)
  if area then
    QM.DB.task = { area = area, t = time(), by = from }
  else
    QM.DB.task = nil
  end
  lastAnnounced = nil
  if not from then
    QM.send(table.concat({ "T", area or 0, (QM.DB.task and QM.DB.task.t) or time() }, QM.SEP), "task")
    if area then
      local dg = D.get(area)
      QM.toast("me", "task", { title = dg.name }, nil, { area = area })
    end
  end
  QM:Changed()
end

QM:On("PARTY_TASK", function(full, area, t)
  local cur = QM.DB.task
  if (cur and cur.area) == area then return end
  -- the newest choice wins (so two people syncing never swap their dungeons)
  if cur and cur.t and t and t > 0 and t < cur.t then return end
  if area then
    local dg = D.get(area)
    if not dg then return end
    QM.DB.task = { area = area, t = time(), by = full }
    QM.toast(full, "task", { title = dg.name }, nil, { area = area })
  elseif cur and cur.by == full then
    QM.DB.task = nil
  end
  lastAnnounced = nil
  QM:Changed()
end)

-- The one next thing to do for the task: a stop, a quest to finish first, or the entrance.
-- Pick up everything you can on the way first; then finish the quests that unlock the rest.
function D.nextAction(dg)
  local p = D.plan(dg)
  local stop = p.stops[1]
  if stop then return { kind = "stop", stop = stop }, p end
  if #p.finish > 0 then
    local f = p.finish[1]
    return { kind = "finish", qid = f.step.qid, forQuest = f.id }, p
  end
  return { kind = "entrance", place = D.entrance(dg) }, p
end

function D.stopText(stop)
  local n = #stop.steps
  local names = {}
  for i, qid in ipairs(stop.steps) do
    if i > 2 then names[#names + 1] = "+" .. (n - 2) .. " more"; break end
    names[#names + 1] = QM.titleOf(qid) or "?"
  end
  return (stop.giver.npc or "the quest giver"), table.concat(names, ", "), n
end

function D.go(dg, opts)
  local a = D.nextAction(dg)
  if a.kind == "finish" then QM.trackOwnQuest(a.qid)
  elseif a.kind == "stop" then
    local npc, names, n = D.stopText(a.stop)
    QM.guide(a.stop.giver, { npc = npc, title = n > 1 and (n .. " quests: " .. names) or names, verb = "Pick up" }, opts)
  elseif a.place then
    QM.guide(a.place, { npc = dg.name, title = "the dungeon entrance", verb = "Go to" }, opts)
  end
end

-- After you pick something up, say where to go next (once per stop).
local function announceNext()
  local dg = D.task()
  if not dg then return end
  local a, p = D.nextAction(dg)
  local key = a.kind .. ":" .. (a.qid or (a.stop and (a.stop.giver.npc or "") .. a.stop.giver.x) or "e")
  if key == lastAnnounced then return end
  lastAnnounced = key
  QM.toast("me", "nextstop", { title = dg.name }, nil, { area = dg.area, action = a, plan = p })
end
D.announceNext = announceNext

---------------------------------------------------------------------------------------------------
-- Auto-share and auto-accept while getting ready for a dungeon
---------------------------------------------------------------------------------------------------

local function someoneLacks(id)
  for _, full in ipairs(QM.mateList()) do
    local m = QM.mates[full]
    if not m then return true end
    if m.demo then
    elseif not m.synced or (not m.quests[id] and not m.done[id]) then return true end
  end
  return false
end

function D.shareIfNeeded(id, quiet)
  local q = QM.me.quests[id]
  if not (q and q.share and QM.groupChannel()) then return false end
  if not someoneLacks(id) then return false end
  QM.pushQuest(id)
  if not quiet then QM.toast("me", "shared", q) end
  return true
end

-- Share every task quest in your log that someone still needs, one every few seconds.
function D.shareAll(dg)
  local set = D.chainSet(dg)
  local todo = {}
  for id, q in pairs(QM.me.quests) do
    if set[id] and q.share and someoneLacks(id) then todo[#todo + 1] = id end
  end
  if #todo == 0 then QM.print("your party already has every quest you can share for %s.", dg.name); return end
  for i, id in ipairs(todo) do
    C_Timer.After((i - 1) * 3, function() D.shareIfNeeded(id) end)
  end
  QM.print("sharing %d quest%s with your party...", #todo, #todo == 1 and "" or "s")
end

QM:On("ACCEPTED", function(id)
  local dg = D.task()
  if not dg or not D.chainSet(dg)[id] then return end
  if QM.DB.autoShare then C_Timer.After(1.5, function() D.shareIfNeeded(id) end) end
  C_Timer.After(2.5, announceNext)
end)

QM:On("DETAIL", function(id)
  local dg = D.task()
  if not (dg and QM.DB.autoAccept and D.chainSet(dg)[id]) then return end
  C_Timer.After(0.3, function()
    if GetQuestID and GetQuestID() == id and AcceptQuest then pcall(AcceptQuest) end
  end)
end)

---------------------------------------------------------------------------------------------------
-- Journal pages (drawn into the journal's wide panel)
---------------------------------------------------------------------------------------------------

local function stateLine(id)
  local st, s = D.state(id)
  if st == "have" then return C.green .. "In your log|r"
  elseif st == "done" then return C.grey .. "Done|r"
  elseif st == "ready" then
    local g = s.giver
    local dist = QM.distanceTo(g.map, g.x, g.y)
    return "From " .. (g.npc or "?") .. C.grey .. ", " .. (QM.mapName(g.map) or "") ..
           (dist and string.format(", %d yd", math.floor(dist / 10 + 0.5) * 10) or "") .. "|r"
  elseif st == "chain" then
    return C.orange .. "Earlier quest first: |r" .. C.gold .. (QM.titleOf(s.qid) or "?") .. "|r" ..
           C.grey .. " (step " .. s.n .. " of " .. s.total .. ")|r"
  elseif st == "finish" then
    return C.orange .. "Finish |r" .. C.gold .. (QM.titleOf(s.qid) or "?") .. "|r" .. C.orange .. " first (it's in your log)|r"
  elseif st == "level" then
    return C.grey .. "Needs level " .. QM.minLevelOf(s.qid) .. (s.qid ~= id and (" for " .. (QM.titleOf(s.qid) or "an earlier quest")) or "") .. "|r"
  elseif st == "item" then
    return C.soft .. "Starts from an item you find: |r" .. (s.giver.item or "?")
  elseif st == "inside" then
    return C.soft .. "You get this one inside the dungeon|r"
  end
  return C.grey .. "Where it starts isn't known|r"
end

local function partyIcons(id)
  local parts = {}
  for _, full in ipairs(QM.mateList()) do
    local m = QM.mates[full]
    if m and m.synced then
      if m.quests[id] then parts[#parts + 1] = QM.nameText(full) .. " " .. W.markup("link", 12)
      elseif m.done[id] then parts[#parts + 1] = QM.nameText(full) .. " " .. W.markup("done", 12)
      else parts[#parts + 1] = C.grey .. QM.short(full) .. " -|r" end
    end
  end
  return table.concat(parts, "   ")
end

-- The dungeon list.
function D.renderList(d, J)
  local y = -8
  y = d:text(y, "Dungeons", "GameFontNormalLarge", 10, nil, 1, 0.82, 0)
  y = d:text(y, "Pick a dungeon and Questmates gets the whole party ready: it walks you to every quest for it, in order, and shares them with your friends.", "GameFontHighlightSmall", 10, nil, 0.8, 0.8, 0.8)

  local task = D.task()
  if task then
    y = D.renderTaskBox(d, y - 4, task)
  end

  local good, other, raids, finished = {}, {}, {}, {}
  local plans = {}
  for _, dg in ipairs(D.all()) do
    local total = #D.questsFor(dg)
    if total > 0 or dg.learned then
      local p = D.plan(dg)
      plans[dg] = p
      if p.total > 0 and #p.done == p.total then finished[#finished + 1] = dg
      elseif dg.raid then raids[#raids + 1] = dg
      elseif D.fits(dg) then good[#good + 1] = dg
      else other[#other + 1] = dg end
    end
  end
  local function row(dg)
    local top = y - 2
    local p = plans[dg]
    local isTask = task and task.area == dg.area
    local isDone = p.total > 0 and #p.done == p.total
    local levels = (dg.lo > 0) and ("   level " .. dg.lo .. (dg.hi ~= dg.lo and ("-" .. dg.hi) or "")) or ""
    d:card(top, 40, function() J.dungeon = dg.area; J.refresh() end, isTask and { 1, 0.82, 0 } or (isDone and { 0.4, 0.4, 0.4 }) or nil)
    if isDone then
      d:icon("done", 12, top - 12, 16)
      local _, fs = d:text(top - 5, C.grey .. dg.name .. "|r", "GameFontHighlight", 34, d.w - 160)
      d:strike(fs)
      d:text(top - 5, C.grey .. levels .. "|r", "GameFontHighlight", 34 + fs:GetStringWidth() + 4, 120)
      d:text(top - 22, C.grey .. "All " .. p.total .. " quest" .. (p.total == 1 and "" or "s") .. " you can do here are done|r", "GameFontHighlightSmall", 34, d.w - 160)
    else
      d:text(top - 5, C.gold .. dg.name .. "|r" .. C.grey .. levels .. "|r", "GameFontHighlight", 14, d.w - 150)
      local sub
      if p.total == 0 then sub = C.grey .. "No quests known yet - they're learned as your party finds them|r"
      else
        sub = p.total .. " quest" .. (p.total == 1 and "" or "s") .. " for you"
        if p.ready > 0 then sub = sub .. C.green .. "  -  " .. p.ready .. " picked up or done|r" end
        if #p.stops > 0 then sub = sub .. C.grey .. "  -  " .. #p.stops .. " place" .. (#p.stops == 1 and "" or "s") .. " to visit|r" end
      end
      if dg.learned or dg.partial then sub = sub .. C.grey .. "  (learned in game)|r" end
      d:text(top - 22, sub, "GameFontHighlightSmall", 14, d.w - 150)
      if isTask then
        d:text(top - 13, C.green .. "Getting ready|r", "GameFontHighlightSmall", d.w - 130, 120)
      elseif p.total > 0 then
        d:action("Get ready", top - 9, function() D.setTask(dg.area); J.dungeon = dg.area; J.refresh() end, 110,
                 "Makes this the party's dungeon: Questmates guides you to its quests and shares them.")
      end
    end
    y = top - 44
  end
  y = d:section(y, "Good for your level", (#good == 0) and "None right around your level - see the others below." or nil)
  for _, dg in ipairs(good) do row(dg) end
  if #other > 0 then
    y = d:section(y, "Other dungeons")
    for _, dg in ipairs(other) do row(dg) end
  end
  if #raids > 0 then
    y = d:section(y, "Raids")
    for _, dg in ipairs(raids) do row(dg) end
  end
  if #finished > 0 then
    y = d:section(y, "All done", "You've finished every quest you can do in these.")
    for _, dg in ipairs(finished) do row(dg) end
  end  y = d:text(y - 6, C.grey .. "Quest data: QuestieDB (WoW Forever). Positions are where the quest giver usually stands.|r", "GameFontDisableSmall", 10)
  return y
end

-- The "what to do next" box for the party's dungeon.
function D.renderTaskBox(d, y, dg)
  local a, p = D.nextAction(dg)
  local top = y
  local box = d:card(top, 62, nil, { 1, 0.82, 0.2 })
  box:EnableMouse(false)
  d:text(top - 6, C.gold .. "Getting ready for " .. dg.name .. "|r" .. C.grey .. "   " .. p.ready .. " of " .. p.total .. " quests|r", "GameFontNormal", 16, d.w - 150)
  local line, btn
  if a.kind == "finish" then
    line = "First finish " .. C.gold .. (QM.titleOf(a.qid) or "?") .. "|r (it's in your log) - it unlocks " .. C.gold .. (QM.titleOf(a.forQuest) or "a dungeon quest") .. "|r."
    btn = "Show me"
  elseif a.kind == "stop" then
    local npc, names, n = D.stopText(a.stop)
    local dist = a.stop.dist and string.format(" - %d yards away", math.floor(a.stop.dist / 10 + 0.5) * 10) or ""
    line = "Next stop: " .. C.white .. npc .. "|r" .. C.grey .. ", " .. (QM.mapName(a.stop.giver.map) or "") .. dist .. "|r\n" ..
           "Pick up " .. C.gold .. names .. "|r" .. (#p.stops > 1 and (C.grey .. "   (" .. (#p.stops - 1) .. " more stop" .. (#p.stops > 2 and "s" or "") .. " after this)|r") or "")
    btn = "Take me there"
  elseif a.place then
    line = C.green .. "You have every quest you can get for now!|r Head to the dungeon entrance" .. C.grey .. ", " .. (QM.mapName(a.place.map) or "") .. "|r."
    btn = "Take me there"
  else
    line = C.green .. "You have every quest you can get for now!|r"
  end
  d:text(top - 24, line, "GameFontHighlightSmall", 16, d.w - 160)
  if btn then d:action(btn, top - 18, function() D.go(dg) end, 130) end
  return top - 70
end

-- One dungeon's page.
function D.renderDungeon(d, J, dg)
  local y = -8
  d:action("All dungeons", y + 2, function() J.dungeon = nil; J.refresh() end, 110)
  y = d:text(y, dg.name, "QuestTitleFont", 10, d.w - 140, 1, 0.82, 0)
  local e = D.entrance(dg)
  local ent = ""
  if e then
    local dist = QM.distanceTo(e.map, e.x, e.y)
    ent = "   Entrance: " .. (QM.mapName(e.map) or "?") .. (dist and string.format(", %d yd", math.floor(dist / 10 + 0.5) * 10) or "")
  end
  if not e then ent = "   Entrance: not known yet - it's learned the first time someone in your party goes in" end
  y = d:text(y, C.grey .. (dg.lo > 0 and ("Level " .. dg.lo .. (dg.hi ~= dg.lo and ("-" .. dg.hi) or "")) or "") .. (dg.raid and "  (raid)" or "") .. ent .. "|r", "GameFontHighlightSmall", 10, d.w - 150)

  local task = D.task()
  if task and task.area == dg.area then
    y = D.renderTaskBox(d, y - 6, dg)
  else
    local top = y - 6
    local box = d:card(top, 52, nil, { 1, 0.82, 0.2 })
    box:EnableMouse(false)
    d:text(top - 8, C.white .. "Doing this dungeon with your party?|r", "GameFontHighlight", 16, d.w - 160)
    d:text(top - 26, C.soft .. "Questmates will walk you to every quest for it, in order, and share them with your friends.|r", "GameFontHighlightSmall", 16, d.w - 160)
    d:action("Get ready", top - 14, function() D.setTask(dg.area); J.refresh() end, 130)
    y = top - 60
  end

  local p = D.plan(dg)
  local function questRow(id, sub)
    local title, level = QM.titleOf(id)
    local st = D.state(id)
    local icon = (st == "have") and "turnin" or (st == "done") and "done" or (st == "ready") and "pickup" or "lock"
    d:icon(icon, 14, y, 14)
    y = d:text(y, C.gold .. (title or ("Quest " .. id)) .. "|r" .. C.grey .. "  [" .. (level or "?") .. "]|r", "GameFontHighlightSmall", 34, d.w - 50)
    y = d:text(y, sub or stateLine(id), "GameFontHighlightSmall", 34, d.w - 50)
    local party = partyIcons(id)
    if party ~= "" then y = d:text(y, party, "GameFontHighlightSmall", 34, d.w - 50) end
    y = y - 5
  end

  if #p.stops > 0 then
    y = d:section(y, "Where to go, in order", "Nearest first. The journal and the tracker always show the next stop.")
    for i, stop in ipairs(p.stops) do
      local npc, _, n = D.stopText(stop)
      local dist = stop.dist and string.format(", %d yd", math.floor(stop.dist / 10 + 0.5) * 10) or ""
      y = d:text(y, (i == 1 and (C.orange .. "Next: |r") or (C.grey .. i .. ". |r")) .. C.white .. npc .. "|r" ..
                 C.grey .. " - " .. (QM.mapName(stop.giver.map) or "?") .. dist .. "|r", "GameFontHighlight", 14, d.w - 30)
      for _, qid in ipairs(stop.steps) do
        local isDungeonQuest = false
        for _, f in ipairs(stop.forQuests) do if f == qid then isDungeonQuest = true end end
        local leads = ""
        if not isDungeonQuest then
          for _, f in ipairs(stop.forQuests) do
            local s = QM.nextStep(f)
            if s.qid == qid then
              local ft = QM.titleOf(f)
              if ft == QM.titleOf(qid) then leads = C.grey .. "  (part " .. s.n .. " of " .. s.total .. ")|r"
              else leads = C.grey .. "  (leads to " .. (ft or "?") .. ")|r" end
              break
            end
          end
        end
        y = d:text(y, "   " .. W.markup("pickup", 12) .. " " .. C.gold .. (QM.titleOf(qid) or "?") .. "|r" .. leads, "GameFontHighlightSmall", 14, d.w - 30)
      end
      y = y - 6
    end
  end
  if #p.finish > 0 then
    y = d:section(y, "Finish these first", "They're in your log and unlock dungeon quests.")
    for _, f in ipairs(p.finish) do questRow(f.id) end
  end
  if #p.have > 0 then
    y = d:section(y, "In your quest log")
    for _, id in ipairs(p.have) do questRow(id) end
    if QM.groupChannel() then
      d:action("Share all with party", y + 4, function() D.shareAll(dg) end, 150, "Shares every quest for this dungeon your friends don't have yet.")
      y = y - 24
    end
  end
  if #p.inside > 0 then
    y = d:section(y, "You get these inside", "They start in the dungeon - from someone you meet or an item you find there.")
    for _, id in ipairs(p.inside) do questRow(id) end
  end
  if #p.later > 0 then
    y = d:section(y, "Not yet", "Higher level, or the start isn't known.")
    for _, l in ipairs(p.later) do questRow(l.id) end
  end
  if #p.done > 0 then
    y = d:section(y, "Already done")
    for _, id in ipairs(p.done) do
      d:icon("done", 14, y, 14)
      local ny, fs = d:text(y, C.grey .. (QM.titleOf(id) or ("Quest " .. id)) .. "|r", "GameFontHighlightSmall", 34, d.w - 50)
      d:strike(fs)
      y = ny - 2
    end
  end
  return y
end
