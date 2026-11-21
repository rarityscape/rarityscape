-- Logger: every message goes to the in-game console AND to a rolling log in PersistentDB
-- (key "log"), so it can be read outside the game from plugins/PluginData.db. The console
-- can't be copied from and the client writes no log file.

local logger = {}

local MAX_LINES = 300 -- keeps the stored log well under PersistentDB's size limit

-- Continue the log from the previous session/reload
local lines = {}
for line in (PersistentDB:GetString("log") or ""):gmatch("[^\n]+") do
    lines[#lines + 1] = line
end

-- No timestamps: os.date isn't available to plugins.
local function write(level, pattern, ...)
    local message = level .. " " .. formatStr(pattern, ...)
    print(message)
    lines[#lines + 1] = message
    while #lines > MAX_LINES do
        table.remove(lines, 1)
    end
    PersistentDB:SetString("log", table.concat(lines, "\n"))
end

-- formatStr-style: logger.info("Synced {}: {} owned", category, count).
-- Pass variable text (errors, names) as values, not inside the pattern.
function logger.info(pattern, ...)
    write("INFO", pattern, ...)
end

function logger.error(pattern, ...)
    write("ERROR", pattern, ...)
end

return logger
