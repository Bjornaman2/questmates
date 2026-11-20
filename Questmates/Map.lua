-- Questmates / Map.lua
-- World map markers, added the same way the game adds its own (a map data provider + pin template):
--   mate   a name tag over each party member: what they're on right now and how far along
--   area   their class icon, softly pulsing, where their current quest's objective is
--   spot   small dots where they recently made progress (kills, items)
--   dest   the map pin they placed: "heading here"
--   giver  a ! where a quest they have (and you don't) starts, or the next step to catch up to it
--   step   numbered markers for a whole catch-up path ("Show on Map" in the journal)
-- Also here: party info on unit / creature tooltips, and a "Show Party" button in the quest log.

local _, QM = ...
local W = QM.W
local C = QM.C
local TEMPLATE = "QuestmatesMapPinTemplate"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

---------------------------------------------------------------------------------------------------
-- Pin
---------------------------------------------------------------------------------------------------

QuestmatesMapPinMixin = CreateFromMixins and MapCanvasPinMixin and CreateFromMixins(MapCanvasPinMixin) or {}
local Pin = QuestmatesMapPinMixin

-- Map markers use only the game's own, ready-coloured icons (tinting plain shapes doesn't work on this
-- client's map: they came out as white circles). Every kind is explained by the legend on the map.

-- The round class icon of a player.
local function setClassIcon(tex, full)
  local class = QM.classOf(full)
  local tc = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
  if class and W.hasAtlas("classicon-" .. class:lower()) then
    tex:SetAtlas("classicon-" .. class:lower())
  elseif tc then
    tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
    tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
  else
    W.icon(tex, "hello")
  end
end
QM.setClassIcon = setClassIcon

local function setArrow(tex)
  if not W.atlas(tex, { "NPE_ArrowDown", "Rewards-Arrow-Down" }) then
    tex:SetTexture("Interface\\Buttons\\UI-MicroStream-Yellow")
    tex:SetTexCoord(0, 1, 0, 1)
  end
end

function Pin:OnLoad()
  -- markers stay about the same size on screen however far you zoom
  if self.SetScalingLimits then self:SetScalingLimits(1, 0.9, 1.1) end
  self.icon = self:CreateTexture(nil, "ARTWORK")
  self.icon:SetPoint("CENTER")
  -- a soft copy of the icon that swells and fades (the "working here" pulse)
  self.ghost = self:CreateTexture(nil, "BACKGROUND")
  self.ghost:SetPoint("CENTER")
  self.ghostAnim = self.ghost:CreateAnimationGroup()
  self.ghostAnim:SetLooping("REPEAT")
  local s = self.ghostAnim:CreateAnimation("Scale")
  if s.SetScaleFrom then s:SetScaleFrom(1, 1); s:SetScaleTo(2.0, 2.0) else s:SetScale(2.0, 2.0) end
  s:SetDuration(1.8); s:SetSmoothing("OUT")
  local a = self.ghostAnim:CreateAnimation("Alpha")
  a:SetFromAlpha(0.6); a:SetToAlpha(0); a:SetDuration(1.8); a:SetSmoothing("OUT")
  -- step number badge
  self.num = self:CreateFontString(nil, "OVERLAY")
  W.font(self.num, "GameFontNormalSmall", "GameFontHighlightSmall")
  self.num:SetPoint("BOTTOMLEFT", self, "TOPRIGHT", -5, -6)
  self.num:SetShadowOffset(1, -1)
  -- small caption under a marker (only the friend's map pin uses one)
  self.caption = self:CreateFontString(nil, "OVERLAY")
  W.font(self.caption, "GameFontHighlightSmall")
  self.caption:SetPoint("TOP", self, "BOTTOM", 0, -1)
  self.caption:SetShadowOffset(1, -1)
  -- one-line name tag beside a party member
  self.label = CreateFrame("Frame", nil, self)
  self.label.bg = self.label:CreateTexture(nil, "BACKGROUND")
  self.label.bg:SetAllPoints()
  self.label.bg:SetColorTexture(0, 0, 0, 0.62)
  self.label.stripe = self.label:CreateTexture(nil, "BORDER")
  self.label.stripe:SetPoint("TOPLEFT"); self.label.stripe:SetPoint("BOTTOMLEFT")
  self.label.stripe:SetWidth(2)
  self.label.text = W.text(self.label, "OVERLAY", "GameFontHighlightSmall")
  self.label.text:SetPoint("LEFT", 6, 0)
  self.bounce = self.icon:CreateAnimationGroup()
  local t1 = self.bounce:CreateAnimation("Translation"); t1:SetOffset(0, 3); t1:SetDuration(0.4); t1:SetSmoothing("OUT"); t1:SetOrder(1)
  local t2 = self.bounce:CreateAnimation("Translation"); t2:SetOffset(0, -3); t2:SetDuration(0.4); t2:SetSmoothing("IN"); t2:SetOrder(2)
  self.bounce:SetLooping("REPEAT")
  -- route chevrons light up one after another
  self.trailAnim = self.icon:CreateAnimationGroup()
  self.trailAnim:SetLooping("REPEAT")
  local r1 = self.trailAnim:CreateAnimation("Alpha"); r1:SetFromAlpha(0.35); r1:SetToAlpha(1); r1:SetDuration(0.3); r1:SetOrder(1)
  local r2 = self.trailAnim:CreateAnimation("Alpha"); r2:SetFromAlpha(1); r2:SetToAlpha(0.35); r2:SetDuration(0.5); r2:SetOrder(2)
  local r3 = self.trailAnim:CreateAnimation("Alpha"); r3:SetFromAlpha(0.35); r3:SetToAlpha(0.35); r3:SetDuration(0.6); r3:SetOrder(3)
  self.trailDelay = r1
end

-- "Take me there" spotlight: a bouncing arrow over the game's own waypoint diamond + a "Go here" card.
function Pin:BuildGuide()
  if self.guideBuilt then return end
  self.guideBuilt = true
  self.arrow = self:CreateTexture(nil, "OVERLAY")
  self.arrow:SetSize(28, 28)
  self.arrow:SetPoint("BOTTOM", self, "TOP", 0, 4)
  setArrow(self.arrow)
  self.arrowAnim = self.arrow:CreateAnimationGroup()
  self.arrowAnim:SetLooping("REPEAT")
  local u = self.arrowAnim:CreateAnimation("Translation"); u:SetOffset(0, 6); u:SetDuration(0.45); u:SetSmoothing("OUT"); u:SetOrder(1)
  local dn = self.arrowAnim:CreateAnimation("Translation"); dn:SetOffset(0, -6); dn:SetDuration(0.45); dn:SetSmoothing("IN"); dn:SetOrder(2)
  self.card = CreateFrame("Frame", nil, self)
  self.card:SetPoint("TOP", self, "BOTTOM", 0, -6)
  self.card.bg = self.card:CreateTexture(nil, "BACKGROUND")
  self.card.bg:SetAllPoints()
  self.card.bg:SetColorTexture(0, 0, 0, 0.78)
  self.card.top = self.card:CreateTexture(nil, "BORDER")
  self.card.top:SetPoint("TOPLEFT"); self.card.top:SetPoint("TOPRIGHT"); self.card.top:SetHeight(1)
  self.card.top:SetColorTexture(1, 0.78, 0.2, 0.9)
  self.card.title = W.text(self.card, "OVERLAY", "GameFontNormal")
  self.card.title:SetPoint("TOP", 0, -4)
  self.card.title:SetJustifyH("CENTER")
  self.card.sub = W.text(self.card, "OVERLAY", "GameFontHighlightSmall")
  self.card.sub:SetPoint("TOP", self.card.title, "BOTTOM", 0, -2)
  self.card.sub:SetJustifyH("CENTER")
  self.intro = self:CreateAnimationGroup()
  local isc = self.intro:CreateAnimation("Scale")
  if isc.SetScaleFrom then isc:SetScaleFrom(2.6, 2.6); isc:SetScaleTo(1, 1) else isc:SetScale(0.4, 0.4) end
  isc:SetDuration(0.55); isc:SetSmoothing("OUT")
  local ia = self.intro:CreateAnimation("Alpha"); ia:SetFromAlpha(0); ia:SetToAlpha(1); ia:SetDuration(0.35)
  self:HideGuide()
end

function Pin:HideGuide()
  if not self.guideBuilt then return end
  self.arrowAnim:Stop(); self.arrow:Hide(); self.card:Hide(); self.intro:Stop()
end

local LEVEL = { mate = "PIN_FRAME_LEVEL_GROUP_MEMBER", area = "PIN_FRAME_LEVEL_AREA_POI", trail = "PIN_FRAME_LEVEL_AREA_POI",
                dest = "PIN_FRAME_LEVEL_WAYPOINT_LOCATION", giver = "PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST",
                step = "PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST", target = "PIN_FRAME_LEVEL_WAYPOINT_LOCATION" }

function Pin:OnAcquired(kind, d)
  self.kind, self.d = kind, d
  if self.UseFrameLevelType then pcall(self.UseFrameLevelType, self, LEVEL[kind] or "PIN_FRAME_LEVEL_AREA_POI") end
  self.icon:Hide(); self.ghost:Hide(); self.num:Hide(); self.caption:Hide(); self.label:Hide()
  self.ghostAnim:Stop(); self.bounce:Stop(); self.trailAnim:Stop()
  self:HideGuide()
  self:SetAlpha(1)
  self.icon:SetVertexColor(1, 1, 1, 1)
  self.icon:SetTexCoord(0, 1, 0, 1)
  if self.icon.SetRotation then self.icon:SetRotation(0) end

  if kind == "mate" then
    self:SetSize(14, 14)                      -- the game draws their dot; we add hover + name tag
  elseif kind == "area" then
    self:SetSize(18, 18)
    self.icon:SetSize(16, 16); setClassIcon(self.icon, d.full); self.icon:Show()
    self.ghost:SetSize(16, 16); setClassIcon(self.ghost, d.full); self.ghost:Show(); self.ghostAnim:Play()
  elseif kind == "dest" then
    self:SetSize(18, 18)
    self.icon:SetSize(16, 16); setClassIcon(self.icon, d.full); self.icon:Show()
    self.caption:SetText(QM.nameText(d.full) .. C.white .. " is going here|r")
    self.caption:Show()
  elseif kind == "giver" then
    self:SetSize(18, 18)
    self.icon:SetSize(18, 18); W.icon(self.icon, "pickup"); self.icon:Show()
    if d.highlight then self.bounce:Play() end
  elseif kind == "step" then
    self:SetSize(18, 18)
    self.icon:SetSize(18, 18)
    local st = QM.stepState(d.qid)
    if d.locked then W.icon(self.icon, "lock"); self:SetAlpha(0.75)
    elseif st == "have" then W.icon(self.icon, "turnin")
    else W.icon(self.icon, "pickup") end
    self.icon:Show()
    if d.next then self.bounce:Play() end
    self.num:SetText(d.label or d.n)
    if d.locked then self.num:SetTextColor(0.7, 0.7, 0.7) else self.num:SetTextColor(1, 0.82, 0) end
    self.num:Show()
  elseif kind == "trail" then
    self:SetSize(12, 12)
    self.icon:SetSize(12, 12); setArrow(self.icon)
    if self.icon.SetRotation then self.icon:SetRotation(d.angle or 0) end
    self.icon:Show()
    self.trailDelay:SetStartDelay(d.delay or 0)
    self.trailAnim:Play()
  elseif kind == "target" then
    self:BuildGuide()
    self:SetSize(22, 22)
    self.arrow:Show(); self.arrowAnim:Play()
    self.card.title:SetText("Go here")
    self.card.sub:SetText((d.npc and (C.white .. d.npc .. "|r") or "") .. (d.title and ((d.npc and (C.grey .. " - |r") or "") .. C.gold .. d.title .. "|r") or ""))
    self.card:SetSize(math.max(self.card.title:GetStringWidth(), self.card.sub:GetStringWidth()) + 16, 34)
    self.card:Show()
    if d.intro then self.intro:Play() end
  end
end

-- Name tag beside the pin on the given side ("RIGHT", "LEFT", "TOP", "BOTTOM").
function Pin:ShowTag(text, side, r, g, b)
  local L = self.label
  L.text:SetText(text)
  L:SetSize(L.text:GetStringWidth() + 10, 14)
  L.stripe:SetColorTexture(r or 1, g or 1, b or 1, 1)
  L:ClearAllPoints()
  if side == "LEFT" then L:SetPoint("RIGHT", self, "LEFT", -3, 0)
  elseif side == "TOP" then L:SetPoint("BOTTOM", self, "TOP", 0, 3)
  elseif side == "BOTTOM" then L:SetPoint("TOP", self, "BOTTOM", 0, -3)
  else L:SetPoint("LEFT", self, "RIGHT", 3, 0) end
  L:Show()
end

function Pin:OnReleased()
  if self.ghostAnim then self.ghostAnim:Stop(); self.bounce:Stop(); self.trailAnim:Stop() end
  self:SetAlpha(1)
  self:HideGuide()
end
local function ago(t)
  local s = GetTime() - (t or GetTime())
  if s < 60 then return "just now" end
  return math.floor(s / 60) .. " min ago"
end

local function giverTooltip(tt, d)
  local title, level = QM.titleOf(d.qid)
  tt:SetText(title or "Quest", 1, 0.82, 0)
  if d.root and d.root ~= d.qid then
    tt:AddLine("Step " .. (d.n or "?") .. " towards " .. C.gold .. (QM.titleOf(d.root) or "") .. "|r", 1, 1, 1, true)
  end
  if d.full then tt:AddLine(QM.nameText(d.full) .. " has " .. (d.root and d.root ~= d.qid and "the quest this leads to" or "this quest"), 1, 1, 1, true) end
  local g = QM.giverOf(d.qid)
  if g then tt:AddLine("Starts at: " .. QM.placeText(g), 1, 1, 1, true) end
  local dist = g and QM.distanceTo(g.map, g.x, g.y)
  if dist then tt:AddLine(string.format("%d yards away", math.floor(dist / 10 + 0.5) * 10), 0.7, 0.7, 0.7) end
  if level and level > 0 then tt:AddLine("Level " .. level, 0.7, 0.7, 0.7) end
end

function Pin:OnMouseEnter()
  local d, tt = self.d, GameTooltip
  tt:SetOwner(self, "ANCHOR_RIGHT")
  if self.kind == "mate" then
    local m = QM.mates[d.full]
    tt:SetText(QM.short(d.full), QM.classColor(d.full))
    local q = m and m.quests[m.focus]
    if q then
      tt:AddLine("Now: " .. q.title, 1, 0.82, 0)
      for _, o in ipairs(q.obj) do
        local s = "- " .. ((o.need > 0) and (o.have .. "/" .. o.need .. " ") or "") .. o.t
        if o.fin then tt:AddLine(s, 0.5, 0.5, 0.5) else tt:AddLine(s, 1, 1, 1) end
      end
    else
      tt:AddLine("Exploring", 0.7, 0.7, 0.7)
    end
  elseif self.kind == "area" then
    local m = QM.mates[d.full]
    local q = m and m.quests[d.qid]
    tt:SetText(QM.short(d.full) .. " is working here", QM.classColor(d.full))
    if q then tt:AddLine(q.title, 1, 0.82, 0) end
    local r = QM.REL[QM.relation(d.qid)]
    tt:AddLine(r[4], r[1], r[2], r[3])
    tt:AddLine("Where their current quest's objective is.", 0.8, 0.8, 0.8, true)
    tt:AddLine(C.grey .. "Click: take me there|r")
  elseif self.kind == "spot" then
    local m = QM.mates[d.full]
    local q = m and m.quests[d.qid]
    tt:SetText(QM.short(d.full) .. " made progress here", QM.classColor(d.full))
    if q then tt:AddLine(q.title, 1, 0.82, 0) end
    tt:AddLine(ago(d.t), 0.7, 0.7, 0.7)
  elseif self.kind == "dest" then
    tt:SetText(QM.short(d.full) .. " is heading here", QM.classColor(d.full))
    local m = QM.mates[d.full]
    local q = m and d.qid and m.quests[d.qid]
    if q then tt:AddLine("For: " .. q.title, 1, 0.82, 0) end
    local dist = QM.distanceTo(d.map, d.x, d.y)
    if dist then tt:AddLine(string.format("%d yards from you", math.floor(dist / 10 + 0.5) * 10), 0.7, 0.7, 0.7) end
    tt:AddLine(C.grey .. "Click: follow (set the same waypoint)|r")
  elseif self.kind == "step" and d.locked then
    giverTooltip(tt, d)
    tt:AddLine("Locked - do step " .. (d.nextN or 1) .. " first", 1, 0.5, 0.3)
    tt:AddLine(C.grey .. "Right-click: open in journal|r")
  elseif self.kind == "giver" or self.kind == "step" then
    giverTooltip(tt, d)
    tt:AddLine(C.grey .. "Click: take me there  -  Right-click: open in journal|r")
  elseif self.kind == "target" then
    tt:SetText("Go here", 1, 0.82, 0)
    if d.npc then tt:AddLine(d.npc, 1, 1, 1) end
    if d.title then tt:AddLine((d.verb or "Pick up") .. ": " .. d.title, 1, 0.82, 0) end
    local dist = QM.distanceTo(d.map, d.x, d.y)
    if dist then tt:AddLine(string.format("%d yards away - follow the arrow on your screen", math.floor(dist / 10 + 0.5) * 10), 0.8, 0.8, 0.8, true) end
    tt:AddLine(C.grey .. "Right-click: stop guiding|r")
  elseif self.kind == "trail" then
    return
  end
  tt:Show()
end

function Pin:OnMouseLeave() GameTooltip:Hide() end

function Pin:OnClickAction(button)
  local d = self.d
  if self.kind == "dest" then QM.followDestination(d.full)
  elseif self.kind == "area" then
    local m = QM.mates[d.full]
    local q = m and m.quests[d.qid]
    QM.guide(d, { npc = QM.short(d.full) .. "'s quest area", title = q and q.title, verb = "Help with" }, { noMap = true })
  elseif self.kind == "target" then
    if button == "RightButton" then QM.stopGuide() end
  elseif self.kind == "giver" or self.kind == "step" then
    if button == "RightButton" then QM:Fire("OPEN", d.full, d.root or d.qid)
    elseif QM.stepState(d.qid) == "have" then
      QM.trackOwnQuest(d.qid)
    elseif d.locked then
      QM.print("do step %d first - you can't get this one yet.", d.nextN or 1)
    else
      local g = QM.giverOf(d.qid)
      QM.guide(g, { npc = g and g.npc, title = QM.titleOf(d.qid), qid = d.qid, verb = "Pick up" }, { noMap = true })
    end
  elseif self.kind == "mate" then QM:Fire("OPEN", d.full)
  end
end

---------------------------------------------------------------------------------------------------
-- Data provider
---------------------------------------------------------------------------------------------------

local Provider
QM.mapPath = nil   -- { root, path, untilT } while "Show on Map" is active

-- Most important first: a lower one is left out when it would sit on top of a higher one
-- (zoom in and it comes back).
local PRIO = { step = 90, dest = 70, giver = 60, area = 50, spot = 10 }
local MIN_GAP = 18   -- pixels on screen

local function canvasPixels(map)
  local ok, canvas = pcall(map.GetCanvas, map)
  local ok2, scale = pcall(map.GetCanvasScale, map)
  if ok and canvas and ok2 and type(scale) == "number" and scale > 0 then
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    if w and w > 0 and h and h > 0 then return w * scale, h * scale end
  end
  return 1000, 667
end

local function isZoneLevel(mapID)
  local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
  local zone = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
  return not (info and info.mapType and info.mapType < zone)
end

local function shortTitle(t)
  if not t then return "" end
  if #t > 26 then t = t:sub(1, 24):gsub("[\192-\255][\128-\191]*$", ""):gsub("%s+$", "") .. "..." end
  return t
end

local function acquire(map, c)
  local ok, pin = pcall(map.AcquirePin, map, TEMPLATE, c.kind, c.d)
  if ok and pin then
    pin:SetPosition(c.x, c.y)
    pin:SetScript("OnEnter", pin.OnMouseEnter)
    pin:SetScript("OnLeave", pin.OnMouseLeave)
    pin:SetScript("OnMouseUp", function(self, btn) self:OnClickAction(btn) end)
    return pin
  end
end

local livePins, lastSig = {}, nil

local function refresh(self, force)
  local map = self:GetMap()
  if not map then return end
  if not (QM.DB and QM.DB.mapPins) then pcall(map.RemoveAllPinsByTemplate, map, TEMPLATE); livePins = {}; lastSig = nil; return end
  local mapID = map:GetMapID()
  if not mapID then return end
  local zoneLevel = isZoneLevel(mapID)
  local PW, PH = canvasPixels(map)

  local cands, mates = {}, {}
  local function add(kind, d, srcMap, x, y)
    local px, py = QM.translate(srcMap, x, y, mapID)
    if px then cands[#cands + 1] = { kind = kind, d = d, x = px, y = py, prio = (PRIO[kind] or 0) + (d.boost or 0) } end
  end
  local giverDone = {}

  -- "Take me there": the spotlight and a trail from where you stood
  local gt = QM.guideTarget
  if gt then
    local tx, ty = QM.translate(gt.map, gt.x, gt.y, mapID)
    if tx then
      cands[#cands + 1] = { kind = "target", d = { npc = gt.npc, title = gt.title, verb = gt.verb, map = gt.map, x = gt.x, y = gt.y,
                            intro = (GetTime() - gt.t) < 1.5 }, x = tx, y = ty, prio = 1000, fixed = true }
      local fm, fx, fy = QM.playerPos()
      local sx, sy
      if fm and fx then sx, sy = QM.translate(fm, fx, fy, mapID) end
      if sx then
        local dx, dy = (tx - sx) * PW, (ty - sy) * PH
        local len = math.sqrt(dx * dx + dy * dy)
        local n = math.min(math.floor(len / 24), 30)
        local angle = (math.atan2 or math.atan)(dx, dy)   -- turns the down-arrow towards the target
        for i = 1, n - 1 do
          local k = i / n
          -- chevrons light up one after another towards the target
          cands[#cands + 1] = { kind = "trail", d = { delay = (i / n) * 1.0, angle = angle }, x = sx + (tx - sx) * k, y = sy + (ty - sy) * k,
                                prio = 0, fixed = true, noBlock = true }
        end
      end
    end
  end

  -- catch-up path from "Show on Map", strictly in order: one marker per place ("2-3" when steps share an NPC)
  local mp = QM.mapPath
  if mp and GetTime() < mp.untilT then
    local nxt = QM.nextStep(mp.root)
    local nextN = nxt and nxt.n or 1
    local groups = {}
    for n, qid in ipairs(mp.path) do
      local g = QM.giverOf(qid)
      if g and g.map and g.x then
        local last = groups[#groups]
        if last and last.g.map == g.map and math.abs(last.g.x - g.x) < 0.004 and math.abs(last.g.y - g.y) < 0.004 then
          last.last = n
          last.ns[#last.ns + 1] = n
        else
          groups[#groups + 1] = { g = g, first = n, last = n, ns = { n } }
        end
      end
    end
    for _, grp in ipairs(groups) do
      local hasNext = false
      for _, n in ipairs(grp.ns) do if n == nextN then hasNext = true end end
      local n = hasNext and nextN or grp.first
      local qid = mp.path[n]
      local locked = grp.first > nextN
      add("step", { qid = qid, n = n, label = grp.first == grp.last and tostring(grp.first) or (grp.first .. "-" .. grp.last),
                    root = mp.root, next = hasNext, locked = locked, nextN = nextN, full = mp.full, boost = hasNext and 5 or 0 },
          grp.g.map, grp.g.x, grp.g.y)
      for _, k in ipairs(grp.ns) do giverDone[mp.path[k]] = true end
    end
  end

  for _, full in ipairs(QM.mateList()) do
    local m = QM.mates[full]
    if m and m.synced then
      if zoneLevel and m.poi and m.poi.map then
        add("area", { full = full, qid = m.poi.id, map = m.poi.map, x = m.poi.x, y = m.poi.y }, m.poi.map, m.poi.x, m.poi.y)
      end
      if m.dest then add("dest", { full = full, map = m.dest.map, x = m.dest.x, y = m.dest.y, qid = m.dest.id }, m.dest.map, m.dest.x, m.dest.y) end
      -- a ! only where you can actually start: the next step of the chain, never a later one
      for qid in pairs(m.quests) do
        if QM.relation(qid) == "theirs" then
          local s = QM.nextStep(qid)
          if s.kind == "pickup" and s.giver and s.giver.map and s.giver.x and not giverDone[s.qid] then
            giverDone[s.qid] = true
            add("giver", { qid = s.qid, root = qid, n = s.n, full = full, highlight = (qid == m.focus), boost = (qid == m.focus) and 5 or 0 },
                s.giver.map, s.giver.x, s.giver.y)
          end
        end
      end
      local px, py
      local unit = QM.unitOf(full)
      if unit then
        local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, unit)
        if ok and pos and pos.GetXY then px, py = pos:GetXY(); px, py = QM.safe(px), QM.safe(py) end
      elseif m.demo and m.demoPos then
        px, py = QM.translate(m.demoPos.map, m.demoPos.x, m.demoPos.y, mapID)
      end
      if px and (px > 0 or py > 0) then mates[#mates + 1] = { kind = "mate", d = { full = full }, x = px, y = py } end
    end
  end

  -- decide what is shown: party members always, then by importance; nothing sits on top of anything
  local placed, shown = {}, {}
  local function clear(c)
    if c.fixed then return true end
    for _, p in ipairs(placed) do
      if not p.noBlock then
        local g = MIN_GAP
        if c.kind == "spot" or p.kind == "spot" then g = 9 end
        local dx, dy = (c.x - p.x) * PW, (c.y - p.y) * PH
        if dx * dx + dy * dy < g * g then return false end
      end
    end
    return true
  end
  for _, c in ipairs(mates) do placed[#placed + 1] = c end
  table.sort(cands, function(a, b) return a.prio > b.prio end)
  for _, c in ipairs(cands) do
    if clear(c) then placed[#placed + 1] = c; shown[#shown + 1] = c end
  end
  for _, c in ipairs(mates) do shown[#shown + 1] = c end

  -- name tags: on a side where nothing is (else none; hover still works)
  for _, c in ipairs(mates) do
    if zoneLevel then
      local m = QM.mates[c.d.full]
      local q = m and m.quests[m.focus]
      local _, _, _, hexName = QM.classColor(c.d.full)
      local text = hexName .. QM.short(c.d.full) .. "|r"
      if q then text = text .. C.grey .. "  " .. shortTitle(q.title) .. " " .. math.floor(QM.progress(q) * 100 + 0.5) .. "%|r" end
      local tw = (#QM.short(c.d.full) + (q and (#shortTitle(q.title) + 6) or 0)) * 5.6 + 14
      local sides = { { "RIGHT", 10 + tw / 2, 0 }, { "LEFT", -10 - tw / 2, 0 }, { "TOP", 0, -14 }, { "BOTTOM", 0, 14 } }
      for _, sd in ipairs(sides) do
        local cx, cy = c.x + sd[2] / PW, c.y + sd[3] / PH
        local free = true
        for _, p in ipairs(placed) do
          if p ~= c and not p.noBlock then
            local dx, dy = math.abs((cx - p.x) * PW), math.abs((cy - p.y) * PH)
            if dx < tw / 2 + 8 and dy < 14 then free = false break end
          end
        end
        if free then c.tag, c.tagSide, c.tagText = true, sd[1], text; break end
      end
    end
  end

  if QM.updateLegend then QM.updateLegend(shown) end

  -- only rebuild when something changed, so animations keep running smoothly
  local parts = { mapID, math.floor(PW) }
  for _, c in ipairs(shown) do
    if c.kind ~= "mate" then
      parts[#parts + 1] = string.format("%s%.3f%.3f%s%s%s", c.kind, c.x, c.y, tostring(c.d.label or c.d.qid or ""),
                                        c.d.next and "n" or "", c.d.locked and "l" or "")
    else
      parts[#parts + 1] = c.d.full .. tostring(c.tagSide) .. tostring(c.tagText)
    end
  end
  local sig = table.concat(parts, "|")
  local alive = livePins[1] and livePins[1]:IsShown()
  if not force and sig == lastSig and (alive or #shown == 0) then
    -- same picture: just move party members along
    for _, pin in ipairs(livePins) do
      if pin.kind == "mate" then
        for _, c in ipairs(mates) do if c.d.full == pin.d.full then pin:SetPosition(c.x, c.y) end end
      end
    end
    return
  end
  lastSig = sig
  pcall(map.RemoveAllPinsByTemplate, map, TEMPLATE)
  livePins = {}
  for _, c in ipairs(shown) do
    local pin = acquire(map, c)
    if pin then
      livePins[#livePins + 1] = pin
      if c.tag then
        local r, g, b = QM.classColor(c.d.full)
        pin:ShowTag(c.tagText, c.tagSide, r, g, b)
      end
    end
  end
end
---------------------------------------------------------------------------------------------------
-- Legend in the corner of the map: explains every kind of marker that is showing right now
---------------------------------------------------------------------------------------------------

local legend
local function legendRow(i)
  legend.rows = legend.rows or {}
  local r = legend.rows[i]
  if r then return r end
  r = CreateFrame("Frame", nil, legend)
  r:SetSize(10, 16)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(14, 14)
  r.icon:SetPoint("LEFT", 0, 0)
  r.text = W.text(r, "OVERLAY", "GameFontHighlightSmall")
  r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
  legend.rows[i] = r
  return r
end

function QM.updateLegend(shown)
  if not legend then return end
  if not (QM.DB and QM.DB.mapLegend) then legend:Hide(); return end
  local items, seen = {}, {}
  local function add(key, setIcon, text)
    if seen[key] then return end
    seen[key] = true
    items[#items + 1] = { setIcon, text }
  end
  for _, c in ipairs(shown) do
    local k, d = c.kind, c.d
    if k == "target" or k == "trail" then
      add("route", function(t) setArrow(t) end, C.gold .. "Your route|r - follow the arrow on your screen")
    elseif k == "area" then
      add("area" .. d.full, function(t) setClassIcon(t, d.full) end, QM.nameText(d.full) .. " is working here")
    elseif k == "dest" then
      add("dest" .. d.full, function(t) setClassIcon(t, d.full) end, QM.nameText(d.full) .. "'s map pin - where they're going")
    elseif k == "giver" then
      add("giver", function(t) W.icon(t, "pickup") end, "Start a quest your friend has")
    elseif k == "step" then
      add("step", function(t) W.icon(t, "pickup") end, "Catch-up steps, in order  " .. W.markup("lock", 12) .. C.grey .. " = do the earlier step first|r")
    end
  end
  if #items == 0 then legend:Hide(); return end
  local w = 0
  for i, it in ipairs(items) do
    local r = legendRow(i)
    r.icon:SetTexCoord(0, 1, 0, 1)
    if r.icon.SetRotation then r.icon:SetRotation(0) end
    it[1](r.icon)
    r.text:SetText(it[2])
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", legend, "TOPLEFT", 8, -20 - (i - 1) * 17)
    r:Show()
    w = math.max(w, r.text:GetStringWidth() + 28)
  end
  for i = #items + 1, #(legend.rows or {}) do legend.rows[i]:Hide() end
  legend:SetSize(math.max(w + 12, 140), 26 + #items * 17)
  legend:Show()
end

local function buildLegend()
  if legend or not WorldMapFrame then return end
  local host = WorldMapFrame.ScrollContainer or WorldMapFrame
  legend = CreateFrame("Frame", "QuestmatesMapLegend", host)
  legend:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 8, 8)
  legend:SetFrameLevel((host:GetFrameLevel() or 1) + 50)
  legend.bg = legend:CreateTexture(nil, "BACKGROUND")
  legend.bg:SetAllPoints()
  legend.bg:SetColorTexture(0, 0, 0, 0.7)
  legend.top = legend:CreateTexture(nil, "BORDER")
  legend.top:SetPoint("TOPLEFT"); legend.top:SetPoint("TOPRIGHT"); legend.top:SetHeight(1)
  legend.top:SetColorTexture(1, 0.78, 0.2, 0.9)
  legend.title = W.text(legend, "OVERLAY", "GameFontNormalSmall")
  legend.title:SetPoint("TOPLEFT", 8, -5)
  legend.title:SetText("Party markers")
  local close = CreateFrame("Button", nil, legend)
  close:SetSize(14, 14)
  close:SetPoint("TOPRIGHT", -4, -3)
  close.t = close:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  close.t:SetPoint("CENTER")
  close.t:SetText("x")
  close:SetScript("OnClick", function() QM.DB.mapLegend = false; legend:Hide(); QM.print("map legend hidden - turn it back on with /qm legend") end)
  close:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Hide the legend (/qm legend brings it back)"); GameTooltip:Show() end)
  close:SetScript("OnLeave", function() GameTooltip:Hide() end)
  legend:Hide()
end

local function setupMap()
  if Provider or not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin) then return end
  -- if the map code loaded after us, give our pin the base pin methods now (ours stay on top)
  if MapCanvasPinMixin then for k, v in pairs(MapCanvasPinMixin) do if Pin[k] == nil then Pin[k] = v end end end
  buildLegend()
  Provider = CreateFromMixins(MapCanvasDataProviderMixin)
  function Provider:RemoveAllData() local m = self:GetMap(); if m then pcall(m.RemoveAllPinsByTemplate, m, TEMPLATE) end end
  function Provider:RefreshAllData(force) local ok, err = pcall(refresh, self, force); if not ok and geterrorhandler then geterrorhandler()(err) end end
  function Provider:OnMapChanged() self:RefreshAllData(true) end
  local ok = pcall(WorldMapFrame.AddDataProvider, WorldMapFrame, Provider)
  if not ok then Provider = nil; return end
  -- zooming changes how close markers are on screen: lay them out again (at most a few times a second)
  local pendingZoom = false
  function Provider:OnCanvasScaleChanged()
    if pendingZoom then return end
    pendingZoom = true
    C_Timer.After(0.15, function() pendingZoom = false; Provider:RefreshAllData() end)
  end
  local ticker
  WorldMapFrame:HookScript("OnShow", function()
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(1.5, function() Provider:RefreshAllData() end)
  end)
  WorldMapFrame:HookScript("OnHide", function() if ticker then ticker:Cancel(); ticker = nil end end)
end

QM:On("UPDATE", function()
  if Provider and WorldMapFrame:IsShown() then Provider:RefreshAllData() end
end)

QM:On("GUIDE", function(target, opts)
  if not opts.noMap then
    if QuestmatesJournal and QuestmatesJournal:IsShown() then QuestmatesJournal:Hide() end
    if OpenWorldMap then pcall(OpenWorldMap, target.map)
    elseif WorldMapFrame and not WorldMapFrame:IsShown() and ToggleWorldMap then pcall(ToggleWorldMap) end
  end
  if Provider then Provider:RefreshAllData(true) end
end)

QM:On("SHOW_ON_MAP", function(id)
  local path = QM.pathTo(id)
  local full
  for _, n in ipairs(QM.mateList()) do if QM.mates[n] and QM.mates[n].quests[id] then full = n break end end
  QM.mapPath = { root = id, path = path, untilT = GetTime() + 300, full = full }
  -- open the map where the next step is (or where they're working on it)
  local target
  local s = QM.nextStep(id)
  if s.kind == "pickup" then target = s.giver end
  if not target and full and QM.mates[full].poi and QM.mates[full].poi.id == id then target = QM.mates[full].poi end
  if not target then target = QM.giverOf(id) end
  if OpenWorldMap and target and target.map then pcall(OpenWorldMap, target.map)
  elseif WorldMapFrame and not WorldMapFrame:IsShown() and ToggleWorldMap then pcall(ToggleWorldMap) end
  if QuestmatesJournal and QuestmatesJournal:IsShown() then QuestmatesJournal:Hide() end
  if Provider then Provider:RefreshAllData(true) end
  if not target then QM.print("no map positions known for that quest yet.") end
end)

---------------------------------------------------------------------------------------------------
-- Tooltips: "Questing: ..." on party members, and their kill/item counts on creatures you hover
---------------------------------------------------------------------------------------------------

local function fullOfUnit(unit)
  local name, realm = UnitFullName(unit)
  name, realm = QM.safe(name), QM.safe(realm)
  if not name then return nil end
  if not realm or realm == "" then realm = GetNormalizedRealmName() or "" end
  return name .. "-" .. realm
end

local function onUnitTooltip(tt)
  if not (QM.DB and QM.DB.tooltips) or tt ~= GameTooltip then return end
  local ok, _, unit = pcall(tt.GetUnit, tt)
  unit = ok and QM.safe(unit) or nil
  if not unit then return end
  if UnitIsPlayer(unit) then
    local full = fullOfUnit(unit)
    local m = full and QM.mates[full]
    if not (m and m.synced) then return end
    local q = m.quests[m.focus]
    if q then
      tt:AddLine("Questing: " .. q.title .. C.grey .. " (" .. math.floor(QM.progress(q) * 100 + 0.5) .. "%)|r", 1, 0.82, 0)
      local r = QM.REL[QM.relation(q.id)]
      tt:AddLine(r[4], r[1], r[2], r[3])
    end
    return
  end
  -- a creature: add each party member's count next to the quest lines the game already shows
  local added = 0
  local name = tt.GetName and tt:GetName()
  if not name then return end
  for i = 2, tt:NumLines() do
    local fs = _G[name .. "TextLeft" .. i]
    local text = fs and QM.safe(fs:GetText())
    if text and text:find("%d+/%d+") then
      for _, full in ipairs(QM.mateList()) do
        local m = QM.mates[full]
        if m and m.synced then
          for _, q in pairs(m.quests) do
            for _, o in ipairs(q.obj) do
              if o.t ~= "" and #o.t > 3 and text:find(o.t, 1, true) and added < 4 then
                tt:AddLine("   " .. QM.nameText(full) .. C.grey .. ": " .. o.have .. "/" .. o.need .. "|r")
                added = added + 1
              end
            end
          end
        end
      end
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Quest log: a "Show Party" button on the quest details page
---------------------------------------------------------------------------------------------------

local qlButton
local function questLogQuest()
  if QuestMapFrame_GetDetailQuestID then
    local ok, id = pcall(QuestMapFrame_GetDetailQuestID)
    if ok and id and id > 0 then return id end
  end
  local id = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
  return (id and id > 0) and id or nil
end

local function updateQLButton()
  if not qlButton then return end
  local id = questLogQuest()
  local show = QM.DB.questLogButton and id and QM.me.quests[id] and (#QM.mateList() > 0)
  qlButton:SetShown(show and true or false)
  qlButton.qid = id
end

local function setupQuestLog()
  if qlButton or not QuestMapFrame then return end
  local qf = QuestMapFrame.QuestsFrame
  local details = (qf and qf.DetailsFrame) or QuestMapFrame.DetailsFrame
  if not details then return end
  qlButton = W.button(details, "Show Party", 104)
  qlButton:SetHeight(22)
  local share = details.ShareButton
  if share then
    qlButton:SetPoint("BOTTOM", share, "TOP", 0, 4)
  else
    qlButton:SetPoint("TOPRIGHT", details, "TOPRIGHT", -8, -8)
  end
  qlButton:SetFrameLevel(details:GetFrameLevel() + 20)
  qlButton:SetScript("OnClick", function(self) if self.qid then QM.suggest(self.qid) end end)
  qlButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Show to your party")
    GameTooltip:AddLine("Pops this quest up on your party's screens, with its whole chain and where every step starts.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  qlButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
  details:HookScript("OnShow", updateQLButton)
  if QuestMapFrame_ShowQuestDetails then hooksecurefunc("QuestMapFrame_ShowQuestDetails", function() C_Timer.After(0, updateQLButton) end) end
  updateQLButton()
end

QM:On("UPDATE", function() if qlButton and qlButton:GetParent():IsVisible() then updateQLButton() end end)

QM:On("INIT", function()
  setupMap()
  setupQuestLog()
  if not Provider or not qlButton then
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function()
      setupMap()
      setupQuestLog()
    end)
  end
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tt) pcall(onUnitTooltip, tt) end)
  elseif GameTooltip:HasScript("OnTooltipSetUnit") then
    GameTooltip:HookScript("OnTooltipSetUnit", function(tt) pcall(onUnitTooltip, tt) end)
  end
end)
