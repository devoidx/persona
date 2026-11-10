# Share card: text for Discord and chat, and the copy box.
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

EDITS = """
  UISpecialFrames = {}
  function tinsert(t, v) t[#t + 1] = v end
  EDITBOXES = {}
  local Frame = getmetatable(CreateFrame())
  local orig = CreateFrame
  function CreateFrame(kind, name, parent, template)
    local f = orig(kind, name, parent, template)
    if kind == "EditBox" then EDITBOXES[#EDITBOXES + 1] = f end
    if kind == "Button" and template == "UIPanelButtonTemplate" then BUTTONS = BUTTONS or {}; BUTTONS[#BUTTONS + 1] = f end
    return f
  end
"""

def start(db, extra=""):
    lua = LuaRuntime()
    lua.execute(STUBS); lua.execute(EDITS); lua.execute(extra)
    ns = lua.table()
    load = lua.eval('function(src, name, ns) return load(src, name)("Persona", ns) end')
    for f in ("Traits.lua", "Moves.lua", "Share.lua", "UI.lua"):
        load(open(f).read(), f, ns)
    ns.db = lua.eval(db)
    ns.OnDBReady(ns.db)
    return lua, ns

# 1. Veteran: Discord format
lua, ns = start(VETERAN, VETERAN_STATS)
d = ns.share.Text("discord")
lines = d.split("\n")
assert lines[0].startswith("**Thrall") and lines[0].endswith("**"), lines[0]
assert lines[1] == "Level 80 Orc Shaman", lines[1]
assert sum(1 for l in lines if l.startswith("- **")) == 3, d
assert lines[-1] == "_Made with Persona, a World of Warcraft addon_"
assert "|c" not in d and "|r" not in d and "{" not in d, d
print("ok: Discord text: title, class line, three traits, footer, no colour codes")

# 2. Veteran: chat format fits one message
c = ns.share.Text("chat")
assert "\n" not in c and len(c) <= 255 and c.endswith(" (Persona addon)"), c
assert c.split(": ", 1)[1].count(",") == 2, c
print("ok: chat text: one line, three traits, under 255 characters")

# 3. Very long trait names: drop traits, never cut one or exceed the limit
long = lua.eval("""function(T)
  T.Build = function() return {
    { label = string.rep("A", 120), text = "x", epithet = "Thrall the Long" },
    { label = string.rep("B", 120), text = "x", epithet = "Thrall the Long" },
    { label = string.rep("C", 120), text = "x", epithet = "Thrall the Long" } } end
end""")
long(ns.traits)
c = ns.share.Text("chat")
assert len(c) <= 255 and "A" * 120 in c and "B" * 120 not in c, (len(c), c[:60])
print("ok: long trait names dropped whole to stay under 255")

# 4. Brand-new character
lua, ns = start(FRESH)
assert "hasn't revealed a personality yet" in ns.share.Text("discord")
assert ns.share.Text("chat") == "Thrall hasn't revealed a personality yet. (Persona addon)"
print("ok: empty profile wording")

# 5. The copy box: /persona share, switching format, stray typing
lua, ns = start(VETERAN, VETERAN_STATS)
cmd = lua.globals().SlashCmdList.PERSONA
cmd("share")
g = lua.globals()
edit = g.EDITBOXES[1]
assert ns.share.IsShown() and edit.text == ns.share.Text("discord")
assert "PersonaShareBox" in list(g.UISpecialFrames.values()), "Escape closes it"
kind_buttons = [b for b in g.BUTTONS.values() if b.text in ("Discord", "Chat")]
chat_btn = [b for b in kind_buttons if b.text == "Chat"][0]
chat_btn.scripts["OnClick"](chat_btn)
assert edit.text == ns.share.Text("chat"), "Chat button switches format"
edit.text = "oops"; edit.scripts["OnTextChanged"](edit, True)
assert edit.text == ns.share.Text("chat"), "typing can't spoil the copy"
cmd("share chat"); assert edit.text == ns.share.Text("chat")
share_btn = [b for b in g.BUTTONS.values() if b.text == "Share"]
assert share_btn, "Share button on the panel"
print("ok: copy box opens, switches format, resists typing; Share button present")
