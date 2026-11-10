# Signature moves: Core.lua + Moves.lua + Traits.lua against a stubbed client.
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
function BreakUpLargeNumbers(n) return tostring(n) end
function UnitName() return "Thrall" end
function UnitSex() return 2 end
FRAMES = {}
local Frame = {}
Frame.__index = Frame
function Frame:RegisterEvent() end
function Frame:RegisterUnitEvent() end
function Frame:UnregisterEvent() end
function Frame:SetScript(k, f) self[k] = f end
function CreateFrame() local f = setmetatable({}, Frame); FRAMES[#FRAMES + 1] = f; return f end
function GetRealZoneText() return "Orgrimmar" end
function GetSubZoneText() return "" end
function IsFlying() return false end
function IsSwimming() return false end
function IsMounted() return false end
function IsFalling() return false end
RESTING, COMBAT, SPEED, FORM, STEALTHED = true, false, 0, nil, false
function IsResting() return RESTING end
function UnitAffectingCombat() return COMBAT end
function GetUnitSpeed() return SPEED end
function GetShapeshiftFormID() return FORM end
function IsStealthed() return STEALTHED end
function UnitIsAFK() return false end
-- Spellbook flyouts: 11 is the mage portal flyout (contains Portal: Stormwind),
-- 12 is some other flyout that must not count
local flyouts = { [11] = { 10059, 446534, 395289 }, [12] = { 99999 } }
function GetFlyoutInfo(id) local f = flyouts[id]; if f then return "Flyout", "", #f, true end end
function GetFlyoutSlotInfo(id, slot) return flyouts[id][slot] end
''')
ns = lua.table()
load = lua.eval('function(src, name, ns) return load(src, name)("Persona", ns) end')
for f in ("Core.lua", "Moves.lua", "Traits.lua"):
    load(open(f).read(), f, ns)
core, moves_frame = lua.globals().FRAMES[1], lua.globals().FRAMES[2]
core.OnEvent(core, "ADDON_LOADED", "Persona")
core.OnEvent(core, "PLAYER_ENTERING_WORLD")
db = lua.globals().PersonaDB
cast = lua.eval('function(f, id) f.OnEvent(f, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid", id) end')
setv = lua.execute

def count(key): return (db.moves[key] or 0)

# Out of combat, in town
cast(moves_frame, 58984); assert count("shadowmeld") == 1, "Shadowmeld in town"
cast(moves_frame, 20580); assert count("shadowmeld") == 2, "Forever's Shadowmeld ID"
cast(moves_frame, 5384);  assert count("feign") == 1
cast(moves_frame, 8690);  cast(moves_frame, 467455)       # hearthstone, then NoCho
assert sum(db.moves.values()) == 3, "hearthstone and hidden spells ignored"
# Shadowmeld outside town doesn't count; nothing counts in combat
setv("RESTING = false"); cast(moves_frame, 58984); assert count("shadowmeld") == 2
setv("RESTING = true; COMBAT = true"); cast(moves_frame, 5384); cast(moves_frame, 58984)
assert count("feign") == 1 and count("shadowmeld") == 2, "in-combat casts ignored"
setv("COMBAT = false")
# Another unit's cast is ignored
moves_frame.OnEvent(moves_frame, "UNIT_SPELLCAST_SUCCEEDED", "party1", "guid", 5384)
assert count("feign") == 1
# Secret spell IDs are ignored
setv("function issecretvalue(v) return v == 5384 end"); cast(moves_frame, 5384); setv("issecretvalue = nil")
assert count("feign") == 1, "secret spell ID ignored"
print("ok: out-of-combat casts counted, town rule, hidden and other-unit casts ignored")

# Portals: the classic list, and newer ones from the flyout that holds Portal: Stormwind
cast(moves_frame, 11417)                  # Portal: Orgrimmar, from the fixed list
cast(moves_frame, 446534)                 # a modern portal, only known via the flyout
cast(moves_frame, 99999)                  # a spell in an unrelated flyout
assert count("portal") == 2, count("portal")
print("ok: portals from the fixed list and the spellbook flyout; unrelated flyouts ignored")

# Sampler: animal form isn't walking; stealth only counts out of combat
tick = lua.eval('function(now) NOW = now; FRAMES[1].OnUpdate(FRAMES[1], 1) end')
setv("SPEED = 7; FORM = 3")
for t in range(1, 11): tick(t)
assert db.formTravel == 10 and db.onFoot == 0, (db.formTravel, db.onFoot)
setv("FORM = nil")
for t in range(11, 16): tick(t)
assert db.onFoot == 5 and db.formTravel == 10
setv("SPEED = 0; STEALTHED = true")
for t in range(16, 21): tick(t)
setv("COMBAT = true")
for t in range(21, 26): tick(t)
assert db.stealthTime == 5, db.stealthTime
setv("COMBAT = false; STEALTHED = false")
print("ok: animal-form travel counted and not walking; stealth outside combat only")

# Traits fire at their thresholds
def traits(**fields):
    for k, v in fields.items():
        if isinstance(v, dict):
            t = lua.table()
            for kk, vv in v.items(): t[kk] = vv
            v = t
        db[k] = v
    return [t.id for t in ns.traits.Build(db).values()]
got = traits(moves={"portal": 9})
assert "taxi" not in got
got = traits(moves={"portal": 10, "feign": 12, "shadowmeld": 10, "soar": 24})
assert "taxi" in got and "dramaqueen" in got and "hider" in got and "soarer" not in got, got
got = traits(tracked=5 * 3600, travel=3600, onFoot=600, formTravel=2400, mounted=600, stealthTime=0, moves={})
assert "nohorse" in got and "pedestrian" not in got, got
got = traits(stealthTime=3600)
assert "lurker" in got, got
print("ok: move traits fire at their thresholds; a druid in travel form isn't a Pedestrian")

report = list(ns.moves.Report().values())
assert any(l.strip().startswith("Portals opened:") for l in report) and any("Stealthed out of combat" in l for l in report)
print("ok: /persona moves report")
