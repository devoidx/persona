-- Persona: Core sampling engine
-- Samples cheap player-state APIs on a throttled OnUpdate and accumulates
-- per-character totals into PersonaDB (written by the client on logout/reload).

local ADDON, ns = ...

-- WoW Forever runs as its own game type ("camelot") on the modern client.
ns.IS_FOREVER = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
local Core = CreateFrame("Frame")
ns.core = Core

local SAMPLE = 0.25          -- seconds between samples
local MOUNT_RESCAN = 10      -- fallback mount rescan interval while mounted
local MIN_FALL = 1.0         -- ignore falls shorter than this (normal jump arcs)

-- Free-fall model for estimating distance from fall duration. These are
-- community-measured approximations, not values the client exposes.
local GRAVITY = 19.29        -- yards/s^2
local TERMINAL = 60.15       -- yards/s
local T_TERMINAL = TERMINAL / GRAVITY

local DEFAULTS = {
  version = 1,
  created = false,
  tracked = 0,               -- seconds observed by the addon
  sessions = 0,
  travel = 0,                -- seconds moving on the ground (on foot or mounted)
  onFoot = 0,                -- seconds moving on the ground, not mounted
  travelJumps = 0,           -- jumps made while moving
  totalJumps = 0,
  mounted = 0,               -- seconds mounted with a known mount
  mounts = {},               -- [mountID] = seconds
  zones = {},                -- ["Zone - Subzone"] = seconds
  idleResting = 0,           -- seconds stationary in a resting area (cities/inns)
  idleZones = {},            -- [zone] = seconds stationary while resting
  falling = 0,               -- seconds in qualifying falls
  falls = 0,
  longestFall = 0,
  fallYards = 0,             -- estimated
  bagSamples = 0,            -- once-a-minute samples of bag fullness
  bagFull = 0,               -- sum of fullness (0-1) over those samples
  deathsSeen = 0,            -- deaths observed since install
  deathZones = {},           -- ["Zone - Subzone"] = deaths there
  afkCount = 0,
  afkTime = 0,               -- seconds flagged AFK
  moves = {},                -- signature moves (Moves.lua), counted out of combat
  pets = {},                 -- [speciesID] = seconds out as your companion
  petNames = {},             -- [speciesID] = custom name if given, else species name
  petTime = 0,               -- seconds with any companion out
  formTravel = 0,            -- seconds travelling in Travel Form / Ghost Wolf
  stealthTime = 0,           -- seconds stealthed out of combat
  emotes = {},               -- [TOKEN] = times performed, e.g. DANCE, BOW
  emoteTotal = 0,
  soloDances = 0,            -- /dance with no target while not grouped
  hours = {},                -- [0-23] = seconds played in that local hour
  days = {},                 -- [0-6, Sunday = 0] = seconds played on that weekday
  played = false,            -- /played total, seconds
  playedAt = false,
  panelOpen = false,
}

-- Midnight secret values: never do arithmetic on something the client has hidden.
local function isSecret(v)
  return issecretvalue ~= nil and issecretvalue(v)
end

local function safeSpeed()
  local s = GetUnitSpeed("player")
  if s == nil or isSecret(s) then return nil end
  return s
end

local function applyDefaults(db)
  for k, v in pairs(DEFAULTS) do
    if db[k] == nil then
      db[k] = (type(v) == "table") and {} or v
    end
  end
end

local function bump(tbl, key, dt)
  if key == nil or key == "" then return end
  tbl[key] = (tbl[key] or 0) + dt
end

function ns.EstimateFallYards(t)
  if t <= T_TERMINAL then
    return 0.5 * GRAVITY * t * t
  end
  return 0.5 * GRAVITY * T_TERMINAL * T_TERMINAL + TERMINAL * (t - T_TERMINAL)
end

---------------------------------------------------------------------------
-- Cached state (updated by events, read by the sampler)
---------------------------------------------------------------------------
local db
local zoneKey, zoneName = nil, nil
local currentMount, lastMountScan = nil, 0
local fallStart = nil
local clockHour, clockDay, clockCheck = nil, nil, 0
local bagCheck, afkSince = 0, nil
local petAcc = 0
local PET_EVERY = 5

-- Which companion pet is out, credited with the time since the last check
local function samplePet(seconds)
  if not (C_PetJournal and C_PetJournal.GetSummonedPetGUID) then return end
  local guid = C_PetJournal.GetSummonedPetGUID()
  if not guid or isSecret(guid) then return end
  local speciesID, customName, _, _, _, _, _, petName = C_PetJournal.GetPetInfoByPetID(guid)
  if not speciesID or isSecret(speciesID) then return end
  db.pets[speciesID] = (db.pets[speciesID] or 0) + seconds
  db.petTime = db.petTime + seconds
  local name = (customName and customName ~= "") and customName or petName
  if name then db.petNames[speciesID] = name end
end
local BAG_EVERY = 60

-- Fullness of the backpack and ordinary bags. Profession bags (non-zero
-- family) and the reagent bag are left out: they fill up by design.
local function sampleBags()
  if not (C_Container and C_Container.GetContainerNumSlots) then return end
  local total, free = 0, 0
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local slots = C_Container.GetContainerNumSlots(bag) or 0
    if slots > 0 then
      local f, family = C_Container.GetContainerNumFreeSlots(bag)
      if (family or 0) == 0 then
        total = total + slots
        free = free + (f or 0)
      end
    end
  end
  if total > 0 then
    db.bagSamples = db.bagSamples + 1
    db.bagFull = db.bagFull + (total - free) / total
  end
end

local function afkChanged(now)
  local afk = UnitIsAFK("player")
  if isSecret(afk) then return end
  if afk and not afkSince then
    afkSince = now
    db.afkCount = db.afkCount + 1
  elseif not afk and afkSince then
    db.afkTime = db.afkTime + (now - afkSince)
    afkSince = nil
  end
end

local function updateZone()
  zoneName = GetRealZoneText() or ""
  local sub = GetSubZoneText() or ""
  if sub ~= "" and sub ~= zoneName then
    zoneKey = zoneName .. " - " .. sub
  else
    zoneKey = zoneName
  end
end

local function scanMount()
  currentMount = nil
  lastMountScan = GetTime()
  if not IsMounted() then return end
  -- Guard: don't assume every client flavour ships the mount journal
  if not (C_MountJournal and C_MountJournal.GetMountIDs) then return end
  local ids = C_MountJournal.GetMountIDs() or {}
  for i = 1, #ids do
    local _, _, _, isActive = C_MountJournal.GetMountInfoByID(ids[i])
    if isActive then
      currentMount = ids[i]
      return
    end
  end
end

local function isGliding()
  if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
    local gliding = C_PlayerInfo.GetGlidingInfo()
    return gliding and not isSecret(gliding)
  end
  return false
end

local function finishFall(now)
  if not fallStart then return end
  local dur = now - fallStart
  fallStart = nil
  if dur < MIN_FALL then return end
  db.falls = db.falls + 1
  db.falling = db.falling + dur
  db.fallYards = db.fallYards + ns.EstimateFallYards(dur)
  if dur > db.longestFall then db.longestFall = dur end
end

---------------------------------------------------------------------------
-- Sampler
---------------------------------------------------------------------------
local acc = 0
local function onUpdate(_, elapsed)
  acc = acc + elapsed
  if acc < SAMPLE then return end
  local dt = acc
  acc = 0
  if not db then return end

  local now = GetTime()
  db.tracked = db.tracked + dt
  bump(db.zones, zoneKey, dt)

  if now - bagCheck >= BAG_EVERY then
    bagCheck = now
    sampleBags()
  end

  petAcc = petAcc + dt
  if petAcc >= PET_EVERY then
    samplePet(petAcc)
    petAcc = 0
  end

  -- Local clock: refresh at most once a minute
  if now - clockCheck >= 60 or not clockHour then
    clockCheck = now
    clockHour, clockDay = tonumber(date("%H")), tonumber(date("%w"))
  end
  bump(db.hours, clockHour, dt)
  bump(db.days, clockDay, dt)

  local flying, swimming = IsFlying(), IsSwimming()
  local mounted = IsMounted()
  local speed = safeSpeed()

  -- Mount time
  if mounted then
    if not currentMount and now - lastMountScan > MOUNT_RESCAN then scanMount() end
    if currentMount then
      db.mounted = db.mounted + dt
      bump(db.mounts, currentMount, dt)
    end
  end

  -- Ground travel
  local moving = speed and speed > 0 and not flying and not swimming
  if moving then
    db.travel = db.travel + dt
    -- Travel Form and Ghost Wolf are getting around, not walking
    local inForm = ns.moves and ns.moves.InTravelForm()
    if not mounted and not inForm then db.onFoot = db.onFoot + dt end
  end
  if ns.moves then
    local inCombat = UnitAffectingCombat("player")
    ns.moves.Sample(dt, moving, mounted, isSecret(inCombat) or inCombat)
  end

  -- Idle in resting areas (cities and inns)
  if speed == 0 and IsResting() and not UnitAffectingCombat("player") then
    db.idleResting = db.idleResting + dt
    bump(db.idleZones, zoneName, dt)
  end

  -- Falls (excludes flying, swimming and skyriding glides)
  if IsFalling() and not flying and not swimming and not isGliding() then
    if not fallStart then fallStart = now - dt end
  elseif fallStart then
    finishFall(now)
  end
end

---------------------------------------------------------------------------
-- Jump counting: JumpOrAscendStart is what the jump keybinding calls.
-- hooksecurefunc runs after it and does not taint it.
---------------------------------------------------------------------------
local function onJump()
  if not db or IsSwimming() or IsFlying() then return end
  db.totalJumps = db.totalJumps + 1
  local s = safeSpeed()
  if s and s > 0 then db.travelJumps = db.travelJumps + 1 end
end

---------------------------------------------------------------------------
-- Emote counting by token (DANCE, BOW...), so it works in every client language.
-- 12.0 replaced DoEmote with C_ChatInfo.PerformEmote and kept DoEmote as a
-- deprecated alias. Both are hooked; if one calls the other, the second
-- sighting of the same token in the same frame is dropped.
--
-- The game also performs emotes by itself: opening the world map or a mailbox
-- plays READ via PerformEmote("READ", nil, true). Those automatic calls pass
-- suppressMoveError = true; typed slash emotes and the emote menu never do,
-- so that argument is what separates the player's emotes from the UI's.
---------------------------------------------------------------------------
local lastEmoteToken, lastEmoteTime
local function onEmote(token, _, suppressMoveError)
  if suppressMoveError then return end
  if not db or type(token) ~= "string" or isSecret(token) then return end
  token = token:upper()
  local now = GetTime()
  if token == lastEmoteToken and now == lastEmoteTime then return end
  lastEmoteToken, lastEmoteTime = token, now

  db.emotes[token] = (db.emotes[token] or 0) + 1
  db.emoteTotal = db.emoteTotal + 1

  if token == "DANCE" then
    local hasTarget = UnitExists("target")
    if not isSecret(hasTarget) and not hasTarget and not IsInGroup() then
      db.soloDances = db.soloDances + 1
    end
  end
end

---------------------------------------------------------------------------
-- Saved-data upgrades, run once per character at load.
---------------------------------------------------------------------------
function ns.migrate(d)
  local v = d.version or 1
  if v < 2 then
    -- 0.5.0 counted the world map and mailbox opening as /read. Those can't be
    -- told apart from real ones after the fact, and a real /read is rare, so
    -- drop READ entirely.
    local bogus = d.emotes and d.emotes.READ or 0
    if bogus > 0 then
      d.emotes.READ = nil
      d.emoteTotal = math.max(0, (d.emoteTotal or 0) - bogus)
    end
    v = 2
  end
  d.version = v
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
Core:RegisterEvent("ADDON_LOADED")
Core:RegisterEvent("PLAYER_ENTERING_WORLD")
Core:RegisterEvent("ZONE_CHANGED")
Core:RegisterEvent("ZONE_CHANGED_INDOORS")
Core:RegisterEvent("ZONE_CHANGED_NEW_AREA")
Core:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
Core:RegisterEvent("TIME_PLAYED_MSG")
Core:RegisterEvent("PLAYER_DEAD")
Core:RegisterEvent("PLAYER_FLAGS_CHANGED")
Core:RegisterEvent("PLAYER_LOGOUT")

Core:SetScript("OnEvent", function(self, event, arg1, ...)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    PersonaDB = PersonaDB or {}
    db = PersonaDB
    applyDefaults(db)
    if not db.created then db.created = time() end
    db.sessions = db.sessions + 1
    ns.migrate(db)
    ns.db = db
    if JumpOrAscendStart then hooksecurefunc("JumpOrAscendStart", onJump) end
    if C_ChatInfo and C_ChatInfo.PerformEmote then hooksecurefunc(C_ChatInfo, "PerformEmote", onEmote) end
    if DoEmote then hooksecurefunc("DoEmote", onEmote) end
    self:UnregisterEvent("ADDON_LOADED")
    if ns.OnDBReady then ns.OnDBReady(db) end
  elseif event == "PLAYER_ENTERING_WORLD" then
    updateZone()
    scanMount()
    fallStart = nil
    self:SetScript("OnUpdate", onUpdate)
  elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
    scanMount()
  elseif event == "TIME_PLAYED_MSG" then
    if db and arg1 and not isSecret(arg1) then
      db.played = arg1
      db.playedAt = time()
      if ns.Refresh then ns.Refresh() end
    end
  elseif event == "PLAYER_DEAD" then
    if db then
      db.deathsSeen = db.deathsSeen + 1
      bump(db.deathZones, zoneKey, 1)
    end
  elseif event == "PLAYER_FLAGS_CHANGED" then
    if db and arg1 == "player" then afkChanged(GetTime()) end
  elseif event == "PLAYER_LOGOUT" then
    -- Logging out while AFK: count the time up to now
    if db and afkSince then
      db.afkTime = db.afkTime + (GetTime() - afkSince)
      afkSince = nil
    end
  else -- zone events
    updateZone()
  end
end)

function ns.ResetDB()
  if not db then return end
  wipe(db)
  applyDefaults(db)
  db.created = time()
  db.sessions = 1
end
