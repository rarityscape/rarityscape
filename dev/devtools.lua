-- Devtools: research dumps used to reverse-engineer the game data and UI. Not used at
-- runtime; main.lua runs one on load when DEV_DUMP is set. A dump is saved to PersistentDB
-- as "<name>_1".."<name>_N" with N in "<name>_count" (plugins/PluginData.db, readable
-- from WSL with sqlite), since the client writes no log file and the console can't be copied.

local catalogue = require("data/catalogue")
local logger = require("lib/logger")

local devtools = {}

local CHUNK_CHARS = 90000 -- one big PersistentDB string silently fails to save

-- Saves lines under "<name>_1".."<name>_N" plus "<name>_count"; returns N.
function devtools.save(name, lines)
    local text = table.concat(lines, "\n")
    local chunks = 0
    for start = 1, #text, CHUNK_CHARS do
        chunks = chunks + 1
        PersistentDB:SetString(name .. "_" .. chunks, text:sub(start, start + CHUNK_CHARS - 1))
    end
    PersistentDB:SetInt(name .. "_count", chunks)
    return chunks
end

-- Reads a property, or nil when `v` doesn't have it (plain values, other config types).
local function field(v, key)
    local ok, value = pcall(function() return v[key] end)
    if ok then
        return value
    end
    return nil
end

-- Config values print as "NAME#id" (plus the current value for variables).
local function describe(v)
    local name = field(v, "configName")
    if name == nil then
        return tostring(v)
    end
    local text = name .. "#" .. tostring(field(v, "id"))
    local typeName = field(v, "typeName")
    if typeName ~= nil and typeName:sub(1, 3) == "Var" then
        text = text .. " = " .. tostring(field(v, "value"))
    end
    return text
end

local function componentKey(c)
    return formatStr("{}/{}:{}:{}", c.interfaceID, c.staticID, c.categoryID, c.dynamicID)
end

-- Calls fn for each dynamic child of c (nothing if c can't have children).
local function eachChild(c, fn)
    pcall(function()
        c:IterateDynamicComponents(function(child)
            fn(child)
            return false
        end)
    end)
end

-- "names": configs and VarPlayers whose name contains a keyword. id.* tables can't be
-- listed with pairs(), so this walks ID ranges with FromID. Freezes the game a few seconds.
local function names(lines)
    local KEYWORDS = { "TITLE", "PET", "EMOTE", "ANIM", "CUSTOMIS", "COSMETIC" }
    local SCANS = {
        { "DBTable", config.DBTable, 0, 5000 },
        { "Enum", config.Enum, 0, 40000 },
        { "Param", config.Param, 0, 20000 },
        { "Struct", config.Struct, 0, 120000 },
        { "VarPlayer", var.VarPlayer, -70000, 20000 }, -- VarBits have negative IDs
    }
    for _, scan in ipairs(SCANS) do
        local label, configTable, firstID, lastID = table.unpack(scan)
        local count, hits = 0, 0
        for i = firstID, lastID do
            local ok, cfg = pcall(configTable.FromID, i)
            if ok and cfg ~= nil then
                count = count + 1
                for _, keyword in ipairs(KEYWORDS) do
                    if cfg.configName:find(keyword, 1, true) then
                        hits = hits + 1
                        lines[#lines + 1] = label .. " " .. describe(cfg)
                        break
                    end
                end
            end
        end
        lines[#lines + 1] = formatStr("== {}: {} configs, {} matches", label, count, hits)
    end
end

-- Every param config, loaded on first use: Struct.paramValues throws inside the API, so
-- structParams() asks each struct about each param instead.
local allParams = nil

local function structParams(lines, struct, indent)
    if allParams == nil then
        allParams = {}
        for paramID = 0, 10000 do
            local ok, p = pcall(config.Param.FromID, paramID)
            if ok and p ~= nil then
                allParams[#allParams + 1] = p
            end
        end
    end
    for _, param in ipairs(allParams) do
        if struct:HasParam(param) then
            lines[#lines + 1] = indent .. describe(param) .. " = " .. describe(struct:GetParamValue(param))
        end
    end
end

-- "cosmetics": the first entries of each catalogue enum, with all their struct params.
local function cosmetics(lines)
    for category, enumName in pairs(catalogue.ENUMS) do
        lines[#lines + 1] = formatStr("== {} ({})", category, enumName)
        for i, pair in ipairs(config.Enum[enumName].values) do
            if i > 6 then
                break
            end
            local struct = config.Struct.FromID(pair[2].id)
            lines[#lines + 1] = "  " .. describe(struct)
            structParams(lines, struct, "    ")
        end
    end
end

-- "lists": the busiest visible lists in any open interface, every child with its type,
-- position, colour and text. Shows how a list marks entries (greyed out = not owned).
local function lists(lines)
    local TOP_LISTS, MAX_CHILDREN, MAX_DEPTH = 5, 400, 3
    local found = {}
    for interfaceID = 0, 3000 do
        local ok, itf = pcall(ui.Interfaces.GetInterface, ui.Interfaces, interfaceID)
        if ok and itf ~= nil then
            -- Static IDs are numbered from 0, so stop after a run of missing ones
            local staticID, misses = 0, 0
            while misses < 20 do
                local got, c = pcall(itf.GetComponent, itf, staticID)
                if got and c ~= nil then
                    misses = 0
                    if c.visibleGlobal then
                        local count = 0
                        eachChild(c, function() count = count + 1 end)
                        if count > 0 then
                            found[#found + 1] = { component = c, count = count }
                        end
                    end
                else
                    misses = misses + 1
                end
                staticID = staticID + 1
            end
        end
    end
    table.sort(found, function(a, b) return a.count > b.count end)

    local function describeComponent(c, indent)
        local rgba = field(c, "rgba")
        local text = c.type == ui.ComponentType.LABEL and (' "' .. tostring(field(c, "content")) .. '"') or ""
        lines[#lines + 1] = formatStr("{}{} type={} at {},{} size {}x{} rgba={} alpha={}{}", indent,
            componentKey(c), tostring(c.type), c.x, c.y, c.width, c.height,
            rgba and string.format("%08X", rgba) or "?", tostring(field(c, "alpha")), text)
    end

    -- Children nested up to MAX_DEPTH deep (grids and collapsible sections nest rows)
    local function describeTree(c, depth)
        describeComponent(c, string.rep("  ", depth))
        if depth < MAX_DEPTH then
            eachChild(c, function(child) describeTree(child, depth + 1) end)
        end
    end

    for i = 1, math.min(TOP_LISTS, #found) do
        lines[#lines + 1] = formatStr("== LIST {} with {} dynamic children",
            componentKey(found[i].component), found[i].count)
        local dumped = 0
        eachChild(found[i].component, function(child)
            dumped = dumped + 1
            if dumped <= MAX_CHILDREN then
                describeTree(child, 1)
            end
        end)
    end
end

-- "achievements": every label in the Achievements window (interface 1851) whose text is an
-- achievement name, with where it lives; plus every visible static holding dynamic children.
local function achievementRows(lines)
    local ACHIEVEMENTS_INTERFACE, MAX_DEPTH = 1851, 4
    local achievements = require("data/achievements")
    local itf = ui.Interfaces:GetInterface(ACHIEVEMENTS_INTERFACE)
    if itf == nil then
        lines[#lines + 1] = "Achievements window not open"
        return
    end

    local function visit(c, depth)
        if c.type == ui.ComponentType.LABEL and achievements.isComplete(c.content) ~= nil then
            lines[#lines + 1] = formatStr("ROW {} parent={} static={} at {},{} size {}x{} rgba={} font={} visible={} \"{}\"",
                componentKey(c), c.parent and componentKey(c.parent) or "none",
                c.parentStatic and componentKey(c.parentStatic) or "none", c.x, c.y, c.width, c.height,
                string.format("%08X", c.rgba), tostring(c.font), tostring(c.visibleGlobal), c.content)
        end
        if depth < MAX_DEPTH then
            eachChild(c, function(child) visit(child, depth + 1) end)
        end
    end

    local staticID, misses = 0, 0
    while misses < 20 do
        local got, c = pcall(itf.GetComponent, itf, staticID)
        if got and c ~= nil then
            misses = 0
            local count = 0
            eachChild(c, function() count = count + 1 end)
            if count > 0 then
                lines[#lines + 1] = formatStr("STATIC {} visible={} at {},{} size {}x{} dynamic children={}",
                    componentKey(c), tostring(c.visibleGlobal), c.x, c.y, c.width, c.height, count)
            end
            visit(c, 0)
        else
            misses = misses + 1
        end
        staticID = staticID + 1
    end
end

local DUMPS = { names = names, cosmetics = cosmetics, lists = lists, achievements = achievementRows }

-- Runs a named dump ("names", "cosmetics", "lists" or "achievements") and saves it.
function devtools.run(name)
    local lines = {}
    local ok, err = pcall(DUMPS[name], lines)
    if not ok then
        table.insert(lines, 1, "ERROR: " .. tostring(err))
    end
    local chunks = devtools.save(name, lines)
    logger.info("Dump '{}': {} lines in {} chunks", name, #lines, chunks)
end

return devtools
