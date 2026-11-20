-- Questmates / Core.lua
-- Reads your quest log, shares it with your party as hidden addon messages, and keeps what every
-- party member is doing. It also learns, account-wide, where quests are picked up and turned in and
-- which quest unlocked which, so a friend who is missing a quest can be shown the way to catch up.
-- The UI files (Toasts, Tracker, Journal, Map) only read QM.* and listen for QM:On("UPDATE").

local ADDON, QM = ...
_G.Questmates = QM

QM.VERSION = "2.8.0"
QM.PREFIX = "QMATE2"
local SEP, OSEP = "~", "^"
local MAXMSG = 250
QM.SEP = SEP

QM.me = { quests = {}, focus = 0, focusSrc = "", zone = "", sub = "", full = "" }
QM.mates = {}       -- [Name-Realm] = everything we know about that party member
QM.roster = {}      -- [Name-Realm] = { unit, class, level }
local me, mates = QM.me, QM.mates

local lastSent, progressAt, acceptedAt, turnedIn, spotSentAt = {}, {}, {}, {}, {}
local manualFocus
local sentFocus, sentZone, sentPOI, lastDone
local lastFullSync = -999
QM.askedPath = {}

---------------------------------------------------------------------------------------------------
-- Tiny event bus for the UI
---------------------------------------------------------------------------------------------------

local listeners = {}
function QM:On(event, fn)
  listeners[event] = listeners[event] or {}
  table.insert(listeners[event], fn)
end
function QM:Fire(event, ...)
  for _, fn in ipairs(listeners[event] or {}) do
    local ok, err = pcall(fn, ...)
    if not ok and geterrorhandler then geterrorhandler()(err) end
  end
end
local changedPending = false
function QM:Changed()
  if changedPending then return end
  changedPending = true
  C_Timer.After(0.1, function() changedPending = false; QM:Fire("UPDATE") end)
end

---------------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------------

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function safe(v) if isSecret(v) then return nil end return v end
QM.safe = safe

QM.C = {
  gold = "|cffffd100", grey = "|cff8c8c8c", white = "|cffffffff", green = "|cff40ff70", red = "|cffff5050",
  orange = "|cffff9a30", blue = "|cff6fb7ff", soft = "|cffd8cfb8",
}
QM.REL = {
  both   = { 0.35, 0.85, 0.40, "You both have this quest" },
  theirs = { 1.00, 0.60, 0.19, "You don't have this quest" },
  done   = { 0.55, 0.55, 0.55, "You already completed this" },
  mine   = { 0.44, 0.72, 1.00, "A party member doesn't have this" },
  solo   = { 1.00, 0.82, 0.00, "" },
}

function QM.hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

local function clean(s, max)
  s = tostring(s or ""):gsub("[~%^|\r\n]", " ")
  if max and #s > max then
    s = s:sub(1, max)
    s = s:gsub("[\192-\255][\128-\191]*$", "")
  end
  return s
end
QM.clean = clean

local function split(s, sep)
  local out, start = {}, 1
  while true do
    local i = s:find(sep, start, true)
    if not i then out[#out + 1] = s:sub(start); return out end
    out[#out + 1] = s:sub(start, i - 1)
    start = i + 1
  end
end

local function myFull()
  local name = UnitName("player")
  local realm = GetNormalizedRealmName and GetNormalizedRealmName() or ""
  return (name or "?") .. "-" .. (realm or "")
end
QM.myFull = myFull

function QM.short(full) return (full and full:match("^[^-]+")) or full or "?" end

function QM.classOf(full)
  if full == "me" or full == me.full then local _, c = UnitClass("player"); return c end
  local r, m = QM.roster[full], mates[full]
  return (r and r.class) or (m and m.class)
end

function QM.classColor(full)
  local class = QM.classOf(full)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return c.r or 1, c.g or 1, c.b or 1, c.colorStr and ("|c" .. c.colorStr) or QM.hex({ c.r, c.g, c.b }) end
  return 1, 1, 1, "|cffffffff"
end
function QM.nameText(full) local _, _, _, h = QM.classColor(full); return h .. QM.short(full) .. "|r" end

function QM.completedByMe(id)
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
    local ok, v = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
    return ok and v == true
  end
  return false
end

-- How a quest relates to you: both / theirs / done.
function QM.relation(id)
  if me.quests[id] then return "both" end
  if QM.completedByMe(id) then return "done" end
  return "theirs"
end

-- For one of your quests: which party members lack it ("mine") or not ("both").
function QM.myRelation(id)
  local any = false
  for _, m in pairs(mates) do
    if m.synced then
      any = true
      if not m.quests[id] and not m.done[id] then return "mine" end
    end
  end
  return any and "both" or "solo"
end

function QM.progress(q)
  local have, need = 0, 0
  if not q then return 0, 0, 0 end
  if q.state == 1 then return 1, 1, 1 end
  for _, o in ipairs(q.obj) do
    if o.need and o.need > 0 then
      have = have + math.min(o.have, o.need)
      need = need + o.need
    end
  end
  if need == 0 then return 0, 0, 0 end
  return have / need, have, need
end

function QM.objText(t)
  t = tostring(t or "")
  t = t:gsub("%s*%d+%s*/%s*%d+%s*", " ")
  t = t:gsub("^[%s:]+", "")
  t = t:gsub("[%s:]+$", "")
  return t
end

local function playerMap()
  return C_Map and C_Map.GetBestMapForUnit and safe(C_Map.GetBestMapForUnit("player"))
end

function QM.playerPos(unit)
  unit = unit or "player"
  local map = C_Map and C_Map.GetBestMapForUnit and safe(C_Map.GetBestMapForUnit(unit))
  if not map then return nil end
  local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, unit)
  if ok and pos and pos.GetXY then
    local x, y = pos:GetXY()
    x, y = safe(x), safe(y)
    if x and y and (x > 0 or y > 0) then return map, x, y end
  end
  return map
end

-- Convert a point on one map to another map (zone <-> continent). nil when they don't overlap.
function QM.translate(fromMap, x, y, toMap)
  if not (fromMap and x and y and toMap) then return nil end
  if fromMap == toMap then return x, y end
  if not (C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
  local ok, cont, world = pcall(C_Map.GetWorldPosFromMapPos, fromMap, CreateVector2D(x, y))
  if not ok or not cont or not world then return nil end
  local ok2, _, pos = pcall(C_Map.GetMapPosFromWorldPos, cont, world, toMap)
  if not ok2 or not pos then return nil end
  local px, py = pos:GetXY()
  if not px or px < 0 or px > 1 or py < 0 or py > 1 then return nil end
  return px, py
end

-- Yards from you to a point, or nil when not on the same continent.
function QM.distanceTo(map, x, y)
  if not (map and x and y and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local pm, px, py = QM.playerPos()
  if not (pm and px) then return nil end
  local ok1, c1, w1 = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
  local ok2, c2, w2 = pcall(C_Map.GetWorldPosFromMapPos, pm, CreateVector2D(px, py))
  if not (ok1 and ok2 and c1 and c1 == c2 and w1 and w2) then return nil end
  local ax, ay = w1:GetXY()
  local bx, by = w2:GetXY()
  return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

function QM.mapName(map)
  local info = map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
  return info and info.name
end

function QM.placeText(p)
  if not p then return nil end
  local s
  if p.item then s = "the item " .. p.item .. " (it drops or is found somewhere)"
  else s = (p.npc and p.npc ~= "") and p.npc or "an item or object" end
  local zone = (p.zone and p.zone ~= "") and p.zone or QM.mapName(p.map)
  if zone then s = s .. ", " .. zone end
  if p.x and p.y and p.x > 0 then s = s .. string.format(" (%.0f, %.0f)", p.x * 100, p.y * 100) end
  return s
end
function QM.playSound(kit)
  if not (QM.DB and QM.DB.sound) then return end
  local id = SOUNDKIT and SOUNDKIT[kit]
  if id then pcall(PlaySound, id, "SFX") end
end

function QM.print(fmt, ...) print(QM.C.gold .. "Questmates:|r " .. string.format(fmt, ...)) end

---------------------------------------------------------------------------------------------------
-- Knowledge: account-wide memory of quest givers, turn-ins and chains (shared with party members)
---------------------------------------------------------------------------------------------------

local function K() return QM.DB.know end
QM.K = K

-- The quest database (QuestData.lua): Q[id] = { name, level, minLevel, raceMask, classMask, preAll, preAny,
-- starter = { kind, name, uiMapID, x, y, friendlyTo }, finisherName }
local function DQ(id) return QM.DData and QM.DData.Q[id] end
QM.DQ = DQ

local band = bit and bit.band or function(a, b)
  local r, p = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then r = r + p end
    a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
  end
  return r
end
QM.band = band

local myRaceBit, myClassBit, myFaction
local function me3()
  if not myRaceBit then
    local _, _, raceID = UnitRace("player")
    local _, _, classID = UnitClass("player")
    myRaceBit = raceID and 2 ^ (raceID - 1) or 0
    myClassBit = classID and 2 ^ (classID - 1) or 0
    myFaction = (UnitFactionGroup("player") == "Horde") and "H" or "A"
  end
  return myRaceBit, myClassBit, myFaction
end

-- Can you (your race, class and faction) ever take this quest?
function QM.questForMe(id)
  local q = DQ(id)
  if not q then return true end
  local rb, cb, fac = me3()
  if q[4] and q[4] > 0 and rb > 0 and band(q[4], rb) == 0 then return false end
  if q[5] and q[5] > 0 and cb > 0 and band(q[5], cb) == 0 then return false end
  local st = q[8]
  if st and st[6] and st[6] ~= "" and not st[6]:find(fac, 1, true) then return false end
  return true
end

function QM.titleOf(id)
  local t = K().titles[id]
  if t then return t[1], t[2] end
  for _, m in pairs(mates) do if m.quests[id] then return m.quests[id].title, m.quests[id].level end end
  local q = DQ(id)
  if q then return q[1], q[2] end
  if C_QuestLog.GetTitleForQuestID then
    local ok, s = pcall(C_QuestLog.GetTitleForQuestID, id)
    if ok and safe(s) and s ~= "" then return s end
  end
  return nil
end

function QM.minLevelOf(id) local q = DQ(id); return q and q[3] or 0 end

-- Where a quest starts: what someone saw when accepting it (most exact), else the quest database.
function QM.giverOf(id)
  local g = K().givers[id]
  if g then return g end
  local q = DQ(id)
  local st = q and q[8]
  if not st then return nil end
  if st[1] == "item" then return { item = st[2], fromDB = true } end
  return { npc = st[2], map = st[3], x = st[4], y = st[5], fromDB = true, object = (st[1] == "obj") or nil }
end

function QM.turninOf(id)
  local t = K().turnins[id]
  if t then return t end
  local q = DQ(id)
  return (q and q[9]) and { npc = q[9] } or nil
end

local function questLinePrev(id)
  if not (C_QuestLine and C_QuestLine.GetQuestLineInfo and C_QuestLine.GetQuestLineQuests) then return nil end
  local ok, info = pcall(C_QuestLine.GetQuestLineInfo, id, playerMap() or 0)
  if not ok or type(info) ~= "table" or not info.questLineID then return nil end
  local ok2, list = pcall(C_QuestLine.GetQuestLineQuests, info.questLineID)
  if not ok2 or type(list) ~= "table" then return nil end
  for i, qid in ipairs(list) do if qid == id and i > 1 then return list[i - 1] end end
end

function QM.prevOf(id) return K().prev[id] or questLinePrev(id) end

-- The quests that must be done before this one (from the database): all of preAll, plus ONE of preAny
-- (the one you've done or have, else the first one your character can take).
function QM.prereqs(id)
  local q = DQ(id)
  if not q then return nil end
  local out = {}
  for _, p in ipairs(q[6] or {}) do out[#out + 1] = p end
  if q[7] then
    local pick
    for _, p in ipairs(q[7]) do
      if me.quests[p] or QM.completedByMe(p) then pick = p break end
    end
    if not pick then for _, p in ipairs(q[7]) do if QM.questForMe(p) then pick = p break end end end
    out[#out + 1] = pick or q[7][1]
  end
  return out
end

-- Everything that leads to a quest, in the order to do it (oldest first), ending with the quest itself.
-- Uses the quest database when it knows the quest, else the chains learned while playing.
function QM.pathTo(id)
  if DQ(id) then
    local path, seen = {}, {}
    local function visit(qid, depth)
      if seen[qid] or depth > 12 then return end
      seen[qid] = true
      for _, p in ipairs(QM.prereqs(qid) or {}) do
        if DQ(p) or K().titles[p] then visit(p, depth + 1) end
      end
      path[#path + 1] = qid
    end
    visit(id, 0)
    -- also follow a learned link the database doesn't have
    if #path == 1 and K().prev[id] then table.insert(path, 1, K().prev[id]) end
    return path
  end
  local path, seen, cur = {}, {}, id
  while cur and not seen[cur] and #path < 8 do
    seen[cur] = true
    table.insert(path, 1, cur)
    cur = QM.prevOf(cur)
  end
  return path
end
-- Where you stand on each step: "done", "have", "todo".
function QM.stepState(id)
  if me.quests[id] then return "have" end
  if QM.completedByMe(id) then return "done" end
  return "todo"
end

---------------------------------------------------------------------------------------------------
-- Reading our own quest log
---------------------------------------------------------------------------------------------------

local function scanLog()
  local list = {}
  if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return list end
  local header
  for i = 1, C_QuestLog.GetNumQuestLogEntries() do
    local info = C_QuestLog.GetInfo(i)
    if info and info.isHeader then header = safe(info.title) end
    if info and not info.isHeader and not info.isHidden and info.questID and info.questID > 0 then
      local id = info.questID
      local objs = {}
      local ok, raw = pcall(C_QuestLog.GetQuestObjectives, id)
      if ok and type(raw) == "table" then
        for k, o in ipairs(raw) do
          objs[k] = { t = QM.objText(o.text), have = tonumber(o.numFulfilled) or 0, need = tonumber(o.numRequired) or 0,
                      fin = o.finished and true or false }
        end
      end
      local state = 0
      if C_QuestLog.IsFailed and C_QuestLog.IsFailed(id) then state = -1
      elseif C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) then state = 1 end
      local share = false
      if C_QuestLog.IsPushableQuest then share = C_QuestLog.IsPushableQuest(id) and true or false end
      list[id] = { id = id, title = info.title or ("Quest " .. id), level = info.level or 0, state = state,
                   share = share, obj = objs, header = header }
      K().titles[id] = { list[id].title, list[id].level }
    end
  end
  return list
end

---------------------------------------------------------------------------------------------------
-- Messages
--   Q quest   R removed   F focus   Z zone   B/E full sync   H hello   A accepted (+giver, +prev)
--   W "how do I get quest X?"   C one step of the answer   S share request   P suggestion
--   J joined you on a quest     D quests of yours I already completed
--   K progress spot (where an objective moved)   M focus-quest objective area (map POI)
---------------------------------------------------------------------------------------------------

local function encodeQuest(q)
  local head = table.concat({ "Q", q.id, q.level, q.state, q.share and 1 or 0, clean(q.title, 60) }, SEP)
  local function build(tmax)
    local parts = { head }
    for _, o in ipairs(q.obj) do
      parts[#parts + 1] = table.concat({ o.have, o.need, o.fin and 1 or 0, clean(o.t, tmax) }, OSEP)
    end
    return table.concat(parts, SEP)
  end
  local msg = build(48)
  if #msg > MAXMSG then msg = build(14) end
  if #msg > MAXMSG then msg = build(0) end
  if #msg > MAXMSG then msg = head end
  return msg
end

local function decodeQuest(f)
  local id = tonumber(f[2])
  if not id then return nil end
  local q = { id = id, level = tonumber(f[3]) or 0, state = tonumber(f[4]) or 0, share = f[5] == "1",
              title = f[6] or ("Quest " .. id), obj = {} }
  for i = 7, #f do
    local o = split(f[i], OSEP)
    q.obj[#q.obj + 1] = { have = tonumber(o[1]) or 0, need = tonumber(o[2]) or 0, fin = o[3] == "1", t = o[4] or "" }
  end
  return q
end

local function encodePlace(p)
  p = p or {}
  return table.concat({ clean(p.npc or "", 36), p.map or "", p.x and string.format("%.4f", p.x) or "",
                        p.y and string.format("%.4f", p.y) or "", clean(p.zone or "", 32) }, SEP)
end

local function decodePlace(f, i)
  local p = { npc = (f[i] and f[i] ~= "") and f[i] or nil, map = tonumber(f[i + 1]), x = tonumber(f[i + 2]),
              y = tonumber(f[i + 3]), zone = f[i + 4] or "" }
  if not p.npc and not p.map then return nil end
  return p
end

local queue, queueKeys, pumping = {}, {}, false
local THROTTLED = {}
do
  local e = Enum and Enum.SendAddonMessageResult
  THROTTLED[(e and e.AddonMessageThrottle) or 3] = true
  THROTTLED[(e and e.ChannelThrottle) or 8] = true
end

local function groupChannel()
  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
end
QM.groupChannel = groupChannel

local function pump()
  pumping = false
  local item = queue[1]
  if not item then return end
  local ch = groupChannel()
  if not ch then wipe(queue); wipe(queueKeys); return end
  local ok, res = pcall(C_ChatInfo.SendAddonMessage, QM.PREFIX, item.msg, ch)
  if ok and THROTTLED[res] then
    pumping = true
    C_Timer.After(1.0, pump)
    return
  end
  table.remove(queue, 1)
  if item.key then queueKeys[item.key] = nil end
  if #queue > 0 then pumping = true; C_Timer.After(0.15, pump) end
end

-- key: a newer message with the same key replaces a queued older one (only the latest state matters).
local function send(msg, key)
  if not groupChannel() then return end
  local item = key and queueKeys[key]
  if item then item.msg = msg
  else
    item = { msg = msg, key = key }
    queue[#queue + 1] = item
    if key then queueKeys[key] = item end
  end
  if not pumping then pumping = true; C_Timer.After(0.05, pump) end
end
QM.send = send

---------------------------------------------------------------------------------------------------
-- What am I doing right now?
--   1. a quest you set yourself ("Set as Now" / right-click)   2. the quest you last progressed (5 min)
--   3. the quest the map is pointing at                          4. the quest you most recently accepted (15 min)
---------------------------------------------------------------------------------------------------

local function computeFocus()
  if manualFocus and me.quests[manualFocus] then return manualFocus, "m" end
  manualFocus = nil
  local now = GetTime()
  local best, bt = 0, 0
  for id, t in pairs(progressAt) do
    if me.quests[id] and t > bt and now - t < 300 then best, bt = id, t end
  end
  if best > 0 then return best, "p" end
  local st = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and safe(C_SuperTrack.GetSuperTrackedQuestID())
  if st and st > 0 and me.quests[st] then return st, "t" end
  for id, t in pairs(acceptedAt) do
    if me.quests[id] and t > bt and now - t < 900 then best, bt = id, t end
  end
  return best, best > 0 and "a" or ""
end

local function sendPOI(force)
  local id, map, x, y = me.focus, nil, nil, nil
  if id and id > 0 and C_QuestLog.GetQuestsOnMap then
    map = playerMap()
    local ok, list = pcall(C_QuestLog.GetQuestsOnMap, map or 0)
    if ok and type(list) == "table" then
      for _, p in ipairs(list) do
        if p.questID == id and p.x and p.y then x, y = safe(p.x), safe(p.y); break end
      end
    end
  end
  me.poi = (x and y) and { map = map, x = x, y = y, id = id } or nil
  local msg = (x and y) and table.concat({ "M", id, map, string.format("%.4f", x), string.format("%.4f", y) }, SEP) or "M~0"
  if force or msg ~= sentPOI then
    sentPOI = msg
    send(msg, "poi")
  end
end

local function updateFocus()
  local id, src = computeFocus()
  me.focus, me.focusSrc = id, src
  if id ~= sentFocus then
    sentFocus = id
    send(table.concat({ "F", id, src }, SEP), "focus")
    sendPOI()
    QM:Changed()
  end
end
QM.updateFocus = updateFocus

function QM.setManualFocus(id)
  if id and not me.quests[id] then return end
  manualFocus = id
  updateFocus()
  QM:Changed()
end
function QM.getManualFocus() return manualFocus end

local function sendZone(force)
  me.zone = safe(GetRealZoneText()) or ""
  me.sub = safe(GetSubZoneText()) or ""
  local msg = table.concat({ "Z", clean(me.zone, 40), clean(me.sub, 40), UnitLevel("player") or 0 }, SEP)
  if force or msg ~= sentZone then
    sentZone = msg
    send(msg, "zone")
  end
end

local doneTimer
local function scheduleDone()
  if doneTimer then return end
  doneTimer = true
  C_Timer.After(2, function()
    doneTimer = nil
    local ids, seen = {}, {}
    for _, m in pairs(mates) do
      if not m.demo then
        for id in pairs(m.quests) do
          if not seen[id] and not me.quests[id] and QM.completedByMe(id) then
            seen[id] = true
            ids[#ids + 1] = id
          end
        end
      end
    end
    local msg = "D" .. SEP .. table.concat(ids, ",")
    if #msg > MAXMSG then msg = (msg:sub(1, MAXMSG):gsub(",[^,]*$", "")) end
    if msg ~= lastDone then
      lastDone = msg
      send(msg, "done")
    end
  end)
end

local function fullSync()
  lastFullSync = GetTime()
  local keep = {}
  for _, it in ipairs(queue) do if not it.key then keep[#keep + 1] = it end end
  wipe(queue); wipe(queueKeys)
  for _, it in ipairs(keep) do queue[#queue + 1] = it end
  send(table.concat({ "B", QM.VERSION }, SEP))
  for id, q in pairs(me.quests) do
    local m = encodeQuest(q)
    lastSent[id] = m
    send(m, "q" .. id)
  end
  send("E")
  sentFocus = nil
  updateFocus()
  sendZone(true)
  sendPOI(true)
  if QM.sendDestination then QM.sendDestination(true) end
  if QM.DB and QM.DB.task then send(table.concat({ "T", QM.DB.task.area, QM.DB.task.t or 0 }, SEP), "task") end
  lastDone = nil
  scheduleDone()
end
QM.fullSync = fullSync

local function onScan()
  local new = scanLog()
  local now = GetTime()
  local progressed = {}
  for id, q in pairs(new) do
    local old = me.quests[id]
    if old then
      for k, o in ipairs(q.obj) do
        local oo = old.obj[k]
        if oo and (o.have > oo.have or (o.fin and not oo.fin)) then progressAt[id] = now; progressed[id] = true end
      end
      if q.state == 1 and old.state ~= 1 then progressAt[id] = now; progressed[id] = true end
    end
  end
  for id in pairs(me.quests) do
    if not new[id] then
      send(table.concat({ "R", id, turnedIn[id] and "t" or "a" }, SEP), "q" .. id)
      lastSent[id], progressAt[id], acceptedAt[id] = nil, nil, nil
      if manualFocus == id then manualFocus = nil end
    end
  end
  wipe(turnedIn)
  me.quests = new
  for id, q in pairs(new) do
    local m = encodeQuest(q)
    if lastSent[id] ~= m then
      lastSent[id] = m
      send(m, "q" .. id)
    end
  end
  -- where did that kill / item happen? party members see it on their map
  for id in pairs(progressed) do
    if now - (spotSentAt[id] or -99) > 15 then
      local map, x, y = QM.playerPos()
      if map and x then
        spotSentAt[id] = now
        send(table.concat({ "K", id, map, string.format("%.4f", x), string.format("%.4f", y) }, SEP), "spot" .. id)
      end
    end
  end
  scheduleDone()
  updateFocus()
  QM:Changed()
end

local scanPending = false
local function scheduleScan()
  if scanPending then return end
  scanPending = true
  C_Timer.After(0.3, function() scanPending = false; onScan() end)
end

---------------------------------------------------------------------------------------------------
-- Party members
---------------------------------------------------------------------------------------------------

function QM.getMate(full)
  local m = mates[full]
  if not m then
    m = { full = full, quests = {}, stale = {}, done = {}, spots = {}, focus = 0, zone = "", sub = "",
          synced = false, toastedFocus = {}, level = 0 }
    mates[full] = m
  end
  return m
end

local function readRoster()
  local new = {}
  local raid = IsInRaid()
  local n = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
  local myRealm = GetNormalizedRealmName and GetNormalizedRealmName() or ""
  for i = 1, n do
    local unit = raid and ("raid" .. i) or ("party" .. i)
    if UnitExists(unit) and not UnitIsUnit(unit, "player") then
      local name, realm = UnitFullName(unit)
      name, realm = safe(name), safe(realm)
      if name and name ~= "" and name ~= UNKNOWNOBJECT then
        if not realm or realm == "" then realm = myRealm end
        local _, class = UnitClass(unit)
        new[name .. "-" .. realm] = { unit = unit, class = safe(class), level = safe(UnitLevel(unit)) }
      end
    end
  end
  return new
end

function QM.unitOf(full)
  local r = QM.roster[full]
  return r and r.unit
end

local function onRoster()
  local new = readRoster()
  local joined = false
  for full in pairs(new) do if not QM.roster[full] then joined = true end end
  for full, m in pairs(mates) do if not new[full] and not m.demo then mates[full] = nil end end
  QM.roster = new
  if joined then
    send("H")
    fullSync()
  end
  QM:Changed()
end

-- Party members in a stable order (demo member included).
function QM.mateList()
  local names = {}
  for full in pairs(QM.roster) do names[#names + 1] = full end
  for full, m in pairs(mates) do if m.demo and not QM.roster[full] then names[#names + 1] = full end end
  table.sort(names)
  return names
end

function QM.toast(full, kind, q, line, extra)
  QM:Fire("TOAST", { full = full, kind = kind, quest = q, line = line, extra = extra })
end

local function pushQuest(id)
  if not me.quests[id] then return end
  if C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(id) end
  if QuestLogPushQuest then
    local ok = pcall(QuestLogPushQuest)
    if not ok then QM.print("couldn't share that quest.") end
  end
end
QM.pushQuest = pushQuest

StaticPopupDialogs["QUESTMATES_SHARE"] = {
  text = "%s would like you to share:\n\n%s",
  button1 = SHARE_QUEST or "Share",
  button2 = CANCEL or "Not now",
  OnAccept = function(self, data) pushQuest(data or (self and self.data)) end,
  timeout = 45,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

-- Answer "how do I get quest X?" with every step we know, oldest first.
local function answerPath(requester, id)
  local path = QM.pathTo(id)
  for i, qid in ipairs(path) do
    local title, level = QM.titleOf(qid)
    local t = K().turnins[qid]
    send(table.concat({ "C", requester, id, i, #path, qid, level or 0, clean(title or "", 50) }, SEP) .. SEP ..
         encodePlace(K().givers[qid]) .. SEP .. clean(t and t.npc or "", 36))
  end
end

local function onMessage(text, sender)
  if isSecret(text) or isSecret(sender) or not sender then return end
  local full = sender:find("-", 1, true) and sender or (sender .. "-" .. (GetNormalizedRealmName() or ""))
  if full == myFull() then return end
  local f = split(text, SEP)
  local cmd = f[1]
  local m = QM.getMate(full)
  m.seen = GetTime()
  local live = m.synced and not m.syncing

  if cmd == "Q" then
    local q = decodeQuest(f)
    if q then
      local old = m.quests[q.id]
      m.quests[q.id] = q
      m.stale[q.id] = nil
      if not K().titles[q.id] then K().titles[q.id] = { q.title, q.level } end
      if live then
        if not old then
          QM.toast(full, "pickup", q)
        elseif q.state == 1 and old.state ~= 1 then
          QM.toast(full, "ready", q)
        else
          for i, o in ipairs(q.obj) do
            local oo = old.obj[i]
            if oo and o.have > oo.have then m.flashAt = GetTime(); m.flashQuest = q.id end
            if o.fin and oo and not oo.fin and o.t ~= "" then QM.toast(full, "objective", q, o) end
          end
        end
      end
    end
  elseif cmd == "B" then
    m.version = f[2]
    if m.version and m.version ~= QM.VERSION and not m.versionWarned then
      m.versionWarned = true
      C_Timer.After(3, function() QM.toast(full, "version", { title = "Questmates " .. m.version .. " (you: " .. QM.VERSION .. ")" }) end)
    end
    m.syncing = true
    wipe(m.stale)
    for id in pairs(m.quests) do m.stale[id] = true end
  elseif cmd == "E" then
    for id in pairs(m.stale) do m.quests[id] = nil end
    wipe(m.stale)
    local first = not m.synced
    m.synced, m.syncing = true, false
    if first then QM.toast(full, "hello") ; QM:Fire("MATE_SYNCED", full) end
    scheduleDone()
  elseif cmd == "R" then
    local id = tonumber(f[2])
    local q = id and m.quests[id]
    if id then m.quests[id] = nil; m.spots[id] = nil end
    if q and live then QM.toast(full, f[3] == "t" and "turnin" or "drop", q) end
    if m.focus == id then m.focus = 0 end
  elseif cmd == "F" then
    local id = tonumber(f[2]) or 0
    if id ~= m.focus then
      m.focus, m.focusSrc, m.focusAt = id, f[3] or "", GetTime()
      local q = m.quests[id]
      local now = GetTime()
      if q and live and now - (m.toastedFocus[id] or -999) > 300 then
        m.toastedFocus[id] = now
        QM.toast(full, "focus", q)
      end
    end
  elseif cmd == "Z" then
    m.zone, m.sub, m.level = f[2] or "", f[3] or "", tonumber(f[4]) or m.level
  elseif cmd == "H" then
    if GetTime() - lastFullSync > 4 then C_Timer.After(0.5 + math.random() * 1.5, fullSync) end
  elseif cmd == "A" then
    local id, prev = tonumber(f[2]), tonumber(f[3])
    if id then
      local p = decodePlace(f, 4)
      if p and not K().givers[id] then K().givers[id] = p end
      if prev and prev > 0 and not K().prev[id] then K().prev[id] = prev end
    end
  elseif cmd == "W" then
    local id = tonumber(f[3])
    if f[2] == myFull() and id then answerPath(full, id) end
  elseif cmd == "C" then
    if f[2] == myFull() or f[2] == "*" then
      local root, i, n, qid = tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6])
      if root and qid then
        if f[8] and f[8] ~= "" and not K().titles[qid] then K().titles[qid] = { f[8], tonumber(f[7]) or 0 } end
        local p = decodePlace(f, 9)
        if p then K().givers[qid] = K().givers[qid] or p end
        if f[14] and f[14] ~= "" and not K().turnins[qid] then K().turnins[qid] = { npc = f[14] } end
        m.paths = m.paths or {}
        local path = m.paths[root] or {}
        path[i] = qid
        path.n = n
        m.paths[root] = path
        if i > 1 and path[i - 1] and not K().prev[qid] then K().prev[qid] = path[i - 1] end
        if i == n then QM.askedPath[root] = "answered" end
      end
    end
  elseif cmd == "S" then
    local id = tonumber(f[3])
    if f[2] == myFull() and id and me.quests[id] then
      local title = (QM.C.gold .. me.quests[id].title .. "|r"):gsub("%%", "%%%%")
      QM.playSound("IG_PLAYER_INVITE")
      StaticPopup_Show("QUESTMATES_SHARE", QM.nameText(full), title, id)
    end
  elseif cmd == "P" then
    local id = tonumber(f[2])
    if id then
      local q = m.quests[id] or { id = id, level = tonumber(f[3]) or 0, title = f[4] or "?", obj = {}, state = 0 }
      if not K().titles[id] then K().titles[id] = { q.title, q.level } end
      m.suggested = { id = id, t = GetTime() }
      QM.toast(full, "suggest", q)
    end
  elseif cmd == "Y" then
    local id = tonumber(f[2])
    if id and f[3] and f[3] ~= "" and K().dq[id] ~= f[3] then K().dq[id] = f[3]; QM:Fire("LEARNED") end
  elseif cmd == "N" then
    local name, map, x, y = f[2], tonumber(f[4]), tonumber(f[5]), tonumber(f[6])
    local e = name and name ~= "" and (K().inst[name] or {})
    if e and not e.x and map and x then
      e.kind, e.map, e.x, e.y = e.kind or f[3], map, x, y
      K().inst[name] = e
      QM:Fire("LEARNED")
    end
  elseif cmd == "T" then
    local area = tonumber(f[2]) or ((f[2] and f[2] ~= "" and f[2] ~= "0") and f[2]) or 0
    m.task = (area ~= 0) and area or nil
    QM:Fire("PARTY_TASK", full, m.task, tonumber(f[3]) or 0)
  elseif cmd == "X" then
    local map, x, y, id = tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
    if map and map > 0 and x then
      local isNew = not (m.dest and m.dest.map == map and math.abs(m.dest.x - x) < 0.002 and math.abs(m.dest.y - y) < 0.002)
      m.dest = { map = map, x = x, y = y, id = (id and id > 0) and id or nil, t = GetTime() }
      if isNew and live then QM.toast(full, "dest", m.dest.id and m.quests[m.dest.id] or nil) end
    else
      m.dest = nil
    end
  elseif cmd == "J" then
    local id = tonumber(f[2])
    if id and me.quests[id] then QM.toast(full, "join", me.quests[id]) end
  elseif cmd == "D" then
    wipe(m.done)
    for id in (f[2] or ""):gmatch("%d+") do m.done[tonumber(id)] = true end
  elseif cmd == "K" then
    local id, map, x, y = tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
    if id and map and x then
      local list = m.spots[id] or {}
      table.insert(list, 1, { map = map, x = x, y = y, t = GetTime() })
      while #list > 6 do table.remove(list) end
      m.spots[id] = list
    end
  elseif cmd == "M" then
    local id, map, x, y = tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
    m.poi = (id and id > 0 and map and x) and { id = id, map = map, x = x, y = y } or nil
  end
  QM:Changed()
end

---------------------------------------------------------------------------------------------------
-- Actions the UI calls
---------------------------------------------------------------------------------------------------

function QM.askShare(full, id)
  local m = mates[full]
  if m and m.demo then
    QM.toast(full, "demo", m.quests[id], "would get a request to share this with you")
    return
  end
  send(table.concat({ "S", full, id }, SEP))
  QM.print("asked %s to share %s.", QM.nameText(full), QM.C.gold .. (QM.titleOf(id) or "the quest") .. "|r")
end

function QM.suggest(id)
  local q = me.quests[id]
  if not q then return end
  if not groupChannel() then QM.print("you're not in a party."); return end
  -- the whole chain travels with the suggestion, so they can see how to catch up the moment they click it
  answerPath("*", id)
  send(table.concat({ "P", id, q.level, clean(q.title, 60) }, SEP))
  QM.playSound("MAP_PING")
  QM.print("showed %s to your party.", QM.C.gold .. q.title .. "|r")
end

-- Your map pin (Ctrl-click on the world map) is shared as "where I'm heading".
local sentDest, followingUntil = nil, 0
function QM.sendDestination(force)
  if not (QM.DB and QM.DB.shareWaypoint) then return end
  if GetTime() < followingUntil then return end   -- we just copied a friend's pin; don't echo it back
  local msg = "X~0"
  local ok, point = pcall(C_Map.GetUserWaypoint)
  if ok and point and point.uiMapID and point.position then
    local x, y = point.position:GetXY()
    if x and y then
      msg = table.concat({ "X", point.uiMapID, string.format("%.4f", x), string.format("%.4f", y), me.focus or 0 }, SEP)
      me.dest = { map = point.uiMapID, x = x, y = y }
    end
  else
    me.dest = nil
  end
  if force or msg ~= sentDest then
    sentDest = msg
    send(msg, "dest")
  end
  QM:Changed()
end

function QM.followDestination(full)
  local m = mates[full]
  if not (m and m.dest) then return end
  followingUntil = GetTime() + 2
  QM.setWaypoint(m.dest, QM.short(full) .. "'s destination")
end

function QM.join(full, id)
  if not me.quests[id] then return end
  QM.setManualFocus(id)
  local m = mates[full]
  if not (m and m.demo) then send(table.concat({ "J", id }, SEP)) end
end

-- Ask a party member for the way to a quest (giver + earlier quests). Answer arrives as "C" messages.
function QM.requestPath(id)
  if QM.askedPath[id] then return end
  for full, m in pairs(mates) do
    if m.quests[id] and not m.demo then
      QM.askedPath[id] = "asked"
      send(table.concat({ "W", full, id }, SEP))
      C_Timer.After(6, function() if QM.askedPath[id] == "asked" then QM.askedPath[id] = "noanswer"; QM:Changed() end end)
      return
    end
  end
end

function QM.setWaypoint(p, label)
  if not (p and p.map and p.x and p.x > 0) then
    QM.print("no map position is known for that yet.")
    return false
  end
  local ok = pcall(function()
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(p.map) then error("no waypoints on this map") end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(p.map, p.x, p.y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
  end)
  if ok then
    QM.playSound("UI_MAP_WAYPOINT_SUPER_TRACK_ON")
    QM.print("waypoint: %s", label or QM.placeText(p))
  else
    QM.print("%s", QM.placeText(p) or "?")
  end
  return ok
end

-- "Take me there": waypoint + the game's arrow, the map opens on the spot with a spotlight and a
-- trail from you, a note says where to go, and another one says when you've arrived.
-- p = { map, x, y }, info = { npc, title, verb, qid }, opts = { noMap = true } when the map is already open.
local guideTicker
function QM.guide(p, info, opts)
  info = info or {}
  if not (p and p.map and p.x and p.x > 0) then
    QM.print("no map position is known for that yet.")
    return
  end
  local where = info.npc or "the marked spot"
  QM.setWaypoint(p, where .. (info.title and (" - " .. info.title) or ""))
  local pm, px, py = QM.playerPos()
  QM.guideTarget = { map = p.map, x = p.x, y = p.y, npc = info.npc, title = info.title, verb = info.verb or "Pick up",
                     qid = info.qid, t = GetTime(), from = (pm and px) and { map = pm, x = px, y = py } or nil }
  QM:Fire("GUIDE", QM.guideTarget, opts or {})
  QM.toast("me", "goto", { title = "Go to " .. where }, nil, QM.guideTarget)
  if guideTicker then guideTicker:Cancel() end
  guideTicker = C_Timer.NewTicker(1, function()
    local g = QM.guideTarget
    if not g then if guideTicker then guideTicker:Cancel(); guideTicker = nil end return end
    local d = QM.distanceTo(g.map, g.x, g.y)
    if d and d < 22 then
      QM.guideTarget = nil
      QM.toast("me", "arrive", { title = "You're there!" }, nil, g)
      QM:Changed()
    elseif GetTime() - g.t > 1200 then
      QM.guideTarget = nil
      QM:Changed()
    end
  end)
end

-- A step that is already in your log: point the game's own arrow at that quest (its objectives / turn-in).
function QM.trackOwnQuest(qid)
  if not QM.me.quests[qid] then return end
  local ok = C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID and pcall(C_SuperTrack.SetSuperTrackedQuestID, qid)
  QM.playSound("UI_MAP_WAYPOINT_SUPER_TRACK_ON")
  QM.toast("me", "finish", QM.me.quests[qid])
  if not ok then QM.print("open your quest log to see where %s takes you.", QM.C.gold .. QM.me.quests[qid].title .. "|r") end
end

function QM.stopGuide()
  QM.guideTarget = nil
  QM:Changed()
end

-- The one thing to do next to get a quest, in order (never a later step):
-- { qid, n, total, kind = "pickup" | "finish", giver, path }
function QM.nextStep(id)
  local path = QM.pathTo(id)
  for n, qid in ipairs(path) do
    local st = QM.stepState(qid)
    if st == "todo" then return { qid = qid, n = n, total = #path, giver = QM.giverOf(qid), kind = "pickup", path = path } end
    if st == "have" and qid ~= id then return { qid = qid, n = n, total = #path, kind = "finish", path = path } end
  end
  return { qid = id, n = #path, total = #path, giver = QM.giverOf(id), kind = "pickup", path = path }
end

-- Do it: guide to the next step (pick-up) or point the arrow at the quest you must finish first.
function QM.doNextStep(id, opts)
  local s = QM.nextStep(id)
  if s.kind == "finish" then QM.trackOwnQuest(s.qid); return s end
  if s.giver and s.giver.map and s.giver.x then
    QM.guide(s.giver, { npc = s.giver.npc, title = QM.titleOf(s.qid), qid = s.qid, verb = "Pick up" }, opts)
  else
    QM.print("nobody knows where %s starts yet.", QM.C.gold .. (QM.titleOf(s.qid) or "that quest") .. "|r")
  end
  return s
end

---------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------

local pendingGiver, pendingTurnin, lastTurnin

local function npcName()
  local n = safe(UnitName("questnpc")) or safe(UnitName("npc"))
  if n == UnitName("player") then return nil end
  return n
end

local function here()
  local map, x, y = QM.playerPos()
  return { map = map, x = x, y = y, zone = safe(GetRealZoneText()) or "" }
end

local ev = CreateFrame("Frame")
QM.eventFrame = ev
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "CHAT_MSG_ADDON",
                     "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_WATCH_UPDATE",
                     "UNIT_QUEST_LOG_CHANGED", "QUEST_DETAIL", "QUEST_COMPLETE", "SUPER_TRACKING_CHANGED", "ZONE_CHANGED",
                     "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "PLAYER_LEVEL_UP", "UNIT_PORTRAIT_UPDATE",
                     "USER_WAYPOINT_UPDATED" }) do
  pcall(ev.RegisterEvent, ev, e)
end

local DEFAULTS = { toasts = true, sound = true, tracker = true, mapPins = true, tooltips = true, chat = false,
                   shareWaypoint = true, questLogButton = true, mapLegend = true, autoShare = true, autoAccept = true,
                   trackerCollapsed = false, journalShown = false }

ev:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    QuestmatesDB = QuestmatesDB or {}
    local DB = QuestmatesDB
    for k, v in pairs(DEFAULTS) do if DB[k] == nil then DB[k] = v end end
    DB.know = DB.know or {}
    for _, k in ipairs({ "givers", "turnins", "prev", "titles", "dq", "inst" }) do DB.know[k] = DB.know[k] or {} end
    QM.DB = DB
    if DB.lastVersion and DB.lastVersion ~= QM.VERSION then
      local from = DB.lastVersion
      C_Timer.After(6, function() QM.toast("me", "updated", { title = "Version " .. QM.VERSION }, nil, { from = from }) end)
    end
    DB.lastVersion = QM.VERSION
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, QM.PREFIX) end
    C_Timer.NewTicker(20, function() updateFocus(); sendPOI() end)
    QM:Fire("INIT")

  elseif event == "PLAYER_ENTERING_WORLD" then
    QM:Fire("ENTERED_WORLD")
    me.full = myFull()
    me.quests = scanLog()
    sendZone()
    onRoster()
    updateFocus()
    QM:Changed()

  elseif event == "GROUP_ROSTER_UPDATE" then
    onRoster()

  elseif event == "CHAT_MSG_ADDON" then
    local prefix, text, _, sender = ...
    if prefix == QM.PREFIX then onMessage(text, sender) end

  elseif event == "QUEST_DETAIL" then
    local id = GetQuestID and safe(GetQuestID())
    local p = here()
    p.npc, p.id, p.t = npcName(), id, GetTime()
    pendingGiver = p
    if id then QM:Fire("DETAIL", id) end

  elseif event == "QUEST_COMPLETE" then
    local id = GetQuestID and safe(GetQuestID())
    local p = here()
    p.npc, p.id = npcName(), id
    pendingTurnin = p

  elseif event == "QUEST_ACCEPTED" then
    local n = select("#", ...)
    local id = n > 0 and tonumber((select(n, ...))) or nil  -- the questID is the last argument
    if id then
      local now = GetTime()
      acceptedAt[id] = now
      local g = pendingGiver
      if not (g and (g.id == id or (not g.id and now - g.t < 120))) then g = here() end
      local place = { npc = g.npc, map = g.map, x = g.x, y = g.y, zone = g.zone }
      K().givers[id] = place
      -- a quest offered by the NPC you just turned something in to is (very likely) unlocked by it
      local prev = 0
      if lastTurnin and now - lastTurnin.t < 120 and lastTurnin.id ~= id
         and (not place.npc or not lastTurnin.npc or place.npc == lastTurnin.npc) then
        prev = lastTurnin.id
        K().prev[id] = prev
      end
      pendingGiver = nil
      send(table.concat({ "A", id, prev }, SEP) .. SEP .. encodePlace(place))
      QM:Fire("ACCEPTED", id)
    end
    scheduleScan()

  elseif event == "QUEST_TURNED_IN" then
    local id = ...
    if id then
      turnedIn[id] = true
      local p = (pendingTurnin and pendingTurnin.id == id) and pendingTurnin or here()
      K().turnins[id] = { npc = p.npc, map = p.map, x = p.x, y = p.y, zone = p.zone }
      lastTurnin = { id = id, npc = p.npc, t = GetTime() }
      pendingTurnin = nil
    end
    scheduleScan()

  elseif event == "UNIT_QUEST_LOG_CHANGED" then
    if ... == "player" then scheduleScan() end

  elseif event == "SUPER_TRACKING_CHANGED" then
    updateFocus()

  elseif event == "PLAYER_LEVEL_UP" then
    C_Timer.After(0.5, function() sendZone(true) end)

  elseif event == "USER_WAYPOINT_UPDATED" then
    C_Timer.After(0.2, function() QM.sendDestination() end)

  elseif event == "UNIT_PORTRAIT_UPDATE" then
    QM:Fire("PORTRAIT", ...)

  elseif event:find("^ZONE_CHANGED") then
    sendZone()
    sendPOI()
    QM:Changed()

  else -- QUEST_LOG_UPDATE, QUEST_REMOVED, QUEST_WATCH_UPDATE
    scheduleScan()
  end
end)

---------------------------------------------------------------------------------------------------
-- Demo: a pretend party member, to try everything alone (/qm demo)
---------------------------------------------------------------------------------------------------

QM.DEMO = "Aldric-Demo"
function QM.toggleDemo()
  local D = QM.DEMO
  if mates[D] then
    mates[D] = nil
    QM.print("demo party member left.")
    QM:Changed()
    return false
  end
  local m = QM.getMate(D)
  m.demo, m.synced, m.class, m.version = true, true, "PALADIN", QM.VERSION
  m.level = UnitLevel("player") or 10
  m.zone, m.sub = (me.zone ~= "" and me.zone) or "Elwynn Forest", "just down the road"
  local n, lacking = 0, nil
  local ids = {}
  for id in pairs(me.quests) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local q = me.quests[id]
    n = n + 1
    if n % 2 == 1 then
      local c = { id = id, level = q.level, title = q.title, share = q.share, state = q.state, obj = {} }
      for k, o in ipairs(q.obj) do
        local have = math.min(o.need, o.have + 2)
        c.obj[k] = { t = o.t, need = o.need, have = have, fin = have >= o.need and o.need > 0 }
      end
      m.quests[id] = c
    elseif not lacking then
      lacking = id
    end
  end
  if lacking then m.done[lacking] = true end
  local lvl = m.level
  local pm, px, py = QM.playerPos()
  px, py = px or 0.5, py or 0.5
  local function near(dx, dy) return { map = pm, x = math.min(math.max(px + dx, 0.02), 0.98), y = math.min(math.max(py + dy, 0.02), 0.98) } end
  m.quests[990001] = { id = 990001, level = lvl, title = "The Lost Shipment", state = 0, share = true,
                       obj = { { t = "Crate of Supplies", have = 2, need = 5, fin = false },
                               { t = "Bandit Thug slain", have = 6, need = 6, fin = true } } }
  m.quests[990002] = { id = 990002, level = math.max(lvl - 1, 1), title = "Report to the Captain", state = 1, share = false, obj = {} }
  -- a learned chain: 990003 -> 990004 -> 990001
  local K_ = K()
  K_.titles[990003] = { "Rumors on the Road", math.max(lvl - 2, 1) }
  K_.titles[990004] = { "A Quartermaster's Worry", math.max(lvl - 1, 1) }
  K_.titles[990001] = { "The Lost Shipment", lvl }
  local g3 = near(-0.06, 0.03); g3.npc = "Guard Hollis"; g3.zone = m.zone
  local g4 = near(0.02, -0.05); g4.npc = "Quartermaster Lewin"; g4.zone = m.zone
  local g1 = near(0.02, -0.05); g1.npc = "Quartermaster Lewin"; g1.zone = m.zone
  K_.givers[990003], K_.givers[990004], K_.givers[990001] = g3, g4, g1
  K_.turnins[990003] = { npc = "Quartermaster Lewin" }
  K_.turnins[990004] = { npc = "Quartermaster Lewin" }
  K_.prev[990004], K_.prev[990001] = 990003, 990004
  m.focus = 990001
  -- a couple of real dungeon quests (The Deadmines) so the dungeon pages show a friend's progress
  for _, id in ipairs({ 166, 2040 }) do
    local q = QM.DQ(id)
    if q then m.quests[id] = { id = id, level = q[2], title = q[1], state = 0, share = true, obj = {} } end
  end
  local poi = near(0.09, 0.06)
  m.poi = { id = 990001, map = pm, x = poi.x, y = poi.y }
  m.spots[990001] = { near(0.085, 0.072), near(0.102, 0.055), near(0.094, 0.043) }
  for _, s in ipairs(m.spots[990001]) do s.t = GetTime() - 60 end
  m.demoPos = near(0.06, 0.035)
  local d = near(0.13, -0.02)
  m.dest = { map = pm, x = d.x, y = d.y, id = 990001, t = GetTime() }
  QM.print("demo on: a pretend party member joined. Type %s/qm demo|r again to remove them.", QM.C.white)
  QM:Changed()
  C_Timer.After(0.8, function() if mates[D] then QM.toast(D, "hello") end end)
  C_Timer.After(3.0, function() if mates[D] then QM.toast(D, "focus", m.quests[990001]) end end)
  C_Timer.After(5.5, function() if mates[D] then QM.toast(D, "dest", m.quests[990001]) end end)
  C_Timer.After(8.0, function() if mates[D] then QM.toast(D, "suggest", m.quests[990001]) end end)
  return true
end
