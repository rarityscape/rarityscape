-- Catalogue: the game's own list of every title, animation and pet (the Customisations
-- window), read from config enums at load. Each cosmetic's key is its struct ID, which is the
-- same in every client language; its display name (in this client's language) is how list
-- rows are recognised, and is uploaded as a label.

local catalogue = {}

-- Category -> enum listing its entries; each entry is a struct with MTXMGT_* params
-- (MTXMGT_NAME, MTXMGT_SUBCAT, MTXMGT_POS_STRING, ...).
catalogue.ENUMS = {
    titles = "MTXMGT_CATEGORY_LIST_TITLE",
    animations = "MTXMGT_CATEGORY_LIST_ANIM",
    pets = "MTXMGT_CATEGORY_LIST_PET",
}

local categoryByName = {} -- display name -> category
local keysByName = {}     -- display name -> { key, ... } in catalogue order (names repeat: 3x "Duke")
local keysByCategory = {} -- category -> { key, ... }
local nameByKey = {}      -- key -> display name

for category, enumName in pairs(catalogue.ENUMS) do
    keysByCategory[category] = {}
    for _, pair in ipairs(config.Enum[enumName].values) do
        -- Enum values don't expose struct params, so reload the struct by ID
        local structID = pair[2].id
        local name = config.Struct.FromID(structID):GetParamValue(config.Param.MTXMGT_NAME)
        if name ~= nil and name ~= "" and name ~= "Clear title" then -- "Clear title": not an unlockable
            local key = tostring(structID)
            categoryByName[name] = category
            keysByName[name] = keysByName[name] or {}
            table.insert(keysByName[name], key)
            table.insert(keysByCategory[category], key)
            nameByKey[key] = name
        end
    end
end

-- Every key in a category, for the catalogue sync.
function catalogue.keysOf(category)
    return keysByCategory[category]
end

-- "titles", "animations" or "pets" for a cosmetic's display name, or nil.
function catalogue.categoryOf(name)
    return categoryByName[name]
end

-- The key of the nth cosmetic with this display name, counting in catalogue order (lists show
-- cosmetics in that order, so the 2nd "Duke" row is the 2nd "Duke" struct).
-- Note: a sub-tab that leaves out same-named entries of other groups can shift this count.
function catalogue.keyOf(name, nth)
    local keys = keysByName[name]
    return keys and (keys[nth] or keys[#keys])
end

-- The display name for a key (uploaded as the label), or nil.
function catalogue.nameOf(key)
    return nameByKey[key]
end

return catalogue
