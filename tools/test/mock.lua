-- WoW API mock for one simulated client. Set before loading: PLAYER, REALM, ATLAS_OK
local clock = 100
function GetTime() return clock end
local timers = {}
C_Timer = {
  After = function(d, fn) timers[#timers + 1] = { t = clock + d, fn = fn } end,
  NewTicker = function(d, fn)
    local tk = { cancelled = false }
    function tk:Cancel() self.cancelled = true end
    local function run() if tk.cancelled then return end fn(tk); if not tk.cancelled then timers[#timers + 1] = { t = clock + d, fn = run } end end
    timers[#timers + 1] = { t = clock + d, fn = run }
    return tk
  end,
}
ERRORS = {}
function geterrorhandler() return function(e) ERRORS[#ERRORS + 1] = tostring(e) end end
function ADVANCE(dt)
  local target = clock + dt
  while true do
    local best, bi
    for i, t in ipairs(timers) do if t.t <= target and (not best or t.t < best.t) then best, bi = t, i end end
    if not best then break end
    table.remove(timers, bi)
    if best.t > clock then clock = best.t end
    local ok, err = pcall(best.fn)
    if not ok then ERRORS[#ERRORS + 1] = "timer: " .. tostring(err) end
  end
  clock = target
end

local N = 0
local mock
local function noop() end
NILKEYS = { TitleTextFallback = true, ShareButton = true, DetailsFrame = true, QuestsFrame = true, ScrollBar = true }
local M = {}
M.CreateTexture = function(self) local t = mock("Texture"); t.parent = self; return t end
M.CreateMaskTexture = function(self) return mock("MaskTexture") end
ALLFS = {}
M.CreateFontString = function(self) local t = mock("FontString"); t.parent = self; ALLFS[#ALLFS + 1] = t; return t end
M.CreateAnimationGroup = function(self) local g = mock("AnimationGroup"); g.anims = {}; return g end
M.CreateAnimation = function(self, kind) return mock("Animation") end
M.Play = function(self) self.playing = true; local f = rawget(self, "scripts").OnFinished; if f then self.playing = false; f(self) end end
M.Stop = function(self) self.playing = false end
M.IsPlaying = function(self) return rawget(self, "playing") == true end
M.GetFontString = function(self) local fs = rawget(self, "fs") if not fs then fs = mock("FontString"); self.fs = fs end return fs end
M.SetScript = function(self, n, f) self.scripts[n] = f end
M.HookScript = function(self, n, f) local old = self.scripts[n]; self.scripts[n] = function(...) if old then old(...) end f(...) end end
M.GetScript = function(self, n) return self.scripts[n] end
M.HasScript = function() return true end
M.Show = function(self) local was = self.shown; self.shown = true; if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end
M.Hide = function(self) local was = self.shown; self.shown = false; if was and self.scripts.OnHide then self.scripts.OnHide(self) end end
M.SetShown = function(self, v) if v then self:Show() else self:Hide() end end
M.IsShown = function(self) return self.shown end
M.IsVisible = function(self) return self.shown end
M.SetText = function(self, s) self.text = s end
M.GetText = function(self) return self.text end
M.SetWidth = function(self, v) self.w = v end
M.GetWidth = function(self) return self.w end
M.SetHeight = function(self, v) self.h = v end
M.GetHeight = function(self) return self.h end
M.SetSize = function(self, a, b) self.w, self.h = a, b end
M.GetRight = function() return 800 end
M.GetStringWidth = function(self) return #(self.text or "") * 6 end
M.GetStringHeight = function() return 12 end
M.GetVerticalScroll = function(self) return self.vs or 0 end
M.SetVerticalScroll = function(self, v) self.vs = v end
M.SetValue = function(self, v) self.value = v end
M.GetValue = function(self) return self.value or 0 end
M.GetFrameLevel = function() return 5 end
M.GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end
M.GetChecked = function(self) return self.checked end
M.SetChecked = function(self, v) self.checked = v end
M.GetName = function(self) return self.name end
M.NumLines = function(self) return #(self.lines or {}) end
M.RegisterEvent = function(self, e) self.events[e] = true end
M.GetParent = function(self) return self.parent or UIParent end
M.SetAtlas = function(self, a) self.atlasName = a end
M.SetTexture = function(self, t) self.file = t end

function mock(kind)
  N = N + 1
  local o = { kind = kind, shown = (kind ~= "Frame" and kind ~= "Button"), scripts = {}, events = {}, w = 100, h = 16, text = nil, id = N }
  return setmetatable(o, { __index = function(t, k)
    if M[k] then return M[k] end
    if type(k) == "string" and k:match("^[A-Z]") and not NILKEYS[k] then return noop end
    return nil
  end })
end
MOCK = mock

FRAMES = {}
function CreateFrame(kind, name, parent, tmpl)
  if tmpl == "MissingTemplate" then error("no template") end
  local f = mock(kind)
  f.shown = true
  f.parent = parent
  f.name = name
  f.template = tmpl
  if name then _G[name] = f end
  FRAMES[#FRAMES + 1] = f
  if tmpl and tmpl:find("ButtonFrameTemplate") then f.SetTitle = function(self, t) self.title = t end; f.Inset = mock("Frame") end
  if tmpl and tmpl:find("QuestmatesMapPinTemplate") then
    for k, v in pairs(QuestmatesMapPinMixin) do f[k] = v end
    f:OnLoad()
  end
  return f
end
UIParent = mock("Frame"); UIParent.shown = true
GameTooltip = mock("GameTooltip"); GameTooltip.name = "GameTooltip"
TT = {}
GameTooltip.lines = {}
function GameTooltip:AddLine(s) TT[#TT + 1] = tostring(s) end
function GameTooltip:SetText(s) TT[#TT + 1] = tostring(s) end
for _, n in ipairs({ "GameFontNormal", "GameFontHighlight", "GameFontHighlightSmall", "GameFontNormalSmall", "GameFontDisableSmall",
                     "GameFontNormalLarge", "GameFontDisable", "QuestTitleFont", "GameFontHighlightMedium" }) do _G[n] = {} end
RAID_CLASS_COLORS = { PALADIN = { r = 0.96, g = 0.55, b = 0.73, colorStr = "fff58cba" }, MAGE = { r = 0.25, g = 0.78, b = 0.92, colorStr = "ff3fc7eb" } }
CLASS_ICON_TCOORDS = { PALADIN = { 0, 0.25, 0.5, 0.75 }, MAGE = { 0.25, 0.5, 0, 0.25 } }
SOUNDKIT = { IG_PLAYER_INVITE = 1, MAP_PING = 2, IG_QUEST_LIST_OPEN = 3 }
SOUNDS = {}
function PlaySound(id) SOUNDS[#SOUNDS + 1] = id end
UNKNOWNOBJECT = "Unknown"
LE_PARTY_CATEGORY_INSTANCE = 2
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
UISpecialFrames = {}
function Mixin(o, ...) for i = 1, select("#", ...) do for k, v in pairs(select(i, ...)) do o[k] = v end end return o end
function CreateFromMixins(...) return Mixin({}, ...) end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function CreateVector2D(x, y) return { x = x, y = y, GetXY = function(s) return s.x, s.y end } end
BackdropTemplateMixin = {}
function SetPortraitTexture() end
StaticPopupDialogs = {}
POPUPS = {}
function StaticPopup_Show(which, a, b, data) POPUPS[#POPUPS + 1] = { which = which, a = a, b = b, data = data } end
PRINTS = {}
function print(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end PRINTS[#PRINTS + 1] = table.concat(t, " ") end
SlashCmdList = {}
function hooksecurefunc(a, b, c) end
C_Texture = { GetAtlasInfo = function(n) if ATLAS_OK then return { width = 16 } end return nil end }
Settings = { RegisterCanvasLayoutCategory = function(p, n) return { GetID = function() return 1 end } end, RegisterAddOnCategory = function() end, OpenToCategory = function() OPENED_SETTINGS = true end }

function UnitName(u) if u == "player" then return PLAYER end if u == "npc" or u == "questnpc" then return NPC end end
function GetNormalizedRealmName() return REALM end
function UnitRace() return "Human", "Human", 1 end
function UnitFactionGroup() return "Alliance" end
function IsInInstance() if INSTANCE then return true, INSTANCE.kind end return false, "none" end
function GetInstanceInfo() return INSTANCE and INSTANCE.name end
ACCEPTED_Q = {}
function AcceptQuest() ACCEPTED_Q[#ACCEPTED_Q + 1] = DETAIL_ID end
time = os.time
function UnitLevel() return MYLEVEL or 12 end
GROUP = {}
function IsInGroup() return #GROUP > 0 end
function IsInRaid() return false end
function GetNumSubgroupMembers() return #GROUP end
function GetNumGroupMembers() return #GROUP + 1 end
function UnitExists(u) if u == "player" then return true end local i = tonumber(u:match("%d+")) return i and GROUP[i] ~= nil end
function UnitIsUnit(a, b) return a == b end
function UnitIsPlayer(u) return u == "player" or u:find("party") ~= nil end
function UnitFullName(u) if u == "player" then return PLAYER, REALM end local g = GROUP[tonumber(u:match("%d+"))] return g.name, g.realm end
function UnitClass(u) if u == "player" then return MYCLASS, MYCLASS end local g = GROUP[tonumber(u:match("%d+"))] return g.class, g.class end
ZONE, SUBZONE = "Elwynn Forest", "Goldshire"
function GetRealZoneText() return ZONE end
function GetSubZoneText() return SUBZONE end
function GetQuestID() return DETAIL_ID end

OUTBOX = {}
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() return true end,
  SendAddonMessage = function(prefix, msg, ch)
    assert(#msg <= 255, "message too long: " .. #msg)
    OUTBOX[#OUTBOX + 1] = { prefix = prefix, msg = msg, ch = ch }
    return 0
  end,
}
LOG = {}
COMPLETED = {}
C_QuestLog = {
  GetNumQuestLogEntries = function() return #LOG end,
  GetInfo = function(i) local q = LOG[i] if q and q.isHeader then return { isHeader = true, title = q.title } end return q and { questID = q.id, title = q.title, level = q.level, isHeader = false } end,
  GetQuestTagInfo = function(id) local t = TAGS and TAGS[id] return t and { tagID = t, tagName = (t == 81 and "Dungeon" or "Raid") } end,
  GetQuestObjectives = function(id)
    for _, q in ipairs(LOG) do if q.id == id then
      local out = {}
      for k, o in ipairs(q.obj) do out[k] = { text = o.text .. ": " .. o.have .. "/" .. o.need, numFulfilled = o.have, numRequired = o.need, finished = o.have >= o.need } end
      return out
    end end
  end,
  IsFailed = function() return false end,
  IsComplete = function(id)
    for _, q in ipairs(LOG) do if q.id == id then
      for _, o in ipairs(q.obj) do if o.have < o.need then return false end end
      return #q.obj > 0
    end end
    return false
  end,
  IsPushableQuest = function(id) for _, q in ipairs(LOG) do if q.id == id then return q.share end end return false end,
  IsQuestFlaggedCompleted = function(id) return COMPLETED[id] == true end,
  SetSelectedQuest = function(id) SELECTED = id end,
  GetSelectedQuest = function() return SELECTED end,
  GetTitleForQuestID = function() return nil end,
  GetQuestsOnMap = function(map) return { { questID = FOCUSPOI or 0, x = 0.3, y = 0.4 } } end,
}
function QuestLogPushQuest() PUSHED = SELECTED end
POS = { 0.42, 0.65 }
USERWP = nil
C_Map = {
  GetBestMapForUnit = function() return 1429 end,
  GetPlayerMapPosition = function(map, unit) return CreateVector2D(POS[1], POS[2]) end,
  CanSetUserWaypointOnMap = function() return true end,
  SetUserWaypoint = function(p) USERWP = p end,
  GetUserWaypoint = function() return USERWP end,
  GetMapInfo = function(m) return { name = "Elwynn Forest", parentMapID = 1415, mapType = 3 } end,
  GetWorldPosFromMapPos = function(m, v) return 0, CreateVector2D(v.x * 3000, v.y * 2000) end,
  GetMapPosFromWorldPos = function(c, w, m) return m, CreateVector2D(w.x / 3000, w.y / 2000) end,
}
UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, position = CreateVector2D(x, y) } end }
C_SuperTrack = { GetSuperTrackedQuestID = function() return 0 end, SetSuperTrackedUserWaypoint = function() end }

-- map canvas
MapCanvasPinMixin = { SetPosition = function(self, x, y) self.px, self.py = x, y end, UseFrameLevelType = function() end, SetScalingLimits = function() end }
MapCanvasDataProviderMixin = { GetMap = function(self) return self.owningMap end }
PINS = {}
WorldMapFrame = CreateFrame("Frame", "WorldMapFrame")
WorldMapFrame.shown = false
WorldMapFrame.ScrollContainer = CreateFrame("Frame", nil, WorldMapFrame)
function WorldMapFrame:AddDataProvider(p) p.owningMap = self; self.provider = p end
function WorldMapFrame:GetMapID() return 1429 end
function WorldMapFrame:GetCanvas() local c = MOCK("Frame"); c.w, c.h = 1000, 667; return c end
function WorldMapFrame:GetCanvasScale() return CANVAS_SCALE or 1 end
function WorldMapFrame:RemoveAllPinsByTemplate() for _, p in ipairs(PINS) do p:Hide() end PINS = {} end
function WorldMapFrame:AcquirePin(t, ...) local p = CreateFrame("Frame", nil, self, t); p:OnAcquired(...); PINS[#PINS + 1] = p; return p end
function OpenWorldMap(m) WorldMapFrame:Show(); OPENED_MAP = m end
QuestMapFrame = CreateFrame("Frame", "QuestMapFrame")
QuestMapFrame.QuestsFrame = CreateFrame("Frame")
QuestMapFrame.QuestsFrame.DetailsFrame = CreateFrame("Frame")
QuestMapFrame.QuestsFrame.DetailsFrame.ShareButton = CreateFrame("Button")
function QuestMapFrame_GetDetailQuestID() return SELECTED end
C_GossipInfo = { GetAvailableQuests = function() local t = {} for _, id in ipairs(GOSSIP_OFFER or {}) do t[#t + 1] = { questID = id } end return t end }
TooltipDataProcessor = { AddTooltipPostCall = function(t, fn) TOOLTIP_CB = fn end }
Enum = { TooltipDataType = { Unit = 2 } }

function FIRE(event, ...)
  for _, f in ipairs(FRAMES) do
    if f.events[event] and f.scripts.OnEvent then
      local ok, err = pcall(f.scripts.OnEvent, f, event, ...)
      if not ok then ERRORS[#ERRORS + 1] = event .. ": " .. tostring(err) end
    end
  end
end

local function strip(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
STRIP = strip
-- every visible font string under a frame (all ancestors shown)
function TEXTS(root)
  local out = {}
  for _, fs in ipairs(ALLFS) do
    local ok, p, inside = fs.shown, fs, false
    while p do
      if not p.shown then ok = false end
      if p == root then inside = true; break end
      p = rawget(p, "parent")
    end
    if ok and inside and fs.text and fs.text ~= "" then out[#out + 1] = strip(fs.text) end
  end
  return table.concat(out, "\n")
end