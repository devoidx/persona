-- Persona: class and racial signature moves.
-- Counts out-of-combat casts of a fixed list of spells. Only listed IDs count,
-- so hidden spells the game casts on the player (like the one that fires after
-- a hearthstone) are ignored. Retail and Forever IDs differ, so both are listed.
-- Also times Travel Form / Ghost Wolf travel and stealth outside combat.

local _, ns = ...
local M = {}
ns.moves = M

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- move key -> { label for the Habits tab, spell IDs (retail and Forever) }
M.LIST = {
  portal     = { label = "Portals opened",            ids = { 10059, 11416, 11419, 11417, 11418, 11420 } },
  summon     = { label = "Summons cast",              ids = { 698 } },
  feign      = { label = "Feign Death, nothing near", ids = { 5384 } },
  shadowmeld = { label = "Shadowmeld in town",        ids = { 58984, 20580 } },
  runwild    = { label = "Running Wild",              ids = { 87840 } },
  rocketjump = { label = "Rocket Jumps",              ids = { 69070 } },
  camp       = { label = "Camps made",                ids = { 312370 } },
  soar       = { label = "Soars",                     ids = { 369536 } },
  stomp      = { label = "War Stomp, nothing near",   ids = { 20549 } },
  escape     = { label = "Escapes from nothing",      ids = { 20589 } },
}

-- Moves that only count in a resting area (town or inn)
local TOWN_ONLY = { shadowmeld = true }

-- Shapeshift form IDs for getting around without a mount
local TRAVEL_FORMS = { [3] = true, [16] = true }   -- Druid Travel Form, Shaman Ghost Wolf

local byId

-- Retail keeps every mage portal in one spellbook flyout. Find the flyout that
-- holds Portal: Stormwind or Portal: Orgrimmar and count all of its spells, so
-- portals added in later patches are picked up without a code change.
local function addPortalFlyout()
  if not (GetFlyoutInfo and GetFlyoutSlotInfo) then return end
  for flyout = 1, 300 do
    local ok, _, _, numSlots = pcall(GetFlyoutInfo, flyout)
    if ok and numSlots and numSlots > 0 then
      local ids, anchor = {}, false
      for slot = 1, numSlots do
        local spellID = GetFlyoutSlotInfo(flyout, slot)
        if spellID then
          ids[#ids + 1] = spellID
          if spellID == 10059 or spellID == 11417 then anchor = true end
        end
      end
      if anchor then
        for _, id in ipairs(ids) do byId[id] = "portal" end
        return
      end
    end
  end
end

local function buildIndex()
  byId = {}
  for key, move in pairs(M.LIST) do
    for _, id in ipairs(move.ids) do byId[id] = key end
  end
  addPortalFlyout()
end

function M.Lookup(spellID)
  if not byId then buildIndex() end
  return byId[spellID]
end

function M.Record(spellID)
  local db = ns.db
  if not db or spellID == nil or isSecret(spellID) then return end
  local key = M.Lookup(spellID)
  if not key then return end
  local inCombat = UnitAffectingCombat("player")
  if isSecret(inCombat) or inCombat then return end
  if TOWN_ONLY[key] and not IsResting() then return end
  db.moves = db.moves or {}
  db.moves[key] = (db.moves[key] or 0) + 1
end

function M.InTravelForm()
  if not GetShapeshiftFormID then return false end
  local form = GetShapeshiftFormID()
  if form == nil or isSecret(form) then return false end
  return TRAVEL_FORMS[form] == true
end

-- Called from Core's sampler every tick
function M.Sample(dt, moving, mounted, inCombat)
  local db = ns.db
  if not db then return end
  if moving and not mounted and M.InTravelForm() then
    db.formTravel = (db.formTravel or 0) + dt
  end
  if not inCombat and IsStealthed then
    local stealthed = IsStealthed()
    if stealthed and not isSecret(stealthed) then
      db.stealthTime = (db.stealthTime or 0) + dt
    end
  end
end

-- /persona moves: what's been counted, so a wrong spell ID shows up as a zero
function M.Report()
  local db, lines = ns.db or {}, {}
  local keys = {}
  for key in pairs(M.LIST) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do
    lines[#lines + 1] = ("  %s: %d"):format(M.LIST[key].label, (db.moves or {})[key] or 0)
  end
  lines[#lines + 1] = ("  Travel form / Ghost Wolf: %s"):format(ns.traits.FmtTime(db.formTravel or 0))
  lines[#lines + 1] = ("  Stealthed out of combat: %s"):format(ns.traits.FmtTime(db.stealthTime or 0))
  return lines
end

local f = CreateFrame("Frame")
if f.RegisterUnitEvent then
  f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
else
  f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end
f:SetScript("OnEvent", function(_, _, unit, _, spellID)
  if unit == "player" then M.Record(spellID) end
end)
