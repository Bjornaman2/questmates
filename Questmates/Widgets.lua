-- Questmates / Widgets.lua
-- Small building blocks drawn with the game's own art: every atlas is checked before use and falls
-- back to a classic texture file, so a missing art name never shows up as a green box.

local _, QM = ...
local W = {}
QM.W = W

-- Use the first atlas the client has, else the file (with optional tex coords).
function W.atlas(tex, names, file, coords)
  if type(names) == "string" then names = { names } end
  if names and C_Texture and C_Texture.GetAtlasInfo then
    for _, n in ipairs(names) do
      if C_Texture.GetAtlasInfo(n) then
        tex:SetAtlas(n)
        return n
      end
    end
  end
  if file then
    tex:SetTexture(file)
    if coords then tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) else tex:SetTexCoord(0, 1, 0, 1) end
  end
  return nil
end

function W.hasAtlas(name) return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) and true or false end

-- The first font object that exists.
function W.font(fs, ...)
  for i = 1, select("#", ...) do
    local n = select(i, ...)
    if _G[n] then fs:SetFontObject(_G[n]); return n end
  end
end

function W.text(parent, layer, ...)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  W.font(fs, ...)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  return fs
end

-- Quest-type icons (the yellow ! and ?), a check mark, and a few others.
W.ICON = {
  pickup  = { { "QuestNormal", "Quest-Available" }, "Interface\\GossipFrame\\AvailableQuestIcon" },
  turnin  = { { "QuestTurnin", "Quest-Complete" }, "Interface\\GossipFrame\\ActiveQuestIcon" },
  done    = { { "common-icon-checkmark", "UI-LFG-ReadyMark" }, "Interface\\RAIDFRAME\\ReadyCheck-Ready" },
  todo    = { { "common-icon-undo" }, "Interface\\RAIDFRAME\\ReadyCheck-Waiting" },
  cross   = { { "common-icon-redx", "UI-LFG-DeclineMark" }, "Interface\\RAIDFRAME\\ReadyCheck-NotReady" },
  lock    = { { "Padlock", "AdventureMapIcon-Lock", "Garr_LockedBuilding" }, "Interface\\LFGFrame\\UI-LFG-ICON-LOCK" },
  map     = { { "poi-door-arrow-up" }, "Interface\\Minimap\\Tracking\\None" },
  link    = { { "Ping_Marker_Icon_OnMyWay", "groupfinder-icon-friend" }, "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon" },
  ping    = { { "Ping_Marker_Icon_Attention", "Ping_Marker_Icon_Warning" }, "Interface\\GossipFrame\\AvailableQuestIcon" },
  hello   = { { "groupfinder-icon-friend", "socialqueuing-icon-group" }, "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon" },
}
function W.icon(tex, kind)
  local d = W.ICON[kind] or W.ICON.pickup
  W.atlas(tex, d[1], d[2])
end

-- The same icons inside text.
function W.markup(kind, size)
  local d = W.ICON[kind] or W.ICON.pickup
  size = size or 14
  if CreateAtlasMarkup then
    for _, n in ipairs(d[1]) do
      if W.hasAtlas(n) then return CreateAtlasMarkup(n, size, size) end
    end
  end
  return "|T" .. d[2] .. ":" .. size .. ":" .. size .. "|t"
end

---------------------------------------------------------------------------------------------------
-- Round portrait with the classic gold ring (the minimap-button ring every player knows)
---------------------------------------------------------------------------------------------------

function W.portrait(parent, size)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)
  f.class = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  f.class:SetAllPoints()
  f.face = f:CreateTexture(nil, "ARTWORK")
  f.face:SetAllPoints()
  if f.CreateMaskTexture then
    local mask = f:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(f.face)
    f.face:AddMaskTexture(mask)
    f.mask = mask
  end
  f.ring = f:CreateTexture(nil, "OVERLAY")
  f.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  local k = size / 17
  f.ring:SetSize(53 * k, 53 * k)
  f.ring:SetPoint("TOPLEFT", f, "TOPLEFT", -7 * k, 5.5 * k)
  -- soft glow behind, pulses when this player has news
  f.glow = f:CreateTexture(nil, "BACKGROUND", nil, -1)
  f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  f.glow:SetTexCoord(0.2, 0.8, 0.2, 0.8)
  f.glow:SetBlendMode("ADD")
  f.glow:SetVertexColor(1, 0.82, 0.3)
  f.glow:SetPoint("CENTER")
  f.glow:SetSize(size * 1.9, size * 1.9)
  f.glow:SetAlpha(0)
  local ag = f.glow:CreateAnimationGroup()
  local a1 = ag:CreateAnimation("Alpha"); a1:SetFromAlpha(0); a1:SetToAlpha(0.9); a1:SetDuration(0.25); a1:SetOrder(1)
  local a2 = ag:CreateAnimation("Alpha"); a2:SetFromAlpha(0.9); a2:SetToAlpha(0); a2:SetDuration(0.9); a2:SetOrder(2)
  a2:SetSmoothing("OUT")
  f.glowAnim = ag
  function f:Pulse() if self.glowAnim then self.glowAnim:Stop(); self.glowAnim:Play() end end
  function f:SetPlayer(full)
    local class = QM.classOf(full)
    local file = "Interface\\TargetingFrame\\UI-Classes-Circles"
    local tc = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if class and W.hasAtlas("classicon-" .. class:lower()) then
      self.class:SetAtlas("classicon-" .. class:lower())
    elseif tc then
      self.class:SetTexture(file)
      self.class:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    else
      self.class:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    local unit = (full == "me") and "player" or QM.unitOf(full)
    self.face:SetTexture(nil)
    if unit and UnitExists(unit) and SetPortraitTexture then
      pcall(SetPortraitTexture, self.face, unit)
      self.face:SetTexCoord(0, 1, 0, 1)
    end
    self.full = full
  end
  return f
end

---------------------------------------------------------------------------------------------------
-- Progress bar that glides to its value and flashes when it moves
---------------------------------------------------------------------------------------------------

function W.bar(parent, w, h)
  local b = CreateFrame("StatusBar", nil, parent)
  b:SetSize(w, h)
  b:SetMinMaxValues(0, 1)
  b:SetValue(0)
  b:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetColorTexture(0, 0, 0, 0.55)
  -- thin border made of four lines so it stays crisp at any scale
  local function edge(p1, p2, horiz)
    local t = b:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(0.45, 0.38, 0.22, 0.9)
    t:SetPoint(p1, b, p1, 0, 0)
    t:SetPoint(p2, b, p2, 0, 0)
    if horiz then t:SetHeight(1) else t:SetWidth(1) end
  end
  edge("TOPLEFT", "TOPRIGHT", true); edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
  edge("TOPLEFT", "BOTTOMLEFT", false); edge("TOPRIGHT", "BOTTOMRIGHT", false)
  b.spark = b:CreateTexture(nil, "OVERLAY", nil, 2)
  b.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
  b.spark:SetBlendMode("ADD")
  b.spark:SetSize(10, h * 2.6)
  b.spark:SetAlpha(0)
  b.flash = b:CreateTexture(nil, "OVERLAY", nil, 1)
  b.flash:SetAllPoints()
  b.flash:SetColorTexture(1, 0.9, 0.5, 1)
  b.flash:SetBlendMode("ADD")
  b.flash:SetAlpha(0)
  local fg = b.flash:CreateAnimationGroup()
  local f1 = fg:CreateAnimation("Alpha"); f1:SetFromAlpha(0.55); f1:SetToAlpha(0); f1:SetDuration(0.7); f1:SetSmoothing("OUT")
  b.flashAnim = fg
  b.target = 0
  b:SetScript("OnUpdate", function(self, elapsed)
    local v = self:GetValue()
    local d = self.target - v
    if math.abs(d) < 0.002 then
      if v ~= self.target then self:SetValue(self.target) end
      self.spark:SetAlpha(0)
      self:SetScript("OnUpdate", nil)
      self.idle = true
      return
    end
    v = v + d * math.min(elapsed * 6, 1)
    self:SetValue(v)
    self.spark:ClearAllPoints()
    self.spark:SetPoint("CENTER", self, "LEFT", self:GetWidth() * v, 0)
    self.spark:SetAlpha(0.9)
  end)
  local onUpdate = b:GetScript("OnUpdate")
  function b:SetTarget(v, color, instant)
    v = math.min(math.max(v or 0, 0), 1)
    if color then self:SetStatusBarColor(color[1], color[2], color[3]) end
    if instant then self:SetValue(v); self.target = v; return end
    if v > self.target + 0.001 and self.seenOnce then self.flashAnim:Stop(); self.flashAnim:Play() end
    self.target = v
    self.seenOnce = true
    if self.idle then self.idle = false; self:SetScript("OnUpdate", onUpdate) end
  end
  return b
end

---------------------------------------------------------------------------------------------------
-- Animations
---------------------------------------------------------------------------------------------------

-- Fade + slide in from the side; returns the group (call :Play()).
function W.slideIn(frame, dx, dy, dur)
  local ag = frame:CreateAnimationGroup()
  local t = ag:CreateAnimation("Translation")
  t:SetOffset(-(dx or 0), -(dy or 0))
  t:SetDuration(0)
  t:SetOrder(1)
  local t2 = ag:CreateAnimation("Translation")
  t2:SetOffset(dx or 0, dy or 0)
  t2:SetDuration(dur or 0.35)
  t2:SetSmoothing("OUT")
  t2:SetOrder(2)
  local a = ag:CreateAnimation("Alpha")
  a:SetFromAlpha(0)
  a:SetToAlpha(1)
  a:SetDuration(dur or 0.35)
  a:SetSmoothing("OUT")
  a:SetOrder(2)
  return ag
end

function W.fade(frame, from, to, dur, onDone)
  local ag = frame:CreateAnimationGroup()
  local a = ag:CreateAnimation("Alpha")
  a:SetFromAlpha(from)
  a:SetToAlpha(to)
  a:SetDuration(dur)
  a:SetSmoothing(to > from and "OUT" or "IN")
  if onDone then ag:SetScript("OnFinished", onDone) end
  return ag
end

-- A light sweep across a frame (like the shine on a new achievement).
function W.shine(frame)
  local clip = CreateFrame("Frame", nil, frame)
  clip:SetAllPoints()
  if clip.SetClipsChildren then clip:SetClipsChildren(true) end
  local tex = clip:CreateTexture(nil, "OVERLAY", nil, 6)
  tex:SetTexture("Interface\\Buttons\\WHITE8X8")
  tex:SetBlendMode("ADD")
  tex:SetSize(60, 200)
  tex:SetPoint("CENTER", clip, "LEFT", -40, 0)
  tex:SetRotation(math.rad(-20))
  if tex.SetGradient and CreateColor then
    tex:SetGradient("HORIZONTAL", CreateColor(1, 0.9, 0.6, 0), CreateColor(1, 0.9, 0.6, 0.22))
  else
    tex:SetVertexColor(1, 0.9, 0.6, 0.12)
  end
  tex:SetAlpha(0)
  local ag = tex:CreateAnimationGroup()
  local a0 = ag:CreateAnimation("Alpha"); a0:SetFromAlpha(0); a0:SetToAlpha(1); a0:SetDuration(0.1); a0:SetOrder(1)
  local mv = ag:CreateAnimation("Translation"); mv:SetOffset(420, 0); mv:SetDuration(0.75); mv:SetSmoothing("IN_OUT"); mv:SetOrder(2)
  local a1 = ag:CreateAnimation("Alpha"); a1:SetFromAlpha(1); a1:SetToAlpha(0); a1:SetDuration(0.2); a1:SetStartDelay(0.55); a1:SetOrder(2)
  ag:SetScript("OnFinished", function() tex:SetAlpha(0) end)
  return ag
end

---------------------------------------------------------------------------------------------------
-- Panels and buttons
---------------------------------------------------------------------------------------------------

-- A dark, softly bordered panel (used where a full Blizzard frame would be too heavy).
function W.panel(f, alpha)
  if not f.SetBackdrop then Mixin(f, BackdropTemplateMixin) end
  f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                  tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  f:SetBackdropColor(0.06, 0.05, 0.04, alpha or 0.92)
  f:SetBackdropBorderColor(0.62, 0.52, 0.30, 1)
end

function W.button(parent, text, w)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 110, 22)
  b:SetText(text)
  b:SetMotionScriptsWhileDisabled(true)
  return b
end

-- A flat text button that lights up gold on hover (like quest log links).
function W.linkButton(parent, h)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(h or 18)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  W.atlas(b.hl, { "Options_List_Hover", "search-highlight" }, "Interface\\QuestFrame\\UI-QuestTitleHighlight")
  b.hl:SetBlendMode("ADD")
  b.hl:SetAlpha(0.5)
  return b
end

function W.divider(parent, w)
  local t = parent:CreateTexture(nil, "ARTWORK")
  if not W.atlas(t, { "Options_HorizontalDivider", "UI-Frame-Divider" }) then
    t:SetColorTexture(0.62, 0.52, 0.30, 0.45)
    t:SetHeight(1)
  else
    t:SetHeight(4)
  end
  t:SetWidth(w)
  return t
end
