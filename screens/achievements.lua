-- Achievements window (Hero -> Achievements): the main list, one row per achievement.
-- Only that list gets codes: an expanded set's dropdown lists the achievements required
-- for it, and the side panels are navigation. Rows are recognised by name; completion comes
-- from the game data (data/achievements.lua), so nothing is recorded from this window.

local achievements = require("data/achievements")

local achievementsScreen = {}

achievementsScreen.recordsOwnership = false -- uploaded from game data at login instead

local INTERFACE_ID, MAIN_LIST_ID = 1851, 40 -- Achievements, its list of achievement rows
local ICON_MARGIN = 22 -- the game puts status icons at the right end of each row

-- Returns the achievement rows in a list, in list order:
-- { label, key, category, owned, codeRight (x where our tier code ends) }
function achievementsScreen.readRows(list)
    local rows = {}
    pcall(function()
        list:IterateDynamicComponents(function(c)
            -- Only labels on screen: collapsed rows stay behind hidden at 0,0
            if c.type == ui.ComponentType.LABEL and c.visibleGlobal and c.width > 0 and c.height > 0 then
                local key = achievements.keyOf(c.content)
                if key ~= nil then
                    rows[#rows + 1] = {
                        label = c, key = key, category = "achievements",
                        owned = achievements.isComplete(c.content),
                        codeRight = math.min(c.x + c.width, list.width - ICON_MARGIN) - 2,
                    }
                end
            end
            return false -- keep iterating
        end)
    end)
    return rows
end

-- Returns { mainList } while the Achievements window shows it, else {}.
function achievementsScreen.visibleLists()
    local list = ui.Interfaces:GetComponent(INTERFACE_ID, MAIN_LIST_ID)
    if list ~= nil and list.visibleGlobal then
        return { list }
    end
    return {}
end

-- Nothing to forget: the main list is looked up directly every tick.
function achievementsScreen.forget()
end

return achievementsScreen
