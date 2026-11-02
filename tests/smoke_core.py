# Runs Core.lua against a stubbed client: checks the emote hooks count tokens,
# drop the duplicate when DoEmote and PerformEmote both fire in one frame,
# and only count solo dances with no target and no group.
import sys
from lupa import LuaRuntime
lua = LuaRuntime()
lua.execute(r'''
NOW = 100
function GetTime() return NOW end
function time() return 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local hooks = {}
function hooksecurefunc(a, b, c)
  if type(a) == "table" then hooks[b] = c else hooks[a] = b end
end
function fireHook(name, ...) hooks[name](...) end
local frame = { scripts = {} }
function frame:RegisterEvent() end
function frame:UnregisterEvent() end
function frame:SetScript(k, f) self.scripts[k] = f end
function CreateFrame() return frame end
CORE = frame
C_ChatInfo = { PerformEmote = function() end }
function DoEmote() end
function JumpOrAscendStart() end
TARGET, GROUPED = false, false
function UnitExists() return TARGET end
function IsInGroup() return GROUPED end
''')
ns = lua.table()
lua.eval('function(src, ns) return load(src, "Core.lua")("Persona", ns) end')(open(sys.argv[1]).read(), ns)
lua.execute('CORE.scripts.OnEvent(CORE, "ADDON_LOADED", "Persona")')
fire = lua.eval('function(name, tok, now, target, grouped) NOW = now; TARGET = target; GROUPED = grouped; fireHook(name, tok) end')

fire("PerformEmote", "dance", 1, False, False)   # counts, solo
fire("DoEmote", "DANCE", 1, False, False)        # same frame duplicate: dropped
fire("DoEmote", "DANCE", 2, True, False)         # has target: not solo
fire("PerformEmote", "DANCE", 3, False, True)    # grouped: not solo
fire("PerformEmote", "bow", 4, False, False)
db = lua.globals().PersonaDB
assert db.emotes["DANCE"] == 3, db.emotes["DANCE"]
assert db.emotes["BOW"] == 1
assert db.emoteTotal == 4, db.emoteTotal
assert db.soloDances == 1, db.soloDances
print("ok: emote hooks, duplicate filter and solo dances")
