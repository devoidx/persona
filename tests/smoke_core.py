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
# Exactly what Blizzard's world map and mailbox do on open
auto = lua.eval('function(now) NOW = now; fireHook("PerformEmote", "READ", nil, true) end')

fire("PerformEmote", "dance", 1, False, False)   # counts, solo
fire("DoEmote", "DANCE", 1, False, False)        # same frame duplicate: dropped
fire("DoEmote", "DANCE", 2, True, False)         # has target: not solo
fire("PerformEmote", "DANCE", 3, False, True)    # grouped: not solo
fire("PerformEmote", "bow", 4, False, False)
auto(5); auto(6)                                 # map, then mailbox: not the player's emotes
fire("PerformEmote", "READ", 7, False, False)    # a typed /read still counts
db = lua.globals().PersonaDB
assert db.emotes["DANCE"] == 3, db.emotes["DANCE"]
assert db.emotes["BOW"] == 1
assert db.emotes["READ"] == 1, ("map/mailbox READ must not count", db.emotes["READ"])
assert db.emoteTotal == 5, db.emoteTotal
assert db.soloDances == 1, db.soloDances
print("ok: emote hooks, duplicate filter, solo dances, automatic READ ignored")

# Upgrade from 0.5.0: Tony's real numbers, 15 emotes of which 10 bogus READ
old = lua.eval('{ version = 1, emotes = { READ = 10, DANCE = 3, BOW = 2 }, emoteTotal = 15 }')
ns.migrate(old)
assert old.emotes["READ"] is None and old.emoteTotal == 5 and old.version == 2, (old.emoteTotal, old.version)
ns.migrate(old)   # runs again on every load: must be a no-op now
assert old.emoteTotal == 5
fresh = lua.eval('{ emotes = {}, emoteTotal = 0 }'); ns.migrate(fresh)
assert fresh.version == 2 and fresh.emoteTotal == 0
print("ok: 0.5.0 data upgraded once (15 -> 5), fresh installs untouched")
