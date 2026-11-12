# Kill traits read from the KillDex addon's per-character table (schema 5).
# No KillDex, another schema, or a mob entry we don't understand: no kill traits, no errors.
import sys
from lupa import LuaRuntime
lua = LuaRuntime()
lua.execute(r'''
date = os.date
function UnitName() return "Zugzwang" end
function UnitSex() return 2 end
function BreakUpLargeNumbers(n) return tostring(n) end
''')
ns = lua.table()
lua.eval('function(src, ns) return load(src, "Traits.lua")("Persona", ns) end')(open(sys.argv[1]).read(), ns)
T = ns.traits
db = lua.eval('''{ tracked = 600, travel = 0, onFoot = 0, travelJumps = 0, totalJumps = 0, mounted = 0, mounts = {},
  zones = {}, idleResting = 0, idleZones = {}, falls = 0, fallYards = 0, longestFall = 0, hours = {}, days = {},
  emotes = {}, emoteTotal = 0, soloDances = 0 }''')

def ids():
    t = T.Build(db)
    return {t[i].id: t[i] for i in range(1, len(t) + 1)}

KILL_IDS = ("grudge", "rarehunter", "exterminator")
def none_of_them(why):
    got = ids()
    for k in KILL_IDS:
        assert k not in got, f"{k} fired: {why}"

none_of_them("KillDex not installed")
assert T.Kills() is None

# Shaped like Zugzwang's real data: 411 kills, one mob 30% of them
lua.execute('''
KillDexCharDB = { schemaVersion = 5, deaths = {}, session = {}, mobs = {
  [1] = { name = "Agitated Etherwyrm", kills = 124, firstKill = 1, lastKill = 2, locations = {}, loot = {}, gold = 0, currency = {}, creatureType = "Unknown" },
  [2] = { name = "Wind Serpent", kills = 10, creatureType = "Beast" },
  [3] = { name = "Wind Serpent", kills = 7, creatureType = "Beast" },
  [4] = { name = "Dionae", kills = 1, classification = "rare" },
} }
for i = 5, 104 do KillDexCharDB.mobs[i] = { name = "Mob " .. i, kills = (i <= 74) and 4 or 1 } end
''')
k = T.Kills()
assert k.total == 124 + 17 + 1 + 70 * 4 + 30, k.total
assert k.kinds == 3 + 100, k.kinds
assert k.top[1].k == "Agitated Etherwyrm" and k.top[2].k == "Wind Serpent" and k.top[2].v == 17, "same-named mobs merged"
got = ids()
assert "grudge" in got and "Agitated Etherwyrm" in got["grudge"].epithet, got.keys()
assert "rarehunter" not in got and "exterminator" not in got
print("ok: Grudge Match from a Zugzwang-shaped kill list; same-named mobs merged;", got["grudge"].text)

# Plenty of rares and kinds
lua.execute('''
for i = 200, 211 do KillDexCharDB.mobs[i] = { name = "Rare " .. i, kills = 1, classification = (i % 2 == 0) and "rare" or "rareelite" } end
for i = 300, 360 do KillDexCharDB.mobs[i] = { name = "Critter " .. i, kills = 1 } end
''')
got = ids()
assert "rarehunter" in got and "exterminator" in got, got.keys()
assert got["rarehunter"].score < 1.5 and got["exterminator"].score < 1.5, "damped"
print("ok: Rare Hunter and Exterminator, damped")

# Too few kills for a grudge
lua.execute('KillDexCharDB = { schemaVersion = 5, mobs = { [1] = { name = "Rat", kills = 20 } } }')
none_of_them("only 20 kills")

# A fresh character, a future schema, and broken entries: off, no errors
for setup, why in (('KillDexCharDB = { schemaVersion = 5, mobs = {}, deaths = {}, session = {} }', "empty"),
                   ('KillDexCharDB.schemaVersion = 6; KillDexCharDB.mobs = { [1] = { name = "Rat", kills = 500 } }', "schema 6"),
                   ('KillDexCharDB = { schemaVersion = 5, mobs = { [1] = { name = "Rat", kills = "500" } } }', "kills not a number"),
                   ('KillDexCharDB = { schemaVersion = 5, mobs = { [1] = "Rat" } }', "mob not a table"),
                   ('KillDexCharDB = { schemaVersion = 5 }', "no mobs table"),
                   ('KillDexCharDB = "nonsense"', "not a table")):
    lua.execute(setup)
    none_of_them(why)
print("ok: empty, schema 6 and malformed KillDex data switch the traits off without errors")
