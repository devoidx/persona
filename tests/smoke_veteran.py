# Regression: a 4,000-hour character's first 41 minutes must not produce
# place or play-time traits (seen on Zugzwang, 2026-11-02).
import sys
from lupa import LuaRuntime
lua = LuaRuntime()
lua.execute(r'''
date = os.date
function UnitName() return "Zugzwang" end
function UnitSex() return 3 end
C_MountJournal = { GetMountInfoByID = function(id) return "Felscorned Wolfhawk" end }
local stats = { {1,"Total deaths","2,899"}, {2,"Deaths from falling","68"}, {3,"Critters killed","11,200"},
  {4,"Quests abandoned","4,252"}, {5,"Quests completed","9,000"}, {6,"Number of hugs","32"},
  {7,"Total waves","57"}, {8,"Total facepalms","2"}, {9,"Total times LOL'd","0"} }
function GetStatisticsCategoryList() return {100} end
function GetCategoryNumAchievements() return #stats end
function GetAchievementInfo(cat, i) if i == nil then return nil end return stats[i][1], stats[i][2] end
function GetStatistic(id) for _, s in ipairs(stats) do if s[1]==id then return s[3] end end end
function BreakUpLargeNumbers(n) return tostring(n) end
''')
ns = lua.table()
lua.eval('function(src, ns) return load(src, "Traits.lua")("Persona", ns) end')(open(sys.argv[1]).read(), ns)
db = lua.eval('''{ tracked=41*60, travel=5*60, onFoot=3*60, travelJumps=22, totalJumps=26,
  mounted=8*60, mounts={[1]=8*60}, zones={["Bastion - Temple of Devotion"]=8*60, ["Bastion - Vestibule of Eternity"]=8*60},
  idleResting=0, idleZones={}, fallYards=331, longestFall=3.5, hours={[12]=41*60}, days={[1]=41*60}, played=4012*3600 }''')
t = ns.traits.Build(db)
labels = [t[i].label for i in range(1, len(t)+1)]
print("TITLE:", ns.traits.Headline(t)); print("TRAITS:", labels)
for banned in ("Homebody", "Night Owl", "Early Bird", "Weekend Warrior"):
    assert banned not in labels, f"{banned} fired on a single session"
print("ok: no place/time traits from one session")

assert "Stone-Faced" in labels, "Stone-Faced should fire: 4,012h played, 0 LOLs"
# (smoke_forever.py covers the other case: statistic not found, trait stays off)
print("ok: Stone-Faced fires on zero LOLs")
