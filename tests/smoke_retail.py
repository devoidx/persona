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
function GetAchievementInfo(cat, i) if i == nil then return nil end return stats[i][1], stats[i][2] end
function GetStatistic(id) for _, s in ipairs(stats) do if s[1]==id then return s[3] end end end
function BreakUpLargeNumbers(n) return tostring(n) end
''')
ns = lua.table()
chunk = lua.eval('function(src, ns) return load(src, "Traits.lua")("Persona", ns) end')
chunk(open(sys.argv[1]).read(), ns)
db = lua.eval('''{ tracked=5*3600, travel=40*60, onFoot=30*60, travelJumps=40*14, totalJumps=900,
  mounted=60*60, mounts={[42]=50*60,[7]=10*60}, zones={["Silvermoon City - The Bazaar"]=3000, ["Eversong"]=200},
  idleResting=5*3600*0.3, idleZones={["Silvermoon City"]=4000}, fallYards=3500, longestFall=7.2,
  hours={[1]=5*3600*0.4,[21]=5*3600*0.6}, days={[0]=4*3600,[3]=3600},
  emotes={DANCE=60, BOW=30, THANK=15, WAVE=5}, emoteTotal=110, soloDances=50,
  bagSamples=120, bagFull=120*0.95, deathsSeen=10, deathZones={["Bastion - Temple of Devotion"]=6, ["Oribos"]=4},
  afkCount=8, afkTime=5*3600*0.15 }''')
traits = ns.traits.Build(db)
print("TITLE:", ns.traits.Headline(traits))
for i in range(1, len(traits)+1):
    t = traits[i]; print(f"{t.score:5.2f}  {t.label}: {t.text}")
print("EMPTY:", ns.traits.EmptyText(lua.eval('{tracked=300}')))

labels = [traits[i].label for i in range(1, len(traits)+1)]
for want in ("Dancer", "Polite", "Dances Alone"):
    assert want in labels, f"{want} should fire: {labels}"
assert "Signature Move" not in labels, "Dancer replaces Signature Move when the top emote is /dance"
print("ok: emote traits")

import re
seen = set()
for day in range(1, 22):
    lua.execute(f'date = function(fmt) if fmt == "%Y-%m-%d" then return "2026-11-{day:02d}" end return os.date(fmt) end')
    tr = ns.traits.Build(db)
    for i in range(1, len(tr) + 1):
        text = tr[i].text
        seen.add(text)
        assert "{" not in text, f"unfilled placeholder: {text}"
        assert len(re.findall(r"minute", text)) <= 1, f"unit repeated: {text}"
        assert "Consent" not in text
print(f"ok: {len(seen)} phrasings rendered cleanly")

# Opposites never appear together: Zugzwang's real case (127 places, 25% in one)
lua.execute('''date = os.date''')
zones = "{" + ", ".join(f'["Place {i}"] = 60' for i in range(126)) + ', ["The Bazaar"] = 15 * 3600 }'
both = lua.eval(f"""{{ tracked = 60 * 3600, travel = 0, onFoot = 0, travelJumps = 0, totalJumps = 0, mounted = 0,
  mounts = {{}}, zones = {zones}, idleResting = 0, idleZones = {{}}, falls = 0, fallYards = 0, longestFall = 0,
  hours = {{ [2] = 20 * 3600, [6] = 20 * 3600 }}, days = {{}}, emotes = {{}}, emoteTotal = 0, soloDances = 0 }}""")
got = [t.id for t in ns.traits.Build(both).values()]
assert not ("homebody" in got and "wanderer" in got), got
assert not ("nightowl" in got and "earlybird" in got), got
assert ("homebody" in got) != ("wanderer" in got), f"exactly one of the pair should remain: {got}"
print("ok: contradictory traits never shown together")

# New traits fire on the shared test character
lua.execute("date = os.date")
ids = [t.id for t in ns.traits.Build(db).values()]
for want in ("hoarder", "nemesis", "wandersoff"):
    assert want in ids, f"{want} should fire: {ids}"
nem = [t for t in ns.traits.Build(db).values() if t.id == "nemesis"][0]
assert "Temple of Devotion" in nem.text and "Bastion -" not in nem.text, nem.text

# Thresholds: an emptier bag flips to Travels Light; too few samples, deaths or breaks: nothing
def build_with(**fields):
    for k, v in fields.items():
        db[k] = v
    return [t.id for t in ns.traits.Build(db).values()]
got = build_with(bagFull=120 * 0.2)
assert "travelslight" in got and "hoarder" not in got, got
got = build_with(bagSamples=59, bagFull=59 * 0.95)
assert "hoarder" not in got and "travelslight" not in got, "needs an hour of samples"
got = build_with(deathsSeen=4)
assert "nemesis" not in got, "needs 5 observed deaths"
got = build_with(deathsSeen=10, afkCount=4)
assert "wandersoff" not in got, "needs 5 breaks"
build_with(bagSamples=120, bagFull=120 * 0.95, afkCount=8)
print("ok: Hoarder / Travels Light / Nemesis / Easily Distracted fire at their thresholds only")

# Every phrasing of every trait this character has is reachable and renders cleanly.
# 120 different days is enough for the daily pick to land on all five.
phrasings = {}
for day in range(120):
    lua.execute(f'date = function(fmt) if fmt == "%Y-%m-%d" then return "2027-D{day}" end return os.date(fmt) end')
    for t in ns.traits.Build(db).values():
        phrasings.setdefault(t.id, set()).add(t.text)
for tid, texts in phrasings.items():
    for text in texts:
        assert "{" not in text, f"{tid}: unfilled placeholder: {text}"
        assert text.count("minute") <= 1, f"{tid}: unit repeated: {text}"
    assert len(texts) == 5, f"{tid}: expected 5 phrasings, saw {len(texts)}"
print(f"ok: {len(phrasings)} traits x 5 phrasings all render cleanly ({sum(map(len, phrasings.values()))} lines)")
