-- Questmates / Journal.lua
-- The Party Quest Journal, written so anyone can use it:
--   * "What can we do together?" home page: plain sentences, each with one button, most important first
--       1. what each friend is doing right now, and whether you can join them
--       2. quests you can turn in together            3. quests you both have: do them together
--       4. quests your friends have that you don't: how to get them (nearest first)
--       5. your quests your friends don't have: share / show them
--   * a page per person: their quests grouped in plain words, what they're on now at the top
--   * a page per quest: one line saying what to do + one big button, then the steps / progress
-- A legend at the bottom explains the icons; a "How it works" box greets first-time users.

local _, QM = ...
local W = QM.W
local C = QM.C

local J = {}
QM.journal = J
local FW, FH = 780, 530
local COL1, COL2 = 200, 236
local COL3 = FW - COL1 - COL2 - 34
local WIDE = COL2 + COL3 + 6

---------------------------------------------------------------------------------------------------
-- Frame and columns
---------------------------------------------------------------------------------------------------

local function makeFrame()
  local ok, f = pcall(CreateFrame, "Frame", "QuestmatesJournal", UIParent, "ButtonFrameTemplate")
  if not ok or not f then
    f = CreateFrame("Frame", "QuestmatesJournal", UIParent, "BackdropTemplate")
    W.panel(f)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    f.TitleTextFallback = W.text(f, "OVERLAY", "GameFontNormal")
    f.TitleTextFallback:SetPoint("TOP", 0, -8)
  end
  f:SetSize(FW, FH)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetTitle then f:SetTitle("Party Quest Journal") elseif f.TitleTextFallback then f.TitleTextFallback:SetText("Party Quest Journal") end
  if f.SetPortraitToAsset then pcall(f.SetPortraitToAsset, f, "Interface\\Icons\\INV_Misc_Map_01")
  elseif f.portrait then f.portrait:SetTexture("Interface\\Icons\\INV_Misc_Map_01") end
  if ButtonFrameTemplate_HideButtonBar then pcall(ButtonFrameTemplate_HideButtonBar, f) end
  if f.Inset then f.Inset:Hide() end
  tinsert(UISpecialFrames, "QuestmatesJournal")
  f:Hide()
  f:SetScript("OnShow", function() QM.playSound("IG_QUEST_LOG_OPEN"); J.refresh() end)
  f:SetScript("OnHide", function() QM.playSound("IG_QUEST_LOG_CLOSE") end)
  return f
end

local function inset(parent, x, w)
  local ok, p = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
  if not ok or not p then
    p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    W.panel(p, 0.5)
  end
  p:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -64)
  p:SetPoint("BOTTOM", parent, "BOTTOM", 0, 46)
  p:SetWidth(w)
  return p
end

local function scroller(panel, w)
  local s = CreateFrame("ScrollFrame", nil, panel)
  s:SetPoint("TOPLEFT", 4, -4)
  s:SetPoint("BOTTOMRIGHT", -4, 4)
  s:EnableMouseWheel(true)
  local child = CreateFrame("Frame", nil, s)
  child:SetSize(w - 8, 10)
  s:SetScrollChild(child)
  s.child, s.w = child, w - 8
  s:SetScript("OnMouseWheel", function(self, d)
    local max = math.max((self.contentH or 0) - self:GetHeight(), 0)
    self:SetVerticalScroll(math.min(math.max(self:GetVerticalScroll() - d * 40, 0), max))
  end)
  function s:SetContentHeight(h)
    self.contentH = h
    child:SetHeight(math.max(h, 1))
    local max = math.max(h - self:GetHeight(), 0)
    if self:GetVerticalScroll() > max then self:SetVerticalScroll(max) end
  end
  return s
end

---------------------------------------------------------------------------------------------------
-- Doc: lays out text, icons, bars and buttons top to bottom in a scroller (pooled)
---------------------------------------------------------------------------------------------------

local Doc = {}
Doc.__index = Doc

local function newDoc(scroll)
  return setmetatable({ s = scroll, parent = scroll.child, w = scroll.w, pools = {}, used = {} }, Doc)
end

function Doc:get(kind, make)
  self.pools[kind] = self.pools[kind] or {}
  self.used[kind] = (self.used[kind] or 0) + 1
  local p = self.pools[kind][self.used[kind]]
  if not p then
    p = make(self.parent)
    self.pools[kind][self.used[kind]] = p
  end
  p:Show()
  return p
end

function Doc:reset()
  for kind, list in pairs(self.pools) do
    for _, p in ipairs(list) do p:Hide() end
    self.used[kind] = 0
  end
end

function Doc:text(y, text, font, x, w, r, g, b)
  local fs = self:get("text", function(parent)
    local f = W.text(parent, "OVERLAY", "GameFontHighlightSmall")
    f:SetWordWrap(true)
    return f
  end)
  W.font(fs, font or "GameFontHighlightSmall")
  fs:ClearAllPoints()
  x = x or 10
  fs:SetPoint("TOPLEFT", self.parent, "TOPLEFT", x, y)
  fs:SetWidth(w or (self.w - x - 10))
  fs:SetText(text)
  if r then fs:SetTextColor(r, g, b) else fs:SetTextColor(1, 1, 1) end
  return y - fs:GetStringHeight() - 4, fs
end

-- A line through a piece of text (finished things).
function Doc:strike(fs, r, g, b)
  local t = self:get("strike", function(parent) return parent:CreateTexture(nil, "OVERLAY", nil, 7) end)
  t:SetColorTexture(r or 0.75, g or 0.75, b or 0.75, 0.9)
  t:ClearAllPoints()
  t:SetPoint("LEFT", fs, "LEFT", -1, 0)
  t:SetSize(math.min(fs:GetStringWidth(), fs:GetWidth() or 9999) + 2, 1)
  return t
end

function Doc:section(y, label, sub)
  y = y - 8
  local ny = self:text(y, label, "GameFontNormal", 10, nil, 1, 0.82, 0)
  local t = self:get("line", function(parent) return parent:CreateTexture(nil, "ARTWORK") end)
  t:SetTexture("Interface\\Buttons\\WHITE8X8")
  if t.SetGradient and CreateColor then
    t:SetGradient("HORIZONTAL", CreateColor(0.9, 0.75, 0.35, 0.8), CreateColor(0.9, 0.75, 0.35, 0))
  else
    t:SetVertexColor(0.9, 0.75, 0.35, 0.5)
  end
  t:SetSize(self.w - 20, 1)
  t:ClearAllPoints()
  t:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 10, ny - 1)
  y = ny - 6
  if sub then y = self:text(y, sub, "GameFontDisableSmall", 10) end
  return y - 2
end

function Doc:icon(kind, x, y, size)
  local t = self:get("icon", function(parent) return parent:CreateTexture(nil, "ARTWORK") end)
  t:SetSize(size or 16, size or 16)
  t:SetVertexColor(1, 1, 1, 1)
  W.icon(t, kind)
  t:ClearAllPoints()
  t:SetPoint("TOPLEFT", self.parent, "TOPLEFT", x, y)
  return t
end

function Doc:portrait(full, x, y, size)
  local p = self:get("port" .. (size or 16), function(parent) return W.portrait(parent, size or 16) end)
  p:ClearAllPoints()
  p:SetPoint("TOPLEFT", self.parent, "TOPLEFT", x, y)
  p:SetPlayer(full)
  return p
end

function Doc:bar(x, y, w, pct, color)
  local b = self:get("bar", function(parent) return W.bar(parent, 100, 8) end)
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", self.parent, "TOPLEFT", x, y)
  b:SetWidth(w)
  b:SetTarget(pct, color, true)
  return b
end

-- A real game button on the right of a line.
function Doc:action(text, y, fn, width, tip)
  local b = self:get("action", function(parent)
    local btn = W.button(parent, "", 120)
    btn:SetScript("OnEnter", function(s)
      if s.tip then GameTooltip:SetOwner(s, "ANCHOR_TOP"); GameTooltip:SetText(s.tip, 1, 1, 1, 1, true); GameTooltip:Show() end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return btn
  end)
  b:SetText(text)
  b:SetWidth(width or math.max(b:GetFontString():GetStringWidth() + 28, 110))
  b:SetScript("OnClick", fn)
  b.tip = tip
  b:ClearAllPoints()
  b:SetPoint("TOPRIGHT", self.parent, "TOPRIGHT", -10, y)
  return b
end

-- A clickable card background for one suggestion.
function Doc:card(y, h, onClick, highlight)
  local c = self:get("card", function(parent)
    local f = CreateFrame("Button", nil, parent)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.hl = f:CreateTexture(nil, "HIGHLIGHT")
    f.hl:SetAllPoints()
    f.hl:SetColorTexture(1, 0.82, 0.3, 0.07)
    f.edge = f:CreateTexture(nil, "BORDER")
    f.edge:SetPoint("TOPLEFT"); f.edge:SetPoint("BOTTOMLEFT")
    f.edge:SetWidth(3)
    f.edge:SetTexture("Interface\\Buttons\\WHITE8X8")
    return f
  end)
  c:ClearAllPoints()
  c:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 6, y)
  c:SetSize(self.w - 12, h)
  c.bg:SetVertexColor(1, 1, 1, highlight and 0.07 or 0.035)
  local col = highlight or { 0.62, 0.52, 0.30 }
  c.edge:SetVertexColor(col[1], col[2], col[3], 0.9)
  c:SetScript("OnClick", onClick)
  c:SetFrameLevel(self.parent:GetFrameLevel() + 1)
  return c
end

---------------------------------------------------------------------------------------------------
-- Plain-language helpers
---------------------------------------------------------------------------------------------------

local function names(list)
  local out = {}
  for i, full in ipairs(list) do out[i] = QM.nameText(full) end
  if #out <= 1 then return out[1] or "" end
  return table.concat(out, ", ", 1, #out - 1) .. " and " .. out[#out]
end

local function yards(p)
  local d = p and QM.distanceTo(p.map, p.x, p.y)
  if not d then return nil end
  if d < 40 then return "right next to you" end
  return string.format("%d yards away", math.floor(d / 10 + 0.5) * 10)
end

local function qt(q) return C.gold .. (q and q.title or "?") .. "|r" end

local nextStep = QM.nextStep

local function stepSentence(s)
  if s.kind == "blocked" then
    return (s.blocked and s.blocked.npc or "The quest giver") .. " doesn't offer " .. C.gold .. (QM.titleOf(s.qid) or "it") .. "|r" ..
           " to you yet - something earlier is missing"
  end
  local title = C.gold .. (QM.titleOf(s.qid) or "the first quest") .. "|r"
  local prefix = s.total > 1 and ("Step " .. s.n .. " of " .. s.total .. ": ") or ""
  if s.kind == "finish" then
    local t = QM.turninOf(s.qid)
    return prefix .. "finish " .. title .. " (it's in your log)" .. (t and t.npc and (" and turn it in to " .. t.npc) or "")
  end
  if s.giver and s.giver.npc then
    local where = yards(s.giver)
    return prefix .. "get " .. title .. " from " .. C.white .. s.giver.npc .. "|r" .. (where and (C.grey .. ", " .. where .. "|r") or "")
  elseif s.giver then
    return prefix .. "pick up " .. title .. (yards(s.giver) and (C.grey .. ", " .. yards(s.giver) .. "|r") or "")
  end
  return prefix .. "get " .. title .. C.grey .. " - where it starts isn't known yet, ask them|r"
end

-- Same sentence, starting with a capital letter.
local function stepSentenceCap(s)
  local t = stepSentence(s)
  return (t:gsub("^%l", string.upper))
end

-- The button action for the next step: guided trip to its quest giver, or (if it's already in your log)
-- the game's arrow pointed at that quest. Never a later step.
local function goTo(s)
  if not s or s.kind == "blocked" then return nil end
  if s.kind == "finish" then return function() QM.trackOwnQuest(s.qid) end end
  if s.giver and s.giver.map and s.giver.x then
    return function() QM.guide(s.giver, { npc = s.giver.npc, title = QM.titleOf(s.qid), qid = s.qid, verb = "Pick up" }) end
  end
end
---------------------------------------------------------------------------------------------------
-- Left: who
---------------------------------------------------------------------------------------------------

local cards = {}
local function card(i)
  if cards[i] then return cards[i] end
  local c = CreateFrame("Button", nil, J.left.child)
  c:SetSize(COL1 - 12, 56)
  c.bg = c:CreateTexture(nil, "BACKGROUND")
  c.bg:SetAllPoints()
  c.bg:SetColorTexture(1, 1, 1, 0.03)
  c.sel = c:CreateTexture(nil, "BORDER")
  c.sel:SetAllPoints()
  if not W.atlas(c.sel, { "PetList-ButtonSelect", "Professions_Recipe_Active" }) then
    c.sel:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    c.sel:SetBlendMode("ADD")
    c.sel:SetVertexColor(1, 0.82, 0.3, 0.6)
  end
  c.sel:Hide()
  c.hl = c:CreateTexture(nil, "HIGHLIGHT")
  c.hl:SetAllPoints()
  c.hl:SetColorTexture(1, 0.82, 0.3, 0.07)
  c.portrait = W.portrait(c, 30)
  c.portrait:SetPoint("LEFT", 8, 0)
  c.home = c:CreateTexture(nil, "ARTWORK")
  c.home:SetSize(32, 32)
  c.home:SetPoint("LEFT", 7, 0)
  c.home:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
  c.name = W.text(c, "OVERLAY", "GameFontNormal")
  c.name:SetPoint("TOPLEFT", c.portrait, "TOPRIGHT", 12, 4)
  c.name:SetPoint("RIGHT", -6, 0)
  c.info = W.text(c, "OVERLAY", "GameFontDisableSmall")
  c.info:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -2)
  c.info:SetPoint("RIGHT", -6, 0)
  c.now = W.text(c, "OVERLAY", "GameFontHighlightSmall")
  c.now:SetPoint("TOPLEFT", c.info, "BOTTOMLEFT", 0, -2)
  c.now:SetPoint("RIGHT", -6, 0)
  c.badge = W.text(c, "OVERLAY", "GameFontNormalSmall")
  c.badge:SetPoint("TOPRIGHT", -6, -5)
  c:SetScript("OnClick", function(self)
    QM.playSound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    J.sel, J.quest = self.full, nil
    J.refresh()
  end)
  cards[i] = c
  return c
end

local function renderLeft(suggestCount)
  local list = { "home", "dungeons", "me" }
  for _, full in ipairs(QM.mateList()) do list[#list + 1] = full end
  local y = -2
  for i, full in ipairs(list) do
    local c = card(i)
    c.full = full
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", J.left.child, "TOPLEFT", 2, y)
    local m = QM.mates[full]
    local special = (full == "home" or full == "dungeons")
    c.home:SetShown(special)
    c.portrait:SetShown(not special)
    if not special then c.portrait:SetPlayer(full) end
    c.home:SetTexture(full == "dungeons" and "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01" or "Interface\\Icons\\INV_Misc_Map_01")
    if full == "dungeons" then
      local dg = QM.Dungeons.task()
      c.name:SetText(C.gold .. "Dungeons|r")
      c.info:SetText("Every dungeon's quests")
      if dg then
        local p = QM.Dungeons.plan(dg)
        c.now:SetText(C.green .. "Getting ready: |r" .. dg.name .. C.grey .. " " .. p.ready .. "/" .. p.total .. "|r")
      else
        c.now:SetText(C.grey .. "Pick one to get the party ready|r")
      end
      c.badge:SetText("")
    elseif full == "home" then
      c.name:SetText(C.gold .. "Start here|r")
      c.info:SetText("What can we do together?")
      c.now:SetText(suggestCount > 0 and (C.soft .. suggestCount .. " suggestion" .. (suggestCount == 1 and "" or "s") .. "|r") or (C.grey .. "Nothing to suggest yet|r"))
      c.badge:SetText("")
    elseif full == "me" then
      c.name:SetText(C.gold .. "You|r")
      c.info:SetText("Level " .. (UnitLevel("player") or "?") .. " - " .. (QM.me.zone or ""))
      local q = QM.me.quests[QM.me.focus]
      c.now:SetText(q and (C.soft .. "Doing: |r" .. q.title) or (C.grey .. "Not on a quest right now|r"))
      c.badge:SetText("")
    else
      c.name:SetText(QM.nameText(full))
      local lvl = (m and m.level and m.level > 0) and m.level or (QM.roster[full] and QM.roster[full].level) or "?"
      c.info:SetText("Level " .. lvl .. " - " .. ((m and m.zone) or ""))
      if not (m and m.synced) then
        c.now:SetText(C.grey .. "Needs Questmates|r")
        c.badge:SetText("")
      else
        local q = m.quests[m.focus]
        c.now:SetText(q and (C.soft .. "Doing: |r" .. q.title) or (C.grey .. "Exploring|r"))
        local need = 0
        for id in pairs(m.quests) do if QM.relation(id) == "theirs" then need = need + 1 end end
        c.badge:SetText(need > 0 and (C.orange .. need .. " new|r") or "")
      end
    end
    c.sel:SetShown(J.sel == full)
    c:Show()
    y = y - 60
  end
  for i = #list + 1, #cards do cards[i]:Hide() end
  J.left:SetContentHeight(-y)
end

---------------------------------------------------------------------------------------------------
-- Home: "What can we do together?" - most important first
---------------------------------------------------------------------------------------------------

local function collectSuggestions()
  local S = { now = {}, turnin = {}, together = {}, catchup = {}, help = {} }
  local mates = {}
  for _, full in ipairs(QM.mateList()) do
    local m = QM.mates[full]
    if m and m.synced then mates[#mates + 1] = full end
  end
  S.mates = mates
  -- 1. what each friend is doing right now
  for _, full in ipairs(mates) do
    local m = QM.mates[full]
    S.now[#S.now + 1] = { full = full, q = m.quests[m.focus] }
  end
  -- 2/3. quests you share
  for id, mine in pairs(QM.me.quests) do
    local with = {}
    for _, full in ipairs(mates) do if QM.mates[full].quests[id] then with[#with + 1] = full end end
    if #with > 0 then
      local allReady = mine.state == 1
      for _, full in ipairs(with) do if QM.mates[full].quests[id].state ~= 1 then allReady = false end end
      if allReady then S.turnin[#S.turnin + 1] = { q = mine, with = with }
      elseif mine.state ~= 1 then S.together[#S.together + 1] = { q = mine, with = with } end
    end
  end
  table.sort(S.together, function(a, b)
    local fa = (a.q.id == QM.me.focus) and 0 or 1
    local fb = (b.q.id == QM.me.focus) and 0 or 1
    if fa ~= fb then return fa < fb end
    if #a.with ~= #b.with then return #a.with > #b.with end
    return a.q.level < b.q.level
  end)
  -- 4. quests they have that you don't, nearest first
  local seen = {}
  for _, full in ipairs(mates) do
    local m = QM.mates[full]
    for id, q in pairs(m.quests) do
      if not seen[id] and QM.relation(id) == "theirs" then
        seen[id] = true
        local who = {}
        for _, f2 in ipairs(mates) do if QM.mates[f2].quests[id] then who[#who + 1] = f2 end end
        local s = nextStep(id)
        local d = s.giver and QM.distanceTo(s.giver.map, s.giver.x, s.giver.y)
        local onIt = false
        for _, f2 in ipairs(who) do if QM.mates[f2].focus == id then onIt = true end end
        S.catchup[#S.catchup + 1] = { q = q, who = who, step = s, dist = d, onIt = onIt }
      end
    end
  end
  table.sort(S.catchup, function(a, b)
    if a.onIt ~= b.onIt then return a.onIt end
    if (a.dist ~= nil) ~= (b.dist ~= nil) then return a.dist ~= nil end
    if a.dist and b.dist and a.dist ~= b.dist then return a.dist < b.dist end
    return a.q.level < b.q.level
  end)
  -- 5. your quests they don't have
  for id, q in pairs(QM.me.quests) do
    local lacking = {}
    for _, full in ipairs(mates) do
      local m = QM.mates[full]
      if not m.quests[id] and not m.done[id] then lacking[#lacking + 1] = full end
    end
    if #lacking > 0 and q.state ~= 1 then S.help[#S.help + 1] = { q = q, who = lacking } end
  end
  table.sort(S.help, function(a, b) return a.q.level < b.q.level end)
  S.count = #S.turnin + #S.together + #S.catchup + #S.help
  return S
end

local MAXPER = 5

local function renderHome(S)
  local d = J.homeDoc
  d:reset()
  local y = -8
  y = d:text(y, "What can we do together?", "GameFontNormalLarge", 10, nil, 1, 0.82, 0)
  y = d:text(y, "Questmates compares everyone's quests and lists what to do next - most important first.", "GameFontHighlightSmall", 10, nil, 0.8, 0.8, 0.8)

  if QM.DB.helpSeen ~= true then
    local top = y - 4
    local c = d:card(top, 84, nil, { 1, 0.82, 0.2 })
    c:EnableMouse(false)
    y = d:text(top - 8, C.gold .. "How it works|r", "GameFontNormal", 16)
    y = d:text(y, "1.  Everyone in your party needs Questmates.\n2.  Below you'll see what your friends are doing and what you can do together.\n3.  Press a button to get there - the game puts an arrow on your screen.", "GameFontHighlightSmall", 16, d.w - 140)
    d:action("Got it", top - 30, function() QM.DB.helpSeen = true; J.refresh() end, 90)
    y = top - 92
  end

  local task = QM.Dungeons and QM.Dungeons.task()
  if task then y = QM.Dungeons.renderTaskBox(d, y - 4, task) end

  if #QM.mateList() == 0 then
    y = d:section(y, "You're not in a party")
    y = d:text(y, "1.  Invite your friend to a party.\n2.  Make sure they have Questmates too (send them  Install Questmates.bat).\n3.  This page fills in by itself.", "GameFontHighlight", 14)
    d:action("Try the demo", y - 4, function() QM.toggleDemo() end, 130, "Adds a pretend party member so you can see how everything works.")
    y = d:text(y - 8, C.grey .. "Want to see it first? Try the demo:|r", "GameFontHighlightSmall", 14)
    J.home:SetContentHeight(-y + 40)
    return
  end
  if #S.mates == 0 then
    y = d:section(y, "Waiting for your friends")
    y = d:text(y, "Nobody in your party has Questmates yet (or it's still loading). Send them  Install Questmates.bat  from your Desktop.", "GameFontHighlight", 14)
    J.home:SetContentHeight(-y + 10)
    return
  end

  -- 1. right now
  y = d:section(y, "Right now")
  for _, e in ipairs(S.now) do
    local top = y - 2
    local q = e.q
    local rel = q and QM.relation(q.id)
    d:card(top, 46, function() QM:Fire("OPEN", e.full, q and q.id) end, q and QM.REL[rel == "both" and "both" or rel] or nil)
    d:portrait(e.full, 16, top - 7, 30)
    local line, sub, btn
    if not q then
      line = QM.nameText(e.full) .. " is exploring (no quest in particular)."
      sub = C.grey .. ((QM.mates[e.full].zone ~= "" and ("In " .. QM.mates[e.full].zone)) or "") .. "|r"
    elseif rel == "both" then
      if QM.me.focus == q.id then
        line = QM.nameText(e.full) .. " and you are both doing " .. qt(q) .. "."
        sub = C.green .. "You're questing together.|r"
      else
        line = QM.nameText(e.full) .. " is doing " .. qt(q) .. " - you have it too!"
        local _, h, n = QM.progress(QM.me.quests[q.id])
        sub = C.green .. "Join them" .. (n > 0 and (" (you're at " .. h .. "/" .. n .. ")") or "") .. ".|r"
        btn = { "Join them", function() QM.join(e.full, q.id) end, "Makes this your current quest and tells " .. QM.short(e.full) .. " you're coming." }
      end
    elseif rel == "done" then
      line = QM.nameText(e.full) .. " is doing " .. qt(q) .. "."
      sub = C.grey .. "You already finished it - you can still help them.|r"
    else
      line = QM.nameText(e.full) .. " is doing " .. qt(q) .. " - you don't have it."
      local s = nextStep(q.id)
      sub = stepSentenceCap(s)
      local go = goTo(s)
      if go then btn = { s.kind == "finish" and "Show me" or "Take me there", go, s.kind == "finish" and "Points the arrow at the quest in your log you need to finish first." or "Opens the map on the spot and puts an arrow on your screen." }
      elseif q.share then btn = { "Ask to share", function() QM.askShare(e.full, q.id) end, "Asks " .. QM.short(e.full) .. " to share it with you." }
      else btn = { "How to get it", function() QM:Fire("OPEN", e.full, q.id) end } end
    end
    d:text(top - 6, line, "GameFontHighlight", 56, d.w - 56 - (btn and 140 or 16))
    d:text(top - 24, sub, "GameFontHighlightSmall", 56, d.w - 56 - (btn and 140 or 16))
    if btn then d:action(btn[1], top - 12, btn[2], 120, btn[3]) end
    y = top - 50
  end

  local function more(list, label)
    if #list > MAXPER then
      y = d:text(y, C.grey .. "...and " .. (#list - MAXPER) .. " more " .. label .. ". Pick a person on the left to see them all.|r", "GameFontHighlightSmall", 14)
    end
  end

  -- 2. turn in together
  if #S.turnin > 0 then
    y = d:section(y, "Turn in together")
    for i, e in ipairs(S.turnin) do
      if i > MAXPER then break end
      local top = y - 2
      d:card(top, 30, function() QM:Fire("OPEN", nil, e.q.id) end, { 1, 0.82, 0 })
      d:icon("turnin", 14, top - 7, 16)
      d:text(top - 8, "You and " .. names(e.with) .. " finished " .. qt(e.q) .. " - turn it in!", "GameFontHighlight", 36, d.w - 50)
      y = top - 34
    end
  end

  -- 3. do together
  if #S.together > 0 then
    y = d:section(y, "Do together", "You both have these quests.")
    for i, e in ipairs(S.together) do
      if i > MAXPER then break end
      local top = y - 2
      d:card(top, 40, function() QM:Fire("OPEN", nil, e.q.id) end, QM.REL.both)
      d:icon("link", 14, top - 12, 16)
      d:text(top - 5, qt(e.q) .. C.grey .. "  with " .. names(e.with) .. "|r", "GameFontHighlight", 36, d.w - 180)
      local parts = { "You " .. math.floor(QM.progress(e.q) * 100 + 0.5) .. "%" }
      for _, full in ipairs(e.with) do
        parts[#parts + 1] = QM.short(full) .. " " .. math.floor(QM.progress(QM.mates[full].quests[e.q.id]) * 100 + 0.5) .. "%"
      end
      d:text(top - 22, C.grey .. table.concat(parts, "   ") .. "|r", "GameFontHighlightSmall", 36, d.w - 180)
      if QM.me.focus == e.q.id then
        d:text(top - 13, C.green .. "Doing it now|r", "GameFontHighlightSmall", d.w - 130, 120)
      else
        d:action("Do this now", top - 9, function() QM.join(e.with[1], e.q.id) end, 120, "Makes this your current quest; your friends see you're on it.")
      end
      y = top - 44
    end
    more(S.together, "shared quests")
  end

  -- 4. catch up
  if #S.catchup > 0 then
    y = d:section(y, "Get your friends' quests", "They have these and you don't. Nearest first.")
    for i, e in ipairs(S.catchup) do
      if i > MAXPER then break end
      local top = y - 2
      d:card(top, 40, function() QM:Fire("OPEN", e.who[1], e.q.id) end, QM.REL.theirs)
      d:icon("pickup", 14, top - 12, 16)
      d:text(top - 5, qt(e.q) .. C.grey .. "  - " .. names(e.who) .. (e.onIt and " (doing it now)" or "") .. "|r", "GameFontHighlight", 36, d.w - 180)
      d:text(top - 22, stepSentenceCap(e.step), "GameFontHighlightSmall", 36, d.w - 180)
      local go = goTo(e.step)
      local holder = e.who[1]
      if e.step.total <= 1 and QM.mates[holder].quests[e.q.id].share and not QM.giverOf(e.q.id) then
        d:action("Ask to share", top - 9, function() QM.askShare(holder, e.q.id) end, 120, "Asks " .. QM.short(holder) .. " to share it with you.")
      elseif go then
        d:action(e.step.kind == "finish" and "Show me" or "Take me there", top - 9, go, 120, e.step.kind == "finish" and "Points the arrow at the quest you need to finish first." or "Opens the map on the spot and puts an arrow on your screen.")
      else
        d:action("How to get it", top - 9, function() QM:Fire("OPEN", holder, e.q.id) end, 120)
      end
      y = top - 44
    end
    more(S.catchup, "quests")
  end

  -- 5. help them
  if #S.help > 0 then
    y = d:section(y, "Your friends don't have these", "Show or share them so you can do them together.")
    for i, e in ipairs(S.help) do
      if i > MAXPER then break end
      local top = y - 2
      d:card(top, 30, function() QM:Fire("OPEN", "me", e.q.id) end, QM.REL.mine)
      d:icon("ping", 14, top - 7, 16)
      d:text(top - 8, qt(e.q) .. C.grey .. "  - " .. names(e.who) .. " doesn't have it|r", "GameFontHighlight", 36, d.w - 180)
      if e.q.share and QM.groupChannel() then
        d:action("Share it", top - 4, function() QM.pushQuest(e.q.id) end, 120, "Sends the quest to your party right now (the game asks them to accept).")
      else
        d:action("Show them", top - 4, function() QM.suggest(e.q.id) end, 120, "Pops it up on their screen with the full chain and where to get it.")
      end
      y = top - 34
    end
    more(S.help, "quests")
  end

  if S.count == 0 then
    y = d:section(y, "All caught up")
    y = d:text(y, "Everyone has the same quests. Nice!", "GameFontHighlight", 14)
  end
  J.home:SetContentHeight(-y + 10)
end

---------------------------------------------------------------------------------------------------
-- Middle: one person's quests
---------------------------------------------------------------------------------------------------

local rows = {}
local function row(i)
  if rows[i] then return rows[i] end
  local r = W.linkButton(J.mid.child, 20)
  r:SetWidth(COL2 - 12)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(14, 14)
  r.icon:SetPoint("LEFT", 4, 0)
  r.text = W.text(r, "OVERLAY", "GameFontHighlightSmall")
  r.text:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
  r.right = W.text(r, "OVERLAY", "GameFontDisableSmall")
  r.right:SetPoint("RIGHT", -4, 0)
  r.right:SetJustifyH("RIGHT")
  r.text:SetPoint("RIGHT", r.right, "LEFT", -4, 0)
  r.sel = r:CreateTexture(nil, "BACKGROUND")
  r.sel:SetAllPoints()
  r.sel:SetColorTexture(1, 0.82, 0.3, 0.14)
  r.sel:Hide()
  r.headerText = W.text(r, "OVERLAY", "GameFontNormalSmall")
  r.headerText:SetPoint("LEFT", 4, -2)
  r.headerText:SetPoint("RIGHT", -4, -2)
  r.line = r:CreateTexture(nil, "ARTWORK")
  r.line:SetHeight(1)
  r.line:SetPoint("BOTTOMLEFT", 4, 1)
  r.line:SetPoint("BOTTOMRIGHT", -4, 1)
  r.line:SetColorTexture(0.62, 0.52, 0.30, 0.5)
  r:SetScript("OnClick", function(self)
    if not self.qid then return end
    QM.playSound("IG_QUEST_LOG_OPEN")
    J.quest = self.qid
    J.refresh()
  end)
  rows[i] = r
  return r
end

local GROUPS_MATE = {
  { key = "now", label = "Doing right now" },
  { key = "both", label = "You have these too" },
  { key = "theirs", label = "You don't have these" },
  { key = "done", label = "You already finished these" },
}
local GROUPS_ME = {
  { key = "now", label = "Doing right now" },
  { key = "mine", label = "Your friends don't have these" },
  { key = "both", label = "Your friends have these too" },
  { key = "solo", label = "Your quests" },
}

local function renderMid()
  local quests, groups, relOf, focus
  local who = J.sel
  if who == "me" then
    quests, groups, relOf, focus = QM.me.quests, GROUPS_ME, QM.myRelation, QM.me.focus
    J.midLabel:SetText("YOUR QUESTS")
  else
    local m = QM.mates[who]
    quests = m and m.quests or {}
    groups, relOf, focus = GROUPS_MATE, QM.relation, m and m.focus
    J.midLabel:SetText(string.upper(QM.short(who)) .. "'S QUESTS")
  end
  local by = {}
  for id, q in pairs(quests) do
    local r = (id == focus) and "now" or relOf(id)
    by[r] = by[r] or {}
    table.insert(by[r], q)
  end
  local i, y = 0, -2
  local first
  for _, g in ipairs(groups) do
    local list = by[g.key]
    if list and #list > 0 then
      table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.title < b.title
      end)
      i = i + 1
      local h = row(i)
      h.qid = nil
      h:SetHeight(22)
      h.icon:Hide(); h.text:SetText(""); h.right:SetText(""); h.sel:Hide()
      local col = (g.key == "now") and { 1, 0.82, 0 } or (QM.REL[g.key] or QM.REL.solo)
      h.headerText:SetText(QM.hex(col) .. g.label .. "|r  " .. C.grey .. #list .. "|r")
      h.headerText:Show(); h.line:Show()
      h:EnableMouse(false)
      h:ClearAllPoints(); h:SetPoint("TOPLEFT", J.mid.child, "TOPLEFT", 2, y); h:Show()
      y = y - 24
      for _, q in ipairs(list) do
        i = i + 1
        local r = row(i)
        r.qid = q.id
        first = first or q.id
        r:SetHeight(20)
        r:EnableMouse(true)
        r.headerText:Hide(); r.line:Hide()
        r.icon:Show()
        local rel = relOf(q.id)
        if q.state == 1 then W.icon(r.icon, "turnin")
        elseif rel == "theirs" then W.icon(r.icon, "pickup")
        elseif rel == "done" then W.icon(r.icon, "done")
        elseif rel == "mine" then W.icon(r.icon, "ping")
        else W.icon(r.icon, "link") end
        r.text:SetText(q.title)
        local pct = QM.progress(q)
        r.right:SetText(q.state == 1 and (C.gold .. "Done|r") or (#q.obj > 0 and (math.floor(pct * 100 + 0.5) .. "%") or ""))
        r.sel:SetShown(J.quest == q.id)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", J.mid.child, "TOPLEFT", 2, y); r:Show()
        y = y - 21
      end
      y = y - 6
    end
  end
  if i == 0 then
    i = 1
    local r = row(1)
    r.qid = nil
    r:EnableMouse(false)
    r.icon:Hide(); r.right:SetText(""); r.sel:Hide(); r.line:Hide(); r.headerText:Hide()
    r.text:SetText(C.grey .. (who == "me" and "Your quest log is empty." or (QM.mates[who] and QM.mates[who].synced) and "No quests right now." or "Waiting for their Questmates...") .. "|r")
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", J.mid.child, "TOPLEFT", 2, -4); r:Show()
    y = -28
  end
  for k = i + 1, #rows do rows[k]:Hide() end
  J.mid:SetContentHeight(-y)
  return first
end

---------------------------------------------------------------------------------------------------
-- Right: one quest. First line = what to do, with one big button.
---------------------------------------------------------------------------------------------------

local function progressBlock(d, y, full, q, label)
  d:portrait(full, 12, y + 1, 16)
  d:text(y, label, "GameFontHighlightSmall", 34, d.w - 150)
  local pct = QM.progress(q)
  d:bar(d.w - 108, y - 2, 96, pct, q.state == 1 and { 1, 0.82, 0 } or { 0.26, 0.62, 1 })
  y = y - 16
  for _, o in ipairs(q.obj) do
    local count = (o.need and o.need > 0) and (o.have .. "/" .. o.need .. " ") or ""
    if o.fin then y = d:text(y, "- " .. count .. o.t, "GameFontDisableSmall", 34, nil, 0.55, 0.55, 0.55)
    else y = d:text(y, "- " .. count .. o.t, "GameFontHighlightSmall", 34) end
  end
  if q.state == 1 then y = d:text(y, "- Finished! Turn it in.", "GameFontNormalSmall", 34, nil, 1, 0.82, 0) end
  return y - 4
end

-- The chain, strictly in order: done steps are ticked, the NEXT step gets the one button, later ones are locked.
local function stepsBlock(d, y, id, mine)
  local path = QM.pathTo(id)
  local nxt = mine and nil or QM.nextStep(id)
  local nextN = nxt and nxt.n
  for n, qid in ipairs(path) do
    local st = QM.stepState(qid)
    local title = QM.titleOf(qid)
    local isNext = (nextN == n)
    local locked = nextN and n > nextN
    local top = y
    if st == "done" then d:icon("done", 12, top, 16)
    elseif locked then d:icon("lock", 12, top, 16)
    elseif st == "have" then d:icon("turnin", 12, top, 16)
    else d:icon("pickup", 12, top, 16) end
    local head
    if isNext then head = C.orange .. "Next: |r" .. C.gold .. (title or ("Quest " .. qid)) .. "|r"
    elseif st == "done" then head = C.grey .. n .. ". " .. (title or ("Quest " .. qid)) .. "|r"
    elseif locked then head = C.grey .. n .. ". " .. (title or ("Quest " .. qid)) .. "|r"
    else head = C.grey .. n .. ". |r" .. C.gold .. (title or ("Quest " .. qid)) .. "|r" end
    y = d:text(y, head, "GameFontHighlightSmall", 34, d.w - 50)
    local g = QM.giverOf(qid)
    local sub
    if st == "done" then sub = C.grey .. "Done|r"
    elseif locked then sub = C.grey .. "Locked - do step " .. nextN .. " first|r"
    elseif st == "have" then
      local t = QM.turninOf(qid)
      sub = C.green .. "In your quest log|r" .. ((qid ~= id) and (C.soft .. " - finish it" .. (t and t.npc and (" and turn it in to " .. t.npc) or "") .. "|r") or "")
    elseif g then
      sub = "From " .. QM.placeText(g) .. (yards(g) and (C.grey .. " - " .. yards(g) .. "|r") or "")
    else sub = C.grey .. "Where it starts isn't known yet|r" end
    y = d:text(y, sub, "GameFontHighlightSmall", 34, d.w - 50)
    y = y - 8
  end
  return y, path
end
local function renderQuest()
  local d = J.detailDoc
  d:reset()
  local id = J.quest
  local y = -8
  if not id then
    y = d:text(y, "Pick a quest on the left to see what to do.", "GameFontDisable", 10)
    J.right:SetContentHeight(-y)
    return
  end
  local mine = QM.me.quests[id]
  local any = mine
  local holders = {}
  for _, full in ipairs(QM.mateList()) do
    local m = QM.mates[full]
    if m and m.quests[id] then holders[#holders + 1] = full; any = any or m.quests[id] end
  end
  local title, level = QM.titleOf(id)
  title = (any and any.title) or title or ("Quest " .. id)
  level = (any and any.level) or level
  local rel = mine and "both" or QM.relation(id)
  local lacking = {}
  for _, full in ipairs(QM.mateList()) do
    local m = QM.mates[full]
    if m and m.synced and not m.quests[id] and not m.done[id] then lacking[#lacking + 1] = full end
  end

  y = d:text(y, title, "QuestTitleFont", 10, nil, 1, 0.82, 0)
  if level and level > 0 then y = d:text(y, "Level " .. level, "GameFontDisableSmall", 10) end

  -- WHAT TO DO (most important, always first)
  local top = y - 4
  local box = d:card(top, 52, nil, rel == "theirs" and QM.REL.theirs or (rel == "done" and QM.REL.done or QM.REL.both))
  box:EnableMouse(false)
  local line, sub, btn
  if mine then
    if mine.state == 1 then
      line, sub = "You finished this quest.", "Go back and turn it in."
    elseif #holders > 0 and QM.me.focus ~= id then
      line, sub = "You and " .. names(holders) .. " both have this.", "Do it together - your friends will see you're on it."
      btn = { "Do this now", function() QM.join(holders[1], id) end }
    elseif #holders > 0 then
      line, sub = "You're doing this together with " .. names(holders) .. ".", "Their progress is below."
    elseif #lacking > 0 then
      line, sub = names(lacking) .. " doesn't have this quest.", "Show it to them - they'll see how to get it."
      btn = (mine.share and QM.groupChannel()) and { "Share it", function() QM.pushQuest(id) end } or { "Show them", function() QM.suggest(id) end }
    else
      line, sub = "This quest is in your log.", ""
      btn = { QM.getManualFocus() == id and "Stop" or "Do this now", function() QM.setManualFocus(QM.getManualFocus() ~= id and id or nil); J.refresh() end }
    end
  elseif rel == "done" then
    line, sub = "You already finished this quest.", (#holders > 0 and (names(holders) .. " is still doing it - you can help them.") or "")
  else
    local s = nextStep(id)
    if s.total > 1 then
      line = "You need " .. (s.total - s.n + 1 == 1 and "1 more step" or ((s.total - s.n + 1) .. " steps")) .. " to get this quest."
    else
      line = "You don't have this quest yet."
    end
    sub = (s.total > 1) and "The steps are listed below - start with the first one." or stepSentenceCap(s)
    local go = goTo(s)
    local holder = holders[1]
    if s.kind == "blocked" then
      line = (s.blocked.npc or "The quest giver") .. " doesn't offer " .. (s.qid == id and "this quest" or (QM.titleOf(s.qid) or "the first step")) .. " to you yet."
      sub = "It needs an earlier quest the quest database doesn't list. What probably unlocks it is below."
    elseif s.total <= 1 and holder and QM.mates[holder].quests[id].share and not s.giver then
      btn = { "Ask to share", function() QM.askShare(holder, id) end }
    elseif go then
      btn = { s.kind == "finish" and "Show me" or "Take me there", go }
    elseif holder and QM.mates[holder].quests[id].share then
      btn = { "Ask to share", function() QM.askShare(holder, id) end }
    end
  end
  local tw = d.w - 30 - (btn and 130 or 0)
  local ny = d:text(top - 8, C.white .. line .. "|r", "GameFontHighlight", 18, tw)
  d:text(ny, C.soft .. (sub or "") .. "|r", "GameFontHighlightSmall", 18, tw)
  if btn then d:action(btn[1], top - 14, btn[2], 120) end
  y = top - 60

  -- then: how to get it (if you don't have it), or everyone's progress (if you do)
  local function progress()
    y = d:section(y, "Progress")
    if mine then y = progressBlock(d, y, "me", mine, C.gold .. "You|r" .. (QM.me.focus == id and (C.grey .. " - doing it now|r") or "")) end
    for _, full in ipairs(holders) do
      local m = QM.mates[full]
      y = progressBlock(d, y, full, m.quests[id], QM.nameText(full) .. (m.focus == id and (C.grey .. " - doing it now|r") or ""))
    end
    for _, full in ipairs(QM.mateList()) do
      local m = QM.mates[full]
      if m and m.synced and not m.quests[id] then
        y = d:text(y, QM.nameText(full) .. "  " .. (m.done[id] and (C.grey .. "already finished it|r") or (C.orange .. "doesn't have it|r")), "GameFontHighlightSmall", 12)
      end
    end
  end
  local function steps()
    local path = QM.pathTo(id)
    if not mine and #path == 1 and not QM.askedPath[id] then QM.requestPath(id) end
    local unknown = not mine and #path <= 1 and not QM.giverOf(id)
    if not unknown and #path <= 1 then return end   -- a single step is already said in the box at the top
    y = d:section(y, mine and "Quest chain" or "How to get it", (not mine and #path > 1) and "Do these in order." or nil)
    if unknown then
      QM.requestPath(id)
      if QM.askedPath[id] == "asked" then
        y = d:text(y, C.grey .. "Asking your friends where it starts...|r", "GameFontHighlightSmall", 12)
      else
        y = d:text(y, "Nobody knows where it starts yet (they picked it up before Questmates was installed).", "GameFontHighlightSmall", 12)
        y = d:text(y, C.grey .. "Ask them in chat, or ask them to share it.|r", "GameFontHighlightSmall", 12)
      end
    elseif mine or #path > 1 then
      y = stepsBlock(d, y, id, mine)
    end
    if not mine and #path == 1 and not QM.askedPath[id] then QM.requestPath(id) end
  end
  -- not offered to you yet: what probably unlocks it (friends' answers first), one step at a time
  local function unlock(s)
    local O = QM.Offers
    O.ask(s.qid)
    local hints = O.hints(s.qid)
    y = d:section(y, "What probably unlocks it", "Quests " .. (s.blocked.npc or "that quest giver") .. " gives or takes around this level that you haven't done.")
    if #hints == 0 then
      y = d:text(y, "None left that you haven't done. Ask your friend what they did right before they got it.", "GameFontHighlightSmall", 12)
      return
    end
    for i, h in ipairs(hints) do
      if i > 6 then y = d:text(y, C.grey .. "...and " .. (#hints - 6) .. " more|r", "GameFontHighlightSmall", 34); break end
      local top = y
      d:icon(i == 1 and "pickup" or "lock", 12, top, 16)
      local title = QM.titleOf(h.qid) or "?"
      local who = ""
      if #h.who > 0 then
        local names = {}
        for _, full in ipairs(h.who) do names[#names + 1] = QM.nameText(full) end
        who = "  " .. table.concat(names, ", ") .. C.green .. " did this - most likely the one|r"
      end
      if h.inLog then
        local q = QM.me.quests[h.qid]
        y = d:text(y, (i == 1 and (C.orange .. "Finish first: |r") or (C.grey .. i .. ". |r")) .. C.gold .. title .. "|r" .. C.green .. "  (in your quest log)|r", "GameFontHighlightSmall", 34, d.w - 160)
        local _, have, need = QM.progress(q)
        y = d:text(y, (q.state == 1 and (C.green .. "Done - turn it in to " .. ((QM.turninOf(h.qid) or {}).npc or "the quest giver") .. "|r")
                       or ("From the same quest giver - finish it and turn it in" .. (need > 0 and (C.grey .. " (" .. have .. "/" .. need .. ")|r") or ""))),
                   "GameFontHighlightSmall", 34, d.w - 160)
        if i == 1 then d:action("Show me", top - 2, function() QM.trackOwnQuest(h.qid) end, 120) end
      else
        y = d:text(y, (i == 1 and (C.orange .. "Try first: |r") or (C.grey .. i .. ". |r")) .. C.gold .. title .. "|r" .. who, "GameFontHighlightSmall", 34, d.w - 160)
        local hs = QM.nextStep(h.qid)
        y = d:text(y, stepSentenceCap(hs), "GameFontHighlightSmall", 34, d.w - 160)
        if i == 1 then
          local go = goTo(hs)
          if go then d:action(hs.kind == "finish" and "Show me" or "Take me there", top - 2, go, 120) end
        end
      end
      y = y - 6
    end
    y = d:text(y, C.grey .. "When you get the quest after one of these, Questmates remembers it for next time.|r", "GameFontDisableSmall", 12)
  end
  if not mine then
    local s = nextStep(id)
    if s.kind == "blocked" then unlock(s) end
  end
  if mine then progress(); steps() else steps(); progress() end
  y = d:text(y - 6, C.grey .. "Quest chains are learned as you and your friends play, so they fill in over time.|r", "GameFontDisableSmall", 10)
  J.right:SetContentHeight(-y + 10)

  -- footer: the rest of the actions
  local acts = { { "Show on Map", function() QM:Fire("SHOW_ON_MAP", id) end, "Opens the map with markers for every step." } }
  if mine then
    if #QM.mateList() > 0 then acts[#acts + 1] = { "Show my friends", function() QM.suggest(id) end, "Pops this quest up on their screens with the full chain." } end
    acts[#acts + 1] = { QM.getManualFocus() == id and "Stop doing this" or "I'm doing this now", function()
      QM.setManualFocus(QM.getManualFocus() ~= id and id or nil); J.refresh() end, "Tells your friends this is the quest you're working on." }
  else
    for _, full in ipairs(holders) do
      if rel == "theirs" and QM.mates[full].quests[id].share then
        acts[#acts + 1] = { "Ask to share", function() QM.askShare(full, id) end, "Asks " .. QM.short(full) .. " to share it with you." }
        break
      end
    end
  end
  return acts
end

---------------------------------------------------------------------------------------------------

local function setFooter(acts)
  for _, b in ipairs(J.buttons) do b:Hide() end
  local x = -8
  for i = #acts, 1, -1 do
    local b = J.buttons[i]
    b:SetText(acts[i][1])
    b:SetWidth(math.max(b:GetFontString():GetStringWidth() + 26, 110))
    b:SetScript("OnClick", acts[i][2])
    b.tip = acts[i][3]
    b:ClearAllPoints()
    b:SetPoint("BOTTOMRIGHT", J.frame, "BOTTOMRIGHT", x, 12)
    x = x - b:GetWidth() - 4
    b:Show()
  end
end

function J.refresh()
  if not J.frame or not J.frame:IsShown() then return end
  if J.sel ~= "me" and J.sel ~= "home" and J.sel ~= "dungeons" and not QM.mates[J.sel] then J.sel = nil end
  J.sel = J.sel or "home"
  local S = collectSuggestions()
  renderLeft(S.count)
  local home = J.sel == "home" or J.sel == "dungeons"
  J.homePanel:SetShown(home)
  J.midPanel:SetShown(not home)
  J.rightPanel:SetShown(not home)
  J.midLabel:SetShown(not home)
  J.rightLabel:SetShown(not home)
  J.homeLabel:SetShown(home)
  if J.sel == "dungeons" then
    local d = J.homeDoc
    d:reset()
    local dg = J.dungeon and QM.Dungeons.get(J.dungeon)
    local y = dg and QM.Dungeons.renderDungeon(d, J, dg) or QM.Dungeons.renderList(d, J)
    J.home:SetContentHeight(-y + 10)
    J.homeLabel:SetText(dg and "DUNGEON" or "DUNGEONS")
    local acts = {}
    if QM.Dungeons.task() then acts[1] = { "Stop getting ready", function() QM.Dungeons.setTask(nil); J.refresh() end, "Ends the party's dungeon task." } end
    setFooter(acts)
  elseif home then
    J.homeLabel:SetText("SUGGESTIONS")
    renderHome(S)
    setFooter({})
  else
    local first = renderMid()
    local valid = J.quest and ((J.sel == "me" and QM.me.quests[J.quest]) or (J.sel ~= "me" and QM.mates[J.sel] and QM.mates[J.sel].quests[J.quest]))
    if not valid and not J.keepQuest and J.quest ~= J.pinned then J.quest = first end
    J.keepQuest = nil
    setFooter(renderQuest() or {})
  end
  local n = #QM.mateList()
  J.frame.subtitle:SetText(n > 0 and ("You + " .. n .. " friend" .. (n == 1 and "" or "s")) or "Not in a party")
end

local function build()
  local f = makeFrame()
  J.frame = f
  f.subtitle = W.text(f, "OVERLAY", "GameFontDisableSmall")
  f.subtitle:SetPoint("TOPLEFT", 66, -36)
  local p1 = inset(f, 10, COL1)
  J.midPanel = inset(f, 10 + COL1 + 6, COL2)
  J.rightPanel = inset(f, 10 + COL1 + COL2 + 12, COL3)
  J.homePanel = inset(f, 10 + COL1 + 6, WIDE)
  J.left = scroller(p1, COL1)
  J.mid = scroller(J.midPanel, COL2)
  J.right = scroller(J.rightPanel, COL3)
  J.home = scroller(J.homePanel, WIDE)
  J.detailDoc = newDoc(J.right)
  J.homeDoc = newDoc(J.home)
  local function colLabel(p, text)
    local fs = W.text(f, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("BOTTOMLEFT", p, "TOPLEFT", 4, 3)
    fs:SetText(text)
    return fs
  end
  colLabel(p1, "WHO")
  J.midLabel = colLabel(J.midPanel, "QUESTS")
  J.rightLabel = colLabel(J.rightPanel, "WHAT TO DO")
  J.homeLabel = colLabel(J.homePanel, "SUGGESTIONS")
  J.buttons = {}
  for i = 1, 4 do
    local b = W.button(f, "", 110)
    b:SetScript("OnEnter", function(s)
      if s.tip then GameTooltip:SetOwner(s, "ANCHOR_TOP"); GameTooltip:SetText(s.tip, 1, 1, 1, 1, true); GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    J.buttons[i] = b
  end
  -- options cog + legend explaining every icon
  local opts = CreateFrame("Button", nil, f)
  opts:SetSize(20, 20)
  opts:SetPoint("BOTTOMLEFT", 14, 14)
  opts.t = opts:CreateTexture(nil, "ARTWORK")
  opts.t:SetAllPoints()
  W.atlas(opts.t, { "questlog-icon-setting", "OptionsIcon-Brown" }, "Interface\\Buttons\\UI-OptionsButton")
  opts:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  opts:SetScript("OnClick", function() QM:Fire("OPTIONS") end)
  opts:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Questmates settings"); GameTooltip:Show() end)
  opts:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local legend = W.text(f, "OVERLAY", "GameFontHighlightSmall")
  legend:SetPoint("LEFT", opts, "RIGHT", 8, 0)
  legend:SetText(W.markup("pickup") .. " you don't have it   " .. W.markup("link") .. " you both have it   " ..
                 W.markup("done") .. " already done   " .. W.markup("turnin") .. " finished / turn in")
  J.legend = legend
end

function J.toggle()
  if not J.frame then build() end
  if J.frame:IsShown() then J.frame:Hide() else J.frame:Show() end
end

QM:On("OPEN", function(full, qid)
  if not J.frame then build() end
  if qid then
    J.sel = nil
    if full and full ~= "me" and QM.mates[full] and QM.mates[full].quests[qid] then J.sel = full
    elseif QM.me.quests[qid] then J.sel = "me"
    else
      for _, n in ipairs(QM.mateList()) do if QM.mates[n] and QM.mates[n].quests[qid] then J.sel = n break end end
    end
    -- nobody has it (a dungeon quest, one that isn't offered yet): show it on your own page
    J.sel = J.sel or (full and QM.mates[full] and full) or "me"
    J.quest = qid
    J.pinned = qid
    J.keepQuest = true
  elseif full then
    J.sel, J.quest = full, nil
  else
    J.sel, J.quest = "home", nil
  end
  if J.frame:IsShown() then J.refresh() else J.frame:Show() end
end)

QM:On("OPEN_DUNGEON", function(area)
  if not J.frame then build() end
  J.sel, J.dungeon = "dungeons", area
  if J.frame:IsShown() then J.refresh() else J.frame:Show() end
end)

QM:On("UPDATE", function() J.refresh() end)
