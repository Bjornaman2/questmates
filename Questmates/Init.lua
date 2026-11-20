-- Questmates / Init.lua: options page (Esc > Options > AddOns > Questmates), slash commands,
-- the AddOns-menu button.

local _, QM = ...
local W = QM.W
local C = QM.C

local OPTIONS = {
  { "tracker", "Party tracker", "The Party section on screen: what everyone is doing right now." },
  { "toasts", "Party notes", "Banners when a party member picks up, finishes, turns in or shows you a quest." },
  { "mapPins", "World map markers", "Party name tags, where they're working, where to get their quests, catch-up steps." },
  { "mapLegend", "Map legend", "A small box in the corner of the map explaining the party markers." },
  { "shareWaypoint", "Share my map pin", "When you place a map pin (Ctrl-click the map), your party sees where you're heading." },
  { "questLogButton", "Show Party button in the quest log", "Pops the selected quest up on your party's screens." },
  { "autoShare", "Share dungeon quests automatically", "While getting ready for a dungeon, quests you pick up for it are shared with your party." },
  { "autoAccept", "Accept dungeon quests automatically", "While getting ready for a dungeon, its quests (and the ones leading to them) are accepted for you." },
  { "tooltips", "Tooltip lines", "What a party member is questing on, and their counts on creatures you hover." },
  { "sound", "Sounds", "Soft sounds with party notes." },
  { "chat", "Also write party notes in chat", "" },
}

local category
local function buildOptions()
  if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
  local p = CreateFrame("Frame")
  p:Hide()
  local title = W.text(p, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Questmates")
  local sub = W.text(p, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  sub:SetText("See what your party is questing on, and how to catch up.  Version " .. QM.VERSION)
  local y = -70
  for _, o in ipairs(OPTIONS) do
    local ok, cb = pcall(CreateFrame, "CheckButton", nil, p, "UICheckButtonTemplate")
    if not ok then cb = CreateFrame("CheckButton", nil, p, "ChatConfigCheckButtonTemplate") end
    cb:SetPoint("TOPLEFT", 16, y)
    local label = W.text(p, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    label:SetText(o[2])
    local desc = W.text(p, "OVERLAY", "GameFontDisableSmall")
    desc:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    desc:SetText(o[3])
    cb:SetScript("OnShow", function(self) self:SetChecked(QM.DB[o[1]] and true or false) end)
    cb:SetScript("OnClick", function(self)
      QM.DB[o[1]] = self:GetChecked() and true or false
      QM.playSound(QM.DB[o[1]] and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
      QM:Changed()
    end)
    y = y - 44
  end
  local function btn(text, x, row, fn)
    local b = W.button(p, text, 150)
    b:SetPoint("TOPLEFT", x, y - 30 - row * 30)
    b:SetScript("OnClick", fn)
  end
  local notesLabel = W.text(p, "OVERLAY", "GameFontNormal")
  notesLabel:SetPoint("TOPLEFT", 16, y - 10)
  notesLabel:SetText("Party notes position")
  btn("Move party notes", 16, 0, function() QM.unlockToasts() end)
  btn("Reset to top", 172, 0, function() QM.resetToasts() end)
  btn("Show a test note", 328, 0, function()
    if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then pcall(HideUIPanel, SettingsPanel) end
    QM.toastTest()
  end)
  btn("Try the demo", 16, 1.4, function() QM.toggleDemo() end)
  btn("Reset tracker position", 172, 1.4, function() QM.resetTracker() end)
  category = Settings.RegisterCanvasLayoutCategory(p, "Questmates")
  Settings.RegisterAddOnCategory(category)
end

QM:On("OPTIONS", function()
  if category and Settings.OpenToCategory then
    local ok = pcall(Settings.OpenToCategory, category:GetID())
    if ok then return end
  end
  QM.print("options: /qm help")
end)

QM:On("INIT", function() pcall(buildOptions) end)

function Questmates_OnAddonCompartmentClick(_, button)
  if button == "RightButton" then QM:Fire("OPTIONS") else QM.journal.toggle() end
end

local function onOff(v) return v and (C.green .. "on|r") or (C.red .. "off|r") end
local TOGGLES = { tracker = "tracker", notes = "toasts", toasts = "toasts", map = "mapPins", pins = "mapPins",
                  share = "shareWaypoint", legend = "mapLegend", tooltips = "tooltips", sound = "sound", chat = "chat", button = "questLogButton" }

-- /qm why <quest name or id>: everything Questmates knows and decides about one quest (also saved to the log).
local function why(arg)
  local id = tonumber(arg)
  if not id and arg ~= "" then
    local want = arg:lower()
    local best
    for qid, r in pairs(QM.DData.Q) do
      if r[1] and r[1]:lower() == want then
        if not best or (QM.questForMe(qid) and not QM.questForMe(best)) then best = qid end
      end
    end
    for qid, q in pairs(QM.me.quests) do if q.title:lower() == want then best = qid end end
    id = best
  end
  if not id then QM.print("which quest? /qm why <quest name or id>"); return end
  local out = {}
  local function add(fmt, ...) local line = string.format(fmt, ...); out[#out + 1] = line; QM.dbg("why: %s", line) end
  local _, _, raceID = UnitRace("player")
  add("Questmates %s - you: level %s, race %s, %s", QM.VERSION, tostring(UnitLevel("player")), tostring(raceID), tostring(UnitFactionGroup("player")))
  local r = QM.DQ(id)
  add("quest %d %s - level %s, needs level %s, for you: %s", id, tostring(QM.titleOf(id)), tostring(r and r[2]), tostring(r and r[3]), tostring(QM.questForMe(id)))
  local g = QM.giverOf(id)
  add("starts at: %s", g and (QM.placeText(g) or "?") .. (g.fromDB and " (database)" or " (seen in game)") or "unknown")
  local path = QM.pathTo(id)
  local parts = {}
  for _, p in ipairs(path) do parts[#parts + 1] = (QM.titleOf(p) or p) .. "=" .. QM.stepState(p) end
  add("path: %s", table.concat(parts, " -> "))
  local O = QM.Offers
  local st = O.status(id)
  local map = r and r[8] and r[8][3]
  local a = map and O.availInfo(map)
  add("game says: %s%s", tostring(st), a and string.format(" (map %d: %d listed checked %ds ago, expected %d, found %d, reliable %s)",
      map, (function() local n = 0 for _ in pairs(a.set) do n = n + 1 end return n end)(), math.floor(GetTime() - a.t), a.expected, a.found, tostring(a.reliable))
      or (O.canAsk() and " (no answer for its map yet)" or " (this game doesn't give that information)"))
  local b = QM.DB.chars and QM.DB.chars[QM.myFull()] and QM.DB.chars[QM.myFull()].blocked[id]
  add("marked not offered: %s", b and ((b.npc or "?") .. " at level " .. tostring(b.level) .. (b.byHand and " (by hand)" or "")) or "no")
  local ds, s = QM.Dungeons.state(id)
  add("plan: %s%s", tostring(ds), s and s.qid and s.qid ~= id and (" - next: " .. tostring(QM.titleOf(s.qid))) or "")
  QM.print("why %s:", C.gold .. tostring(QM.titleOf(id)) .. "|r")
  for _, line in ipairs(out) do print("  " .. line) end
end

SLASH_QUESTMATES1 = "/qm"
SLASH_QUESTMATES2 = "/questmates"
SlashCmdList.QUESTMATES = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "" then
    QM.journal.toggle()
  elseif msg:match("^why") then
    why((msg:gsub("^why%s*", "")))
  elseif msg == "dungeons" or msg == "dungeon" or msg == "d" then
    QM:Fire("OPEN_DUNGEON", QM.DB.task and QM.DB.task.area or nil)
  elseif msg == "demo" then
    QM.toggleDemo()
  elseif msg == "sync" then
    QM.send("H"); QM.fullSync(); QM.print("sent your quest log to the party.")
  elseif msg == "movenotes" or msg == "movetoasts" then
    QM.unlockToasts()
  elseif msg == "reset" then
    QM.resetTracker()
  elseif msg == "options" or msg == "config" then
    QM:Fire("OPTIONS")
  elseif TOGGLES[msg] then
    local k = TOGGLES[msg]
    QM.DB[k] = not QM.DB[k]
    QM.print("%s %s", msg, onOff(QM.DB[k]))
    QM:Changed()
  else
    QM.print("commands")
    print("  /qm  -  open the Party Quest Journal")
    print("  /qm demo  -  a pretend party member, to try everything alone")
    print("  /qm dungeons  -  every dungeon's quests; get the party ready for one")
    print("  /qm why <quest>  -  why Questmates says what it says about a quest")
    print("  /qm options  -  settings      /qm sync  -  resend your quest log")
    print("  /qm movenotes  -  move the party notes      /qm reset  -  reset the tracker position")
    print("  /qm tracker | notes | map | share | tooltips | sound | chat | button  -  switch a part on/off")
  end
end
