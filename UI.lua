-- Persona: panel docked to the right of the character frame.
-- Parented to UIParent and only anchored to CharacterFrame, rather than
-- injected as a real tab, to stay clear of Blizzard's panel layout and taint.

local _, ns = ...
local T = ns.traits

local WIDTH, PAD = 300, 14
local panel, body, toggle, title, subtitle
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

  title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", PAD, -PAD)
  title:SetWidth(WIDTH - PAD * 2 - 24)
  title:SetJustifyH("LEFT")
  title:SetText("Persona")

  subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  subtitle:SetWidth(WIDTH - PAD * 2)
  subtitle:SetJustifyH("LEFT")

  local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() ns.SetPanel(false) end)

  body = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  body:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -10)
  body:SetWidth(WIDTH - PAD * 2)
  body:SetJustifyH("LEFT")
  body:SetSpacing(2)

  if CharacterFrame then
    toggle = CreateFrame("Button", nil, CharacterFrame, "UIPanelButtonTemplate")
    toggle:SetSize(80, 22)
    toggle:SetPoint("TOPRIGHT", CharacterFrame, "BOTTOMRIGHT", 0, -2)
    toggle:SetText("Persona")
    toggle:SetScript("OnClick", function() ns.SetPanel(not panel:IsShown()) end)

    CharacterFrame:HookScript("OnShow", function()
      if ns.db and ns.db.panelOpen then ns.SetPanel(true, true) end
    end)
    CharacterFrame:HookScript("OnHide", function() panel:Hide() end)
  end
end

local function anchor()
  panel:ClearAllPoints()
  if CharacterFrame and CharacterFrame:IsShown() then
    panel:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 4, 0)
  else
    panel:SetPoint("CENTER")
  end
end

function ns.Refresh()
  if not panel or not panel:IsShown() or not ns.db then return end
  local db = ns.db
  local lines = {}
  local function add(s) lines[#lines + 1] = s end
  local gold, grey = "|cffffd100", "|cff9d9d9d"

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
  title:SetText(T.Headline(traits))
  local level, race, class = UnitLevel("player"), UnitRace("player"), UnitClass("player")
  subtitle:SetText(("Level %d %s %s, as seen through %s habits"):format(level or 0, race or "", class or "",
    (UnitSex("player") == 2 and "his") or (UnitSex("player") == 3 and "her") or "their"))

  add(gold .. "Who they are|r")
  local MAX_SHOWN = 6
  for i, t in ipairs(traits) do
    if i > MAX_SHOWN then
      add(("%s...and %d more quirks.|r"):format(grey, #traits - MAX_SHOWN))
      add(" ")
      break
    end
    add(("|cff66ccff%s.|r %s"):format(t.label, t.text))
    add(" ")
  end
  if #traits == 0 or db.tracked < T.MIN_TRACKED then
    add(T.EmptyText(db))
    add(" ")
  end

  add(gold .. "The evidence|r")
  local travelMin = db.travel / 60
  add(("Jumps: %s total, %s while travelling%s"):format(BreakUpLargeNumbers(db.totalJumps),
    BreakUpLargeNumbers(db.travelJumps),
    travelMin >= 1 and (" (%.1f/min)"):format(db.travelJumps / travelMin) or ""))
  if (db.emoteTotal or 0) > 0 then
    local fav = T.TopN(db.emotes, 1)[1]
    add(("Emotes: %s (favourite: /%s, %s times)"):format(BreakUpLargeNumbers(db.emoteTotal),
      fav.k:lower(), BreakUpLargeNumbers(fav.v)))
  end
  add(("Ground travel: %s (%s on foot)"):format(T.FmtTime(db.travel), T.FmtTime(db.onFoot)))
  add(("Idle in towns: %s"):format(T.FmtTime(db.idleResting)))
  add(("Falls: %d, ~%s yd est., longest %.1fs"):format(db.falls,
    BreakUpLargeNumbers(math.floor(db.fallYards)), db.longestFall))
  local peak = T.TopN(db.hours, 1)[1]
  if peak then add(("Most active: %s"):format(T.HourRange(peak.k))) end

  add(" ")
  add(gold .. "Lifetime record|r")
  local deaths, fallDeaths = T.LifetimeDeaths()
  if deaths and fallDeaths then
    add(("Deaths: %s (%s from falling)"):format(BreakUpLargeNumbers(deaths), BreakUpLargeNumbers(fallDeaths)))
  end
  local function stat(label, key)
    local v = T.Stat(key)
    if v and v > 0 then add(("%s: %s"):format(label, BreakUpLargeNumbers(v))) end
  end
  stat("Quests abandoned", "abandoned")
  stat("Critters killed", "critters")
  stat("Hugs", "hugs")
  stat("Waves", "waves")
  stat("LOLs", "lols")
  stat("Facepalms", "facepalms")

  local mounts = T.TopN(db.mounts, 3)
  if #mounts > 0 then
    add(" ")
    add(gold .. "Favourite mounts|r")
    for _, m in ipairs(mounts) do add(("%s - %s"):format(T.MountName(m.k), T.FmtTime(m.v))) end
  end

  local zones = T.TopN(db.zones, 5)
  if #zones > 0 then
    add(" ")
    add(gold .. "Most visited|r")
    for _, z in ipairs(zones) do add(("%s - %s"):format(z.k, T.FmtTime(z.v))) end
  end

  body:SetText(table.concat(lines, "\n"))
  panel:SetHeight(title:GetStringHeight() + subtitle:GetStringHeight() + body:GetStringHeight() + 50)
end

function ns.SetPanel(show, fromCharFrame)
  if not panel then return end
  if show then
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

ns.OnDBReady = function() build() end

SLASH_PERSONA1 = "/persona"
SlashCmdList.PERSONA = function(msg)
  msg = strtrim(msg or ""):lower()
  if msg == "stats" then
    print("|cff66ccffPersona|r: lifetime statistics on this client:")
    T.DumpStats()
  elseif msg == "reset" then
    ns.ResetDB()
    print("|cff66ccffPersona|r: data reset for this character.")
    ns.Refresh()
  else
    ns.SetPanel(not (panel and panel:IsShown()))
  end
end
