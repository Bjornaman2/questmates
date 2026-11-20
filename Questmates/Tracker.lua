-- Questmates / Tracker.lua
-- "Party" section that sits on screen like the game's own objective tracker: one block per party
-- member with their portrait, where they are, the quest they're on right now, its objectives and a
-- progress bar, and a line saying what that quest means for you (you have it / you need it / join).

local _, QM = ...
local W = QM.W
local C = QM.C

local WIDTH = 252
local T = CreateFrame("Frame", "QuestmatesTracker", UIParent)
T:SetSize(WIDTH, 30)
T:SetFrameStrata("LOW")
T:SetClampedToScreen(true)
T:SetMovable(true)
T:Hide()
QM.tracker = T

---------------------------------------------------------------------------------------------------
-- Header
---------------------------------------------------------------------------------------------------

local header = CreateFrame("Button", nil, T)
header:SetSize(WIDTH, 26)
header:SetPoint("TOPLEFT")
header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
header:RegisterForDrag("LeftButton")
header.bg = header:CreateTexture(nil, "BACKGROUND")
if W.atlas(header.bg, { "ui-questtracker-primary-objective-header", "UI-QuestTracker-Primary-Objective-Header",
                        "Objective-Header" }) then
  header.bg:SetPoint("TOPLEFT", -20, 8)
  header.bg:SetPoint("BOTTOMRIGHT", 12, -8)
else
  header.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
  header.bg:SetAllPoints()
  if header.bg.SetGradient and CreateColor then
    header.bg:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.75), CreateColor(0, 0, 0, 0))
  else
    header.bg:SetVertexColor(0, 0, 0, 0.4)
  end
  local line = header:CreateTexture(nil, "ARTWORK")
  line:SetTexture("Interface\\Buttons\\WHITE8X8")
  line:SetHeight(1)
  line:SetPoint("BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", 0, 0)
  if line.SetGradient and CreateColor then
    line:SetGradient("HORIZONTAL", CreateColor(0.9, 0.75, 0.35, 0.9), CreateColor(0.9, 0.75, 0.35, 0))
  end
end
header.text = W.text(header, "OVERLAY", "ObjectiveTrackerHeaderFont", "GameFontNormalMed2", "GameFontNormal")
header.text:SetPoint("LEFT", 8, 0)
header.text:SetText("Party")
header.count = W.text(header, "OVERLAY", "GameFontDisableSmall")
header.count:SetPoint("LEFT", header.text, "RIGHT", 6, -1)

local collapse = CreateFrame("Button", nil, header)
collapse:SetSize(16, 16)
collapse:SetPoint("RIGHT", -4, 0)
collapse.tex = collapse:CreateTexture(nil, "ARTWORK")
collapse.tex:SetAllPoints()
collapse:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")

local book = CreateFrame("Button", nil, header)
book:SetSize(16, 16)
book:SetPoint("RIGHT", collapse, "LEFT", -6, 0)
book.tex = book:CreateTexture(nil, "ARTWORK")
book.tex:SetAllPoints()
W.atlas(book.tex, { "QuestLog-icon-shareQuest", "groupfinder-icon-quest", "questlog-questtypeicon-group" }, "Interface\\Icons\\INV_Misc_Book_08")
book:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
book:SetScript("OnClick", function() QM:Fire("OPEN") end)
book:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText("Party Quest Journal")
  GameTooltip:AddLine("Everyone's quests, where to get them, and how to catch up.", 1, 1, 1, true)
  GameTooltip:Show()
end)
book:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function setCollapseArt()
  local col = QM.DB and QM.DB.trackerCollapsed
  if not W.atlas(collapse.tex, col and { "ui-questtrackerbutton-expand-all", "UI-QuestTrackerButton-Expand-All" }
                                  or { "ui-questtrackerbutton-collapse-all", "UI-QuestTrackerButton-Collapse-All" }) then
    collapse.tex:SetTexture(col and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
    collapse.tex:SetTexCoord(0, 1, 0, 1)
  end
end

local function toggleCollapse()
  QM.DB.trackerCollapsed = not QM.DB.trackerCollapsed
  setCollapseArt()
  QM.PlaySoundCollapse = true
  QM.playSound(QM.DB.trackerCollapsed and "IG_MAINMENU_OPTION_CHECKBOX_OFF" or "IG_MAINMENU_OPTION_CHECKBOX_ON")
  QM:Changed()
end
collapse:SetScript("OnClick", toggleCollapse)
header:SetScript("OnClick", function(_, btn)
  if btn == "RightButton" then QM:Fire("OPEN") else toggleCollapse() end
end)
header:SetScript("OnDragStart", function() if not QM.DB.trackerLocked then T:StartMoving() end end)
header:SetScript("OnDragStop", function()
  T:StopMovingOrSizing()
  local p, _, rp, x, y = T:GetPoint()
  QM.DB.trackerPoint = { p, rp, x, y }
end)
header:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText("Party")
  GameTooltip:AddLine("Click: collapse / expand", 1, 1, 1)
  GameTooltip:AddLine("Right-click: open the Party Quest Journal", 1, 1, 1)
  GameTooltip:AddLine("Drag: move", 1, 1, 1)
  GameTooltip:Show()
end)
header:SetScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------------------------------------------
-- Blocks
---------------------------------------------------------------------------------------------------

local blocks, blockPool = {}, {}
local MAXOBJ = 3

local function newBlock()
  local b = CreateFrame("Button", nil, T)
  b:SetWidth(WIDTH)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.hl = b:CreateTexture(nil, "BACKGROUND")
  b.hl:SetAllPoints()
  b.hl:SetTexture("Interface\\Buttons\\WHITE8X8")
  if b.hl.SetGradient and CreateColor then
    b.hl:SetGradient("HORIZONTAL", CreateColor(1, 0.82, 0.3, 0.12), CreateColor(1, 0.82, 0.3, 0))
  else
    b.hl:SetVertexColor(1, 0.82, 0.3, 0.06)
  end
  b.hl:Hide()

  b.portrait = W.portrait(b, 22)
  b.portrait:SetPoint("TOPLEFT", 6, -5)
  b.name = W.text(b, "OVERLAY", "GameFontNormal")
  b.name:SetPoint("TOPLEFT", b.portrait, "TOPRIGHT", 12, 2)
  b.where = W.text(b, "OVERLAY", "GameFontDisableSmall")
  b.where:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -1)
  b.where:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  b.lvl = W.text(b, "OVERLAY", "GameFontDisableSmall")
  b.lvl:SetPoint("LEFT", b.name, "RIGHT", 5, -1)

  b.qicon = b:CreateTexture(nil, "ARTWORK")
  b.qicon:SetSize(14, 14)
  b.title = W.text(b, "OVERLAY", "ObjectiveTrackerLineFont", "GameFontNormal")
  b.title:SetTextColor(1, 0.82, 0)
  b.objs = {}
  for i = 1, MAXOBJ do
    local fs = W.text(b, "OVERLAY", "ObjectiveTrackerLineFont", "GameFontHighlightSmall")
    b.objs[i] = fs
  end
  b.bar = W.bar(b, WIDTH - 44, 7)
  b.status = W.text(b, "OVERLAY", "GameFontHighlightSmall")
  b.join = W.button(b, "Join", 52)
  b.join:SetHeight(18)
  b.join:SetNormalFontObject(GameFontNormalSmall)
  b.join:SetHighlightFontObject(GameFontHighlightSmall)

  b.anim = W.slideIn(b, 10, 0, 0.35)

  b:SetScript("OnEnter", function(self)
    self.hl:Show()
    if self.tip then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      self.tip(GameTooltip)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self, btn)
    if btn == "RightButton" and self.questId then
      local g = QM.mates[self.full] and QM.mates[self.full].poi
      if g and g.id == self.questId then QM.setWaypoint(g, QM.short(self.full) .. "'s objective area") return end
    end
    QM:Fire("OPEN", self.full, self.questId)
  end)
  return b
end

local function objLine(o)
  local count = (o.need and o.need > 0) and (o.have .. "/" .. o.need .. " ") or ""
  local t = (o.t ~= "" and o.t) or "Objective"
  return "- " .. count .. t, o.fin
end

local function questTip(full, q)
  return function(tt)
    tt:SetText(q.title, 1, 0.82, 0)
    tt:AddLine(QM.nameText(full) .. C.grey .. "  [" .. q.level .. "]|r")
    for _, o in ipairs(q.obj) do
      local s, fin = objLine(o)
      if fin then tt:AddLine(s, 0.5, 0.5, 0.5) else tt:AddLine(s, 1, 1, 1) end
    end
    local mine = QM.me.quests[q.id]
    tt:AddLine(" ")
    if mine then
      tt:AddLine("You", 1, 0.82, 0)
      for _, o in ipairs(mine.obj) do
        local s, fin = objLine(o)
        if fin then tt:AddLine(s, 0.5, 0.5, 0.5) else tt:AddLine(s, 1, 1, 1) end
      end
    else
      local r = QM.REL[QM.relation(q.id)]
      tt:AddLine(r[4], r[1], r[2], r[3])
      local g = QM.giverOf(q.id)
      if g then tt:AddLine("Starts at: " .. QM.placeText(g), 1, 1, 1, true) end
    end
    tt:AddLine(" ")
    tt:AddLine(C.grey .. "Click: open in the Party Quest Journal|r")
    local m = QM.mates[full]
    if m and m.poi and m.poi.id == q.id then tt:AddLine(C.grey .. "Right-click: waypoint to their objective area|r") end
  end
end

local function fillBlock(b, full, collapsed)
  local m = QM.mates[full]
  local y = -5
  b.full = full
  b.portrait:SetPlayer(full)
  local _, _, _, hexName = QM.classColor(full)
  b.name:SetText(hexName .. QM.short(full) .. "|r")
  local lvl = (m and m.level and m.level > 0) and m.level or (QM.roster[full] and QM.roster[full].level)
  b.lvl:SetText(lvl and ("Lv " .. lvl) or "")
  local where = ""
  if m and m.zone ~= "" then
    where = m.zone
    if m.sub ~= "" and m.sub ~= m.zone then where = m.sub .. ", " .. m.zone end
    if QM.me.zone ~= "" and m.zone == QM.me.zone then where = where .. C.green .. "  (nearby)|r" end
  end
  b.where:SetText(where)
  b.where:SetShown(not collapsed)
  y = collapsed and -26 or -32

  for _, fs in ipairs(b.objs) do fs:Hide() end
  b.bar:Hide(); b.status:Hide(); b.join:Hide(); b.qicon:Hide(); b.title:Hide()
  b.questId, b.tip = nil, nil

  if not m or not m.synced then
    b.title:ClearAllPoints()
    b.title:SetPoint("TOPLEFT", b, "TOPLEFT", 34, y)
    b.title:SetPoint("RIGHT", b, "RIGHT", -6, 0)
    b.title:SetText(C.grey .. ((m and m.seen) and "Syncing quests..." or "Doesn't have Questmates yet") .. "|r")
    b.title:Show()
    b.tip = function(tt)
      tt:SetText(QM.short(full))
      tt:AddLine("No quest info yet.", 1, 1, 1)
      tt:AddLine("They need Questmates installed too - send them the installer.", 0.8, 0.8, 0.8, true)
    end
    b:SetHeight(-y + 18)
    return
  end

  local q = m.quests[m.focus]
  if not q then
    b.title:ClearAllPoints()
    b.title:SetPoint("TOPLEFT", b, "TOPLEFT", 34, y)
    b.title:SetPoint("RIGHT", b, "RIGHT", -6, 0)
    local n = 0
    for _ in pairs(m.quests) do n = n + 1 end
    b.title:SetText(C.grey .. "Exploring - " .. n .. " quest" .. (n == 1 and "" or "s") .. " in log|r")
    b.title:Show()
    b:SetHeight(-y + 18)
    return
  end

  b.questId = q.id
  b.tip = questTip(full, q)
  local rel = QM.relation(q.id)
  b.qicon:ClearAllPoints()
  b.qicon:SetPoint("TOPLEFT", b, "TOPLEFT", 32, y + 1)
  if q.state == 1 then W.icon(b.qicon, "turnin")
  elseif rel == "both" then W.icon(b.qicon, "link")
  elseif rel == "done" then W.icon(b.qicon, "done")
  else W.icon(b.qicon, "pickup") end
  if rel == "theirs" then b.qicon:SetVertexColor(1, 0.65, 0.3) else b.qicon:SetVertexColor(1, 1, 1) end
  b.qicon:Show()
  b.title:ClearAllPoints()
  b.title:SetPoint("TOPLEFT", b.qicon, "TOPRIGHT", 4, -1)
  b.title:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  b.title:SetText(q.title)
  b.title:Show()
  y = y - 16

  if collapsed then b:SetHeight(-y + 4); return end

  local shown = 0
  for i, o in ipairs(q.obj) do
    if shown >= MAXOBJ then break end
    if not o.fin or #q.obj <= MAXOBJ then
      shown = shown + 1
      local fs = b.objs[shown]
      local s, fin = objLine(o)
      fs:SetText(s)
      if fin then fs:SetTextColor(0.55, 0.55, 0.55) else fs:SetTextColor(0.9, 0.9, 0.9) end
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", b, "TOPLEFT", 44, y)
      fs:SetPoint("RIGHT", b, "RIGHT", -6, 0)
      fs:Show()
      y = y - 13
    end
  end
  if q.state == 1 then
    local fs = b.objs[math.min(shown + 1, MAXOBJ)]
    fs:SetText("- Ready for turn-in")
    fs:SetTextColor(1, 0.82, 0)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", b, "TOPLEFT", 44, y)
    fs:Show()
    y = y - 13
  end

  local pct = QM.progress(q)
  b.bar:ClearAllPoints()
  b.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 44, y - 3)
  b.bar:SetWidth(WIDTH - 52)
  local color = q.state == 1 and { 1, 0.82, 0 } or { 0.26, 0.62, 1 }
  local instant = b.barQuest ~= q.id
  b.barQuest = q.id
  b.bar:SetTarget(pct, color, instant)
  b.bar:Show()
  y = y - 14

  -- what it means for you
  local mine = QM.me.quests[q.id]
  local st
  if mine then
    local mp, h, n = QM.progress(mine)
    if QM.me.focus == q.id then st = C.green .. "Questing together|r"
    else st = C.green .. "You have it|r" .. C.grey .. (n > 0 and (" - " .. h .. "/" .. n) or "") .. "|r" end
    if mine.state == 1 then st = C.green .. "You're done too|r" end
    if QM.me.focus ~= q.id and mine.state ~= 1 then
      b.join:ClearAllPoints()
      b.join:SetPoint("TOPRIGHT", b, "TOPRIGHT", -6, y + 2)
      b.join:SetScript("OnClick", function() QM.join(full, q.id) end)
      b.join:Show()
    end
  elseif rel == "done" then
    st = C.grey .. "You already did this one|r"
  else
    local path = QM.pathTo(q.id)
    local g = QM.giverOf(q.id)
    if #path > 1 then st = C.orange .. "You need this|r" .. C.grey .. " - " .. (#path - 1) .. " step" .. (#path > 2 and "s" or "") .. " to catch up|r"
    elseif g and g.npc then st = C.orange .. "You need this|r" .. C.grey .. " - from " .. g.npc .. "|r"
    else st = C.orange .. "You need this quest|r" end
  end
  b.status:ClearAllPoints()
  b.status:SetPoint("TOPLEFT", b, "TOPLEFT", 44, y)
  b.status:SetPoint("RIGHT", b, "RIGHT", b.join:IsShown() and -62 or -6, 0)
  b.status:SetText(st)
  b.status:Show()
  y = y - 16
  b:SetHeight(-y + 4)
end

-- The party's dungeon (when getting ready for one): progress + the next stop, one click to go.
local taskBlock
local function renderTask(y)
  local dg = QM.Dungeons and QM.Dungeons.task()
  if not dg then if taskBlock then taskBlock:Hide() end return y end
  if not taskBlock then
    local b = CreateFrame("Button", nil, T)
    b:SetWidth(WIDTH)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.hl = b:CreateTexture(nil, "BACKGROUND")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 0.82, 0.3, 0.07)
    b.hl:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(20, 20)
    b.icon:SetPoint("TOPLEFT", 7, -4)
    b.icon:SetTexture("Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
    b.title = W.text(b, "OVERLAY", "GameFontNormal")
    b.title:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 8, 1)
    b.title:SetPoint("RIGHT", b, "RIGHT", -6, 0)
    b.bar = W.bar(b, WIDTH - 44, 7)
    b.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 36, -22)
    b.next = W.text(b, "OVERLAY", "ObjectiveTrackerLineFont", "GameFontHighlightSmall")
    b.next:SetPoint("TOPLEFT", b, "TOPLEFT", 36, -33)
    b.next:SetPoint("RIGHT", b, "RIGHT", -6, 0)
    b.next:SetWordWrap(true)
    b.anim = W.slideIn(b, 10, 0, 0.35)
    b:SetScript("OnEnter", function(self)
      self.hl:Show()
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText("Getting ready for " .. (self.dgName or "a dungeon"))
      GameTooltip:AddLine("Click: take me to the next stop", 1, 1, 1)
      GameTooltip:AddLine("Right-click: open the dungeon page", 1, 1, 1)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self, btn)
      local cur = QM.Dungeons.task()
      if not cur then return end
      if btn == "RightButton" then QM:Fire("OPEN_DUNGEON", cur.area) else QM.Dungeons.go(cur) end
    end)
    taskBlock = b
  end
  local b = taskBlock
  local a, p = QM.Dungeons.nextAction(dg)
  b.dgName = dg.name
  b.title:SetText(C.gold .. dg.name .. "|r" .. C.grey .. "  " .. p.ready .. "/" .. p.total .. " quests|r")
  b.bar:SetTarget(p.total > 0 and (p.ready / p.total) or 1, { 1, 0.7, 0.15 }, b.lastArea ~= dg.area)
  if b.lastArea ~= dg.area then b.anim:Stop(); b.anim:Play() end
  b.lastArea = dg.area
  local txt
  if a.kind == "stop" then
    local npc, names = QM.Dungeons.stopText(a.stop)
    txt = C.orange .. "Next: |r" .. npc .. C.grey .. " - " .. names .. "|r"
  elseif a.kind == "finish" then
    txt = C.orange .. "Next: |r" .. "finish " .. (QM.titleOf(a.qid) or "a quest") .. " first"
  else
    txt = C.green .. "All picked up - head to the dungeon|r"
  end
  b.next:SetText(txt)
  b:SetHeight(36 + b.next:GetStringHeight() + 4)
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", T, "TOPLEFT", 0, y)
  b:Show()
  return y - b:GetHeight() - 6
end

local function render()
  if not QM.DB then return end
  local list = QM.mateList()
  local hasTask = QM.Dungeons and QM.Dungeons.task()
  local show = QM.DB.tracker and (#list > 0 or hasTask)
  if not show then T:Hide(); return end
  local collapsed = QM.DB.trackerCollapsed
  setCollapseArt()
  local synced = 0
  for _, full in ipairs(list) do if QM.mates[full] and QM.mates[full].synced then synced = synced + 1 end end
  header.count:SetText(#list > 0 and (synced .. "/" .. #list) or "")

  local y = renderTask(-30)
  local seen = {}
  for _, full in ipairs(list) do
    local b = blocks[full]
    local fresh = false
    if not b then
      b = table.remove(blockPool) or newBlock()
      blocks[full] = b
      fresh = true
    end
    seen[full] = true
    local m = QM.mates[full]
    local focus = m and m.focus or 0
    fillBlock(b, full, collapsed)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", T, "TOPLEFT", 0, y)
    b:Show()
    if fresh or b.lastFocus ~= focus then
      b.anim:Stop(); b.anim:Play()
      if not fresh and focus ~= 0 then b.portrait:Pulse() end
    end
    if m and m.flashAt and m.flashAt ~= b.lastFlash then
      b.lastFlash = m.flashAt
      if not fresh then b.portrait:Pulse() end
    end
    b.lastFocus = focus
    y = y - b:GetHeight() - 4
  end
  for full, b in pairs(blocks) do
    if not seen[full] then b:Hide(); blocks[full] = nil; blockPool[#blockPool + 1] = b end
  end
  T:SetHeight(-y)
  if not T:IsShown() then
    T:Show()
    T:SetAlpha(0)
    if not T.fadeIn then T.fadeIn = W.fade(T, 0, 1, 0.5, function() T:SetAlpha(1) end) end
    T.fadeIn:Play()
    T:SetAlpha(1)
  end
end

local function place()
  T:ClearAllPoints()
  local p = QM.DB.trackerPoint
  if p then
    T:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    T:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -330, -230)
  end
end

function QM.resetTracker()
  QM.DB.trackerPoint = nil
  place()
  QM:Changed()
end

QM:On("INIT", function()
  place()
  setCollapseArt()
  local ev = CreateFrame("Frame")
  pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_DISABLED")
  pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")
  ev:SetScript("OnEvent", function(_, e)
    -- step back a little during fights, like the game's own tracker fades its extras
    T:SetAlpha(e == "PLAYER_REGEN_DISABLED" and 0.45 or 1)
  end)
end)
QM:On("UPDATE", render)
QM:On("PORTRAIT", function(unit)
  for full, b in pairs(blocks) do if QM.unitOf(full) == unit then b.portrait:SetPlayer(full) end end
end)
