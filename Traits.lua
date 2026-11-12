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
      "Walking is for other people. {name} hops along at {n} jumps a minute.",
      "{n} jumps a minute on the move. {name}'s knees have filed a complaint.",
    },
  },
  grounded = {
    label = "Grounded",
    epithet = "{name} the Composed",
    lines = {
      "{name} walks like someone with places to be. Barely {n} jumps a minute.",
      "Feet on the ground, always. {name} manages {n} jumps a minute on the move.",
      "{name} keeps both feet on the ground: {n} jumps a minute, if that.",
      "Jumping is beneath {name}. {n} jumps a minute on the road.",
      "{name} travels with quiet dignity. {n} jumps a minute, all of them necessary.",
    },
  },
  cityslicker = {
    label = "City Slicker",
    epithet = "{name}, Idler of {place}",
    lines = {
      "{name} spends {p}% of {his} time standing perfectly still in town, mostly in {place}. Waiting for something. Or someone.",
      "Need {name}? Try {place}. {p}% of {his} playtime is spent in town doing absolutely nothing.",
      "{p}% of {name}'s life is spent idling in town. The guards in {place} know {his} face by now.",
      "{name} could give tours of {place}. {p}% of {his} time is spent standing around in town.",
      "Some adventurers adventure. {name} stands in {place}: {p}% of all {his} time, idle in town.",
    },
  },
  homebody = {
    label = "Homebody",
    epithet = "{name} the Homebody",
    lines = {
      "{name} has a favourite spot: {place}. {p}% of {his} life happens there.",
      "{name} keeps coming back to {place}: {p}% of all {his} time is spent there.",
      "{place} is where {name} feels at home: {p}% of {his} time is spent there.",
      "All roads lead {name} back to {place}: {p}% of {his} time.",
      "{name} could draw {place} from memory. {p}% of {his} life happens there.",
    },
  },
  wanderer = {
    label = "Wanderer",
    epithet = "{name} the Wanderer",
    lines = {
      "{name} has set foot in {n} different places and shows no sign of stopping.",
      "{n} places visited. {name} doesn't stay anywhere long.",
      "{name} has seen {n} different corners of the world and wants to see more.",
      "{n} places and counting. Staying put isn't {name}'s style.",
      "Maps were made for people like {name}: {n} places visited so far.",
    },
  },
  loyal = {
    label = "Loyal",
    epithet = "{name}, Rider of {mount}",
    lines = {
      "{name} and {mount} are inseparable: {p}% of all riding time.",
      "Other mounts exist. {name} has heard of them. Still rides {mount} {p}% of the time.",
      "{name} rides {mount} {p}% of the time. The rest of the stable is gathering dust.",
      "Whatever the journey, {name} takes {mount}: {p}% of all riding time.",
      "{mount} has carried {name} for {p}% of all {his} riding. True love.",
    },
  },
  collector = {
    label = "Stable Master",
    epithet = "{name} the Collector",
    lines = {
      "{name} can't pick a favourite. {n} different mounts ridden so far.",
      "A mount for every mood: {name} has ridden {n} of them.",
      "{name} has ridden {n} different mounts. The stable master sends a card every holiday.",
      "{n} mounts ridden. {name} believes every outfit needs a matching mount.",
      "Why ride one mount when {name} can ride {n}?",
    },
  },
  pedestrian = {
    label = "Pedestrian",
    epithet = "{name} the Footsore",
    lines = {
      "{name} owns mounts but prefers to walk. {p}% of {his} ground travel is on foot.",
      "Mounts are for other people. {name} walks {p}% of the way.",
      "{name} walks {p}% of the way. The mounts wait patiently at home.",
      "{p}% of {name}'s travel happens on foot. Bootmakers love {name}.",
      "{name} prefers to see the world at walking pace: {p}% of {his} ground travel is on foot.",
    },
  },
  gravityfan = {
    label = "Gravity Enthusiast",
    epithet = "{name}, Friend of Gravity",
    lines = {
      "{name} has fallen roughly {n} yards. Nobody has asked why.",
      "Gravity and {name} go way back: about {n} yards fallen.",
      "About {n} yards fallen so far. {name} takes the scenic route down.",
      "{name} has dropped roughly {n} yards. Stairs are for the cautious.",
      "Roughly {n} yards of falling. {name} and the ground keep meeting unexpectedly.",
    },
  },
  leap = {
    label = "Leap of Faith",
    epithet = "{name} the Bold",
    lines = {
      "{name}'s longest fall lasted {n} seconds. Long enough to reconsider several decisions.",
      "{n} seconds in free fall, once. {name} still talks about it.",
      "{name} once fell for {n} seconds and landed on {his} feet. Probably.",
      "The record: {n} seconds of free fall. {name} calls it a shortcut.",
      "{n} seconds in the air, once. {name} had time to think about lunch.",
    },
  },
  gravityvictim = {
    label = "Gravity Victim",
    epithet = "{name}, Slain by Floors",
    lines = {
      "The floor has killed {name} {f} times. That's {p}% of all {his} deaths.",
      "{p}% of {name}'s {d} deaths were the floor's fault, not the enemy's.",
      "{name} has been killed by the floor {f} times: {p}% of all {his} deaths.",
      "Bosses, dragons, demons: none of them have killed {name} like the ground has. {f} times so far.",
      "{p}% of {name}'s deaths came from falling. The floor remains undefeated.",
    },
  },
  -- Lifetime statistics
  quitter = {
    label = "Commitment Issues",
    epithet = "{name} the Undecided",
    lines = {
      "{name} has abandoned {n} quests, {p}% of every quest {his} journal has ever held.",
      "{n} quests abandoned. {name} prefers to keep {his} options open.",
      "{name} has a habit of starting things. {n} quests abandoned so far.",
      "{n} quests left unfinished. {name} will get back to them. Probably.",
      "Quest givers across Azeroth are still waiting on {name}: {n} quests abandoned.",
    },
  },
  menace = {
    label = "Menace to Wildlife",
    epithet = "{name}, Bane of Squirrels",
    lines = {
      "{n} critters have died at {name}'s hands. The rabbits speak of {name} only in whispers.",
      "{name} has killed {n} critters. None of them were a threat.",
      "{name} has killed {n} critters. The squirrels have started a support group.",
      "{n} critters lost to {name}. None of them saw it coming.",
      "Rabbits, frogs, squirrels: {n} of them, all by {name}'s hand.",
    },
  },
  hugger = {
    label = "The Hugger",
    epithet = "{name} the Warm",
    lines = {
      "{name} has hugged {n} times. Nobody is safe.",
      "{n} hugs given. {name} is a lot, but in a nice way.",
      "{n} hugs and counting. {name} has never met a stranger.",
      "{name} has hugged {n} times. Personal space is a suggestion.",
      "Everyone gets a hug from {name}. {n} so far.",
    },
  },
  joker = {
    label = "Easily Amused",
    epithet = "{name} the Giggling",
    lines = {
      "{name} has /lol'd {n} times. Not everything was that funny.",
      "{n} laughs on record. {name} is a generous audience.",
      "{name} laughs easily: {n} laughs so far.",
      "{n} times, {name} has found something hilarious. Usually a wipe.",
      "Tell {name} a joke. Any joke. {n} laughs on record.",
    },
  },
  exasperated = {
    label = "Exasperated",
    epithet = "{name} the Long-Suffering",
    lines = {
      "{name} has facepalmed {n} times. Group content has not been kind.",
      "{n} facepalms. {name} has seen things.",
      "{n} facepalms on record. {name} expected better from all of you.",
      "{name} has facepalmed {n} times. Some of them were deserved.",
      "Every facepalm tells a story. {name} has {n} of them.",
    },
  },
  friendly = {
    label = "Friendly",
    epithet = "{name} the Neighbourly",
    lines = {
      "{name} has waved {n} times. Strangers included.",
      "{n} waves and counting. {name} greets everyone.",
      "{n} waves on record. {name} never passes anyone without saying hello.",
      "{name} has waved {n} times. Most of them were waved back.",
      "Hello, hello, hello: {name} has waved {n} times.",
    },
  },
  cheerleader = {
    label = "Cheerleader",
    epithet = "{name} the Encouraging",
    lines = {
      "{name} has cheered {n} times. Every win counts, apparently.",
      "{n} cheers on record. {name} is everyone's biggest fan.",
      "{name} has cheered {n} times. No achievement goes unnoticed.",
      "{n} cheers so far. {name} brings the energy.",
      "Someone has to celebrate. {name} has cheered {n} times.",
    },
  },
  sardonic = {
    label = "Sardonic",
    epithet = "{name} the Unimpressed",
    lines = {
      "{name} has played the world's smallest violin {n} times. Sympathy is in short supply.",
      "{n} tiny violin performances. {name} has heard your complaint.",
      "{name} keeps a very small violin ready at all times. {n} performances so far.",
      "{n} renditions of the world's smallest violin. {name} has heard it all before.",
      "Your complaint has been noted. {name} has played the tiny violin {n} times.",
    },
  },
  stoneface = {
    label = "Stone-Faced",
    epithet = "{name} the Unamused",
    lines = {
      "{n} hours played, and {name} has never once /lol'd.",
      "{name} has seen everything Azeroth has to offer in {n} hours. None of it was funny.",
      "{n} hours. Not a single laugh. {name} is a tough crowd.",
      "{n} hours in Azeroth, and not one /lol. {name} is very hard to impress.",
      "Gnomes, goblins, murlocs: {n} hours of it, and {name} has never laughed once.",
    },
  },
  -- Emotes (counted since install)
  signature = {
    label = "Signature Move",
    epithet = "{name}, Master of {emote}",
    lines = {
      "{name}'s signature move is {emote}, used {n} times and counting.",
      "Ask {name} anything. The answer is usually {emote} ({n} times so far).",
      "{name} says it best with {emote}: {n} times so far.",
      "{emote} is {name}'s go-to. {n} times and counting.",
      "If {name} had a catchphrase, it would be {emote}. Used {n} times.",
    },
  },
  dancer = {
    label = "Dancer",
    epithet = "{name} the Dancer",
    lines = {
      "{name} has danced {n} times, {p}% of all {his} emotes.",
      "When in doubt, {name} dances. {n} times and counting.",
      "{name} dances first and asks questions later. {n} dances so far.",
      "{p}% of {name}'s emotes are dancing. Every occasion is a dance occasion.",
      "{n} dances on record. {name} doesn't need music.",
    },
  },
  polite = {
    label = "Polite",
    epithet = "{name} the Courteous",
    lines = {
      "{p}% of {name}'s emotes are bows, thanks and salutes. Somebody raised {name} well.",
      "{name} is unfailingly polite: {p}% of all emotes are courtesies.",
      "{name} always minds {his} manners: {p}% of all emotes are courtesies.",
      "Bow, thank, salute: {p}% of {name}'s emotes. A credit to the realm.",
      "{p}% of {name}'s emotes are polite ones. Grandma would be proud.",
    },
  },
  rude = {
    label = "Rude",
    epithet = "{name} the Insufferable",
    lines = {
      "{p}% of {name}'s emotes are rude. The innkeepers have been warned.",
      "{name} communicates mainly in rude gestures: {p}% of all emotes.",
      "{name} has a gesture for every occasion, and {p}% of them are rude.",
      "{p}% of {name}'s emotes are rude. The tavern keeps a portrait behind the bar.",
      "Manners are optional for {name}: {p}% of all emotes are rude ones.",
    },
  },
  solodancer = {
    label = "Dances Alone",
    epithet = "{name}, Who Dances Alone",
    lines = {
      "{name} has danced alone {n} times. No target, no group, no audience.",
      "{n} solo dances. {name} doesn't need anyone else to have a good time.",
      "{n} dances, nobody watching. {name} dances for the joy of it.",
      "No partner, no group, no problem. {name} has danced alone {n} times.",
      "{name} has danced solo {n} times. The best audience is no audience.",
    },
  },
  -- Bags, deaths and breaks (observed since install)
  hoarder = {
    label = "Hoarder",
    epithet = "{name} the Packrat",
    lines = {
      "{name}'s bags are {p}% full on average. Nothing gets thrown away.",
      "Every slot spoken for: {name}'s bags average {p}% full.",
      "{name} might need that later. Bags {p}% full, on average.",
      "{p}% full, all the time. {name}'s bags are a museum.",
      "{name} has never met a grey item {his} bags couldn't hold. {p}% full on average.",
    },
  },
  travelslight = {
    label = "Travels Light",
    epithet = "{name} the Unburdened",
    lines = {
      "{name}'s bags are only {p}% full on average. Everything has a place, and most places are empty.",
      "{name} sells everything. Bags average just {p}% full.",
      "Light bags, light heart: {name}'s bags sit at {p}% full.",
      "Only {p}% full. {name} vendors first and asks questions never.",
      "{name} carries only what matters. Bags {p}% full on average.",
    },
  },
  nemesis = {
    label = "Nemesis",
    epithet = "{name}, Doomed in {place}",
    lines = {
      "{place} has it in for {name}: {n} of {his} {d} recent deaths happened there.",
      "{name} has died {n} times in {place}. It's starting to feel personal.",
      "Of {name}'s {d} recent deaths, {n} were in {place}. Every story needs a villain.",
      "{place} has claimed {name} {n} times. The spirit healer waves hello.",
      "{n} deaths in {place} alone. {name} keeps going back anyway.",
    },
  },
  wandersoff = {
    label = "Easily Distracted",
    epithet = "{name} the Elsewhere",
    lines = {
      "{name} has gone AFK {n} times. {p}% of {his} time online is spent somewhere else.",
      "Back in five. {name} has said it {n} times, and been away for {t} in total.",
      "{p}% of {name}'s playtime is AFK. The kettle needs a lot of attention.",
      "{name} has wandered off {n} times. Azeroth waits patiently.",
      "{t} AFK across {n} breaks. {name} has a life outside Azeroth, apparently.",
    },
  },
  -- Signature moves: class and racial abilities used outside combat (Moves.lua)
  taxi = {
    label = "Taxi Service",
    epithet = "{name}, Keeper of Portals",
    lines = {
      "{name} has opened {n} portals. Most of them for strangers who didn't say thanks.",
      "{n} portals and counting. {name} should really start charging.",
      "Need a lift? {name} has opened {n} portals so far.",
      "{name} has opened {n} portals. The fare is a bottle of water, apparently.",
      "{n} portals opened. Somewhere, a queue is forming in front of {name}.",
    },
  },
  summoner = {
    label = "Summoning Circle",
    epithet = "{name} the Summoner",
    lines = {
      "{name} has summoned {n} times. Nobody walks to the dungeon on {his} watch.",
      "{n} summons cast. {name} is the reason the group arrived on time.",
      "{name} has dragged people across Azeroth {n} times. Click the portal, please.",
      "Ritual of Summoning, {n} times. {name} just needs two more clicks.",
      "{n} summons and counting. Every group needs someone like {name}.",
    },
  },
  nohorse = {
    label = "Never Owned a Horse",
    epithet = "{name} the Shapeshifter",
    lines = {
      "{p}% of {name}'s ground travel happens in animal form. Mounts are for other people.",
      "Why buy a mount? {name} covers {p}% of the road on four legs of {his} own.",
      "{name} prefers {his} own legs, all four of them: {p}% of ground travel in animal form.",
      "{p}% of the time, {name} gets around in animal form. The stable master has given up.",
      "{name} has never needed a saddle. {p}% of {his} ground travel is in animal form.",
    },
  },
  lurker = {
    label = "Lurker",
    epithet = "{name} the Unseen",
    lines = {
      "{name} spends {p}% of {his} time stealthed, mostly hiding from nobody in particular.",
      "{t} spent in stealth outside combat. {name} likes to watch.",
      "You might not have seen {name}. That's the point: {p}% of {his} time is spent stealthed.",
      "{p}% of {name}'s time is spent out of sight. Old habits.",
      "{name} has lurked for {t} without a fight in sight.",
    },
  },
  dramaqueen = {
    label = "Drama Queen",
    epithet = "{name} the Melodramatic",
    lines = {
      "{name} has played dead {n} times with nothing attacking. Very convincing.",
      "{n} Feign Deaths with no enemy in sight. {name} just likes lying down.",
      "{name} has collapsed dramatically {n} times for no reason at all.",
      "{n} times, {name} has dropped dead in front of nobody. An award-worthy performance.",
      "Nothing was attacking. {name} feigned death anyway, {n} times.",
    },
  },
  hider = {
    label = "Hiding From Nobody",
    epithet = "{name} of the Shadows",
    lines = {
      "{name} has vanished into the shadows in town {n} times. Nobody was looking.",
      "{n} Shadowmelds in the middle of town. {name} is avoiding someone.",
      "{name} hides in plain sight: {n} Shadowmelds in town so far.",
      "Shadowmeld, in town, {n} times. Whoever {name} is hiding from hasn't noticed.",
      "{n} times, {name} has melted into the shadows at the bank. Very mysterious.",
    },
  },
  wildrunner = {
    label = "Runs With the Pack",
    epithet = "{name} the Untamed",
    lines = {
      "{name} has dropped to all fours {n} times. Who needs a mount?",
      "{n} times Running Wild. {name} prefers the original model.",
      "{name} has run wild {n} times and counting. The tailor despairs.",
      "Mounts are fine, but {name} has gone Running Wild {n} times.",
      "{n} sprints on all fours. {name} hasn't fully settled into city life.",
    },
  },
  rocketeer = {
    label = "Rocket Commuter",
    epithet = "{name} the Airborne",
    lines = {
      "{name} has rocket-jumped {n} times. Walking is so slow.",
      "{n} Rocket Jumps outside combat. {name} commutes by explosion.",
      "Why take the stairs? {name} has rocket-jumped {n} times.",
      "{name} has launched into the air {n} times. Landing optional.",
      "{n} rocket jumps and no injuries reported. {name} is very lucky.",
    },
  },
  camper = {
    label = "Happy Camper",
    epithet = "{name} of the Campfire",
    lines = {
      "{name} has made camp {n} times. Anywhere can be home.",
      "{n} camps pitched. {name} is always ready to put the kettle on.",
      "{name} has set up camp {n} times. The inns are losing money.",
      "Tent, fire, nap: {name} has made camp {n} times.",
      "{n} campfires and counting. {name} never stays at an inn.",
    },
  },
  soarer = {
    label = "Born to Soar",
    epithet = "{name} of the Skies",
    lines = {
      "{name} has taken to the skies {n} times. Mounts are for the wingless.",
      "{n} Soars and counting. {name} doesn't do stairs.",
      "{name} has soared {n} times. The ground is just somewhere to land.",
      "Wings out, {n} times. {name} has never once waited for a flight path.",
      "{n} take-offs. {name} has a complicated relationship with the ground.",
    },
  },
  stomper = {
    label = "Stomps for Fun",
    epithet = "{name} the Thunderous",
    lines = {
      "{name} has War Stomped {n} times with nothing to stomp. The floor had it coming.",
      "{n} War Stomps outside combat. {name} likes to make an entrance.",
      "{name} stomps for fun: {n} times with no enemy in sight.",
      "The ground shakes, {n} times, for no reason. That's just {name}.",
      "{n} stomps and nobody stunned. {name} is just expressing {his} feelings.",
    },
  },
  escapee = {
    label = "Escape Artist",
    epithet = "{name} the Slippery",
    lines = {
      "{name} has escaped {n} times from absolutely nothing.",
      "{n} escapes, zero captors. {name} likes to stay in practice.",
      "{name} has wriggled free {n} times. Nothing was holding on.",
      "Escape Artist, used {n} times outside combat. {name} trusts nobody.",
      "{n} times, {name} has escaped from an empty room.",
    },
  },
  -- Companion pets (observed since install)
  neveralone = {
    label = "Never Alone",
    epithet = "{name} and Friends",
    lines = {
      "{name} always brings a friend: a companion is out {p}% of the time.",
      "{p}% of {name}'s adventures come with a tiny sidekick.",
      "Wherever {name} goes, something small follows. {p}% of the time, anyway.",
      "{name} never travels alone. A companion trots along {p}% of the time.",
      "A companion is out {p}% of the time. {name} likes the company.",
    },
  },
  bestfriend = {
    label = "Best Friends",
    epithet = "{name}, Keeper of {pet}",
    lines = {
      "{pet} has been at {name}'s side for {t}. The others are a bit jealous.",
      "{name} and {pet} go everywhere together: {p}% of all companion time.",
      "Other pets exist. {name} only has eyes for {pet}.",
      "{pet} goes everywhere with {name}. {t} so far.",
      "{p}% of {name}'s companion time belongs to {pet}. Inseparable.",
    },
  },
  menagerie = {
    label = "Menagerie",
    epithet = "{name} the Zookeeper",
    lines = {
      "{name} has brought {n} different companions along. Nobody gets left out.",
      "{n} companions and counting. {name} rotates them fairly.",
      "{name} can't pick a favourite pet. {n} have had a turn so far.",
      "A different friend every day: {n} companions out with {name} so far.",
      "{n} companions have travelled with {name}. The stable is getting crowded.",
    },
  },
  -- Combat pets (observed since install)
  oldfriend = {
    label = "Old Friend",
    epithet = "{name} and {pet}",
    lines = {
      "{pet} has fought beside {name} for {t}. Some bonds don't break.",
      "{name} and {pet}: {p}% of all {his} time with a pet out. Partners for life.",
      "Other pets have come and gone. {pet} stays at {name}'s side.",
      "{t} of {pet} at {name}'s side. Loyalty works both ways.",
      "{name} trusts one pet above all others: {pet}, out {p}% of the time.",
    },
  },
  beaststable = {
    label = "Stable of Beasts",
    epithet = "{name} the Beastmaster",
    lines = {
      "{name} has fought alongside {n} different pets. Every one has a story.",
      "{n} pets and counting. {name} likes to mix things up.",
      "{name}'s stable holds {n} veterans so far.",
      "A pet for every occasion: {n} have fought with {name}.",
      "{n} different pets have had {name}'s back.",
    },
  },
  lonewolf = {
    label = "Lone Wolf",
    epithet = "{name} the Lone Wolf",
    lines = {
      "{name} prefers to hunt alone. A pet is out only {p}% of the time.",
      "Pets are a distraction. {name} has one out just {p}% of the time.",
      "{name} works alone. The stable master hasn't seen {his} pets in a while.",
      "Only {p}% of the time with a pet out. {name} does the hunting personally.",
      "{name} keeps the pets at home: out just {p}% of the time.",
    },
  },
  -- When they play
  nightowl = {
    label = "Night Owl",
    epithet = "{name} of the Small Hours",
    lines = {
      "{p}% of {name}'s adventures happen between midnight and 5am. Sleep is for NPCs.",
      "{name} does {his} best work after midnight: {p}% of all play.",
      "{p}% of {name}'s play happens after midnight. The moon knows {name} well.",
      "While the world sleeps, {name} plays: {p}% of all adventures happen between midnight and 5am.",
      "{name} keeps vampire hours. {p}% of {his} play is between midnight and 5am.",
    },
  },
  earlybird = {
    label = "Early Bird",
    epithet = "{name} the Dawnwalker",
    lines = {
      "{name} is up before the world: {p}% of play happens between 5am and 9am.",
      "{p}% of {name}'s adventures start before breakfast.",
      "{name} logs in with the sunrise. {p}% of play happens between 5am and 9am.",
      "Coffee, then Azeroth. {p}% of {name}'s play happens between 5am and 9am.",
      "{p}% of {name}'s adventures start between 5am and 9am. The early bird gets the loot.",
    },
  },
  weekender = {
    label = "Weekend Warrior",
    epithet = "{name}, Saturday's Hero",
    lines = {
      "{name} saves the world on weekends: {p}% of {his} play is Saturday and Sunday.",
      "Weekdays belong to someone else. {p}% of {name}'s play happens at the weekend.",
      "{p}% of {name}'s play is on Saturdays and Sundays. The weekend is sacred.",
      "Monday to Friday, {name} is somebody else. {p}% of play happens at the weekend.",
      "{name} saves Azeroth on weekends: {p}% of all play.",
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

  -- Signature moves: counts only grow, so they're damped like lifetime statistics
  local moves = db.moves or {}
  local MOVE_TRAITS = {
    { "taxi", "portal", 10 }, { "summoner", "summon", 10 }, { "dramaqueen", "feign", 10 },
    { "hider", "shadowmeld", 10 }, { "wildrunner", "runwild", 20 }, { "rocketeer", "rocketjump", 25 },
    { "camper", "camp", 10 }, { "soarer", "soar", 25 }, { "stomper", "stomp", 10 }, { "escapee", "escape", 10 },
  }
  for _, m in ipairs(MOVE_TRAITS) do
    local n = moves[m[2]] or 0
    if n >= m[3] then
      add(m[1], 1 + 0.25 * math.log(n / m[3]), { n = BreakUpLargeNumbers(n) })
    end
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

    -- Bags: an hour of once-a-minute samples
    if (db.bagSamples or 0) >= 60 then
      local full = db.bagFull / db.bagSamples
      if full >= 0.9 then
        add("hoarder", 1 + (full - 0.9) * 10, { p = pct(full) })
      elseif full <= 0.35 then
        add("travelslight", 1 + (0.35 - full) * 4, { p = pct(full) })
      end
    end

    -- Where you die: 5+ observed deaths, 40%+ of them in one place
    if (db.deathsSeen or 0) >= 5 then
      local spot, n = top(db.deathZones or {})
      if spot and n >= 3 and n / db.deathsSeen >= 0.4 then
        add("nemesis", (n / db.deathsSeen) / 0.4, { n = n, d = db.deathsSeen, place = placeName(spot) })
      end
    end

    -- AFK: 3h observed, 5+ breaks, 10%+ of the time away
    if db.tracked >= T.MIN_PATTERN and (db.afkCount or 0) >= 5 then
      local share = (db.afkTime or 0) / db.tracked
      if share >= 0.1 then
        add("wandersoff", share / 0.1, { n = db.afkCount, p = pct(share), t = T.FmtTime(db.afkTime) })
      end
    end

    -- Animal-form travel: half the ground travel, and at least half an hour of it
    local formTravel = db.formTravel or 0
    if formTravel >= 1800 and db.travel > 0 and formTravel / db.travel >= 0.5 then
      local share = formTravel / db.travel
      add("nohorse", share / 0.5, { p = pct(share) })
    end

    -- Stealth outside combat: 10% of the time, at least half an hour
    local stealth = db.stealthTime or 0
    if stealth >= 1800 and stealth / db.tracked >= 0.1 then
      add("lurker", (stealth / db.tracked) / 0.1, { p = pct(stealth / db.tracked), t = T.FmtTime(stealth) })
    end

    -- Companion pets: share of time with one out, a favourite, or sheer variety
    local petTime = db.petTime or 0
    if petTime / db.tracked >= 0.5 then
      add("neveralone", (petTime / db.tracked) / 0.5, { p = pct(petTime / db.tracked) })
    end
    if petTime >= 3600 then
      local species, t = top(db.pets or {})
      if species and count(db.pets) >= 2 and t / petTime >= 0.6 then
        local names = db.petNames or {}
        local petName = names[species] or "a companion"
        add("bestfriend", (t / petTime) / 0.6, { pet = petName, p = pct(t / petTime), t = T.FmtTime(t) })
      end
    end
    local kinds = count(db.pets or {})
    if kinds >= 15 then add("menagerie", 1 + 0.25 * math.log(kinds / 15), { n = kinds }) end

    -- Combat pets: one favourite, a big stable, or (hunters only) hardly any pet at all
    local combatTime = db.combatPetTime or 0
    if combatTime >= 2 * 3600 then
      local pet, t = top(db.combatPets or {})
      if pet and t / combatTime >= 0.7 then
        add("oldfriend", (t / combatTime) / 0.7, { pet = pet, p = pct(t / combatTime), t = T.FmtTime(t) })
      end
    end
    -- Hunter-only: other classes' pets (a Death Knight's ghoul, say) may get a new
    -- name each summon, which would look like a big stable
    local classFile = UnitClass and select(2, UnitClass("player"))
    local stable = count(db.combatPets or {})
    if classFile == "HUNTER" and stable >= 8 then
      add("beaststable", 1 + 0.25 * math.log(stable / 8), { n = stable })
    end
    if classFile == "HUNTER" and db.tracked >= T.MIN_PATTERN and combatTime / db.tracked < 0.1 then
      add("lonewolf", 1.2, { p = pct(combatTime / db.tracked) })
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

  -- Traits that contradict each other as personality, even when the data
  -- supports both: keep only the stronger of each pair.
  local OPPOSITES = { { "homebody", "wanderer" }, { "nightowl", "earlybird" }, { "oldfriend", "lonewolf" } }
  local byId = {}
  for i, t in ipairs(out) do byId[t.id] = i end
  local drop = {}
  for _, pair in ipairs(OPPOSITES) do
    local a, b = byId[pair[1]], byId[pair[2]]
    if a and b then drop[out[a].score >= out[b].score and b or a] = true end
  end
  local kept = {}
  for i, t in ipairs(out) do
    if not drop[i] then kept[#kept + 1] = t end
  end

  table.sort(kept, function(x, y) return x.score > y.score end)
  return kept
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
