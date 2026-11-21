-- RarityScape: shows how rare each title, animation, pet and achievement is, right in the
-- game's windows, and keeps the player's own unlocks synced to the rarity API.
--
-- Files:
--   main.lua                    wiring, the per-tick loop and when to sync
--   secret.lua                  the request signing key
--   data/catalogue.lua          game data: every title/animation/pet, its key and name
--   data/achievements.lua       game data: every achievement, its key and completion
--   data/ownership.lua          owned titles/animations/pets as seen in Customisations, per player
--   data/settings.lua           the player's choices: which rows get a code, tooltip options
--   screens/customisations.lua  the Customisations window's visible list and its rows
--   screens/achievements.lua    the Achievements window's main list and its rows
--   ui/overlay.lua              the tier code on each row; ui/tooltip.lua its hover text
--   ui/settings_panel.lua       the cog's settings panel in the Plugin Hub
--   ui/common.lua               our text look, the tier code column, percentages
--   sync/api.lua                HTTP to the rarity backend, and the player's (hashed) ID
--   sync/catalogue.lua          keeps the backend's item list and English labels complete
--   sync/sign.lua               request signatures (HMAC-SHA256)
--   lib/sha256.lua              SHA-256 and HMAC-SHA256 (signatures, player ID, fingerprints)
--   lib/json.lua, lib/logger.lua  JSON; logging to the console and PersistentDB ("log")
--   dev/devtools.lua            research dumps, development only (see DEV_DUMP)
--
-- Sync with the API (uploads send only the owned keys per category):
--   achievements            on login, then checked hourly and re-sent if more were completed
--   titles/animations/pets  when their tab is shown, at most once an hour per category
--                           (ownership is only visible there)
--   catalogue               all keys + English labels, only when the game data changed
--   rarity table            on login and hourly (304 while unchanged); a new player is refused
--                           it until their first upload, so then also right after that
-- The settings' Synchronize button downloads the rarity table now (syncNow). The Sync tab
-- explains all this to players (SYNC_LINES in ui/settings_panel.lua): keep the two in step.

local logger = require("lib/logger")
local catalogue = require("data/catalogue")
local achievements = require("data/achievements")
local ownership = require("data/ownership")
local customisationsScreen = require("screens/customisations")
local achievementsScreen = require("screens/achievements")
local overlay = require("ui/overlay")
local settingsPanel = require("ui/settings_panel")
local api = require("sync/api")
local catalogueSync = require("sync/catalogue")

local DEV_DUMP = nil -- development only: "names", "cosmetics", "lists" or "achievements" dumps on load

local HOUR_TICKS = 50 * 3600 -- logic ticks run at 50 per second; plugins have no clock

-- Windows we draw rarity on. A screen has visibleLists(), readRows(list), forget(list) and
-- recordsOwnership (true when ownership can only be read from its rows).
local SCREENS = { customisationsScreen, achievementsScreen }

local tick = 0
local trackingID = nil        -- the logged-in character's; a different one means a new login
local lastSync = 0            -- tick of the last login/hourly sync
local uploadedCompleted = nil -- completed achievements at the last successful upload
local lastUpload = {}         -- category -> tick of its last upload (titles, animations, pets)

-- After a rarity download (see api.fetchRarity): redraw if it brought new data.
local function onRarity(outcome)
    if outcome == "updated" then
        overlay.invalidate()
    end
end

-- The API only gives the rarity table to players who uploaded, so a new player's login fetch
-- is refused: fetch it again after their first successful upload. That fetch can join one
-- that left before the upload arrived (see api.fetchRarity); if that one is refused, ask again.
local function afterUpload()
    if not api.hasRarity() then
        api.fetchRarity(function(outcome)
            if outcome == "refused" then
                api.fetchRarity(onRarity)
            else
                onRarity(outcome)
            end
        end)
    end
end

-- On login and hourly: refresh the rarity table, sync the catalogue if the game data changed,
-- and upload achievements when the number completed differs from the last successful upload
-- (first sync, new completions, or a retry).
local function sync()
    api.fetchRarity(onRarity)
    catalogueSync.sync({
        titles = { keys = catalogue.keysOf("titles"), nameOf = catalogue.nameOf },
        animations = { keys = catalogue.keysOf("animations"), nameOf = catalogue.nameOf },
        pets = { keys = catalogue.keysOf("pets"), nameOf = catalogue.nameOf },
        achievements = { keys = achievements.keys(), nameOf = achievements.nameOf },
    })
    local completed = achievements.completedKeys()
    if #completed ~= uploadedCompleted then
        api.uploadOwned("achievements", completed, function()
            uploadedCompleted = #completed
            afterUpload()
        end)
    end
end

-- The settings' Synchronize button: downloads the rarity now. Only a download: uploads need
-- the game's windows (ownership shows in their rows) and already run on their own schedule.
-- Answers "not_logged_in" right away, else "started" and later onDone(outcome) with
-- api.fetchRarity's outcome. (The settings panel keeps the button from being clicked rapidly.)
local function syncNow(onDone)
    if trackingID == nil then
        return "not_logged_in"
    end
    logger.info("synchronizing now (settings button)")
    api.fetchRarity(function(outcome)
        onRarity(outcome)
        onDone(outcome)
    end)
    return "started"
end

-- A list appeared or its rows changed: record what it shows the player owns (and upload that
-- at most hourly per category), then draw.
local function updateList(screen, list)
    local rows = screen.readRows(list)
    if #rows == 0 then
        screen.forget(list) -- emptied, e.g. by a tab switch
        return
    end
    -- Before login it isn't known whose rows these are; login redraws, and records them then
    if screen.recordsOwnership and trackingID ~= nil then
        local category = ownership.record(rows)
        local last = lastUpload[category]
        if last == nil or tick - last >= HOUR_TICKS then
            lastUpload[category] = tick
            api.uploadOwned(category, ownership.ownedKeys(category), afterUpload)
        end
    end
    overlay.draw(list, rows, api.rarityOf)
end

-- Each logic tick: sync on login and hourly, (re)draw lists whose rows changed, and keep the
-- codes over their rows while lists scroll or move.
local function onTick()
    tick = tick + 1
    local currentID = Player.GetTrackingID() -- nil until a few seconds after login
    if currentID ~= nil and currentID ~= trackingID then
        trackingID, lastSync, uploadedCompleted, lastUpload = currentID, tick, nil, {}
        ownership.usePlayer(api.playerID()) -- this player's snapshots, never another character's
        logger.info("logged in")
        overlay.invalidate() -- lists already on screen are read again, for this player
        sync()
    elseif trackingID ~= nil and tick - lastSync >= HOUR_TICKS then
        lastSync = tick
        sync()
    end

    local visible = {}
    for _, screen in ipairs(SCREENS) do
        for _, list in ipairs(screen.visibleLists()) do
            visible[#visible + 1] = list
            if not overlay.isDrawn(list) then
                updateList(screen, list)
            end
            overlay.follow(list)
        end
    end
    overlay.showOnly(visible)
end

logger.info("RarityScape starting (trackingAccess={}, httpAccess={}, api URL={})",
    tostring(Plugin.HasPermission(PluginPermissions.trackingAccess)),
    tostring(Plugin.HasPermission(PluginPermissions.httpAccess)),
    tostring(Plugin.urls.api))
Event.OptionalPermissionChanged.Subscribe("rarity", function(e)
    logger.info("permission {} is now {}", e.permissionName, tostring(e.enabled))
end)
settingsPanel.subscribe({
    onChange = overlay.invalidate, -- redraw with the new choices
    syncNow = syncNow,
    tiers = api.tiers,
})

if DEV_DUMP ~= nil then
    require("dev/devtools").run(DEV_DUMP)
end

Event.Logic.Subscribe("rarity", function()
    local ok, err = pcall(onTick)
    if not ok then
        Event.Logic.Unsubscribe("rarity") -- stop rather than fail 50 times a second
        logger.error("stopped: {}", tostring(err))
    end
end)
logger.info("RarityScape running")
