# Runs Core.lua's sampler and events against a stubbed client: bag fullness
# (profession bags excluded, sampled once a minute), deaths by place, AFK time.
import sys
from lupa import LuaRuntime
lua = LuaRuntime()
lua.execute(r'''
NOW = 0
function GetTime() return NOW end
function time() return 0 end
date = os.date
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function hooksecurefunc() end
local frame = { scripts = {} }
function frame:RegisterEvent() end
function frame:UnregisterEvent() end
function frame:SetScript(k, f) self.scripts[k] = f end
function CreateFrame() return frame end
CORE = frame
ZONE, SUB = "Bastion", "Temple of Devotion"
function GetRealZoneText() return ZONE end
function GetSubZoneText() return SUB end
function IsFlying() return false end
function IsSwimming() return false end
function IsMounted() return false end
function IsFalling() return false end
function IsResting() return false end
function UnitAffectingCombat() return false end
function GetUnitSpeed() return 0 end
AFK = false
function UnitIsAFK() return AFK end
NUM_BAG_SLOTS = 4
-- backpack 16 (2 free), bag 1: 20 (full), bag 2: profession bag 30 (all free), bag 3: empty slot
local bags = { [0] = { 16, 2, 0 }, [1] = { 20, 0, 0 }, [2] = { 30, 30, 8 }, [3] = { 0, 0, 0 } }
PET = "BattlePet-0-1"
C_PetJournal = {
  GetSummonedPetGUID = function() return PET end,
  GetPetInfoByPetID = function(guid) return 42, "Mr Whiskers", 25, 0, 0, 0, false, "Black Tabby Cat" end,
}
C_Container = {
  GetContainerNumSlots = function(b) return bags[b] and bags[b][1] or 0 end,
  GetContainerNumFreeSlots = function(b) local x = bags[b]; if x then return x[2], x[3] end return 0, 0 end,
}
''')
ns = lua.table()
lua.eval('function(src, ns) return load(src, "Core.lua")("Persona", ns) end')(open(sys.argv[1]).read(), ns)
ev = lua.eval('function(e, a) CORE.scripts.OnEvent(CORE, e, a) end')
tick = lua.eval('function(now) NOW = now; CORE.scripts.OnUpdate(CORE, 0.3) end')
ev("ADDON_LOADED", "Persona")
ev("PLAYER_ENTERING_WORLD", None)
db = lua.globals().PersonaDB

# Bags: first sample once 60s have passed, then at most one a minute
tick(30);  assert db.bagSamples == 0, "no sample before a minute"
tick(60);  assert db.bagSamples == 1
tick(90);  assert db.bagSamples == 1, "only once a minute"
tick(121); assert db.bagSamples == 2
full = db.bagFull / db.bagSamples
assert abs(full - 34 / 36) < 1e-9, f"profession bag excluded: expected 34/36, got {full}"
print("ok: bag fullness, profession bags excluded, once a minute")

# Deaths by place
ev("PLAYER_DEAD", None); ev("PLAYER_DEAD", None)
lua.execute('SUB = "Aspirant\'s Crucible"'); ev("ZONE_CHANGED", None)
ev("PLAYER_DEAD", None)
assert db.deathsSeen == 3
assert db.deathZones["Bastion - Temple of Devotion"] == 2 and db.deathZones["Bastion - Aspirant's Crucible"] == 1
print("ok: deaths counted by place")

# AFK: on at 200, off at 500 (300s); other units ignored; logout while AFK counts
lua.execute("NOW = 200; AFK = true");  ev("PLAYER_FLAGS_CHANGED", "player")
lua.execute("NOW = 300");              ev("PLAYER_FLAGS_CHANGED", "party1")
lua.execute("NOW = 500; AFK = false"); ev("PLAYER_FLAGS_CHANGED", "player")
assert db.afkCount == 1 and db.afkTime == 300, (db.afkCount, db.afkTime)
lua.execute("NOW = 600; AFK = true");  ev("PLAYER_FLAGS_CHANGED", "player")
lua.execute("NOW = 650");              ev("PLAYER_FLAGS_CHANGED", "player")   # still AFK: no double count
lua.execute("NOW = 660");              ev("PLAYER_LOGOUT", None)
assert db.afkCount == 2 and db.afkTime == 360, (db.afkCount, db.afkTime)
print("ok: AFK periods, other units ignored, logout while AFK")

# Companion pets: credited every 5 seconds with the time since the last check
pets_before = db.petTime
for i in range(20):                       # 20 ticks of 0.3s = 6s
    lua.execute(f"NOW = {1000 + i}"); core_tick = lua.eval('function() CORE.scripts.OnUpdate(CORE, 0.3) end'); core_tick()
assert abs(db.petTime - pets_before - 5.1) < 1e-6 or abs(db.petTime - pets_before - 5.4) < 1e-6, db.petTime
assert db.pets[42] == db.petTime and db.petNames[42] == "Mr Whiskers", "custom name preferred"
lua.execute('PET = nil')
before = db.petTime
for i in range(40):
    lua.execute(f"NOW = {2000 + i}"); core_tick()
assert db.petTime == before, "no companion out: nothing credited"
lua.execute('C_PetJournal = nil')
for i in range(40):
    lua.execute(f"NOW = {3000 + i}"); core_tick()
print("ok: companion time and custom names; no pet or no pet journal: nothing recorded, no errors")
