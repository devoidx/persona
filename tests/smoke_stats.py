# Statistics resolve by ID on a non-English client, and fall back to the
# English title when an ID doesn't resolve.
import sys
from lupa import LuaRuntime

def run(src, setup):
    lua = LuaRuntime()
    lua.execute('date = os.date; function BreakUpLargeNumbers(n) return tostring(n) end')
    lua.execute(setup)
    ns = lua.table()
    lua.eval('function(src, ns) return load(src, "Traits.lua")("Persona", ns) end')(src, ns)
    return ns.traits

src = open(sys.argv[1]).read()

# German client: titles translated, values use "." as thousands separator, no title would match
german = run(src, r'''
local byId = { [60] = {"Tode insgesamt", "2.901"}, [114] = {"Tode durch Stürze", "69"},
  [94] = {"Abgebrochene Quests", "4.252"}, [98] = {"Abgeschlossene Quests", "17.339"},
  [108] = {"Getötete Kleintiere", "11.210"}, [1066] = {"Wie oft gelacht", "0"} }
function GetAchievementInfo(a, b) if b == nil and byId[a] then return a, byId[a][1] end end
function GetStatistic(id) return byId[id] and byId[id][2] end
function GetStatisticsCategoryList() return {} end
''')
assert german.Stat("deaths") == 2901, german.Stat("deaths")
assert german.Stat("abandoned") == 4252 and german.Stat("critters") == 11210
assert german.Stat("lols") == 0, "found but never used must be 0, not nil"
assert german.Stat("hugs") is None, "absent statistic must be nil"
print("ok: German client resolves by ID")

# IDs renumbered: every ID lookup fails, English titles still match
fallback = run(src, r'''
local list = { {9001, "Total deaths", "120"}, {9002, "Deaths from falling", "18"} }
function GetAchievementInfo(a, b)
  if b == nil then return nil end
  local s = list[b]; if s then return s[1], s[2] end
end
function GetStatisticsCategoryList() return {1} end
function GetCategoryNumAchievements() return #list end
function GetStatistic(id) for _, s in ipairs(list) do if s[1] == id then return s[3] end end end
''')
d, f = fallback.LifetimeDeaths()
assert (d, f) == (120, 18), (d, f)
print("ok: title fallback when IDs don't resolve")

# No statistics API at all (possible on Forever): everything nil, no errors
none = run(src, '')
assert none.Stat("deaths") is None
print("ok: no statistics API")
