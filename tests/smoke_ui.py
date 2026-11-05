# Runs UI.lua (with Traits.lua) against stub frames: open docked, drag,
# reopen at the saved spot, character frame closing leaves a moved panel up,
# /persona dock, and /persona reset keeping the position.
import sys
from lupa import LuaRuntime
lua = LuaRuntime()
lua.execute(r'''
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
function Frame:GetStringHeight() return 10 end
function Frame:StartMoving() self.moving = true end
function Frame:StopMovingOrSizing() self.moving = false end
function CreateFrame(_, name) local f = Frame.new(); if name then _G[name] = f end; return f end
UIParent = Frame.new(); UIParent.name = "UIParent"
CharacterFrame = Frame.new(); CharacterFrame.name = "CharacterFrame"
''')
ns = lua.table()
load = lua.eval('function(src, name, ns) return load(src, name)("Persona", ns) end')
load(open(sys.argv[1]).read(), "Traits.lua", ns)
load(open(sys.argv[2]).read(), "UI.lua", ns)
ns.db = lua.eval('''{ tracked = 0, travel = 0, onFoot = 0, travelJumps = 0, totalJumps = 0, mounted = 0,
  mounts = {}, zones = {}, idleResting = 0, idleZones = {}, falls = 0, fallYards = 0, longestFall = 0,
  hours = {}, days = {}, emotes = {}, emoteTotal = 0, soloDances = 0, panelOpen = false }''')
lua.globals().ns = ns
ns.OnDBReady(ns.db)
# Like Core's ResetDB: wipe, then refill the defaults
lua.globals().ns.ResetDB = lua.eval('''function()
  for k in pairs(ns.db) do ns.db[k] = nil end
  for _, k in ipairs({"tracked","travel","onFoot","travelJumps","totalJumps","mounted","idleResting",
                      "falls","fallYards","longestFall","emoteTotal","soloDances"}) do ns.db[k] = 0 end
  for _, k in ipairs({"mounts","zones","idleZones","hours","days","emotes"}) do ns.db[k] = {} end
end''')
P, C, U = lua.globals().PersonaPanel, lua.globals().CharacterFrame, lua.globals().UIParent
point = lambda: P.GetPoint(P, 1)

# 1. Docked: opens beside the character frame
C.Show(C); ns.SetPanel(True)
p, rel, rp, x, y = point()
assert rel.name == "CharacterFrame" and p == "TOPLEFT" and rp == "TOPRIGHT", (p, rp)

# 2. Drag: simulate the frame ending up at TOPLEFT of UIParent, 200, -150
P.scripts["OnDragStart"](P); assert P.moving
P.ClearAllPoints(P); P.SetPoint(P, "TOPLEFT", U, "TOPLEFT", 200, -150)
P.scripts["OnDragStop"](P)
assert ns.db.panelPos and ns.db.panelPos.x == 200 and ns.db.panelPos.y == -150

# 3. Closing the character frame leaves a moved panel open
C.Hide(C); assert P.IsShown(P), "moved panel should stay open"

# 4. Reopen: comes back at the saved spot, not docked
ns.SetPanel(False); C.Show(C); ns.SetPanel(True)
p, rel, rp, x, y = point()
assert rel.name == "UIParent" and (x, y) == (200, -150), (rel, x, y)

# 5. /persona reset keeps the position
lua.globals().SlashCmdList.PERSONA("reset")
assert ns.db.panelPos and ns.db.panelPos.x == 200, "reset should keep the window position"

# 6. /persona dock: back beside the character frame, and closes with it again
lua.globals().SlashCmdList.PERSONA("dock")
assert ns.db.panelPos is None
p, rel, rp, x, y = point()
assert rel.name == "CharacterFrame", "dock should re-anchor immediately"
C.Hide(C); assert not P.IsShown(P), "docked panel should close with the character frame"
print("ok: drag, reopen, dock and reset")

# Minimap addons button: the TOC names must exist as globals, and behave
import re
toc = open("Persona.toc").read()
names = dict(re.findall(r"^## (AddonCompartmentFunc\w*): *(\S+)", toc, re.M))
assert set(names) == {"AddonCompartmentFunc", "AddonCompartmentFuncOnEnter", "AddonCompartmentFuncOnLeave"}, names
g = lua.globals()
for field, fn in names.items():
    assert g[fn] is not None, f"{field} names {fn}, which UI.lua doesn't define"
click, enter, leave = (g[names[k]] for k in ("AddonCompartmentFunc", "AddonCompartmentFuncOnEnter", "AddonCompartmentFuncOnLeave"))
lua.execute('''
TIP = { lines = {} }
GameTooltip = setmetatable({}, { __index = function() return function() end end })
function GameTooltip:AddLine(t) TIP.lines[#TIP.lines + 1] = t end
function GameTooltip:Show() TIP.shown = true end
function GameTooltip:Hide() TIP.shown = false end
''')
C.Hide(C); ns.SetPanel(False)
click("Persona", "LeftButton"); assert P.IsShown(P), "left click opens"
click("Persona", "LeftButton"); assert not P.IsShown(P), "left click closes"
ns.db.panelPos = lua.eval('{ point = "CENTER", relPoint = "CENTER", x = 1, y = 2 }')
click("Persona", "RightButton"); assert ns.db.panelPos is None, "right click docks"
enter("Persona", lua.eval('{}'))
tip = lua.globals().TIP
assert tip.shown and tip.lines[1] == "Persona" and tip.lines[2] == "Thrall", list(tip.lines.values())
leave("Persona", None); assert not tip.shown
print("ok: minimap addons button")
