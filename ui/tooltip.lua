-- Tooltip: one text box on the plugin layer, shown next to the mouse cursor.
-- Note: the Mouse API doesn't apply UI scaling yet, so at an interface scale other than 100%
-- the box may sit a little away from the cursor.

local common = require("ui/common")

local tooltip = {}

local MIN_WIDTH, HEIGHT = 260, 26
-- shortcut: estimated width per character of common.FONT; measure the text if the API ever can
local CHAR_WIDTH = 7
local BACKGROUND = Vector4.new(0.08, 0.07, 0.06, 0.92)
local CURSOR_GAP = 16

local box, text = nil, nil -- created on first use, and again if the plugin layer was reloaded

local function create()
    box = ui.Layer.new(common.pluginLayer())
    local background = ui.Rectangle.new(box)
    background:SetSize(0, 0, 1.0, 1.0)
    background.colour = BACKGROUND
    background.fill = true
    text = ui.Text.new(box)
    text:SetPos(8, 0)
    text:SetSize(-16, 0, 1.0, 1.0)
    text.colour = common.TEXT_COLOUR
    text.font = common.FONT
    text:AlignTo(ui.AlignMode.TOPLEFT, ui.AlignMode.CENTRE)
end

-- Shows `content` (game text markup allowed) next to the mouse cursor.
function tooltip.show(content)
    local mouse = Mouse.IsAvailable() and Mouse.GetPosition() or nil
    if mouse == nil then
        return -- no mouse, no hover (mobile)
    end
    if not common.alive(box) then
        create()
    end
    text.content = content
    local plain = content:gsub("<[^>]*>", "") -- without colour markup
    local width = math.max(MIN_WIDTH, #plain * CHAR_WIDTH + 16)
    box:SetSize(width, HEIGHT)

    local x, y = math.floor(mouse.x) + CURSOR_GAP, math.floor(mouse.y) - HEIGHT // 2
    if x + width > box.parent.width then
        x = math.floor(mouse.x) - CURSOR_GAP - width -- left of the cursor near the right edge
    end
    box:SetPos(x, y)
    box.hidden = false
    box:MoveToFront()
end

function tooltip.hide()
    if common.alive(box) then
        box.hidden = true
    end
end

return tooltip
