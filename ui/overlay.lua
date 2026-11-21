-- Overlay: draws each row's rarity tier code ("R", coloured) at the right end of the row, with
-- the full rarity ("Rare: owned by 5.12% of players") as a tooltip on hover. Rows the player's
-- settings filter out (category, tier, not owned) get no code.
--
-- The codes are not children of the game's list: components added there share the game's
-- dynamic IDs and broke its scripts (expanding an achievement set left the list unscrollable).
-- Instead each list gets a viewport layer of ours on the plugin layer, laid over the list's
-- visible area, and follow() keeps the codes over their rows every tick.

local common = require("ui/common")
local tooltip = require("ui/tooltip")
local settings = require("data/settings")
local logger = require("lib/logger")

local overlay = {}

-- Per list (by "interface/static"):
--   viewport   our layer over the list's visible area
--   codes      { label, row, x, height, placedX, placedY, hidden } per code; row is the
--              game's row label (followed every tick), x is in the list's content coordinates
--   signature  the first and last rows when we drew, to detect a rebuild (see signatureOf)
--   view       the viewport's last position and size
local lists = {}

local function keyOf(list)
    return list.interfaceID .. "/" .. list.staticID
end

local function stateOf(list)
    local key = keyOf(list)
    lists[key] = lists[key] or { codes = {} }
    return lists[key]
end

-- The code shown in the row, its colour (nil: plain) and the tooltip text, for a rarity or
-- unknown (nil).
local function describe(rarity)
    if rarity == nil then
        return "?", nil, "Rarity not known yet"
    end
    local detail = rarity.percent == 0 and "owned by nobody yet (0%)"
        or formatStr("owned by {} of players", common.formatPercent(rarity.percent))
    -- owners is nil from an API that doesn't send it yet
    if rarity.owners ~= nil and rarity.percent > 0 and settings.get("player_counts") then
        detail = formatStr("{} ({} {})", detail, rarity.owners, rarity.owners == 1 and "player" or "players")
    end
    return rarity.tier, rarity.colour, formatStr("<col={}>{}</col>: {}", rarity.colour, rarity.tierName, detail)
end

-- The first and last rows by their place in the list (dynamic IDs) and what they say. When the
-- game rebuilds the list (other tab, category, ...) those places hold other rows, or none.
local function signatureOf(rows)
    local function spot(label)
        return { categoryID = label.categoryID, dynamicID = label.dynamicID, text = label.content }
    end
    return { first = spot(rows[1].label), last = spot(rows[#rows].label) }
end

-- Looked up fresh from the list every time: references to rows the game deleted can keep
-- answering with their old values.
local function signatureChanged(list, signature)
    local function stillThere(spot)
        local c = list:GetChild(spot.categoryID, spot.dynamicID)
        return c ~= nil and c.content == spot.text and c.visibleGlobal and c.height > 0
    end
    local ok, same = pcall(function() return stillThere(signature.first) and stillThere(signature.last) end)
    return not (ok and same)
end

-- The component that clips and scrolls the list: the list itself, or the nearest ancestor
-- whose content is bigger than itself. RS3 does both: Achievements scrolls the list itself,
-- Customisations scrolls a container around a list that is as tall as all its rows.
local function clipOf(list)
    local c = list
    for _ = 1, 8 do
        local ok, scrolls = pcall(function() return c.scrollHeight > c.height end)
        if ok and scrolls then
            return c
        end
        if c.parent == nil then
            break
        end
        c = c.parent
    end
    return list
end

-- True while our codes match the list's rows (no rebuild since we drew them).
function overlay.isDrawn(list)
    local state = stateOf(list)
    return state.signature ~= nil and common.alive(state.viewport) and not signatureChanged(list, state.signature)
end

-- Forces a redraw of every list on the next tick, e.g. once fresh rarity data has arrived.
function overlay.invalidate()
    for _, state in pairs(lists) do
        state.signature = nil
    end
end

-- Keeps a list's codes over their rows, every tick. Lays our viewport over the list's visible
-- area (its clip) and places each code by its own row's current position, shifted by where the
-- list sits in the clip and how far the clip is scrolled (xyGlobal ignores scrolling). Codes
-- outside the visible area are hidden. Rows move on their own while sets expand or collapse,
-- so each code follows its row rather than a position remembered at draw time.
function overlay.follow(list)
    local state = stateOf(list)
    if not common.alive(state.viewport) then
        return
    end

    -- Looked up every tick: right after a window opens the game hasn't set the list's scroll
    -- size yet, so an earlier answer can point at a component that never scrolls.
    local clip = clipOf(list)
    local clipAt, listAt = clip.xyGlobal, list.xyGlobal
    local x, y, width, height = math.floor(clipAt.x), math.floor(clipAt.y), clip.width, clip.height
    local view = state.view
    if view == nil or view.x ~= x or view.y ~= y or view.width ~= width or view.height ~= height then
        state.viewport:SetPos(x, y)
        state.viewport:SetSize(width, height)
        state.view = { x = x, y = y, width = width, height = height }
    end

    local offsetX = math.floor(listAt.x) - x - clip.scrollX
    local offsetY = math.floor(listAt.y) - y - clip.scrollY
    for _, code in ipairs(state.codes) do
        -- A row that's gone, hidden or collapsed (parked at 0,0 without size) hides its code
        local ok, rowY, rowShown = pcall(function()
            return code.row.y, code.row.visibleGlobal and code.row.height > 0
        end)
        local codeX, codeY = code.x + offsetX, (ok and rowY or 0) + offsetY
        local hidden = not (ok and rowShown) or codeY < 0 or codeY + code.height > height
        if hidden ~= code.hidden then
            code.label.hidden = hidden
            code.hidden = hidden
        end
        if not hidden and (codeX ~= code.placedX or codeY ~= code.placedY) then
            code.label:SetPos(codeX, codeY)
            code.placedX, code.placedY = codeX, codeY
        end
    end
end

-- Shows the viewports of the given lists and hides all others (closed windows, other tabs).
function overlay.showOnly(visibleLists)
    local visible = {}
    for _, list in ipairs(visibleLists) do
        visible[keyOf(list)] = true
    end
    for key, state in pairs(lists) do
        if common.alive(state.viewport) then
            state.viewport.hidden = not visible[key]
        end
    end
    if #visibleLists == 0 then
        tooltip.hide() -- the window closed while hovering a code
    end
end

-- Draws one tier code per row the settings show, its code column ending at row.codeRight on
-- the row's line. rarityOf(category, key) returns { tier, percent, owners, tierName, colour } or nil.
function overlay.draw(list, rows, rarityOf)
    tooltip.hide() -- it may belong to one of the codes about to go
    local state = stateOf(list)
    if common.alive(state.viewport) then
        state.viewport:DeleteAll() -- the previous codes; the viewport holds nothing else
    else
        state.viewport = ui.Layer.new(common.pluginLayer())
        state.viewport.clickthrough = true -- clicks and scrolling reach the game's list
    end
    state.codes, state.signature, state.view = {}, signatureOf(rows), nil

    for _, row in ipairs(rows) do
        local rarity = rarityOf(row.category, row.key)
        if not settings.shows(row.category, row.owned, rarity and rarity.tier) then
            goto continue -- the signature still covers the row, so no redraw every tick
        end
        local code, colour, detail = describe(rarity)
        local label = common.newCode(state.viewport, code, colour, row.label.height)
        label.hidden = true -- follow() places and shows it
        label:Subscribe(ui.Hook.ONMOUSEOVER, function()
            -- The game calls hooks directly, outside main.lua's error handling
            local ok, err = pcall(tooltip.show, detail)
            if not ok then
                logger.error("tooltip: {}", tostring(err))
            end
            return true
        end)
        label:Subscribe(ui.Hook.ONMOUSELEAVE, function()
            tooltip.hide()
            return true
        end)
        state.codes[#state.codes + 1] = { label = label, row = row.label, x = row.codeRight - common.CODE_WIDTH,
                                          height = row.label.height, hidden = true }
        ::continue::
    end
    overlay.follow(list)
end

return overlay
