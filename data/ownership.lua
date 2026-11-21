-- Ownership: which titles, animations and pets the player owns, as last seen in the
-- Customisations lists (the only place the game shows it), keyed by struct ID. Persisted in
-- PersistentDB so lists seen in earlier sessions still count. PersistentDB is shared by every
-- character played on this PC, so each player has their own snapshots
-- ("owned_<category>_<player>"): one character's unlocks never end up in another's uploads.

local catalogue = require("data/catalogue")
local logger = require("lib/logger")

local ownership = {}

local player = nil    -- whose snapshots are loaded (see usePlayer)
local snapshots = nil -- category -> { key -> owned }, for that player

local function savedAs(category)
    return "owned_" .. category .. "_" .. player
end

-- Loads a player's snapshots, on every login and before anything is recorded. playerID is the
-- API's (hashed) player ID; its first 16 hex digits are plenty to tell this PC's players apart.
function ownership.usePlayer(playerID)
    player, snapshots = playerID:sub(1, 16), {}
    for category in pairs(catalogue.ENUMS) do
        snapshots[category] = PersistentDB:GetStructuredData(savedAs(category)) or {}
    end
end

-- Merges the rows of a list that was just shown (one category) into that category's snapshot.
-- Returns the category.
function ownership.record(rows)
    local category = rows[1].category
    local snapshot, changed = snapshots[category], 0
    for _, row in ipairs(rows) do
        if snapshot[row.key] ~= row.owned then
            snapshot[row.key] = row.owned
            changed = changed + 1
        end
    end
    if changed > 0 then
        PersistentDB:SetStructuredData(savedAs(category), snapshot)
        logger.info("ownership: {} {} changed", changed, category)
    end
    return category
end

-- Keys of everything owned in a category, as far as its lists have been seen.
function ownership.ownedKeys(category)
    local keys = {}
    for key, owned in pairs(snapshots[category]) do
        if owned then
            keys[#keys + 1] = key
        end
    end
    return keys
end

return ownership
