-- Catalogue sync: keeps the backend's list of items (and their English names) complete, about
-- once per RS3 update instead of with every upload. Per category, a fingerprint of every key in
-- the game data is compared with the one saved after the last successful sync (PersistentDB
-- "catalogue_fp_<category>"). Only when it differs (new content, or first run) do we send all
-- keys (the API registers new ones and answers which lack a label), and then, from English
-- clients only, those labels, so the stats page shows English names.

local api = require("sync/api")
local sha256 = require("lib/sha256")

local catalogueSync = {}

-- A fingerprint of a set of keys, the same whatever their order: changes when a key is
-- added or removed (e.g. new content in an RS3 update).
local function fingerprint(keys)
    local sorted = {}
    for i, key in ipairs(keys) do
        sorted[i] = key
    end
    table.sort(sorted)
    return #sorted .. "-" .. sha256.hex(table.concat(sorted, ","))
end

-- The Language option's labels are always in English ("English", "German", ...)
local function isEnglishClient()
    local ok, language = pcall(function()
        local option = game.options.Language
        return option:GetLabel(option.setting)
    end)
    return ok and language == "English"
end

-- sources: { category -> { keys = { key, ... }, nameOf = function(key) -> display name } }
function catalogueSync.sync(sources)
    local english = isEnglishClient()
    for category, source in pairs(sources) do
        local current = fingerprint(source.keys)
        local savedAs = "catalogue_fp_" .. category
        if PersistentDB:GetString(savedAs) ~= current then
            api.checkCatalogue(category, source.keys, function(missingKeys)
                local function done()
                    PersistentDB:SetString(savedAs, current)
                end
                if #missingKeys == 0 or not english then
                    done() -- nothing to add, or not ours to add (labels must be English)
                else
                    api.uploadLabels(category, missingKeys, source.nameOf, done)
                end
            end)
        end
    end
end

return catalogueSync
