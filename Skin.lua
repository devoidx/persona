-- Persona: matching the player's UI suite.
-- EllesmereUI publishes a skinning API: register once, and at login it hands
-- over a table of primitives that restyle frames in the player's chosen look.
-- The player can turn this off per addon in EllesmereUI's options, in which
-- case the callback never runs and Persona keeps the default look.
-- API: https://github.com/EllesmereGaming/EllesmereUI/blob/main/SKINNING_API.md

local _, ns = ...
local K = {}
ns.skin = K

local S   -- EllesmereUI's skin primitives, once it has called us

local function font(fs) if fs and S.Font then S.Font(fs) end end

-- Accent colour for the selected tab; re-read whenever the theme changes
function K.Accent()
  if not (S and S.GetAccentColor) then return end
  local r, g, b = S.GetAccentColor()
  if r then ns.accent = { r, g, b } end
  if ns.Refresh then ns.Refresh() end
end

function K.Panel()
  local u = ns.ui
  if not (S and u and u.panel) then return end
  if S.Shell then S.Shell(u.panel) end
  if S.CloseButton and u.close then S.CloseButton(u.close) end
  if S.Button then
    if u.share then S.Button(u.share) end
    if u.toggle then S.Button(u.toggle) end
  end
  font(u.title); font(u.subtitle); font(u.body)
  -- Tabs are Persona's own buttons, not Blizzard tab templates, so they take
  -- the theme's font and accent colour rather than S.Tab
  for _, b in pairs(u.tabs or {}) do font(b.label) end
  K.Accent()
end

function K.ShareBox()
  local p = ns.share and ns.share.parts
  if not (S and p and p.box) then return end
  if S.Panel then S.Panel(p.box) end
  if S.CloseButton and p.close then S.CloseButton(p.close) end
  if S.Button then
    for _, b in ipairs(p.buttons or {}) do S.Button(b) end
  end
  if S.EditBox and p.edit then S.EditBox(p.edit) end                     -- API v3+
  if S.ScrollBar and p.scroll and p.scroll.ScrollBar then S.ScrollBar(p.scroll.ScrollBar) end
  font(p.heading); font(p.hint)
end

if EllesmereUI and EllesmereUI.RegisterSkin then
  EllesmereUI.RegisterSkin("Persona", function(skin)
    S = skin
    K.Panel()
    K.ShareBox()   -- only if the share box has been opened already; otherwise it skins itself when built
    if S.OnLooksChanged then S.OnLooksChanged(K.Accent) end
  end)
end
