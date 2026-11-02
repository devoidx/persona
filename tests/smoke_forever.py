import sys
from lupa import LuaRuntime
lua = LuaRuntime()
lua.execute(r'''
date = os.date
WOW_PROJECT_CAMELOT = 18; WOW_PROJECT_ID = 18
function UnitName() return "Elowen" end
function UnitSex() return 3 end
function BreakUpLargeNumbers(n) return tostring(n) end
-- No statistics API, no mount journal: worst case for a new client flavour
''')
ns = lua.table(); ns.IS_FOREVER = True
chunk = lua.eval('function(src, ns) return load(src, "Traits.lua")("Persona", ns) end')
chunk(open(sys.argv[1]).read(), ns)
# Level-30 character: never mounted, walks everywhere, plays late
db = lua.eval('''{ tracked=6*3600, travel=3*3600, onFoot=3*3600, travelJumps=3*60*12, totalJumps=3000,
  mounted=0, mounts={}, zones={["Elwynn Forest - Goldshire"]=2*3600, ["Westfall"]=3600},
  idleResting=1800, idleZones={["Stormwind City"]=1800}, fallYards=400, longestFall=2.1,
  hours={[23]=3*3600,[1]=3*3600}, days={[2]=6*3600} }''')
t = ns.traits.Build(db)
print("TITLE:", ns.traits.Headline(t))
for i in range(1, len(t)+1): print(f"{t[i].score:5.2f}  {t[i].label}: {t[i].text}")
