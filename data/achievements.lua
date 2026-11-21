-- Achievements: every achievement and whether the player completed it, read straight from
-- the game's configs, so no window has to be opened. Each achievement's key is its config ID,
-- the same in every client language; its display name (in this client's language) is how
-- rows in the Achievements window are recognised, and is uploaded as a label.
-- main.lua uploads the completed keys on login, and hourly when more were completed.

local achievements = {}

local MAX_ACHIEVEMENT_ID = 6000       -- IDs run up to ~5120
local COMPLETE, DEPRECATED = -2, -4   -- AchievementProgressType values of `progress`

local configsByName = {} -- display name -> configs with that name (names repeat across variants)
local nameByKey = {}     -- key -> display name
local configs = {}       -- every config we track
for achievementID = 0, MAX_ACHIEVEMENT_ID do
    local ok, cfg = pcall(config.Achievement.FromID, achievementID)
    -- League tasks are a separate game mode, not shown in the Achievements window
    if ok and cfg ~= nil and cfg.name ~= "" and cfg.configName:sub(1, 7) ~= "LEAGUE_" then
        configsByName[cfg.name] = configsByName[cfg.name] or {}
        table.insert(configsByName[cfg.name], cfg)
        nameByKey[tostring(cfg.id)] = cfg.name
        configs[#configs + 1] = cfg
    end
end

-- The key of the achievement shown with this display name, or nil when there's none.
-- Note: same-named variants map to the first one, since a row can't tell them apart.
function achievements.keyOf(name)
    local named = configsByName[name]
    return named and tostring(named[1].id)
end

-- True when the player completed the achievement shown with this display name, nil when
-- there's none.
function achievements.isComplete(name)
    local named = configsByName[name]
    return named and named[1].progress == COMPLETE
end

-- Keys of every current (not deprecated) achievement, for the catalogue sync.
function achievements.keys()
    local keys = {}
    for _, cfg in ipairs(configs) do
        if cfg.progress ~= DEPRECATED then
            keys[#keys + 1] = tostring(cfg.id)
        end
    end
    return keys
end

-- Keys of the achievements the player completed.
function achievements.completedKeys()
    local keys = {}
    for _, cfg in ipairs(configs) do
        if cfg.progress == COMPLETE then
            keys[#keys + 1] = tostring(cfg.id)
        end
    end
    return keys
end

-- The display name for a key (uploaded as the label), or nil.
function achievements.nameOf(key)
    return nameByKey[key]
end

return achievements
