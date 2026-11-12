-- Persona: panel docked to the right of the character frame.
-- Parented to UIParent and only anchored to CharacterFrame, rather than
-- injected as a real tab, to stay clear of Blizzard's panel layout and taint.
-- Dragging the panel undocks it: it then opens where it was left until
-- "/persona dock" puts it back beside the character frame.

local _, ns = ...
local T = ns.traits

local WIDTH, PAD = 320, 14
local panel, body, toggle, title, subtitle, tabBar
local openedFrom   -- "character" when opened from the character screen; this session only
local TABS = { "Profile", "Habits", "Emotes", "Lifetime", "Places", "Roster" }
local tabButtons = {}
-- Colour of the selected tab: Blizzard gold unless a UI skin supplies its accent (Skin.lua)
ns.accent = { 1, 0.82, 0 }
local playedRequested = false

local function build()
  panel = CreateFrame("Frame", "PersonaPanel", UIParent, "BackdropTemplate")
  panel:SetWidth(WIDTH)
  panel:SetFrameStrata("HIGH")
  panel:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  -- Near-opaque so other addons' text can't bleed through
  panel:SetBackdropColor(0.04, 0.04, 0.07, 0.95)
  panel:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
  panel:Hide()

  -- Drag to move. The position is saved by us (in PersonaDB), not by the
  -- client's layout cache, so the docked default isn't overridden behind our back.
  panel:SetMovable(true)
  panel:SetClampedToScreen(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  if panel.SetDontSavePosition then panel:SetDontSavePosition(true) end
  panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
  panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint(1)
    if ns.db and point then
      ns.db.panelPos = { point = point, relPoint = relPoint, x = x, y = y }
    end
  end)

  title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", PAD, -PAD)
  title:SetWidth(WIDTH - PAD * 2 - 24 - 60)   -- room for the Share button
  title:SetJustifyH("LEFT")
  title:SetText("Persona")

  subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  subtitle:SetWidth(WIDTH - PAD * 2)
  subtitle:SetJustifyH("LEFT")

  local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() ns.SetPanel(false) end)

  local share = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  share:SetSize(56, 20)
  share:SetPoint("TOPRIGHT", -30, -7)
  share:SetText("Share")
  share:SetScript("OnClick", function() if ns.share then ns.share.Show() end end)

  -- Tabs: plain buttons rather than Blizzard's tab templates, whose names have
  -- changed between expansions and may differ on Forever.
  tabBar = CreateFrame("Frame", nil, panel)
  tabBar:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -8)
  tabBar:SetSize(WIDTH - PAD * 2, 20)
  local line = tabBar:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(0.6, 0.6, 0.6, 0.4)
  line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
  local tabWidth = (WIDTH - PAD * 2) / #TABS
  for i, name in ipairs(TABS) do
    local b = CreateFrame("Button", nil, tabBar)
    b:SetSize(tabWidth, 20)
    b:SetPoint("BOTTOMLEFT", (i - 1) * tabWidth, 0)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.label:SetPoint("CENTER", 0, 1)
    b.label:SetText(name)
    b.underline = b:CreateTexture(nil, "OVERLAY")
    b.underline:SetColorTexture(1, 0.82, 0, 1)
    b.underline:SetPoint("BOTTOMLEFT", 4, 0); b.underline:SetPoint("BOTTOMRIGHT", -4, 0); b.underline:SetHeight(2)
    b:SetScript("OnClick", function() ns.SetTab(name) end)
    tabButtons[name] = b
  end

  body = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  body:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -10)
  body:SetWidth(WIDTH - PAD * 2)
  body:SetJustifyH("LEFT")
  body:SetSpacing(2)

  if CharacterFrame then
    toggle = CreateFrame("Button", nil, CharacterFrame, "UIPanelButtonTemplate")
    toggle:SetSize(80, 22)
    toggle:SetPoint("TOPRIGHT", CharacterFrame, "BOTTOMRIGHT", 0, -2)
    toggle:SetText("Persona")
    toggle:SetScript("OnClick", function() ns.SetPanel(not panel:IsShown(), false, "character") end)

    CharacterFrame:HookScript("OnShow", function()
      if ns.db and ns.db.panelOpen then ns.SetPanel(true, true, "character") end
    end)
    -- Closes with the character screen if it was opened from there (moved or not),
    -- or if it's docked beside it. Opened any other way and moved, it stays.
    CharacterFrame:HookScript("OnHide", function()
      if openedFrom == "character" or not (ns.db and ns.db.panelPos) then panel:Hide() end
    end)
  end

  -- The parts a UI skin (Skin.lua) restyles
  ns.ui = { panel = panel, close = close, share = share, toggle = toggle,
            title = title, subtitle = subtitle, body = body, tabs = tabButtons }
  if ns.skin then ns.skin.Panel() end
end

local function anchor()
  panel:ClearAllPoints()
  local pos = ns.db and ns.db.panelPos
  if pos then
    panel:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
  elseif CharacterFrame and CharacterFrame:IsShown() then
    panel:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 4, 0)
  else
    panel:SetPoint("CENTER")
  end
end

local grey, blue = "|cff9d9d9d", "|cff66ccff"
-- Section headings use the same accent as the selected tab: Blizzard gold by
-- default, the theme's colour under EllesmereUI
local function heading()
  local a = ns.accent
  local function h(x) return math.floor(math.max(0, math.min(1, x)) * 255 + 0.5) end
  return ("|cff%02x%02x%02x"):format(h(a[1]), h(a[2]), h(a[3]))
end
local function pctOf(part, whole) return whole > 0 and math.floor(part / whole * 100 + 0.5) or 0 end
local function num(n) return BreakUpLargeNumbers(math.floor(n or 0)) end

local Tab = {}

function Tab.Profile(db, add)
  -- Coverage: be upfront that this only knows what it has seen.
  if db.played then
    local share = db.played > 0 and math.min(1, db.tracked / db.played) or 0
    -- Veteran characters will sit under 1% for a long time; say so plainly
    local shown = share < 0.01 and "since install" or ("%d%% of your playtime"):format(math.floor(share * 100 + 0.5))
    add(("%sWatching for %s (%s)|r"):format(grey, T.FmtTime(db.tracked), shown))
  else
    add(("%sObserved %s since install|r"):format(grey, T.FmtTime(db.tracked)))
  end
  add(" ")
  local traits = T.Build(db)
  for _, t in ipairs(traits) do
    add(("%s%s.|r %s"):format(blue, t.label, t.text))
    add(" ")
  end
  if #traits == 0 or db.tracked < T.MIN_TRACKED then add(T.EmptyText(db)) end
end

function Tab.Habits(db, add)
  add(heading() .. "On the move|r")
  local travelMin = db.travel / 60
  -- One value per line: the panel fits about 38 characters before wrapping.
  add(("Jumps: %s (%s while travelling)"):format(num(db.totalJumps), num(db.travelJumps)))
  if travelMin >= 1 then add(("Jump rate on the move: %.1f a minute"):format(db.travelJumps / travelMin)) end
  add(("Ground travel: %s (%s on foot)"):format(T.FmtTime(db.travel), T.FmtTime(db.onFoot)))
  add(("Falls: %d, longest %.1fs"):format(db.falls, db.longestFall))
  if db.fallYards >= 1 then add(("Distance fallen: about %s yd"):format(num(db.fallYards))) end
  local town = T.TopN(db.idleZones, 1)[1]
  add(("Idle in towns: %s"):format(T.FmtTime(db.idleResting)))
  if town then add(("Mostly in %s"):format(town.k)) end
  if (db.bagSamples or 0) > 0 then
    add(("Bags: %d%% full on average"):format(pctOf(db.bagFull, db.bagSamples)))
  end
  if (db.afkCount or 0) > 0 then
    add(("AFK: %s, %s in total"):format(db.afkCount == 1 and "once" or db.afkCount == 2 and "twice"
      or (num(db.afkCount) .. " times"), T.FmtTime(db.afkTime)))
  end

  -- Signature moves, only the ones actually used
  local used = {}
  for key, move in pairs(ns.moves and ns.moves.LIST or {}) do
    local n = (db.moves or {})[key] or 0
    if n > 0 then used[#used + 1] = { label = move.label, n = n } end
  end
  table.sort(used, function(a, b) return a.n > b.n end)
  local formTravel, stealth = db.formTravel or 0, db.stealthTime or 0
  if #used > 0 or formTravel > 0 or stealth > 0 then
    add(" ")
    add(heading() .. "Signature moves|r")
    for _, u in ipairs(used) do add(("%s: %s"):format(u.label, num(u.n))) end
    if formTravel > 0 then add(("In animal form: %s"):format(T.FmtTime(formTravel))) end
    if stealth > 0 then add(("Stealthed outside combat: %s"):format(T.FmtTime(stealth))) end
  end

  local combatTime = db.combatPetTime or 0
  if combatTime > 0 then
    add(" ")
    add(heading() .. "Combat pets|r")
    add(("Pet out: %d%% of the time"):format(pctOf(combatTime, T.Observed(db, "combatPetTime"))))
    for _, p in ipairs(T.TopN(db.combatPets or {}, 3)) do
      local family = (db.combatPetFamily or {})[p.k]
      add(("%s%s - %s"):format(p.k, family and (" (" .. family .. ")") or "", T.FmtTime(p.v)))
    end
  end

  -- Kills come from the KillDex addon, so the section only shows when it's installed
  local kills = T.Kills()
  if kills and kills.total > 0 then
    add(" ")
    add(heading() .. "Kills (from KillDex)|r")
    add(("Kills: %s"):format(BreakUpLargeNumbers(kills.total)))
    add(("Kinds of creature: %s"):format(BreakUpLargeNumbers(kills.kinds)))
    if kills.rares > 0 then add(("Rares: %d"):format(kills.rares)) end
    for i = 1, math.min(3, #kills.top) do
      add(("%s - %s"):format(kills.top[i].k, BreakUpLargeNumbers(kills.top[i].v)))
    end
  end

  local petTime = db.petTime or 0
  if petTime > 0 then
    add(" ")
    -- "Vanity pets", not "companions": on a hunter or warlock "companion" reads as the combat pet
    add(heading() .. "Vanity pets|r")
    add(("Vanity pet out: %d%% of the time"):format(pctOf(petTime, T.Observed(db, "petTime"))))
    for _, p in ipairs(T.TopN(db.pets or {}, 3)) do
      add(("%s - %s"):format((db.petNames or {})[p.k] or "Vanity pet", T.FmtTime(p.v)))
    end
  end

  add(" ")
  add(heading() .. "When you play|r")
  local function hours(from, to)
    local t = 0
    for h = from, to do t = t + (db.hours[h] or 0) end
    return t
  end
  if db.tracked > 0 then
    add(("Night (00-05): %d%%"):format(pctOf(hours(0, 4), db.tracked)))
    add(("Morning (05-12): %d%%"):format(pctOf(hours(5, 11), db.tracked)))
    add(("Afternoon (12-17): %d%%"):format(pctOf(hours(12, 16), db.tracked)))
    add(("Evening (17-24): %d%%"):format(pctOf(hours(17, 23), db.tracked)))
    add(("Weekends: %d%%"):format(pctOf((db.days[0] or 0) + (db.days[6] or 0), db.tracked)))
    local peak = T.TopN(db.hours, 1)[1]
    if peak then add(("Most active: %s"):format(T.HourRange(peak.k))) end
  else
    add(grey .. "Nothing recorded yet.|r")
  end

  add(" ")
  add(heading() .. "Favourite mounts|r")
  local mounts = T.TopN(db.mounts, 5)
  if #mounts == 0 then
    add(grey .. "No riding recorded yet.|r")
  else
    for _, m in ipairs(mounts) do
      add(("%s - %s (%d%%)"):format(T.MountName(m.k), T.FmtTime(m.v), pctOf(m.v, db.mounted)))
    end
  end
end

function Tab.Emotes(db, add)
  local total = db.emoteTotal or 0
  if total == 0 then
    add("No emotes yet.")
    add(" ")
    add(grey .. "Persona counts every emote you use from now on: /dance, /wave, /bow and the rest.|r")
  else
    add(("%s emotes, %s different"):format(num(total), num(#T.TopN(db.emotes, 1000))))
    add(" ")
    for _, e in ipairs(T.TopN(db.emotes, 10)) do
      add(("/%s - %s (%d%%)"):format(e.k:lower(), num(e.v), pctOf(e.v, total)))
    end
    if (db.soloDances or 0) > 0 then
      add(" ")
      local n = db.soloDances
      add("Danced alone: " .. (n == 1 and "once" or n == 2 and "twice" or (num(n) .. " times")))
    end
  end
  add(" ")
  add(grey .. "Counted since install. Lifetime waves, cheers, hugs and more are on the Lifetime tab.|r")
end

function Tab.Lifetime(_, add)
  local deaths = T.Stat("deaths")
  if deaths == nil and T.Stat("completed") == nil then
    add("This client has no Statistics panel to read.")
    return
  end
  add(grey .. "From your Statistics panel: this character's whole life, not just since install.|r")
  add(" ")
  -- Zeros are shown on purpose: never having laughed is a fact too.
  local function stat(label, key, extra)
    local v = T.Stat(key)
    if v then add(("%s: %s%s"):format(label, num(v), extra or "")) end
  end
  add(heading() .. "Survival|r")
  local falls = T.Stat("fallDeaths")
  stat("Deaths", "deaths", (deaths and falls and deaths > 0) and (" (%s from falling)"):format(num(falls)) or "")
  stat("Creatures killed", "creatures")
  stat("Critters killed", "critters")
  add(" ")
  add(heading() .. "Questing|r")
  local done, quit = T.Stat("completed"), T.Stat("abandoned")
  stat("Completed", "completed")
  stat("Abandoned", "abandoned", (done and quit and done + quit > 0) and (" (%d%%)"):format(pctOf(quit, done + quit)) or "")
  add(" ")
  add(heading() .. "Social|r")
  stat("Waves", "waves")
  stat("Cheers", "cheers")
  stat("Hugs", "hugs")
  stat("LOLs", "lols")
  stat("Facepalms", "facepalms")
  stat("World's smallest violin", "violins")
end

-- A zone's own name is recorded when you're in no named subzone: open ground,
-- and most flying. Where the same zone also has named subzones in the list,
-- say so, or "Bastion" alone looks like a mistake. Zones with no subzones
-- (small islands and the like) keep their plain name.
local function placeLabel(key, zones)
  if key:find(" %- ") then return key end
  local prefix = key .. " - "
  for other in pairs(zones) do
    if other:sub(1, #prefix) == prefix then return key .. " (between places)" end
  end
  return key
end

function Tab.Places(db, add)
  local places = T.TopN(db.zones, 1000)
  if #places == 0 then
    add(grey .. "Nowhere recorded yet.|r")
    return
  end
  add(("%d places visited"):format(#places))
  add(" ")
  add(heading() .. "Share of your time|r")
  -- Share first, so a long place name can wrap without splitting the number
  for i = 1, math.min(10, #places) do
    local z = places[i]
    add(("%d%%  %s"):format(pctOf(z.v, db.tracked), placeLabel(z.k, db.zones)))
  end
  if (db.deathsSeen or 0) > 0 then
    add(" ")
    add(heading() .. "Where you die|r")
    for _, z in ipairs(T.TopN(db.deathZones or {}, 3)) do
      add(("%d%%  %s"):format(pctOf(z.v, db.deathsSeen), placeLabel(z.k, db.zones)))
    end
  end
  local towns = T.TopN(db.idleZones, 3)
  if #towns > 0 then
    add(" ")
    add(heading() .. "Where you stand around|r")
    for _, z in ipairs(towns) do add(("%s - %s"):format(z.k, T.FmtTime(z.v))) end
  end
end

function Tab.Roster(_, add)
  local R = ns.roster
  if not R then return end
  local list = R.List()
  if #list <= 1 then
    add(("Only %s so far."):format(UnitName("player") or "you"))
    add(" ")
    add(grey .. "Log into your other characters with Persona installed and they'll appear here.|r")
    return
  end
  local ordered, w = R.Ordered(list)
  local total = 0
  for _, c in ipairs(ordered) do total = total + (w[c.key] or 0) end

  add(heading() .. "Your characters|r")
  for _, c in ipairs(ordered) do
    if c.stale then
      add(("%s%s|r"):format(grey, c.title or c.name))
      add(("%sNot seen for %d days|r"):format(grey, math.floor((time() - (c.lastSeen or 0)) / 86400)))
    else
      local colour = RAID_CLASS_COLORS and c.class and RAID_CLASS_COLORS[c.class]
      local hex = colour and colour.colorStr or "ffffffff"
      add(("|c%s%s|r"):format(hex, c.title or c.name))
      local share = total > 0 and math.floor((w[c.key] or 0) / total * 100 + 0.5) or 0
      add(("%sLevel %d, %d%% of your time%s|r"):format(grey, c.level or 0, share, c.current and ", playing now" or ""))
    end
  end

  local who = R.Comparisons(list)
  if #who > 0 then
    add(" ")
    add(heading() .. "Who's who|r")
    for _, line in ipairs(who) do add(line) end
  end

  local traits = R.AccountTraits(list)
  if #traits > 0 then
    add(" ")
    add(heading() .. "Your account|r")
    for _, t in ipairs(traits) do
      add(("%s%s.|r %s"):format(blue, t.label, t.text))
    end
  end
end

local function currentTab()
  local t = ns.db and ns.db.panelTab
  return (t and Tab[t]) and t or "Profile"
end

function ns.Refresh()
  if not panel or not panel:IsShown() or not ns.db then return end
  local db = ns.db

  title:SetText(T.Headline(T.Build(db)))
  local level, race, class = UnitLevel("player"), UnitRace("player"), UnitClass("player")
  subtitle:SetText(("Level %d %s %s, as seen through %s habits"):format(level or 0, race or "", class or "",
    (UnitSex("player") == 2 and "his") or (UnitSex("player") == 3 and "her") or "their"))

  local selected = currentTab()
  for name, b in pairs(tabButtons) do
    local on = name == selected
    local a = ns.accent
    if on then b.label:SetTextColor(a[1], a[2], a[3]) else b.label:SetTextColor(0.6, 0.6, 0.6) end
    b.underline:SetColorTexture(a[1], a[2], a[3], 1)
    b.underline:SetShown(on)
  end

  local lines = {}
  Tab[selected](db, function(s) lines[#lines + 1] = s end)
  body:SetText(table.concat(lines, "\n"))
  panel:SetHeight(title:GetStringHeight() + subtitle:GetStringHeight() + 20 + body:GetStringHeight() + 60)
end

function ns.SetTab(name)
  if not Tab[name] or not ns.db then return end
  ns.db.panelTab = name
  ns.Refresh()
end

-- source: "character" when opened from the character screen, nil otherwise
function ns.SetPanel(show, fromCharFrame, source)
  if not panel then return end
  if show then
    openedFrom = source
    anchor()
    panel:Show()
    -- /played prints to chat, so only ask when the player actually opens the panel.
    if not playedRequested then
      playedRequested = true
      RequestTimePlayed()
    end
    ns.Refresh()
  else
    panel:Hide()
  end
  if ns.db and not fromCharFrame then ns.db.panelOpen = show end
end

-- Live refresh while open
local ticker = 0
local refresher = CreateFrame("Frame")
refresher:SetScript("OnUpdate", function(_, e)
  ticker = ticker + e
  if ticker >= 2 then ticker = 0; ns.Refresh() end
end)


---------------------------------------------------------------------------
-- Minimap addons button (the addon compartment). The game calls these by the
-- names given in Persona.toc: click(addonName, mouseButton), enter/leave(addonName, button).
---------------------------------------------------------------------------
local function onClick(mouseButton)
  if mouseButton == "RightButton" then
    if ns.db then ns.db.panelPos = nil end
    if panel and panel:IsShown() then anchor() end
    return
  end
  ns.SetPanel(not (panel and panel:IsShown()))
end

local function fillTooltip(tt)
  tt:AddLine("Persona")
  if ns.db then tt:AddLine(T.Headline(T.Build(ns.db)), 1, 1, 1) end
  tt:AddLine("Click to open or close", 0.6, 0.6, 0.6)
  tt:AddLine("Right-click to dock beside the character frame", 0.6, 0.6, 0.6)
end

function Persona_OnCompartmentClick(_, mouseButton) onClick(mouseButton) end

function Persona_OnCompartmentEnter(_, button)
  if not GameTooltip then return end
  GameTooltip:SetOwner(button, "ANCHOR_LEFT")
  fillTooltip(GameTooltip)
  GameTooltip:Show()
end

function Persona_OnCompartmentLeave()
  if GameTooltip then GameTooltip:Hide() end
end

---------------------------------------------------------------------------
-- Classic minimap button (LibDBIcon), for minimap replacements and button
-- collectors that don't show Blizzard's addons button. Bundled in Libs/.
-- If the libraries are missing, there's simply no button.
---------------------------------------------------------------------------
local minimapIcon

local function setupMinimapButton()
  local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
  minimapIcon = LibStub and LibStub("LibDBIcon-1.0", true)
  if not (LDB and minimapIcon and ns.db) then minimapIcon = nil; return end
  local launcher = LDB:NewDataObject("Persona", {
    type = "launcher",
    text = "Persona",
    icon = "Interface\\Icons\\INV_Misc_Book_09",
    OnClick = function(_, mouseButton) onClick(mouseButton) end,
    OnTooltipShow = fillTooltip,
  })
  ns.db.minimap = ns.db.minimap or {}   -- LibDBIcon keeps hide and minimapPos here
  minimapIcon:Register("Persona", launcher, ns.db.minimap)
end

-- Assigned here, below both functions, so setupMinimapButton is in scope
ns.OnDBReady = function() build(); setupMinimapButton() end

function ns.ToggleMinimapButton()
  if not minimapIcon then
    print("|cff66ccffPersona|r: the minimap button isn't available (libraries missing).")
    return
  end
  local cfg = ns.db.minimap
  cfg.hide = not cfg.hide
  if cfg.hide then minimapIcon:Hide("Persona") else minimapIcon:Show("Persona") end
  print(("|cff66ccffPersona|r: minimap button %s. Type /persona minimap to %s it."):format(
    cfg.hide and "hidden" or "shown", cfg.hide and "show" or "hide"))
end

SLASH_PERSONA1 = "/persona"
SlashCmdList.PERSONA = function(msg)
  msg = strtrim(msg or ""):lower()
  if msg == "share" or msg == "share chat" then
    if ns.share then ns.share.Show(msg == "share chat" and "chat" or "discord") end
  elseif msg == "moves" then
    print("|cff66ccffPersona|r: signature moves counted on this character:")
    for _, line in ipairs(ns.moves and ns.moves.Report() or {}) do print(line) end
  elseif msg == "stats" then
    print("|cff66ccffPersona|r: lifetime statistics on this client:")
    T.DumpStats()
  elseif msg == "minimap" then
    ns.ToggleMinimapButton()
  elseif msg:match("^forget") then
    local reply = ns.roster and ns.roster.Forget(msg:match("^forget%s*(.*)$")) or "Roster unavailable."
    print("|cff66ccffPersona|r: " .. reply)
    ns.Refresh()
  elseif msg == "dock" then
    if ns.db then ns.db.panelPos = nil end
    print("|cff66ccffPersona|r: panel docked beside the character frame again.")
    if panel and panel:IsShown() then anchor() end
  elseif msg == "reset" then
    local pos = ns.db and ns.db.panelPos
    ns.ResetDB()
    if ns.db then ns.db.panelPos = pos end   -- resetting the profile keeps the window where it is
    print("|cff66ccffPersona|r: data reset for this character.")
    ns.Refresh()
  else
    ns.SetPanel(not (panel and panel:IsShown()))
  end
end
