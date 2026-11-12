-- Persona: account-wide roster.
-- An addon only sees the character that's logged in, so each character leaves
-- a small summary in PersonaAccountDB (shared by every character on this WoW
-- account and game) when it logs in and out. The Roster tab reads them all.
-- Per-character data in PersonaDB is never touched here.

local _, ns = ...
local T = ns.traits
local R = {}
ns.roster = R

R.STALE_DAYS = 60
local DAY = 24 * 3600

-- "Zugzwang is your <word> one." Traits without a word aren't compared.
local WORDS = {
  restless = "restless", grounded = "composed", cityslicker = "town-loving",
  homebody = "stay-at-home", wanderer = "wandering", loyal = "loyal",
  collector = "mount-collecting", pedestrian = "walking", gravityfan = "falling",
  leap = "daredevil", gravityvictim = "clumsy", quitter = "quest-abandoning",
  menace = "critter-hunting", hugger = "huggable", joker = "giggly",
  exasperated = "exasperated", friendly = "friendly", cheerleader = "cheerful",
  sardonic = "sarcastic", stoneface = "stone-faced", dancer = "dancing",
  polite = "polite", rude = "rude", solodancer = "solo-dancing",
  nightowl = "nocturnal", earlybird = "early-rising", weekender = "weekend",
  hoarder = "hoarding", travelslight = "tidy", wandersoff = "easily distracted",
  taxi = "portal-opening", summoner = "summoning", nohorse = "four-legged", lurker = "sneaky",
  dramaqueen = "dramatic", hider = "shadowy", wildrunner = "wild", rocketeer = "rocket-powered",
  camper = "outdoorsy", soarer = "high-flying", stomper = "stompy", escapee = "slippery",
  neveralone = "sociable", menagerie = "pet-collecting",
  beaststable = "beast-collecting", lonewolf = "lone-wolf",
}

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

local function account()
  PersonaAccountDB = PersonaAccountDB or {}
  local a = PersonaAccountDB
  a.version = a.version or 1
  a.characters = a.characters or {}
  return a
end

local function playerKey()
  local guid = UnitGUID("player")
  if not guid or isSecret(guid) then return nil end
  return guid
end

-- Summary of the logged-in character, built from its live PersonaDB
local function summarise(db)
  local traits = T.Build(db)
  local scores, top = {}, {}
  for i, t in ipairs(traits) do
    scores[t.id] = t.score
    if i <= 3 then top[#top + 1] = t.label end
  end
  local _, classFile = UnitClass("player")
  return {
    name = UnitName("player"),
    -- Forever adds a surname. GetUnitName returns "First Surname" there and
    -- just the name on retail; UnitName's second value is a surname on Forever
    -- and a realm on retail, so it's never used.
    fullName = GetUnitName and GetUnitName("player", false) or UnitName("player"),
    realm = GetRealmName and GetRealmName() or nil,
    class = classFile,
    level = UnitLevel("player"),
    title = T.Headline(traits),
    traits = top,
    scores = scores,
    tracked = db.tracked or 0,
    played = db.played or nil,
    lastSeen = time(),
  }
end

function R.Save()
  local key, db = playerKey(), ns.db
  if not key or not db then return end
  account().characters[key] = summarise(db)
end

-- Characters for display: the live character always uses fresh data
function R.List()
  R.Save()
  local now, list = time(), {}
  for key, c in pairs(account().characters) do
    c.key = key
    c.current = key == playerKey()
    c.stale = not c.current and (now - (c.lastSeen or 0)) > R.STALE_DAYS * DAY
    list[#list + 1] = c
  end
  return list
end

-- Play time used to compare characters: /played only if every active
-- character has it, otherwise time observed, so one big number can't skew it.
local function weights(active)
  local allPlayed = #active > 0
  for _, c in ipairs(active) do
    if not c.played then allPlayed = false end
  end
  local total, w = 0, {}
  for _, c in ipairs(active) do
    w[c.key] = (allPlayed and c.played or c.tracked) or 0
    total = total + w[c.key]
  end
  return w, total
end

local function shares(list)
  local active = {}
  for _, c in ipairs(list) do
    if not c.stale then active[#active + 1] = c end
  end
  local w, total = weights(active)
  table.sort(active, function(a, b) return w[a.key] > w[b.key] end)
  return active, w, total
end

-- "Who's who": for each trait, the qualified character with the highest score
function R.Comparisons(list)
  local qualified = {}
  for _, c in ipairs(list) do
    if not c.stale and (c.tracked or 0) >= T.MIN_TRACKED then qualified[#qualified + 1] = c end
  end
  if #qualified < 2 then return {} end
  -- Who holds each trait most strongly
  local best = {}
  for _, c in ipairs(qualified) do
    for id, score in pairs(c.scores or {}) do
      if WORDS[id] and (not best[id] or score > best[id].score) then
        best[id] = { key = c.key, name = c.name, score = score }
      end
    end
  end
  -- One line per character: the trait they're most known for. A long-played
  -- main would otherwise win nearly every trait and fill the whole list.
  local mine = {}
  for id, b in pairs(best) do
    if not mine[b.key] or b.score > mine[b.key].score then
      mine[b.key] = { score = b.score, text = ("%s is your %s one."):format(b.name, WORDS[id]) }
    end
  end
  local lines = {}
  for _, l in pairs(mine) do lines[#lines + 1] = l end
  table.sort(lines, function(a, b) return a.score > b.score end)
  local out = {}
  for i = 1, math.min(8, #lines) do out[i] = lines[i].text end
  return out
end

-- Traits of the account as a whole
function R.AccountTraits(list)
  local active, w, total = shares(list)
  local out = {}
  if #active < 2 or total <= 0 then return out end
  local top = active[1]
  local topShare = w[top.key] / total
  if #active >= 5 and topShare <= 0.4 then
    out[#out + 1] = { label = "Altoholic", text = ("%d characters, and none of them gets more than %d%% of your time.")
      :format(#active, math.floor(topShare * 100 + 0.5)) }
  end
  if topShare >= 0.75 then
    out[#out + 1] = { label = "One True Main", text = ("%s gets %d%% of your time. The others are just visiting.")
      :format(top.name, math.floor(topShare * 100 + 0.5)) }
  end
  local second = active[2]
  if (top.tracked or 0) >= T.MIN_TRACKED and (second.tracked or 0) >= T.MIN_TRACKED
      and next(top.scores or {}) and next(second.scores or {}) then
    local shared = false
    for id in pairs(top.scores) do
      if second.scores[id] then shared = true end
    end
    if not shared then
      out[#out + 1] = { label = "Split Personality", text = ("%s and %s don't share a single habit.")
        :format(top.name, second.name) }
    end
  end
  return out
end

function R.Ordered(list)
  local active, w = shares(list)
  local stale = {}
  for _, c in ipairs(list) do
    if c.stale then stale[#stale + 1] = c end
  end
  table.sort(stale, function(a, b) return (a.lastSeen or 0) > (b.lastSeen or 0) end)
  for _, c in ipairs(stale) do active[#active + 1] = c end
  return active, w
end

-- /persona forget Name, Name-Realm, or First Surname on Forever.
-- Returns a message for the chat frame.
function R.Forget(arg)
  arg = ((arg or ""):lower():gsub("%s", ""))
  if arg == "" then return "Usage: /persona forget Name (or Name-Realm, or First Surname)." end
  local hits = {}
  for key, c in pairs(account().characters) do
    local name = (c.name or ""):lower()
    local withRealm = name .. "-" .. ((c.realm or ""):lower():gsub("%s", ""))
    local fullName = ((c.fullName or ""):lower():gsub("[%s%-]", ""))
    -- An exact full name wins outright, so "Jeem Hunt" isn't ambiguous with "Jeem Stone"
    if fullName ~= "" and fullName ~= name and (arg:gsub("%-", "")) == fullName then hits = { key }; break end
    if arg == name or arg == withRealm then hits[#hits + 1] = key end
  end
  if #hits == 0 then return ("No character called %s in the roster."):format(arg) end
  if #hits > 1 then return ("More than one %s: use their full name or Name-Realm."):format(arg) end
  if hits[1] == playerKey() then return "You can't forget the character you're playing." end
  local c = account().characters[hits[1]]
  account().characters[hits[1]] = nil
  return ("Forgot %s."):format(c.fullName or c.name)
end

-- Keep the summary current: on entering the world and on logout
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_LOGOUT")
f:SetScript("OnEvent", function() R.Save() end)
