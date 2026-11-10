-- Persona: share card.
-- Addons can't write to the clipboard, so this shows the text in a box with
-- everything selected: Ctrl+C, then paste into Discord or chat.

local _, ns = ...
local T = ns.traits
local S = {}
ns.share = S

S.CHAT_LIMIT = 255
local TOP = 3

local function classLine()
  local level, race, class = UnitLevel("player"), UnitRace("player"), UnitClass("player")
  return ("Level %d %s %s"):format(level or 0, race or "", class or "")
end

-- kind: "discord" (several lines, Markdown) or "chat" (one line, fits a chat message)
function S.Text(kind)
  local db = ns.db
  if not db then return "" end
  local traits = T.Build(db)
  local title = T.Headline(traits)
  local name = UnitName("player") or "This character"

  if kind == "chat" then
    if #traits == 0 then
      return ("%s hasn't revealed a personality yet. (Persona addon)"):format(name)
    end
    local suffix = " (Persona addon)"
    local line = title .. ":"
    for i = 1, math.min(TOP, #traits) do
      local piece = (i == 1 and " " or ", ") .. traits[i].label
      -- Keep within one chat message: drop traits rather than cut one in half
      if #line + #piece + #suffix > S.CHAT_LIMIT then break end
      line = line .. piece
    end
    return line .. suffix
  end

  local lines = { "**" .. title .. "**", classLine(), "" }
  if #traits == 0 then
    lines[#lines + 1] = ("%s hasn't revealed a personality yet."):format(name)
  else
    for i = 1, math.min(TOP, #traits) do
      lines[#lines + 1] = ("- **%s.** %s"):format(traits[i].label, traits[i].text)
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "_Made with Persona, a World of Warcraft addon_"
  return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- The copy box
---------------------------------------------------------------------------
local box, edit, hint, kindButtons
local current = "discord"

local function fill()
  edit:SetText(S.Text(current))
  edit:SetFocus()
  edit:HighlightText()
  for k, b in pairs(kindButtons) do
    b:SetAlpha(k == current and 1 or 0.6)
  end
end

local function build()
  box = CreateFrame("Frame", "PersonaShareBox", UIParent, "BackdropTemplate")
  box:SetSize(420, 230)
  box:SetPoint("CENTER")
  box:SetFrameStrata("DIALOG")
  box:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  box:SetBackdropColor(0.04, 0.04, 0.07, 0.97)
  box:EnableMouse(true)
  box:SetMovable(true)
  box:RegisterForDrag("LeftButton")
  box:SetScript("OnDragStart", box.StartMoving)
  box:SetScript("OnDragStop", box.StopMovingOrSizing)

  local heading = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  heading:SetPoint("TOPLEFT", 14, -14)
  heading:SetText("Share your Persona")

  local close = CreateFrame("Button", nil, box, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)

  kindButtons = {}
  local x = 14
  for _, k in ipairs({ "discord", "chat" }) do
    local b = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    b:SetSize(90, 22)
    b:SetPoint("TOPLEFT", x, -40)
    b:SetText(k == "discord" and "Discord" or "Chat")
    b:SetScript("OnClick", function() current = k; fill() end)
    kindButtons[k] = b
    x = x + 96
  end

  local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -70)
  scroll:SetPoint("BOTTOMRIGHT", -34, 36)
  edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject("ChatFontNormal")
  edit:SetWidth(360)
  edit:SetScript("OnEscapePressed", function() box:Hide() end)
  -- Typing in the box would change the text; put it back so a stray key can't spoil the copy
  edit:SetScript("OnTextChanged", function(self, userInput)
    if userInput then self:SetText(S.Text(current)); self:HighlightText() end
  end)
  scroll:SetScrollChild(edit)

  hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", 14, 14)
  hint:SetText("Press Ctrl+C to copy (Cmd+C on a Mac), then paste it anywhere.")

  tinsert(UISpecialFrames, "PersonaShareBox")   -- Escape closes it like other windows
  box:Hide()

  -- The parts a UI skin (Skin.lua) restyles
  S.parts = { box = box, close = close, edit = edit, scroll = scroll, heading = heading, hint = hint,
              buttons = { kindButtons.discord, kindButtons.chat } }
  if ns.skin then ns.skin.ShareBox() end
end

function S.Show(kind)
  if not box then build() end
  current = kind or current
  box:Show()
  fill()
end

function S.IsShown() return box ~= nil and box:IsShown() end
