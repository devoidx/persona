import sys
from lupa import LuaRuntime
lua = LuaRuntime()
lua.execute(r'''
date = os.date
function UnitName() return "Thrall" end
function UnitSex() return 2 end
C_MountJournal = { GetMountInfoByID = function(id) return "Swift Spectral Tiger" end }
local stats = { {1,"Total deaths","120"}, {2,"Deaths from falling","18"}, {3,"Total waves","340"},
  {4,"Total times LOL'd","1,204"}, {5,"Critters killed","2,511"}, {6,"Quests abandoned","301"},
  {7,"Quests completed","1,900"}, {8,"Number of hugs","12"} }
function GetStatisticsCategoryList() return {100} end
function GetCategoryNumAchievements() return #stats end
function GetAchievementInfo(cat, i) return stats[i][1], stats[i][2] end
function GetStatistic(id) for _, s in ipairs(stats) do if s[1]==id then return s[3] end end end
function BreakUpLargeNumbers(n) return tostring(n) end
''')
ns = lua.table()
chunk = lua.eval('function(src, ns) return load(src, "Traits.lua")("Persona", ns) end')
chunk(open(sys.argv[1]).read(), ns)
db = lua.eval('''{ tracked=5*3600, travel=40*60, onFoot=30*60, travelJumps=40*14, totalJumps=900,
  mounted=60*60, mounts={[42]=50*60,[7]=10*60}, zones={["Silvermoon City - The Bazaar"]=3000, ["Eversong"]=200},
  idleResting=5*3600*0.3, idleZones={["Silvermoon City"]=4000}, fallYards=3500, longestFall=7.2,
  hours={[1]=5*3600*0.4,[21]=5*3600*0.6}, days={[0]=4*3600,[3]=3600} }''')
traits = ns.traits.Build(db)
print("TITLE:", ns.traits.Headline(traits))
for i in range(1, len(traits)+1):
    t = traits[i]; print(f"{t.score:5.2f}  {t.label}: {t.text}")
print("EMPTY:", ns.traits.EmptyText(lua.eval('{tracked=300}')))
