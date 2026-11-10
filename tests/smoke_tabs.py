# Each tab of the panel: once for a veteran character with full data and the
# Statistics panel, once for a brand-new character on a client without statistics.
import sys
from lupa import LuaRuntime

STUBS = r'''
date = os.date
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function print() end
function BreakUpLargeNumbers(n) return tostring(n) end
function UnitName() return "Thrall" end
function UnitSex() return 2 end
function UnitLevel() return 80 end
function UnitRace() return "Orc" end
function UnitClass() return "Shaman" end
function RequestTimePlayed() end
C_MountJournal = { GetMountInfoByID = function() return "Wolf" end }
SlashCmdList = {}

-- Generic stub frame: any unknown method is a no-op; points and visibility are real.
local Frame = {}
Frame.__index = function(t, k)
  local m = rawget(Frame, k)
  if m then return m end
  return function() return 0 end
end
function Frame.new() return setmetatable({ shown = false, points = {}, scripts = {}, hooks = {} }, Frame) end
function Frame:Show() self.shown = true; if self.hooks.OnShow then self.hooks.OnShow(self) end end
function Frame:Hide() self.shown = false; if self.hooks.OnHide then self.hooks.OnHide(self) end end
function Frame:IsShown() return self.shown end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetPoint(p, rel, rp, x, y)
  if type(rel) ~= "table" then rel, rp, x, y = nil, nil, rel, rp end
  self.points[#self.points + 1] = { p, rel, rp, x, y }
end
function Frame:GetPoint(i) local q = self.points[i or 1]; if q then return q[1], q[2], q[3], q[4], q[5] end end
function Frame:SetScript(k, f) self.scripts[k] = f end
function Frame:HookScript(k, f) self.hooks[k] = f end
function Frame:CreateFontString() return Frame.new() end
function Frame:CreateTexture() return Frame.new() end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text end
function Frame:SetShown(v) self.shown = v and true or false end
function Frame:GetStringHeight() return 10 end
function Frame:StartMoving() self.moving = true end
function Frame:StopMovingOrSizing() self.moving = false end
function CreateFrame(_, name) local f = Frame.new(); if name then _G[name] = f end; return f end
UIParent = Frame.new(); UIParent.name = "UIParent"
CharacterFrame = Frame.new(); CharacterFrame.name = "CharacterFrame"
'''

RECORD_FONTSTRINGS = """
  FONTSTRINGS = {}
  local Frame = getmetatable(CreateFrame())
  function Frame:CreateFontString(_, _, template)
    local f = setmetatable({ shown = false, points = {}, scripts = {}, hooks = {}, template = template }, Frame)
    FONTSTRINGS[#FONTSTRINGS + 1] = f
    return f
  end
"""

VETERAN_STATS = """
  local stats = { [60] = "2,901", [114] = "69", [94] = "4,252", [98] = "17,339", [108] = "11,210",
    [1065] = "57", [1045] = "37", [1042] = "32", [1066] = "0", [1047] = "2", [1067] = "0" }
  function GetAchievementInfo(a, b) if b == nil and stats[a] then return a, "stat" end end
  function GetStatistic(id) return stats[id] end
"""

VETERAN = """{ tracked = 6 * 3600, travel = 40 * 60, onFoot = 30 * 60, travelJumps = 400, totalJumps = 900,
  mounted = 3600, mounts = { [42] = 3000, [7] = 600 },
  zones = { ["Bastion - Temple of Devotion"] = 2 * 3600, ["Oribos"] = 3600, ["Valdrakken"] = 1800 },
  idleResting = 1800, idleZones = { ["Oribos"] = 1500, ["Valdrakken"] = 300 },
  falls = 9, fallYards = 331, longestFall = 3.5,
  hours = { [1] = 3 * 3600, [20] = 3 * 3600 }, days = { [0] = 4 * 3600, [3] = 2 * 3600 },
  emotes = { DANCE = 6, BOW = 3, WAVE = 1 }, emoteTotal = 10, soloDances = 2, panelOpen = false,
  bagSamples = 100, bagFull = 87, deathsSeen = 4, deathZones = { ["Oribos"] = 3, ["Valdrakken"] = 1 },
  afkCount = 1, afkTime = 754, moves = { feign = 12, shadowmeld = 3 }, formTravel = 0, stealthTime = 600 }"""

FRESH = """{ tracked = 0, travel = 0, onFoot = 0, travelJumps = 0, totalJumps = 0, mounted = 0, mounts = {},
  zones = {}, idleResting = 0, idleZones = {}, falls = 0, fallYards = 0, longestFall = 0,
  hours = {}, days = {}, emotes = {}, emoteTotal = 0, soloDances = 0, panelOpen = false }"""

def start(db, extra=""):
    lua = LuaRuntime()
    lua.execute(STUBS)
    lua.execute(RECORD_FONTSTRINGS)
    lua.execute(extra)
    ns = lua.table()
    load = lua.eval('function(src, name, ns) return load(src, name)("Persona", ns) end')
    load(open(sys.argv[1]).read(), "Traits.lua", ns)
    load(open("Moves.lua").read(), "Moves.lua", ns)
    load(open(sys.argv[2]).read(), "UI.lua", ns)
    ns.db = lua.eval(db)
    ns.OnDBReady(ns.db)
    ns.SetPanel(True)
    body = lua.eval("""function()
      -- the body is the one font string drawn in GameFontHighlight
      for _, f in ipairs(FONTSTRINGS) do
        if f.template == "GameFontHighlight" then return f.text or "" end
      end
      error("no body font string")
    end""")
    def check(tab, *wanted, absent=()):
        ns.SetTab(tab)
        assert ns.db.panelTab == tab
        text = body()
        for w in wanted:
            assert w in text, f"{tab}: missing {w!r}\n{text}"
        for w in absent:
            assert w not in text, f"{tab}: should not contain {w!r}\n{text}"
        assert "{" not in text and "nil" not in text, f"{tab}: bad formatting\n{text}"
        if tab == "Habits":
            import re
            for line in re.sub(r"\|c\w{8}|\|r", "", text).split("\n"):
                assert len(line) <= 38, f"Habits line too long to fit: {line!r}"
    return ns, check

# 1. Veteran character
ns, check = start(VETERAN, VETERAN_STATS)
check("Profile", "Observed 6h 0m since install", "Menace to Wildlife", absent=("and more quirks",))
check("Habits", "Jumps: 900 (400 while travelling)", "Jump rate on the move: 10.0 a minute",
      "Distance fallen: about 331 yd", "Night (00-05): 50%", "Evening (17-24): 50%", "Weekends: 67%",
      "Wolf - 50m (83%)", "Idle in towns: 30m", "Mostly in Oribos",
      "Bags: 87% full on average", "AFK: once, 12m in total",
      "Signature moves", "Feign Death, nothing near: 12", "Shadowmeld in town: 3", "Stealthed outside combat: 10m",
      absent=("In animal form",))
check("Emotes", "10 emotes, 3 different", "/dance - 6 (60%)", "Danced alone: twice")
ns.db.soloDances = 1
check("Emotes", "Danced alone: once")
ns.db.soloDances = 3
check("Emotes", "Danced alone: 3 times")
check("Lifetime", "Deaths: 2901 (69 from falling)", "Abandoned: 4252 (20%)", "LOLs: 0", "World's smallest violin: 0")
check("Places", "3 places visited", "33%  Bastion - Temple of Devotion", "Where you stand around",
      "Where you die", "75%  Oribos", "25%  Valdrakken")
ns.SetPanel(False); ns.SetPanel(True)
assert ns.db.panelTab == "Places", "last tab remembered"
ns.SetTab("Bogus"); assert ns.db.panelTab == "Places", "unknown tab ignored"
ns.db.panelTab = "Nonsense"; ns.Refresh()   # bad saved value must not error
print("ok: veteran character, all five tabs")

# 2. Brand-new character, no Statistics panel on this client
ns, check = start(FRESH)
check("Profile", "Thrall", absent=("Menace", "Watching for"))
for tab, want in (("Habits", "No riding recorded yet."), ("Habits", "Nothing recorded yet."),
                  ("Emotes", "No emotes yet."), ("Lifetime", "no Statistics panel"),
                  ("Places", "Nowhere recorded yet.")):
    check(tab, want, absent=("Bags:", "AFK:", "Where you die", "Signature moves"))
print("ok: brand-new character, every tab has an empty state")
