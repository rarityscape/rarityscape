-- Customisations window: finds the visible Titles/Animations/Pets list and reads its rows.
-- The API has no "interface opened" event, so main.lua polls visibleLists() every logic tick.
-- Ownership is only visible here (greyed-out rows), so main.lua records it from these rows.

local catalogue = require("data/catalogue")

local customisations = {}

customisations.recordsOwnership = true

local INTERFACE_ID = 1311         -- Customisations
local MAX_STATIC_ID = 600         -- it has ~520 static components
local NOT_OWNED_RGBA = 0x8E8E8EFF -- the game greys out rows the player doesn't own
local SEARCH_EVERY = 5            -- ticks between list searches (10x/s)

local activeStaticID = nil -- static ID of the list currently showing
local tickCount = 0

-- Returns the cosmetic rows in a list, in list order:
-- { label, key, category, owned, codeRight (x where our tier code ends) }
function customisations.readRows(list)
    local rows = {}
    local seen = {} -- display name -> rows with that name so far (names repeat: 3x "Duke")
    -- pcall: most static components can't have children and throw here
    pcall(function()
        list:IterateDynamicComponents(function(c)
            -- Only labels on screen: hidden rows can sit at 0,0 with no size
            if c.type == ui.ComponentType.LABEL and c.visibleGlobal and c.width > 0 and c.height > 0 then
                local category = catalogue.categoryOf(c.content)
                if category ~= nil then
                    seen[c.content] = (seen[c.content] or 0) + 1
                    rows[#rows + 1] = { label = c, key = catalogue.keyOf(c.content, seen[c.content]),
                                        category = category, owned = c.rgba ~= NOT_OWNED_RGBA,
                                        codeRight = c.x + c.width - 2 }
                end
            end
            return false -- keep iterating
        end)
    end)
    return rows
end

-- Returns the cosmetics list currently on screen as { list }, or {} (one tab shows one list).
-- Cheap while the same list stays up; after forget() or a tab switch it searches the window
-- for the list that has rows.
function customisations.visibleLists()
    tickCount = tickCount + 1
    local itf = ui.Interfaces:GetInterface(INTERFACE_ID)
    if itf == nil then
        activeStaticID = nil -- window closed
        return {}
    end

    if activeStaticID ~= nil then
        local list = itf:GetComponent(activeStaticID)
        if list ~= nil and list.visibleGlobal then
            return { list }
        end
        activeStaticID = nil -- switched to another tab
    end

    -- No list showing yet: search the window's components, at most every SEARCH_EVERY ticks
    if tickCount % SEARCH_EVERY ~= 0 then
        return {}
    end
    for staticID = 0, MAX_STATIC_ID do
        local ok, list = pcall(itf.GetComponent, itf, staticID)
        if ok and list ~= nil and list.visibleGlobal and #customisations.readRows(list) > 0 then
            activeStaticID = staticID
            return { list }
        end
    end
    return {}
end

-- Drops the current list so the next call searches again. Needed because on a tab switch
-- the game empties the old list but can leave it "visible".
function customisations.forget(_list)
    activeStaticID = nil
end

return customisations
