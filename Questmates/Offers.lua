-- Questmates / Offers.lua
-- The quest database can miss a prerequisite (WoW Forever's newest quests especially). So when you talk to a
-- quest giver, Questmates checks which quests they really offer you. A quest it expected but they don't offer
-- is marked "blocked" (for this character, until you level up or it shows up): the guide skips it, and its page
-- explains it and finds what probably unlocks it:
--   * your friends' games report which of that NPC's nearby quests they've done that you haven't ("U"/"V")
--   * otherwise, that NPC's other quests around that level you haven't done
-- When you later accept it, the quest you turned in just before is recorded as its prerequisite (Core).

local _, QM = ...
local C = QM.C
local O = {}
QM.Offers = O

local function charDB()
  QM.DB.chars = QM.DB.chars or {}
  local me = QM.myFull()
  QM.DB.chars[me] = QM.DB.chars[me] or {}
  local c = QM.DB.chars[me]
  c.blocked = c.blocked or {}
  return c
end

---------------------------------------------------------------------------------------------------
-- Ask the game: which quests can you pick up right now? (the same data the map's "!" quest offers use:
-- C_QuestLine.RequestQuestLinesForMap -> QUESTLINE_UPDATE -> GetAvailableQuestLines). The server decides it,
-- so hidden prerequisites, level and faction are already taken into account.
---------------------------------------------------------------------------------------------------

local avail = {}       -- [uiMapID] = { t, set = {questID = true}, pos = {questID = {x, y}}, reliable }
local requested = {}   -- [uiMapID] = time asked
local function canAsk()
  return C_QuestLine and C_QuestLine.RequestQuestLinesForMap and C_QuestLine.GetAvailableQuestLines and true or false
end
O.canAsk = canAsk

function O.request(map)
  if not (canAsk() and map) then return end
  if requested[map] and GetTime() - requested[map] < 15 then return end
  requested[map] = GetTime()
  pcall(C_QuestLine.RequestQuestLinesForMap, map)
end

local function readMap(map)
  if not QM.DData then return end
  local set, pos = {}, {}
  local ok, list = pcall(C_QuestLine.GetAvailableQuestLines, map)
  if ok and type(list) == "table" then
    for _, info in ipairs(list) do
      local id = QM.safe(info.questID)
      if id then set[id] = true; pos[id] = { QM.safe(info.x), QM.safe(info.y) } end
    end
  end
  if C_QuestLine.GetForceVisibleQuests then
    local ok2, force = pcall(C_QuestLine.GetForceVisibleQuests, map)
    if ok2 and type(force) == "table" then for _, id in ipairs(force) do set[id] = true end end
  end
  -- Can we trust a quest's ABSENCE? Only if the game lists most of the quests on this map that you can
  -- plainly take (no prerequisites at all, level ok, not done).
  local lvl = UnitLevel("player") or 1
  local expected, found = 0, 0
  for qid, r in pairs(QM.DData.Q) do
    local st = r[8]
    if st and st[3] == map and not r[6] and not r[7] and (r[3] or 0) <= lvl and not QM.me.quests[qid]
       and QM.questForMe(qid) and not QM.completedByMe(qid) then
      expected = expected + 1
      if set[qid] then found = found + 1 end
    end
  end
  avail[map] = { t = GetTime(), set = set, pos = pos, expected = expected, found = found,
                 reliable = expected >= 3 and found / expected >= 0.6 }
  local n, ids = 0, {}
  for id in pairs(set) do n = n + 1; if #ids < 40 then ids[#ids + 1] = id end end
  QM.dbg("available on map %s: %d quests (expected %d, found %d, reliable %s) %s", tostring(map), n, expected, found,
         tostring(avail[map].reliable), table.concat(ids, ","))
end

-- "available" / "unavailable" / nil (the game hasn't told us, or its list for that map isn't complete enough)
function O.status(id)
  local q = QM.DQ(id)
  local map = q and q[8] and q[8][3]
  local a = map and avail[map]
  if not a then return nil end
  if a.set[id] then return "available" end
  if a.reliable and GetTime() - a.t < 600 then return "unavailable" end
  return nil
end

-- Where the game puts the quest offer (more exact than the database).
function O.offerPos(id)
  local q = QM.DQ(id)
  local map = q and q[8] and q[8][3]
  local a = map and avail[map]
  local p = a and a.pos[id]
  if p and p[1] then return map, p[1], p[2] end
end

-- Is this quest not available to you (the game says so, or the NPC didn't offer it)?
function O.blocked(id)
  if not QM.DB then return nil end
  local st = O.status(id)
  if st == "available" then return nil end
  local b = charDB().blocked[id]
  if b and (UnitLevel("player") or 1) > (b.level or 0) then b = nil end   -- you levelled since: try again
  if b then return b end
  if st == "unavailable" then
    local q = QM.DQ(id)
    return { npc = q and q[8] and q[8][2], auto = true }
  end
  return nil
end

-- Which maps matter: where the next quests are (dungeon task, friends' quests, the guide) + where you are.
local function interestingMaps()
  local maps = {}
  local pm = QM.playerPos()
  if pm then maps[pm] = true end
  local function add(id)
    local q = QM.DQ(id)
    if q and q[8] and q[8][3] then maps[q[8][3]] = true end
  end
  local g = QM.guideTarget
  if g and g.qid then add(g.qid) end
  local dg = QM.Dungeons and QM.Dungeons.task()
  if dg then for id in pairs(QM.Dungeons.chainSet(dg)) do add(id) end end
  for _, full in ipairs(QM.mateList()) do
    local m = QM.mates[full]
    if m and m.quests then for id in pairs(m.quests) do for _, p in ipairs(QM.pathTo(id)) do add(p) end end end
  end
  return maps
end

function O.refresh()
  if not canAsk() then return end
  for map in pairs(interestingMaps()) do O.request(map) end
end

local qev = CreateFrame("Frame")
pcall(qev.RegisterEvent, qev, "QUESTLINE_UPDATE")
qev:SetScript("OnEvent", function(_, _, requestRequired)
  if requestRequired then
    for map, t in pairs(requested) do if GetTime() - t < 300 then requested[map] = nil; O.request(map) end end
    return
  end
  for map, t in pairs(requested) do if GetTime() - t < 300 then pcall(readMap, map) end end
  QM:Changed()
end)
C_Timer.NewTicker(30, function() pcall(O.refresh) end)
for _, e in ipairs({ "ENTERED_WORLD", "ACCEPTED", "TURNED_IN", "LEARNED" }) do
  QM:On(e, function() C_Timer.After(2, function() pcall(O.refresh) end) end)
end
local refreshSoon = false
QM:On("UPDATE", function()
  if refreshSoon then return end
  refreshSoon = true
  C_Timer.After(5, function() refreshSoon = false; pcall(O.refresh) end)
end)

-- "He doesn't offer it?" - the player tells us (the game has no way to ask an NPC without talking to them).
function O.markBlocked(qids, npc)
  local c = charDB()
  for _, qid in ipairs(qids) do
    c.blocked[qid] = { npc = npc, level = UnitLevel("player") or 1, t = time(), byHand = true }
    O.ask(qid)
  end
  if QM.guideTarget and QM.guideTarget.npc == npc then QM.stopGuide() end
  QM:Changed()
end

-- Quests near this one that could unlock it: same NPC (gives or takes), a bit lower or equal level.
function O.candidates(id)
  local q = QM.DQ(id)
  local st = q and q[8]
  local npc = st and st[2]
  local lvl = q and q[2] or 0
  local out = {}
  if not npc then return out end
  for qid, r in pairs(QM.DData.Q) do
    if qid ~= id and r[2] and r[2] >= lvl - 8 and r[2] <= lvl and ((r[8] and r[8][2] == npc) or r[9] == npc)
       and QM.questForMe(qid) then
      out[#out + 1] = qid
    end
  end
  table.sort(out, function(a, b) return (QM.DData.Q[a][2] or 0) > (QM.DData.Q[b][2] or 0) end)
  return out
end

-- What you could do about it: candidates you haven't done, the ones a friend has done first.
local hintCache = {}
function O.hints(id)
  local c = hintCache[id]
  if c and GetTime() - c.t < 5 then return c.list end
  local list = O.computeHints(id)
  hintCache[id] = { t = GetTime(), list = list }
  return list
end
QM:On("UPDATE", function() wipe(hintCache) end)
function O.computeHints(id)
  local list = {}
  for _, qid in ipairs(O.candidates(id)) do
    if QM.me.quests[qid] and QM.me.quests[qid].state ~= -1 then
      list[#list + 1] = { qid = qid, who = {}, inLog = true }
    elseif not QM.completedByMe(qid) then
      local who = {}
      for _, full in ipairs(QM.mateList()) do
        local m = QM.mates[full]
        if m and m.unlock and m.unlock[id] and m.unlock[id][qid] then who[#who + 1] = full end
      end
      list[#list + 1] = { qid = qid, who = who }
    end
  end
  table.sort(list, function(a, b)
    if (a.inLog == true) ~= (b.inLog == true) then return a.inLog == true end
    if (#a.who > 0) ~= (#b.who > 0) then return #a.who > 0 end
    return (QM.DData.Q[a.qid][2] or 0) > (QM.DData.Q[b.qid][2] or 0)
  end)
  return list
end

-- Ask friends which candidates they've done (answer arrives as "V").
local asked = {}
function O.ask(id)
  if asked[id] and GetTime() - asked[id] < 60 then return end
  asked[id] = GetTime()
  QM.send(table.concat({ "U", id }, QM.SEP))
end

QM:On("UNLOCK_ASK", function(full, id)
  local done = {}
  for _, qid in ipairs(O.candidates(id)) do
    if QM.completedByMe(qid) or QM.me.quests[qid] then done[#done + 1] = qid end
  end
  if QM.me.quests[id] or QM.completedByMe(id) then
    QM.send(table.concat({ "V", full, id, table.concat(done, ",") }, QM.SEP))
  end
end)

QM:On("UNLOCK_ANSWER", function(full, id, list)
  local m = QM.mates[full]
  if not m then return end
  m.unlock = m.unlock or {}
  local set = {}
  for x in (list or ""):gmatch("%d+") do set[tonumber(x)] = true end
  m.unlock[id] = set
  QM:Changed()
end)

---------------------------------------------------------------------------------------------------
-- Talking to a quest giver
---------------------------------------------------------------------------------------------------

-- Is this quest one you're actively after (guide, dungeon plan, a friend's quest)?
local function relevant(id)
  local g = QM.guideTarget
  if g and g.qid == id then return true end
  local dg = QM.Dungeons and QM.Dungeons.task()
  if dg and QM.Dungeons.chainSet(dg)[id] then return true end
  for _, full in ipairs(QM.mateList()) do
    local m = QM.mates[full]
    if m and m.quests then
      for qid in pairs(m.quests) do
        if qid == id then return true end
        local s = QM.nextStep(qid)
        if s and s.qid == id then return true end
      end
    end
  end
  return false
end

function O.availInfo(map) return avail[map] end

local function check(npc, offered)
  local oids = {}
  for id in pairs(offered or {}) do oids[#oids + 1] = id end
  QM.dbg("talked to %s: offers %s", tostring(npc), (#oids > 0) and table.concat(oids, ",") or "nothing new")
  if not npc or not QM.DData then return end
  local c = charDB()
  local lvl = UnitLevel("player") or 1
  local newly = {}
  for qid, r in pairs(QM.DData.Q) do
    if r[8] and r[8][1] == "npc" and r[8][2] == npc then
      if offered[qid] then
        c.blocked[qid] = nil
      elseif relevant(qid) or (QM.Dungeons and QM.Dungeons.task() and QM.Dungeons.chainSet(QM.Dungeons.task())[qid]) then
        local why
        if QM.me.quests[qid] then why = "in log"
        elseif QM.completedByMe(qid) then why = "done"
        elseif not QM.questForMe(qid) then why = "not for this character"
        elseif O.status(qid) == "available" then why = "game lists it as available"
        elseif (r[3] or 0) > lvl then why = "level " .. tostring(r[3])
        elseif QM.nextStep(qid).qid ~= qid then why = "earlier step first: " .. tostring(QM.nextStep(qid).qid)
        end
        QM.dbg("  %d %s: %s", qid, tostring(r[1]), why and ("not marked (" .. why .. ")") or "NOT OFFERED -> marked")
        if not why then
          if not c.blocked[qid] then newly[#newly + 1] = qid end
          c.blocked[qid] = { npc = npc, level = lvl, t = time() }
        end
      end
    end
  end
  if #newly > 0 then
    for _, qid in ipairs(newly) do O.ask(qid) end
    QM.toast("me", "notoffered", { id = newly[1], title = QM.titleOf(newly[1]) }, nil, { npc = npc, more = #newly - 1 })
    -- the guide was going here for it: move on
    local g = QM.guideTarget
    if g and g.npc == npc then QM.stopGuide() end
    if QM.Dungeons then QM.Dungeons.announceNext() end
    QM:Changed()
  end
end

local function npcName()
  local n = QM.safe(UnitName("npc")) or QM.safe(UnitName("questnpc"))
  if n == UnitName("player") then return nil end
  return n
end

-- A quest list seen just now (gossip / greeting): a quest window that follows came from that list.
local lastList = { npc = nil, t = -999 }

local ev = CreateFrame("Frame")
for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event)
  QM.dbg("event %s (npc %s)", event, tostring(npcName()))
  local offered, ok = {}, false
  if event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
    -- the NPC opened an in-progress / turn-in window straight away: they have nothing new for you
    -- (with anything new to offer, the game shows their quest list first)
    local npc = npcName()
    if npc and not (lastList.npc == npc and GetTime() - lastList.t < 60) then
      C_Timer.After(0, function() local okc, err = pcall(check, npc, {}); if not okc then QM.dbg("check error: %s", tostring(err)) end end)
    else
      QM.dbg("  (came from their quest list - already checked)")
    end
    return
  end
  if event == "GOSSIP_SHOW" and C_GossipInfo and C_GossipInfo.GetAvailableQuests then
    local list
    ok, list = pcall(C_GossipInfo.GetAvailableQuests)
    if ok and type(list) == "table" then
      for _, q in ipairs(list) do if q.questID then offered[q.questID] = true end end
    else ok = false end
  elseif event == "QUEST_GREETING" and GetNumAvailableQuests then
    ok = true
    for i = 1, GetNumAvailableQuests() do
      local id = GetAvailableQuestInfo and select(5, GetAvailableQuestInfo(i))
      if not id then ok = false break end     -- can't tell the quest IDs here: don't guess
      offered[id] = true
    end
  end
  if not ok then QM.dbg("  could not read the quest list (%s)", event) end
  if ok then
    local npc = npcName()
    lastList.npc, lastList.t = npc, GetTime()
    C_Timer.After(0, function() local okc, err = pcall(check, npc, offered); if not okc then QM.dbg("check error: %s", tostring(err)) end end)
  end
end)

-- a quest dialog opened directly: that quest is offered
QM:On("DETAIL", function(id)
  if QM.DB and id then charDB().blocked[id] = nil end
end)
QM:On("ACCEPTED", function(id)
  if not (QM.DB and id) then return end
  local c = charDB()
  local b = c.blocked[id]
  c.blocked[id] = nil
  -- it wasn't offered before; the quest you turned in since then is what unlocked it
  local lt = QM.lastTurnin
  if b and lt and lt.id ~= id and not QM.prevOf(id) and (time() - (b.t or 0)) < 6 * 3600 then
    QM.K().prev[id] = lt.id
    QM.send(table.concat({ "A", id, lt.id }, QM.SEP) .. QM.SEP .. QM.SEP .. QM.SEP .. QM.SEP .. QM.SEP)
    QM.print("learned: %s unlocks %s.", C.gold .. (QM.titleOf(lt.id) or "?") .. "|r", C.gold .. (QM.titleOf(id) or "?") .. "|r")
  end
end)
