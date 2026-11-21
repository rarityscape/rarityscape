-- Shared by the overlay, the tooltip and the settings: the look of our text, percentages, and
-- helpers for our own components on the plugin layer (the layer the API reserves for plugins,
-- above the game's UI).

local common = {}

common.FONT = 26 -- the game's plain font; some rows use a serif one, our codes never do
common.TEXT_COLOUR = Vector4.new(0.89, 0.84, 0.81, 1.0) -- 0xE3D7CF, the game's row text

-- Tier codes ("C" … "UR") sit left-aligned in a column this wide wherever they're drawn (the
-- lists' overlay, the settings), so they line up with each other and with what follows them.
common.CODE_WIDTH = 26

-- A tier code (or "?") as a text component `height` tall in the code column, in the tier's
-- colour (hex, nil for plain text). The caller places it.
function common.newCode(parent, code, colour, height)
    local text = ui.Text.new(parent)
    text.font = common.FONT
    text.isShadowed = true
    text.colour = common.TEXT_COLOUR
    text.content = colour and formatStr("<col={}>{}</col>", colour, code) or code
    text:SetSize(common.CODE_WIDTH, height)
    text:AlignTo(ui.AlignMode.TOPLEFT, ui.AlignMode.CENTRE)
    return text
end

-- At most 2 decimals; "<0.01%" for tiny shares, "0%" only when nobody owns it. Same rules as
-- formatPercent in the API's src/tiers.js.
function common.formatPercent(percent)
    if percent == 0 then
        return "0%"
    end
    if percent < 0.01 then
        return "<0.01%"
    end
    local text = string.format("%.2f", percent):gsub("0+$", ""):gsub("%.$", "") -- 50.00 -> 50
    return text .. "%"
end

function common.pluginLayer()
    return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
end

-- True if one of our components still exists. The game can reload the plugin layer (e.g.
-- after an interface layout change), which removes everything on it.
function common.alive(component)
    return component ~= nil and pcall(function() return component.visible end)
end

return common
