# Race and class flavour lines: a matching character sees its own line on some
# days; other races and classes never do; the Forever bar for Bloodthirsty.
import sys
from lupa import LuaRuntime

def build(race, cls, forever=False, days=60):
    lua = LuaRuntime()
    lua.execute(r'''
    DAY = 0
    function date(fmt) return os.date(fmt, 1793577600 + DAY * 86400) end
    function UnitName() return "Thrall" end
    function UnitSex() return 2 end
    function BreakUpLargeNumbers(n) return tostring(n) end
    local stats = { [107] = "310,170", [108] = "11,210" }
    function GetAchievementInfo(a, b) if b == nil and stats[a] then return a, "stat" end end
    function GetStatistic(id) return stats[id] end
    ''')
    lua.execute(f'function UnitRace() return "Race", "{race}" end function UnitClass() return "Class", "{cls}" end')
    ns = lua.table()
    if forever:
        ns.IS_FOREVER = True
    lua.eval('function(src, ns) return load(src, "Traits.lua")("Persona", ns) end')(open(sys.argv[1]).read(), ns)
    db = lua.eval('''{ tracked = 600, travel = 0, onFoot = 0, travelJumps = 0, totalJumps = 0, mounted = 0, mounts = {},
      zones = {}, idleResting = 0, idleZones = {}, falls = 0, fallYards = 0, longestFall = 0, hours = {}, days = {},
      emotes = {}, emoteTotal = 0, soloDances = 0 }''')
    texts = {}
    for d in range(days):
        lua.execute(f"DAY = {d}")
        t = ns.traits.Build(db)
        for i in range(1, len(t) + 1):
            texts.setdefault(t[i].id, set()).add(t[i].text)
    return texts

druid = build("Tauren", "DRUID")
assert any("Cenarion Circle" in x for x in druid["menace"]), "druid flavour line never shown in 60 days"
assert any("Earth Mother is keeping count" in x for x in druid["menace"]), "tauren flavour line never shown in 60 days"
assert any("critters" in x and "Cenarion" not in x and "Earth Mother" not in x for x in druid["menace"]), "usual lines still used"
print("ok: a tauren druid sees both flavour lines and the usual ones")

human = build("Human", "MAGE")
assert not any("Cenarion" in x or "Earth Mother" in x for x in human["menace"]), "other race/class lines leaked"
assert any("Icecrown" in x for x in build("Scourge", "DEATHKNIGHT")["bloodthirsty"])
assert not any("Icecrown" in x for x in human["bloodthirsty"])
print("ok: nobody sees another race's or class's lines")

# Forever: 310,170 kills qualifies either way; a 20,000-kill Forever character qualifies, a retail one doesn't
def bloodthirsty_at(kills, forever):
    lua = LuaRuntime()
    lua.execute(f'''
    date = os.date
    function UnitName() return "Thrall" end function UnitSex() return 2 end
    function BreakUpLargeNumbers(n) return tostring(n) end
    function GetAchievementInfo(a, b) if b == nil and a == 107 then return a, "stat" end end
    function GetStatistic(id) if id == 107 then return "{kills}" end end
    ''')
    ns = lua.table()
    if forever:
        ns.IS_FOREVER = True
    lua.eval('function(src, ns) return load(src, "Traits.lua")("Persona", ns) end')(open(sys.argv[1]).read(), ns)
    db = lua.eval('{ tracked = 0, travel = 0, onFoot = 0, travelJumps = 0, totalJumps = 0, mounted = 0, mounts = {}, zones = {}, idleResting = 0, idleZones = {}, falls = 0, fallYards = 0, longestFall = 0, hours = {}, days = {}, emotes = {}, emoteTotal = 0, soloDances = 0 }')
    t = ns.traits.Build(db)
    return any(t[i].id == "bloodthirsty" for i in range(1, len(t) + 1))

assert bloodthirsty_at(20000, True) and not bloodthirsty_at(20000, False)
assert not bloodthirsty_at(5000, True)
print("ok: Bloodthirsty starts at 10,000 kills on Forever, 100,000 on retail")
