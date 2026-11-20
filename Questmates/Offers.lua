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

-- Is this quest marked as not offered to you (and still not offered at your level)?
function O.blocked(id)
  if not QM.DB then return nil end
  local b = charDB().blocked[id]
  if not b then return nil end
  if (UnitLevel("player") or 1) > (b.level or 0) then return nil end   -- you levelled since: try again
  return b
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
function O.hints(id)
  local list = {}
  for _, qid in ipairs(O.candidates(id)) do
    if not QM.completedByMe(qid) and not QM.me.quests[qid] then
      local who = {}
      for _, full in ipairs(QM.mateList()) do
        local m = QM.mates[full]
        if m and m.unlock and m.unlock[id] and m.unlock[id][qid] then who[#who + 1] = full end
      end
      list[#list + 1] = { qid = qid, who = who }
    end
  end
  table.sort(list, function(a, b)
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

local function check(npc, offered)
  if not npc or not QM.DData then return end
  local c = charDB()
  local lvl = UnitLevel("player") or 1
  local newly = {}
  for qid, r in pairs(QM.DData.Q) do
    if r[8] and r[8][1] == "npc" and r[8][2] == npc then
      if offered[qid] then
        c.blocked[qid] = nil
      elseif not QM.me.quests[qid] and not QM.completedByMe(qid) and QM.questForMe(qid)
             and (r[3] or 0) <= lvl and QM.nextStep(qid).qid == qid and relevant(qid) then
        if not c.blocked[qid] then newly[#newly + 1] = qid end
        c.blocked[qid] = { npc = npc, level = lvl, t = time() }
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

local ev = CreateFrame("Frame")
for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event)
  local offered, ok = {}, false
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
  if ok then
    local npc = npcName()
    C_Timer.After(0, function() pcall(check, npc, offered) end)
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
