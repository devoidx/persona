# Roster tab: summaries in PersonaAccountDB, comparisons, account traits,
# stale characters and /persona forget.
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

DAY = 86400
NOW = 2_000_000_000

CLIENT = f"""
  NOW = {NOW}
  function time() return NOW end
  function UnitGUID() return "Player-1-THRALL" end
  function UnitClass() return "Shaman", "SHAMAN" end
  function GetRealmName() return "Argent Dawn" end
  RAID_CLASS_COLORS = {{ SHAMAN = {{ colorStr = "ff0070dd" }}, HUNTER = {{ colorStr = "ffaad372" }}, MAGE = {{ colorStr = "ff3fc7eb" }} }}
"""

# Thrall, the live character: restless jumper (10 jumps/min over 40 minutes)
THRALL = """{ tracked = 6 * 3600, travel = 40 * 60, onFoot = 0, travelJumps = 400, totalJumps = 900,
  mounted = 0, mounts = {}, zones = {}, idleResting = 0, idleZones = {}, falls = 0, fallYards = 0,
  longestFall = 0, hours = {}, days = {}, emotes = {}, emoteTotal = 0, soloDances = 0, panelOpen = false }"""

def start(others):
    lua = LuaRuntime()
    lua.execute(STUBS)
    lua.execute(RECORD_FONTSTRINGS)
    lua.execute(CLIENT)
    lua.execute("PersonaAccountDB = { characters = " + others + " }")
    ns = lua.table()
    load = lua.eval('function(src, name, ns) return load(src, name)("Persona", ns) end')
    for f in ("Traits.lua", "Roster.lua", "UI.lua"):
        load(open(f).read(), f, ns)
    ns.db = lua.eval(THRALL)
    ns.OnDBReady(ns.db)
    ns.SetPanel(True)
    def text():
        ns.SetTab("Roster")
        return lua.eval("""function()
          for _, f in ipairs(FONTSTRINGS) do
            if f.template == "GameFontHighlight" then return f.text or "" end
          end
        end""")()
    return lua, ns, text

def char(name, cls, tracked, scores, played="nil", days_ago=1):
    s = ", ".join(f"{k} = {v}" for k, v in scores.items())
    return (f'["Player-1-{name.upper()}"] = {{ name = "{name}", realm = "Argent Dawn", class = "{cls}", level = 80, '
            f'title = "{name}", traits = {{}}, scores = {{ {s} }}, tracked = {tracked}, played = {played}, '
            f'lastSeen = {NOW - days_ago * DAY} }}')

# 1. Only the live character
lua, ns, text = start("{}")
t = text()
assert "Only Thrall so far." in t, t
assert "Player-1-THRALL" in [k for k in lua.globals().PersonaAccountDB.characters.keys()], "live character saved"
print("ok: single character empty state, live summary saved")

# 2. Zugzwang (more restless, a critter menace), Elowen (stale), Thrall live
others = "{" + ", ".join([
    char("Zugzwang", "HUNTER", 15 * 3600, {"restless": 3.0, "menace": 2.0}),
    char("Elowen", "MAGE", 9 * 3600, {"restless": 9.0}, days_ago=90),
]) + "}"
lua, ns, text = start(others)
t = text()
plain = t
for a, b in (("|cff0070dd", ""), ("|cffaad372", ""), ("|cff9d9d9d", ""), ("|cffffd100", ""), ("|cff66ccff", ""), ("|r", "")):
    plain = plain.replace(a, b)
assert "|cffaad372Zugzwang" in t and "|cff0070ddThrall" in t, "class colours"
assert plain.index("Zugzwang") < plain.index("Thrall") < plain.index("Elowen"), f"order by time, stale last:\n{plain}"
assert "Level 80, 71% of your time" in plain, plain          # 15h of 21h observed (no /played for all)
assert "playing now" in plain
assert "Not seen for 90 days" in plain
assert "Zugzwang is your restless one." in plain, plain       # Elowen scores higher but is stale
assert "Zugzwang is your critter-hunting one." in plain
assert "Elowen is your" not in plain
assert "{" not in plain and "nil" not in plain, plain
print("ok: list, colours, order, shares, stale character, comparisons")

# 3. /played used only when every active character has it
lua, ns, text = start("{" + char("Zugzwang", "HUNTER", 15 * 3600, {}, played=4000 * 3600) + "}")
assert "Level 80, 71% of your time" in text().replace("|cff9d9d9d", "").replace("|r", ""), "Thrall has no /played: fall back to observed time"
ns.db.played = 1000 * 3600
assert "Level 80, 80% of your time" in text().replace("|cff9d9d9d", "").replace("|r", ""), "both have /played: use it"
print("ok: /played only when every character has it")

# 4. Account traits
five = "{" + ", ".join(char(n, "MAGE", 5 * 3600, {}) for n in ("Ada", "Bo", "Cy", "Di")) + "}"
lua, ns, text = start(five)
assert "Altoholic." in text(), text()
lua, ns, text = start("{" + char("Alt", "MAGE", 1 * 3600, {}) + "}")
ns.db.tracked = 30 * 3600
assert "One True Main." in text() and "Thrall gets 97% of your time" in text(), text()
lua, ns, text = start("{" + char("Zugzwang", "HUNTER", 15 * 3600, {"menace": 2.0}) + "}")
assert "Split Personality." in text() and "Zugzwang and Thrall don't share a single habit." in text(), text()
lua, ns, text = start("{" + char("Zugzwang", "HUNTER", 15 * 3600, {"restless": 2.0}) + "}")
assert "Split Personality." not in text(), "they share Restless"
print("ok: Altoholic, One True Main, Split Personality")

# 5. /persona forget
lua, ns, text = start(others)
text()   # saves the live character, as entering the world does in game
cmd = lua.globals().SlashCmdList.PERSONA
chars = lua.globals().PersonaAccountDB.characters
cmd("forget Elowen"); assert chars["Player-1-ELOWEN"] is None
cmd("forget thrall"); assert chars["Player-1-THRALL"] is not None, "can't forget the live character"
cmd("forget zugzwang-argentdawn"); assert chars["Player-1-ZUGZWANG"] is None, "Name-Realm form"
cmd("forget nobody")   # no error
print("ok: forget by name and Name-Realm; live character protected")

# 6. Forever: same first name, different surnames, same ruleset "realm".
#    UnitName's second value is the surname there; Persona must not treat it as a realm.
forever = """
  function UnitGUID() return "Player-6949-JEEMHUNT" end
  function UnitName() return "Jeem", "Hunt" end
  function GetUnitName() return "Jeem Hunt" end
  function GetRealmName() return "Classic Beta PvE" end
"""
lua = LuaRuntime()
lua.execute(STUBS); lua.execute(RECORD_FONTSTRINGS); lua.execute(CLIENT); lua.execute(forever)
lua.execute("""PersonaAccountDB = { characters = {
  ["Player-6949-JEEMSTONE"] = { name = "Jeem", fullName = "Jeem Stone", realm = "Classic Beta PvE", class = "MAGE",
    level = 30, title = "Jeem", traits = {}, scores = {}, tracked = 3600, lastSeen = NOW - 86400 },
  ["Player-6949-OTHER"] = { name = "Ada", fullName = "Ada Lake", realm = "Classic Beta PvE", class = "MAGE",
    level = 30, title = "Ada", traits = {}, scores = {}, tracked = 3600, lastSeen = NOW - 86400 } } }""")
ns = lua.table()
load = lua.eval('function(src, name, ns) return load(src, name)("Persona", ns) end')
for f in ("Traits.lua", "Roster.lua", "UI.lua"):
    load(open(f).read(), f, ns)
ns.db = lua.eval(THRALL)
ns.OnDBReady(ns.db)
ns.roster.Save()
chars = lua.globals().PersonaAccountDB.characters
me = chars["Player-6949-JEEMHUNT"]
assert me.name == "Jeem" and me.fullName == "Jeem Hunt" and me.realm == "Classic Beta PvE", (me.name, me.fullName, me.realm)
F = ns.roster.Forget
assert "More than one" in F("jeem"), "two Jeems: ambiguous"
assert "can't forget" in F("Jeem Hunt"), "full name finds the live character"
assert F("jeem stone") == "Forgot Jeem Stone." and chars["Player-6949-JEEMSTONE"] is None
assert F("ada-lake") == "Forgot Ada Lake.", "First-Surname form works too"
print("ok: Forever surnames stored as full name, never as realm; forget by full name")
