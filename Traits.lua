-- Persona: turns raw totals into a written portrait of the character.
-- Each trait has several phrasings and an epithet. The phrasing is picked
-- from a seed of the trait and today's date, so it stays put through the
-- panel's live refresh but reads differently tomorrow. The strongest trait
-- gives the character their title ("Thrall the Restless").

local _, ns = ...
local T = {}
ns.traits = T

T.MIN_TRACKED = 20 * 60
-- Where and when someone plays needs several sessions before it says anything:
-- one evening in one zone is a session, not a personality.
T.MIN_PATTERN = 3 * 3600

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function top(tbl)
  local bestK, bestV
  for k, v in pairs(tbl) do
    if not bestV or v > bestV then bestK, bestV = k, v end
  end
  return bestK, bestV or 0
end

local function count(tbl)
  local n = 0
  for _ in pairs(tbl) do n = n + 1 end
  return n
end

function T.TopN(tbl, n)
  local list = {}
  for k, v in pairs(tbl) do list[#list + 1] = { k = k, v = v } end
  table.sort(list, function(a, b) return a.v > b.v end)
  for i = #list, n + 1, -1 do list[i] = nil end
  return list
end

function T.FmtTime(s)
  s = math.floor(s or 0)
  local h = math.floor(s / 3600)
  local m = math.floor((s % 3600) / 60)
  if h > 0 then return ("%dh %dm"):format(h, m) end
  if m > 0 then return ("%dm"):format(m) end
  return ("%ds"):format(s)
end

function T.MountName(id)
  local name = C_MountJournal and C_MountJournal.GetMountInfoByID and C_MountJournal.GetMountInfoByID(id)
  return name or ("Mount #" .. tostring(id))
end

local function pct(x) return math.floor(x * 100 + 0.5) end

-- "Silvermoon City - The Bazaar" -> "The Bazaar"
local function placeName(key)
  if not key then return nil end
  return key:match(" %- (.+)$") or key
end

local function who()
  local name = UnitName("player") or "You"
  local sex = UnitSex("player")
  local his = (sex == 2 and "his") or (sex == 3 and "her") or "their"
  return name, his
end

local function hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
  return h
end

local function pick(id, list)
  return list[hash(id .. date("%Y-%m-%d")) % #list + 1]
end

local function fill(tpl, vars)
  return (tpl:gsub("{(%w+)}", function(k)
    local v = vars[k]
    if v == nil then return "{" .. k .. "}" end
    return tostring(v)
  end))
end

---------------------------------------------------------------------------
-- Lifetime statistics (predate the addon, so they work on day one).
-- Looked up by title on an English client rather than by hardcoded IDs.
---------------------------------------------------------------------------
-- Statistics we read. IDs are the same in every client language (taken from
-- /persona stats on a 12.1.5 client); the English title is only a fallback in
-- case Blizzard ever renumbers one.
T.STATS = {
  deaths     = { id = 60,   title = "Total deaths" },
  fallDeaths = { id = 114,  title = "Deaths from falling" },
  waves      = { id = 1065, title = "Total waves" },
  cheers     = { id = 1045, title = "Total cheers" },
  lols       = { id = 1066, title = "Total times LOL'd" },
  facepalms  = { id = 1047, title = "Total facepalms" },
  violins    = { id = 1067, title = "Total times playing world's smallest violin" },
  hugs       = { id = 1042, title = "Number of hugs" },
  critters   = { id = 108,  title = "Critters killed" },
  abandoned  = { id = 94,   title = "Quests abandoned" },
  completed  = { id = 98,   title = "Quests completed" },
}

local statIDs

local function resolveStats()
  statIDs = {}
  -- Guard: statistics may be missing or empty on some client flavours
  if not (GetStatistic and GetAchievementInfo) then return end

  -- 1. By ID: works in any language
  local missing = {}
  for key, s in pairs(T.STATS) do
    local id = GetAchievementInfo(s.id)
    if id then statIDs[key] = s.id else missing[s.title] = key end
  end
  if not next(missing) or not GetStatisticsCategoryList then return end

  -- 2. By English title, for any ID that didn't resolve
  for _, cat in ipairs(GetStatisticsCategoryList() or {}) do
    for i = 1, (GetCategoryNumAchievements(cat) or 0) do
      local id, name = GetAchievementInfo(cat, i)
      if id and missing[name] then statIDs[missing[name]] = id end
    end
  end
end

-- Returns the lifetime value, 0 if never recorded, nil if the statistic wasn't found.
-- Digits only, so "4,252" and "4.252" both read as 4252.
function T.Stat(key)
  if not statIDs then resolveStats() end
  local id = statIDs[key]
  if not id then return nil end
  local v = GetStatistic(id)
  if not v or v == "--" then return 0 end
  return tonumber((v:gsub("[^%d]", ""))) or 0
end

function T.LifetimeDeaths()
  return T.Stat("deaths"), T.Stat("fallDeaths")
end

-- Debug: which statistics resolved on this client, under the client's own names
function T.DumpStats()
  if not statIDs then resolveStats() end
  for key, s in pairs(T.STATS) do
    local id = statIDs[key]
    local name = id and select(2, GetAchievementInfo(id)) or s.title
    print(("  %s: %s"):format(name, id and (tostring(T.Stat(key)) .. " (id " .. id .. ")") or "|cffff6060not found|r"))
  end
end

---------------------------------------------------------------------------
-- Trait copy. Placeholders: {name} {his} {n} {p} {place} {mount} {d} {f}
---------------------------------------------------------------------------
local COPY = {
  restless = {
    label = "Restless",
    epithet = "{name} the Restless",
    lines = {
      "{name} cannot walk anywhere without bouncing: {n} jumps a minute on the road.",
      "Somewhere, a physics engine is tired. {name} jumps {n} times a minute while travelling.",
      "{name} treats every road as a trampoline. {n} jumps a minute, and no sign of stopping.",
    },
  },
  grounded = {
    label = "Grounded",
    epithet = "{name} the Composed",
    lines = {
      "{name} walks like someone with places to be. Barely {n} jumps a minute.",
      "Feet on the ground, always. {name} manages {n} jumps a minute on the move.",
    },
  },
  cityslicker = {
    label = "City Slicker",
    epithet = "{name}, Idler of {place}",
    lines = {
      "{name} spends {p}% of {his} time standing perfectly still in town, mostly in {place}. Waiting for something. Or someone.",
      "Need {name}? Try {place}. {p}% of {his} playtime is spent in town doing absolutely nothing.",
      "{p}% of {name}'s life is spent idling in town. The guards in {place} know {his} face by now.",
    },
  },
  homebody = {
    label = "Homebody",
    epithet = "{name} the Homebody",
    lines = {
      "{name} has a favourite spot: {place}. {p}% of {his} life happens there.",
      "{name} keeps coming back to {place}: {p}% of all {his} time is spent there.",
    },
  },
  wanderer = {
    label = "Wanderer",
    epithet = "{name} the Wanderer",
    lines = {
      "{name} has set foot in {n} different places and shows no sign of stopping.",
      "{n} places visited. {name} doesn't stay anywhere long.",
    },
  },
  loyal = {
    label = "Loyal",
    epithet = "{name}, Rider of {mount}",
    lines = {
      "{name} and {mount} are inseparable: {p}% of all riding time.",
      "Other mounts exist. {name} has heard of them. Still rides {mount} {p}% of the time.",
    },
  },
  collector = {
    label = "Stable Master",
    epithet = "{name} the Collector",
    lines = {
      "{name} can't pick a favourite. {n} different mounts ridden so far.",
      "A mount for every mood: {name} has ridden {n} of them.",
    },
  },
  pedestrian = {
    label = "Pedestrian",
    epithet = "{name} the Footsore",
    lines = {
      "{name} owns mounts but prefers to walk. {p}% of {his} ground travel is on foot.",
      "Mounts are for other people. {name} walks {p}% of the way.",
    },
  },
  gravityfan = {
    label = "Gravity Enthusiast",
    epithet = "{name}, Friend of Gravity",
    lines = {
      "{name} has fallen roughly {n} yards. Nobody has asked why.",
      "Gravity and {name} go way back: about {n} yards fallen.",
    },
  },
  leap = {
    label = "Leap of Faith",
    epithet = "{name} the Bold",
    lines = {
      "{name}'s longest fall lasted {n} seconds. Long enough to reconsider several decisions.",
      "{n} seconds in free fall, once. {name} still talks about it.",
    },
  },
  gravityvictim = {
    label = "Gravity Victim",
    epithet = "{name}, Slain by Floors",
    lines = {
      "The floor has killed {name} {f} times. That's {p}% of all {his} deaths.",
      "{p}% of {name}'s {d} deaths were the floor's fault, not the enemy's.",
    },
  },
  -- Lifetime statistics
  quitter = {
    label = "Commitment Issues",
    epithet = "{name} the Undecided",
    lines = {
      "{name} has abandoned {n} quests, {p}% of every quest {his} journal has ever held.",
      "{n} quests abandoned. {name} prefers to keep {his} options open.",
    },
  },
  menace = {
    label = "Menace to Wildlife",
    epithet = "{name}, Bane of Squirrels",
    lines = {
      "{n} critters have died at {name}'s hands. The rabbits speak of {name} only in whispers.",
      "{name} has killed {n} critters. None of them were a threat.",
    },
  },
  hugger = {
    label = "The Hugger",
    epithet = "{name} the Warm",
    lines = {
      "{name} has hugged {n} times. Nobody is safe.",
      "{n} hugs given. {name} is a lot, but in a nice way.",
    },
  },
  joker = {
    label = "Easily Amused",
    epithet = "{name} the Giggling",
    lines = {
      "{name} has /lol'd {n} times. Not everything was that funny.",
      "{n} laughs on record. {name} is a generous audience.",
    },
  },
  exasperated = {
    label = "Exasperated",
    epithet = "{name} the Long-Suffering",
    lines = {
      "{name} has facepalmed {n} times. Group content has not been kind.",
      "{n} facepalms. {name} has seen things.",
    },
  },
  friendly = {
    label = "Friendly",
    epithet = "{name} the Neighbourly",
    lines = {
      "{name} has waved {n} times. Strangers included.",
      "{n} waves and counting. {name} greets everyone.",
    },
  },
  cheerleader = {
    label = "Cheerleader",
    epithet = "{name} the Encouraging",
    lines = {
      "{name} has cheered {n} times. Every win counts, apparently.",
      "{n} cheers on record. {name} is everyone's biggest fan.",
    },
  },
  sardonic = {
    label = "Sardonic",
    epithet = "{name} the Unimpressed",
    lines = {
      "{name} has played the world's smallest violin {n} times. Sympathy is in short supply.",
      "{n} tiny violin performances. {name} has heard your complaint.",
    },
  },
  stoneface = {
    label = "Stone-Faced",
    epithet = "{name} the Unamused",
    lines = {
      "{n} hours played, and {name} has never once /lol'd.",
      "{name} has seen everything Azeroth has to offer in {n} hours. None of it was funny.",
      "{n} hours. Not a single laugh. {name} is a tough crowd.",
    },
  },
  -- Emotes (counted since install)
  signature = {
    label = "Signature Move",
    epithet = "{name}, Master of {emote}",
    lines = {
      "{name}'s signature move is {emote}, used {n} times and counting.",
      "Ask {name} anything. The answer is usually {emote} ({n} times so far).",
    },
  },
  dancer = {
    label = "Dancer",
    epithet = "{name} the Dancer",
    lines = {
      "{name} has danced {n} times, {p}% of all {his} emotes.",
      "When in doubt, {name} dances. {n} times and counting.",
    },
  },
  polite = {
    label = "Polite",
    epithet = "{name} the Courteous",
    lines = {
      "{p}% of {name}'s emotes are bows, thanks and salutes. Somebody raised {name} well.",
      "{name} is unfailingly polite: {p}% of all emotes are courtesies.",
    },
  },
  rude = {
    label = "Rude",
    epithet = "{name} the Insufferable",
    lines = {
      "{p}% of {name}'s emotes are rude. The innkeepers have been warned.",
      "{name} communicates mainly in rude gestures: {p}% of all emotes.",
    },
  },
  solodancer = {
    label = "Dances Alone",
    epithet = "{name}, Who Dances Alone",
    lines = {
      "{name} has danced alone {n} times. No target, no group, no audience.",
      "{n} solo dances. {name} doesn't need anyone else to have a good time.",
    },
  },
  -- When they play
  nightowl = {
    label = "Night Owl",
    epithet = "{name} of the Small Hours",
    lines = {
      "{p}% of {name}'s adventures happen between midnight and 5am. Sleep is for NPCs.",
      "{name} does {his} best work after midnight: {p}% of all play.",
    },
  },
  earlybird = {
    label = "Early Bird",
    epithet = "{name} the Dawnwalker",
    lines = {
      "{name} is up before the world: {p}% of play happens between 5am and 9am.",
      "{p}% of {name}'s adventures start before breakfast.",
    },
  },
  weekender = {
    label = "Weekend Warrior",
    epithet = "{name}, Saturday's Hero",
    lines = {
      "{name} saves the world on weekends: {p}% of {his} play is Saturday and Sunday.",
      "Weekdays belong to someone else. {p}% of {name}'s play happens at the weekend.",
    },
  },
}

-- Emote groups for the Polite and Rude traits (tokens as the game names them)
local POLITE = { "BOW", "THANK", "SALUTE", "CURTSEY", "KNEEL", "WELCOME", "GREET", "APPLAUD" }
local RUDE = { "RUDE", "SPIT", "CHICKEN", "TAUNT", "GLOAT", "MOCK", "INSULT", "FART" }
T.EMOTE_MIN = 30   -- emotes needed before emote traits can appear

-- Hour labels for the evidence list
function T.HourRange(h)
  return ("%02d:00-%02d:00"):format(h, (h + 1) % 24)
end

local function sumRange(tbl, from, to)
  local t = 0
  for h = from, to do t = t + (tbl[h] or 0) end
  return t
end

---------------------------------------------------------------------------
-- Build: returns traits strongest first, each { id, label, text, epithet, score }
---------------------------------------------------------------------------
function T.Build(db)
  local name, his = who()
  local out = {}

  -- score = how far past its threshold the trait is; decides ordering and title
  local function add(id, score, vars, isLifetime)
    local c = COPY[id]
    vars.name, vars.his = name, his
    out[#out + 1] = {
      id = id,
      label = c.label,
      text = fill(pick(id, c.lines), vars),
      epithet = fill(c.epithet, vars),
      score = score,
      lifetime = isLifetime or false,
    }
  end

  -- Lifetime statistics: no sampling needed, so these work on day one.
  -- These grow for years, so they're scored on a damped log scale: ten times
  -- the threshold is worth about the same as a habit just past its own.
  local function damp(ratio) return 1 + 0.25 * math.log(ratio) end
  local function lifetime(id, value, threshold, vars)
    if value and value >= threshold then
      vars.n = vars.n or BreakUpLargeNumbers(value)
      add(id, damp(value / threshold), vars, true)
    end
  end

  local deaths, fallDeaths = T.LifetimeDeaths()
  if deaths and fallDeaths and deaths >= 20 and fallDeaths >= 5 then
    local share = fallDeaths / deaths
    if share >= 0.05 then
      add("gravityvictim", damp(share / 0.05), { p = pct(share), d = deaths, f = fallDeaths }, true)
    end
  end

  local abandoned, completed = T.Stat("abandoned"), T.Stat("completed")
  if abandoned and completed and abandoned >= 50 then
    local share = abandoned / (abandoned + completed)
    if share >= 0.1 then
      add("quitter", damp(share / 0.1), { n = BreakUpLargeNumbers(abandoned), p = pct(share) }, true)
    end
  end

  lifetime("menace", T.Stat("critters"), 250, {})
  lifetime("hugger", T.Stat("hugs"), 50, {})
  lifetime("joker", T.Stat("lols"), 100, {})
  lifetime("exasperated", T.Stat("facepalms"), 50, {})
  lifetime("friendly", T.Stat("waves"), 100, {})
  lifetime("cheerleader", T.Stat("cheers"), 100, {})
  lifetime("sardonic", T.Stat("violins"), 25, {})

  -- An absence can be a trait too: never laughing in hundreds of hours is a choice.
  -- Needs /played (requested when the panel opens) and a statistic that was found:
  -- nil means "not found on this client", 0 means "found, never used".
  local STONE_HOURS = 500
  local lols = T.Stat("lols")
  if lols == 0 and db.played and db.played >= STONE_HOURS * 3600 then
    local hours = math.floor(db.played / 3600)
    add("stoneface", damp(hours / STONE_HOURS), { n = BreakUpLargeNumbers(hours) }, true)
  end

  -- Emotes: gated on how many have been seen, not on time played
  local emotes, emoteTotal = db.emotes or {}, db.emoteTotal or 0
  if emoteTotal >= T.EMOTE_MIN then
    local tok, n = top(emotes)
    local share = n / emoteTotal
    if tok == "DANCE" and share >= 0.35 then
      add("dancer", share / 0.35, { n = BreakUpLargeNumbers(n), p = pct(share) })
    elseif tok and n >= 15 and share >= 0.25 then
      add("signature", share / 0.25, { emote = "/" .. tok:lower(), n = BreakUpLargeNumbers(n) })
    end
    local function groupShare(list)
      local sum = 0
      for _, t in ipairs(list) do sum = sum + (emotes[t] or 0) end
      return sum / emoteTotal
    end
    local polite, rude = groupShare(POLITE), groupShare(RUDE)
    if polite >= 0.4 then add("polite", polite / 0.4, { p = pct(polite) }) end
    if rude >= 0.3 then add("rude", rude / 0.3, { p = pct(rude) }) end
  end
  local solo, dances = db.soloDances or 0, emotes.DANCE or 0
  if solo >= 25 and dances > 0 and solo / dances >= 0.7 then
    -- A count that only grows: damp it so it can't hold the title forever
    add("solodancer", 1 + 0.25 * math.log(solo / 25), { n = BreakUpLargeNumbers(solo) })
  end

  if db.tracked >= T.MIN_TRACKED then
    -- When they play
    local night = sumRange(db.hours, 0, 4) / db.tracked
    local morning = sumRange(db.hours, 5, 8) / db.tracked
    local weekend = ((db.days[0] or 0) + (db.days[6] or 0)) / db.tracked
    local patterns = db.tracked >= T.MIN_PATTERN
    if patterns and night >= 0.3 then add("nightowl", night / 0.3, { p = pct(night) }) end
    if patterns and morning >= 0.3 then add("earlybird", morning / 0.3, { p = pct(morning) }) end
    -- Weekends are 2/7 (29%) of the week, so 60% is a real lean, not chance
    if patterns and weekend >= 0.6 then
      add("weekender", weekend / 0.6, { p = pct(weekend) })
    end

    -- Jumping while travelling
    local travelMin = db.travel / 60
    if travelMin >= 5 then
      local jpm = db.travelJumps / travelMin
      if jpm >= 8 then
        add("restless", jpm / 8, { n = math.floor(jpm + 0.5) })
      elseif jpm < 0.5 then
        add("grounded", 1.1, { n = ("%.1f"):format(jpm) })
      end
    end

    -- Standing still in town
    local idleShare = db.idleResting / db.tracked
    if idleShare >= 0.25 then
      local city = top(db.idleZones)
      add("cityslicker", idleShare / 0.25, { p = pct(idleShare), place = city or "town" })
    end

    -- Favourite haunt / wanderer
    local spot, spotT = top(db.zones)
    if spot and db.tracked >= T.MIN_PATTERN and spotT / db.tracked >= 0.2 then
      local share = spotT / db.tracked
      add("homebody", share / 0.2, { p = pct(share), place = placeName(spot) })
    end
    local places = count(db.zones)
    if places >= 60 then add("wanderer", places / 60, { n = places }) end

    -- Mounts
    if db.mounted >= 10 * 60 then
      local id, t = top(db.mounts)
      -- Loyalty only means something once there was a choice of mount
      if id and count(db.mounts) >= 2 and t / db.mounted >= 0.5 then
        local share = t / db.mounted
        add("loyal", share / 0.5, { p = pct(share), mount = T.MountName(id) })
      end
      local ridden = count(db.mounts)
      local need = ns.IS_FOREVER and 4 or 12
      if ridden >= need then add("collector", ridden / need, { n = ridden }) end

      -- Walking only counts as a choice once the character actually rides
      if db.travel >= 10 * 60 and db.onFoot / db.travel >= 0.6 then
        local share = db.onFoot / db.travel
        add("pedestrian", share / 0.6, { p = pct(share) })
      end
    end

    -- Falling
    if db.fallYards >= 2000 then
      add("gravityfan", db.fallYards / 2000, { n = BreakUpLargeNumbers(math.floor(db.fallYards)) })
    end
    if db.longestFall >= 6 then
      add("leap", db.longestFall / 6, { n = ("%.1f"):format(db.longestFall) })
    end
  end

  table.sort(out, function(a, b) return a.score > b.score end)
  return out
end

---------------------------------------------------------------------------
-- Framing text for the panel
---------------------------------------------------------------------------
-- The title comes from an observed habit when there is one; lifetime
-- statistics only name the character until the addon has seen enough.
function T.Headline(traits)
  for _, t in ipairs(traits) do
    if not t.lifetime then return t.epithet end
  end
  if traits[1] then return traits[1].epithet end
  return (who())
end

function T.EmptyText(db)
  local name = who()
  if db.tracked < T.MIN_TRACKED then
    return fill(pick("mystery", {
      "{name} is still a mystery. Give it another {t}.",
      "Too early to judge {name}. Check back in {t}.",
      "Still watching {name}. Another {t} and the habits will start to show.",
    }), { name = name, t = T.FmtTime(T.MIN_TRACKED - db.tracked) })
  end
  return fill(pick("normal", {
    "{name} is suspiciously well-adjusted. For now.",
    "Nothing odd about {name} yet. Nobody stays normal forever.",
  }), { name = name })
end
