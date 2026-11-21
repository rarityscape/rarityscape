-- Settings: the player's choices and which rows they give a tier code. Saved in PersistentDB as
-- "setting_<name>", per PC like any preference (every character played here shares them). The
-- cog's panel (ui/settings_panel.lua) shows and changes them; the overlay asks shows().

local logger = require("lib/logger")

local settings = {}

-- Every setting is a tickbox (snake_case like the plugin's other keys): titles, animations,
-- pets, achievements, tier_<code> (tier_ur … tier_c), owned_only and player_counts. All are on
-- by default except those listed here.
local DEFAULTS = { owned_only = false, player_counts = false }

local values = {} -- name -> true/false, read from PersistentDB on first use

function settings.get(name)
    if values[name] == nil then
        local saved = PersistentDB:GetBool("setting_" .. name) -- nil until first changed
        if saved == nil then
            saved = DEFAULTS[name] ~= false
        end
        values[name] = saved
    end
    return values[name]
end

-- Saves a setting; returns true when that changed it (the panel can report the same change
-- twice: a row click and the tickbox's own press).
function settings.set(name, value)
    if value == settings.get(name) then
        return false
    end
    values[name] = value
    PersistentDB:SetBool("setting_" .. name, value)
    logger.info("setting {} is now {}", name, tostring(value))
    return true
end

-- The setting for a tier, by its code: "UR" -> "tier_ur".
function settings.tierSetting(code)
    return "tier_" .. code:lower()
end

-- Whether a row gets a tier code: its category and tier are shown, and it's owned unless
-- owned_only is off. tier is nil while the item's rarity isn't known.
function settings.shows(category, owned, tier)
    return settings.get(category)
        and (owned or not settings.get("owned_only"))
        and (tier == nil or settings.get(settings.tierSetting(tier)))
end

return settings
