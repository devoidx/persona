# Minimap button: real LibStub, CallbackHandler and LibDataBroker from Libs/,
# a recording stand-in for LibDBIcon. Also checks the no-libraries case.
import sys
from lupa import LuaRuntime

DB = '''{ tracked = 0, travel = 0, onFoot = 0, travelJumps = 0, totalJumps = 0, mounted = 0,
  mounts = {}, zones = {}, idleResting = 0, idleZones = {}, falls = 0, fallYards = 0, longestFall = 0,
  hours = {}, days = {}, emotes = {}, emoteTotal = 0, soloDances = 0, panelOpen = false }'''

def start(with_libs):
    global lua
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
    lua.execute("function securecallfunction(f, ...) return f(...) end")
    load = lua.eval('function(src, name, ns) return load(src, name)("Persona", ns) end')
    if with_libs:
        for f in ("Libs/LibStub/LibStub.lua", "Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua",
                  "Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua"):
            lua.execute(open(f).read())
        lua.execute('''
          local icon = LibStub:NewLibrary("LibDBIcon-1.0", 1)
          REG = {}
          function icon:Register(name, obj, cfg) REG.name, REG.obj, REG.cfg = name, obj, cfg end
          function icon:Hide(name) REG.hidden = true end
          function icon:Show(name) REG.hidden = false end
        ''')
    ns = lua.table()
    load(open(sys.argv[1]).read(), "Traits.lua", ns)
    load(open(sys.argv[2]).read(), "UI.lua", ns)
    ns.db = lua.eval(DB)
    ns.OnDBReady(ns.db)
    return ns

# 1. With libraries
ns = start(True)
g = lua.globals()
reg = g.REG
assert reg.name == "Persona", "LibDBIcon:Register not called"
ldb = g.LibStub("LibDataBroker-1.1")[0]
assert ldb.GetDataObjectByName(ldb, "Persona") is not None, "no LibDataBroker object"
assert lua.eval("rawequal")(reg.cfg, ns.db.minimap), "button settings must live in PersonaDB.minimap"
P = g.PersonaPanel
reg.obj.OnClick(None, "LeftButton"); assert P.IsShown(P), "left click opens"
reg.obj.OnClick(None, "LeftButton"); assert not P.IsShown(P), "left click closes"
ns.db.panelPos = lua.eval('{ point = "CENTER", relPoint = "CENTER", x = 1, y = 2 }')
reg.obj.OnClick(None, "RightButton"); assert ns.db.panelPos is None, "right click docks"
lua.execute("TT = { lines = {} }; function TT:AddLine(t) self.lines[#self.lines + 1] = t end")
reg.obj.OnTooltipShow(g.TT); assert g.TT.lines[1] == "Persona" and g.TT.lines[2] == "Thrall"
g.SlashCmdList.PERSONA("minimap"); assert reg.hidden and ns.db.minimap.hide, "first toggle hides"
g.SlashCmdList.PERSONA("minimap"); assert not reg.hidden and not ns.db.minimap.hide, "second toggle shows"
print("ok: minimap button registers, clicks, tooltip, hide toggle saved")

# 2. Without libraries: no button, no errors, slash command explains
ns = start(False)
assert lua.globals().PersonaPanel is not None, "panel must still build"
lua.globals().SlashCmdList.PERSONA("minimap")
print("ok: no libraries, no errors")
