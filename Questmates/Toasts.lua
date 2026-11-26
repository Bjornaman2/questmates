-- Questmates / Toasts.lua
-- Party news as banners in the style of the game's own alerts: a portrait in the classic gold ring,
-- a small quest icon, the quest title in gold and a coloured line saying what it means for you.
-- They slide in, shine once, wait (longer while the mouse is on them) and fade away.

local _, QM = ...
local W = QM.W
local C = QM.C

local WIDTH, HEIGHT, GAP, MAXN = 360, 62, 6, 3
local LIFE = 7

local anchor = CreateFrame("Frame", "QuestmatesToastAnchor", UIParent)
anchor:SetSize(WIDTH, HEIGHT)
local DEFAULT_Y = -28   -- just under the top edge, above the error / zone text area
anchor:SetPoint("TOP", UIParent, "TOP", 0, DEFAULT_Y)
anchor:SetFrameStrata("HIGH")
anchor:SetClampedToScreen(true)
anchor:SetMovable(true)

local active, pool = {}, {}

local function gradientEdge(t, left)
  if t.SetGradient and CreateColor then
    local a, b = CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.78)
    if left then t:SetGradient("HORIZONTAL", a, b) else t:SetGradient("HORIZONTAL", b, a) end
  else
    t:SetVertexColor(0, 0, 0, 0.5)
  end
end

local function hairline(parent, point)
  local holder = {}
  for i, side in ipairs({ "LEFT", "RIGHT" }) do
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetHeight(1)
    t:SetPoint(point .. side, parent, point .. side, 0, 0)
    t:SetPoint(point, parent, point, 0, 0)
    if t.SetGradient and CreateColor then
      local a, b = CreateColor(0.95, 0.78, 0.38, 0), CreateColor(0.95, 0.78, 0.38, 0.9)
      if side == "LEFT" then t:SetGradient("HORIZONTAL", a, b) else t:SetGradient("HORIZONTAL", b, a) end
    else
      t:SetVertexColor(0.95, 0.78, 0.38, 0.6)
    end
    holder[i] = t
  end
  return holder
end

local layout

local function release(t)
  for i, x in ipairs(active) do if x == t then table.remove(active, i) break end end
  t:Hide()
  t:SetScript("OnUpdate", nil)
  pool[#pool + 1] = t
  layout()
end

local function create()
  local t = CreateFrame("Button", nil, anchor)
  t:SetSize(WIDTH, HEIGHT)
  t:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  t.mid = t:CreateTexture(nil, "BACKGROUND")
  t.mid:SetColorTexture(0, 0, 0, 0.78)
  t.mid:SetPoint("TOPLEFT", 60, 0)
  t.mid:SetPoint("BOTTOMRIGHT", -60, 0)
  t.left = t:CreateTexture(nil, "BACKGROUND")
  t.left:SetTexture("Interface\\Buttons\\WHITE8X8")
  t.left:SetPoint("TOPLEFT"); t.left:SetPoint("BOTTOMRIGHT", t.mid, "BOTTOMLEFT")
  gradientEdge(t.left, true)
  t.right = t:CreateTexture(nil, "BACKGROUND")
  t.right:SetTexture("Interface\\Buttons\\WHITE8X8")
  t.right:SetPoint("TOPLEFT", t.mid, "TOPRIGHT"); t.right:SetPoint("BOTTOMRIGHT")
  gradientEdge(t.right, false)
  hairline(t, "TOP")
  hairline(t, "BOTTOM")

  t.portrait = W.portrait(t, 34)
  t.portrait:SetPoint("LEFT", t, "LEFT", 42, 1)
  t.kind = t:CreateTexture(nil, "OVERLAY", nil, 3)
  t.kind:SetSize(20, 20)
  t.kind:SetPoint("CENTER", t.portrait, "BOTTOMRIGHT", -1, 3)

  t.line1 = W.text(t, "OVERLAY", "GameFontHighlightSmall")
  t.line1:SetPoint("TOPLEFT", t.portrait, "TOPRIGHT", 16, 4)
  t.line1:SetPoint("RIGHT", t, "RIGHT", -30, 0)
  t.title = W.text(t, "OVERLAY", "GameFontNormalLarge", "GameFontNormal")
  t.title:SetPoint("TOPLEFT", t.line1, "BOTTOMLEFT", 0, -2)
  t.title:SetPoint("RIGHT", t, "RIGHT", -30, 0)
  t.line3 = W.text(t, "OVERLAY", "GameFontHighlightSmall")
  t.line3:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -2)
  t.line3:SetPoint("RIGHT", t, "RIGHT", -30, 0)

  t.inAnim = W.slideIn(t, 0, -14, 0.4)
  t.shineAnim = W.shine(t)
  t.outAnim = W.fade(t, 1, 0, 0.6, function() release(t) end)

  t:SetScript("OnEnter", function(self)
    self.hover = true
    if self.outAnim:IsPlaying() then self.outAnim:Stop(); self:SetAlpha(1) end
  end)
  t:SetScript("OnLeave", function(self) self.hover = false; self.born = GetTime() - LIFE + 2 end)
  t:SetScript("OnClick", function(self, btn)
    if btn == "RightButton" then self.outAnim:Play(); return end
    if self.data and self.data.click then self.data.click() end
    self.outAnim:Play()
  end)
  return t
end

function layout()
  for i, t in ipairs(active) do
    t.targetY = -(i - 1) * (HEIGHT + GAP)
    if not t.curY then t.curY = t.targetY end
  end
end

local function tick(self, elapsed)
  if self.curY ~= self.targetY then
    local d = self.targetY - self.curY
    self.curY = (math.abs(d) < 0.5) and self.targetY or (self.curY + d * math.min(elapsed * 10, 1))
    self:ClearAllPoints()
    self:SetPoint("TOP", anchor, "TOP", 0, self.curY)
  end
  if not self.hover and not self.outAnim:IsPlaying() and GetTime() - self.born > LIFE then
    self.outAnim:Play()
  end
end

-- What a quest means for you, as a coloured line.
local function relationLine(q)
  if not q or not q.id then return "" end
  local r = QM.relation(q.id)
  if r == "both" then
    local mine = QM.me.quests[q.id]
    local pct = mine and math.floor(QM.progress(mine) * 100 + 0.5) or 0
    return C.green .. "You have it too" .. (mine and mine.state ~= 1 and (" - " .. pct .. "% done") or "") .. "|r"
  elseif r == "done" then
    return C.grey .. "You already completed this|r"
  end
  local g = QM.giverOf(q.id)
  return C.orange .. "You don't have this" .. (g and g.npc and (" - from " .. g.npc) or "") .. "|r"
end

local TEXT = {
  hello     = { "is questing with you", "hello" },
  pickup    = { "picked up a quest", "pickup", "IG_QUEST_LIST_OPEN" },
  objective = { "completed an objective", "done" },
  ready     = { "is ready to turn in", "turnin", "IG_QUEST_LIST_COMPLETE" },
  turnin    = { "turned in", "turnin" },
  focus     = { "is now working on", "map" },
  suggest   = { "suggests doing", "ping", "MAP_PING" },
  join      = { "joined you on", "link", "IG_PLAYER_INVITE" },
  drop      = { "abandoned", "cross" },
  dest      = { "placed a map pin", "ping", "MAP_PING" },
  goto      = { "Follow the arrow on your screen", "map" },
  task      = { "picked a dungeon for the party", "ping", "MAP_PING" },
  nextstop  = { "Getting ready for a dungeon", "map" },
  shared    = { "Shared with your party", "link" },
  updated   = { "Questmates was updated", "done", "IG_QUEST_LIST_OPEN" },
  notoffered = { "Not offered to you yet", "lock" },
  version   = { "has a different Questmates version", "ping" },
  arrive    = { "You made it", "pickup", "IG_QUEST_LIST_OPEN" },
  finish    = { "Finish this quest first - the arrow now points to it", "turnin" },
  demo      = { "", "ping" },
}

local function show(d)
  if not QM.DB or not QM.DB.toasts then return end
  local spec = TEXT[d.kind] or TEXT.pickup
  local q = d.quest
  local m = QM.mates[d.full]
  local line1 = QM.nameText(d.full) .. " " .. C.soft .. spec[1] .. "|r"
  if d.full == "me" then line1 = C.soft .. spec[1] .. "|r" end
  local title = q and q.title or ""
  local line3 = relationLine(q)

  if d.kind == "hello" then
    local need = 0
    if m then for id in pairs(m.quests) do if QM.relation(id) == "theirs" then need = need + 1 end end end
    title = "Party quests are now shared"
    line3 = need > 0 and (C.orange .. need .. " of their quests are new to you|r") or (C.green .. "You're all caught up|r")
  elseif d.kind == "objective" and d.line then
    line3 = C.white .. d.line.t .. (d.line.need > 0 and (" " .. d.line.have .. "/" .. d.line.need) or "") .. "|r"
  elseif d.kind == "ready" or d.kind == "turnin" then
    local mine = q and QM.me.quests[q.id]
    if mine and mine.state == 1 then line3 = C.green .. "You're both done - go turn it in together!|r"
    elseif mine then
      local _, have, need = QM.progress(mine)
      line3 = C.orange .. "You still need to finish it" .. (need > 0 and (" (" .. have .. "/" .. need .. ")") or "") .. "|r"
    end
  elseif d.kind == "focus" and q and QM.me.quests[q.id] and QM.me.focus ~= q.id then
    line3 = C.green .. "You have it too|r" .. C.grey .. " - click to join them|r"
    d.click = function() QM.join(d.full, q.id) end
  elseif d.kind == "dest" then
    local dest = m and m.dest
    title = q and q.title or "Heading somewhere"
    local dist = dest and QM.distanceTo(dest.map, dest.x, dest.y)
    line3 = C.soft .. "Click to follow their pin|r" ..
            (dist and (C.grey .. string.format(" - %d yd away", math.floor(dist / 10 + 0.5) * 10) .. "|r") or "")
    d.click = function() QM.followDestination(d.full) end
  elseif d.kind == "goto" and d.extra then
    local g = d.extra
    local dist = QM.distanceTo(g.map, g.x, g.y)
    line3 = C.gold .. (g.verb or "Pick up") .. " " .. (g.title or "the quest") .. "|r" ..
            (dist and (C.grey .. string.format(" - %d yd", math.floor(dist / 10 + 0.5) * 10) .. "|r") or "")
    d.click = function() if OpenWorldMap then pcall(OpenWorldMap, g.map) end end
  elseif d.kind == "arrive" and d.extra then
    local g = d.extra
    line3 = C.white .. (g.npc and ("Talk to " .. g.npc) or "Look around here") .. "|r" ..
            (g.title and (C.soft .. " to " .. string.lower(g.verb or "pick up") .. " |r" .. C.gold .. g.title .. "|r") or "")
  elseif d.kind == "task" and d.extra then
    local dg = QM.Dungeons.get(d.extra.area)
    if dg then
      local p = QM.Dungeons.plan(dg)
      if d.full == "me" then line1 = C.soft .. "Your party is getting ready for|r" end
      line3 = C.soft .. p.total .. " quests for you - click to see where to go first|r"
    end
    d.click = function() QM:Fire("OPEN_DUNGEON", d.extra.area) end
  elseif d.kind == "nextstop" and d.extra then
    local a, p = d.extra.action, d.extra.plan
    local dg = QM.Dungeons.get(d.extra.area)
    if a.kind == "stop" then
      local npc, names = QM.Dungeons.stopText(a.stop)
      title = "Next stop: " .. npc
      line3 = C.gold .. names .. "|r" .. C.grey .. "  -  " .. p.ready .. "/" .. p.total .. " quests|r"
    elseif a.kind == "finish" then
      title = "Finish " .. (QM.titleOf(a.qid) or "a quest") .. " first"
      line3 = C.soft .. "It unlocks a quest for " .. (dg and dg.name or "the dungeon") .. "|r"
    else
      title = "All quests picked up!"
      local where = dg and QM.Dungeons.whereText(dg)
      line3 = C.green .. "Head to the entrance|r" .. (where and (C.grey .. " - " .. where .. "|r") or "") ..
              C.grey .. "  -  click for the way|r"
    end
    d.click = function() if dg then QM.Dungeons.go(dg) end end
  elseif d.kind == "notoffered" and d.extra then
    line3 = C.soft .. (d.extra.npc or "They") .. " doesn't offer it - it needs an earlier quest. Click to see what probably unlocks it.|r"
    d.click = function() QM:Fire("OPEN", nil, q.id) end
  elseif d.kind == "updated" then
    line3 = C.soft .. "It updated itself" .. (d.extra and d.extra.from and (" from " .. d.extra.from) or "") .. ". Type /qm to open the journal.|r"
    d.click = function() QM.journal.toggle() end
  elseif d.kind == "version" then
    line3 = C.soft .. "The newest one installs itself - restart WoW (or /reload) to load it.|r"
  elseif d.kind == "shared" then
    line3 = C.soft .. "Your friends get a window to accept it|r"
  elseif d.kind == "finish" then
    line3 = C.soft .. "When it's done, the next step unlocks.|r"
  elseif d.kind == "join" then
    line3 = C.green .. "Questing together|r"
  elseif d.kind == "demo" then
    line3 = C.grey .. (d.line or "") .. "|r"
  end
  d.click = d.click or function() QM:Fire("OPEN", d.full, q and q.id) end

  if QM.DB.chat then QM.print("%s %s %s", QM.nameText(d.full), spec[1], q and (C.gold .. q.title .. "|r") or "") end

  local t = table.remove(pool) or create()
  t.data = d
  t.portrait:SetPlayer(d.full)
  W.icon(t.kind, spec[2])
  t.line1:SetText(line1)
  t.title:SetText(title)
  t.line3:SetText(line3)
  t.born = GetTime()
  t.hover = false
  t:SetAlpha(1)
  table.insert(active, 1, t)
  while #active > MAXN do
    local old = active[#active]
    table.remove(active)
    old:Hide(); old:SetScript("OnUpdate", nil); pool[#pool + 1] = old
  end
  t.curY = 0
  layout()
  t.curY = t.targetY
  t:ClearAllPoints()
  t:SetPoint("TOP", anchor, "TOP", 0, t.curY)
  t:SetScript("OnUpdate", tick)
  t:Show()
  t.inAnim:Play()
  C_Timer.After(0.25, function() if t.data == d then t.shineAnim:Play() end end)
  t.portrait:Pulse()
  if spec[3] then QM.playSound(spec[3]) end
end

QM:On("TOAST", show)

function QM.toastTest()
  QM.toast(QM.me.full ~= "" and QM.me.full or "me", "demo", { title = "Notifications look like this" }, "Click a note to open it - right-click to dismiss")
end

-- Move the party notes: a gold outline you drag, with Done / Reset. Saved per account.
local function savePoint()
  local p, _, rp, x, y = anchor:GetPoint()
  QM.DB.toastPoint = { p, rp, x, y }
end

function QM.resetToasts()
  QM.DB.toastPoint = nil
  anchor:ClearAllPoints()
  anchor:SetPoint("TOP", UIParent, "TOP", 0, DEFAULT_Y)
  QM.print("party notes moved back to the top of the screen.")
end

function QM.lockToasts()
  if anchor.mover and anchor.mover:IsShown() then
    anchor.mover:Hide()
    QM.playSound("IG_MAINMENU_OPTION_CHECKBOX_OFF")
    QM.print("party notes locked in place.")
  end
end

function QM.unlockToasts()
  if anchor.mover and anchor.mover:IsShown() then QM.lockToasts(); return end
  if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then pcall(HideUIPanel, SettingsPanel) end
  local mv = anchor.mover
  if not mv then
    mv = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
    W.panel(mv, 0.55)
    mv:SetBackdropBorderColor(1, 0.82, 0.2, 1)
    mv:SetPoint("TOPLEFT", -6, 6)
    mv:SetPoint("BOTTOMRIGHT", 6, -(HEIGHT + GAP) * (MAXN - 1) - 6)
    mv:SetFrameStrata("DIALOG")
    mv:EnableMouse(true)
    mv:RegisterForDrag("LeftButton")
    mv:SetScript("OnDragStart", function() anchor:StartMoving() end)
    mv:SetScript("OnDragStop", function() anchor:StopMovingOrSizing(); savePoint() end)
    mv:SetScript("OnMouseUp", function(_, btn) if btn == "RightButton" then QM.lockToasts() end end)
    local title = W.text(mv, "OVERLAY", "GameFontNormalLarge", "GameFontNormal")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Party notes")
    local hint = W.text(mv, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
    hint:SetText("Drag to move.  Up to three notes stack downwards from the top.")
    local done = W.button(mv, DONE or "Done", 90)
    done:SetPoint("BOTTOMRIGHT", mv, "BOTTOM", -4, 12)
    done:SetScript("OnClick", QM.lockToasts)
    local reset = W.button(mv, RESET or "Reset", 90)
    reset:SetPoint("BOTTOMLEFT", mv, "BOTTOM", 4, 12)
    reset:SetScript("OnClick", QM.resetToasts)
    anchor.mover = mv
  end
  mv:Show()
  QM.playSound("IG_MAINMENU_OPTION_CHECKBOX_ON")
  QM.print("drag the party notes where you like, then press Done (or type /qm movenotes).")
end

QM:On("INIT", function()
  local p = QM.DB.toastPoint
  -- notes saved by 2.0.0 at its old default spot (lower on screen) move up to the new default
  if p and p[1] == "TOP" and p[2] == "TOP" and math.abs((p[3] or 0)) < 1 and math.abs((p[4] or 0) + 185) < 1 then
    QM.DB.toastPoint, p = nil, nil
  end
  if p then anchor:ClearAllPoints(); anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end
end)