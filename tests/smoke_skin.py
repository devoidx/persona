# EllesmereUI skinning: Persona registers with EllesmereUI's skinning API and
# hands over its frames; without EllesmereUI nothing changes.
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
VETERAN = """{ tracked = 6 * 3600, travel = 40 * 60, onFoot = 30 * 60, travelJumps = 400, totalJumps = 900,
  mounted = 3600, mounts = { [42] = 3000, [7] = 600 },
  zones = { ["Bastion - Temple of Devotion"] = 2 * 3600, ["Oribos"] = 3600, ["Valdrakken"] = 1800 },
  idleResting = 1800, idleZones = { ["Oribos"] = 1500, ["Valdrakken"] = 300 },
  falls = 9, fallYards = 331, longestFall = 3.5,
  hours = { [1] = 3 * 3600, [20] = 3 * 3600 }, days = { [0] = 4 * 3600, [3] = 2 * 3600 },
  emotes = { DANCE = 6, BOW = 3, WAVE = 1 }, emoteTotal = 10, soloDances = 2, panelOpen = false,
  bagSamples = 100, bagFull = 87, deathsSeen = 4, deathZones = { ["Oribos"] = 3, ["Valdrakken"] = 1 },
  afkCount = 1, afkTime = 754, moves = { feign = 12, shadowmeld = 3 }, formTravel = 0, stealthTime = 600 }"""

FAKE_EUI = """
  CALLS = {}
  local function rec(name) return function(frame, ...) CALLS[#CALLS + 1] = { name = name, frame = frame } end end
  ACCENT = { 0.2, 0.6, 1 }
  SKIN = {
    apiVersion = 4,
    Shell = rec("Shell"), Panel = rec("Panel"), Button = rec("Button"), CloseButton = rec("CloseButton"),
    EditBox = rec("EditBox"), ScrollBar = rec("ScrollBar"), Font = rec("Font"),
    GetAccentColor = function() return ACCENT[1], ACCENT[2], ACCENT[3] end,
    OnLooksChanged = function(fn) LOOKS = fn end,
  }
  EllesmereUI = { RegisterSkin = function(name, fn) REGISTERED = name; SKINFN = fn end }
"""

def start(with_eui):
    lua = LuaRuntime()
    lua.execute(STUBS); lua.execute(EDITS)
    if with_eui: lua.execute(FAKE_EUI)
    ns = lua.table()
    load = lua.eval('function(src, name, ns) return load(src, name)("Persona", ns) end')
    for f in ("Traits.lua", "Moves.lua", "Share.lua", "UI.lua", "Skin.lua"):   # TOC order: Skin.lua last
        load(open(f).read(), f, ns)
    ns.db = lua.eval(VETERAN)
    ns.OnDBReady(ns.db)          # ADDON_LOADED: panel built before EllesmereUI calls back at login
    return lua, ns

def calls(lua, name, frame=None):
    out = []
    for c in lua.globals().CALLS.values():
        if c.name == name and (frame is None or lua.eval("rawequal")(c.frame, frame)):
            out.append(c)
    return out

# 1. With EllesmereUI: register under the folder name, skin at login
lua, ns = start(True)
g = lua.globals()
assert g.REGISTERED == "Persona"
assert len(g.CALLS) == 0, "nothing styled before EllesmereUI calls back"
g.SKINFN(g.SKIN)
u = ns.ui
assert calls(lua, "Shell", u.panel), "window"
assert calls(lua, "CloseButton", u.close)
assert calls(lua, "Button", u.share) and calls(lua, "Button", u.toggle), "Share and Persona buttons"
assert len(calls(lua, "Font")) >= 3 + 6, "title, subtitle, body and the six tab labels"
assert list(ns.accent.values()) == [0.2, 0.6, 1], "tab accent from the theme"
print("ok: panel handed to EllesmereUI at login; accent colour applied to tabs")

# 2. Share box opened after login is styled when built
ns.share.Show()
p = ns.share.parts
assert calls(lua, "Panel", p.box) and calls(lua, "EditBox", p.edit) and len(calls(lua, "Button")) >= 4
print("ok: share box styled when first opened")

# 3. Theme change updates the accent
lua.execute("ACCENT = { 0.9, 0.1, 0.4 }")
g.LOOKS()
assert list(ns.accent.values()) == [0.9, 0.1, 0.4]
print("ok: live theme change updates the tab accent")

# 4. Without EllesmereUI: default look, no errors
lua, ns = start(False)
assert list(ns.accent.values()) == [1, 0.82, 0]
ns.share.Show(); ns.SetPanel(True); ns.SetTab("Habits")
print("ok: without EllesmereUI nothing changes")
