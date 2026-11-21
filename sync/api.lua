-- API: talks to the rarity backend (~/projects/rs-rarity-api), an HTTP API in front of Redis
-- (the plugin never talks to Redis directly). Needs trackingAccess, httpAccess and the "api"
-- base URL in plugin.json (without a path: signatures cover the path from "/"). JSON both
-- ways; items are identified by key, a stable game ID that's the same in every language:
--   POST /owned              {"achievements": [1618, …]}     everything the player owns
--   POST /catalogue/missing  {"titles": [11088, …]}          every key we know; answers those
--                                                             without a label: {"titles": ["99999"]}
--   POST /catalogue          {"titles": {"11088": "Duke"}}   from English clients only
--   GET  /rarity             {"titles": {"11088": {"tier": "C", "percent": 100, "owners": 42}}}
--                                                             (only after this player uploaded)
--   GET  /tiers              [{"code", "name", "maxPercent", "colour"}] (the backend owns them)
-- All but /tiers are signed (sync/sign.lua). Every request says which plugin version sent it.

local json = require("lib/json")
local logger = require("lib/logger")
local sha256 = require("lib/sha256")
local sign = require("sync/sign")

local api = {}

-- Sent as X-Plugin-Version so the API can tell releases apart. Keep it equal to "version" in
-- plugin.json: plugins can't read their own manifest.
local PLUGIN_VERSION = "0.2.0"

local rarity = nil     -- category -> { key -> { tier = "R", percent = 5.12, owners = 42 } }, as GET /rarity sends it
local rarityETag = nil -- version of `rarity`; the API answers 304 (no body) while it's current
local tiers = nil      -- code -> { name = "Rare", colour = "3d8bff" }, fetched once per session
local tierList = nil   -- the same as GET /tiers sends them: rarest first, { code, name, maxPercent, colour }

local hashedFor, hashedID = nil, nil -- the last tracking ID and its hash, computed once per login

-- The player's ID for the API: the SHA-256 of the tracking ID, never the ID itself (Jagex's
-- submission example keeps tracking information out of HTTP transfers). One-way: getting the
-- tracking ID back means guessing it. nil until the tracking ID is available.
local function playerID()
    local trackingID = Player.GetTrackingID()
    if trackingID == nil then
        return nil
    end
    if trackingID ~= hashedFor then
        hashedFor, hashedID = trackingID, sha256.hex("rs-rarity:" .. tostring(trackingID))
        logger.info("player ID (quote it to have your data deleted): {}", hashedID)
    end
    return hashedID
end

-- The player's API ID (see above), also how this PC's players are kept apart in storage.
api.playerID = playerID

-- What keeps the API from being used right now, for the log; nil when nothing does.
local function missing(id)
    local problems = {}
    if not Plugin.HasPermission(PluginPermissions.httpAccess) then
        problems[#problems + 1] = "httpAccess permission"
    end
    if Plugin.urls.api == nil then
        problems[#problems + 1] = "api URL in plugin.json"
    end
    if id == nil then
        problems[#problems + 1] = "tracking ID"
    end
    return #problems > 0 and table.concat(problems, ", ") or nil
end

-- Sends a request, signed (X-Player-ID, X-Signature) unless options.public. Skipped, and
-- logged, while the API can't be used: then it returns false and onResponse is never called.
-- Otherwise onResponse(r) gets the finished request.
local function send(what, method, path, body, onResponse, options)
    options = options or {}
    local id = playerID()
    local problem = missing(id)
    if problem ~= nil then
        logger.info("api: {} skipped, missing: {}", what, problem)
        return false
    end
    local request = HTTPRequest.new(Plugin.urls.api, path)
    request:AddHeader("X-Plugin-Version", PLUGIN_VERSION)
    if not options.public then
        request:AddHeader("X-Player-ID", id)
        request:AddHeader("X-Signature", sign.header(method, path, id, body))
    end
    for name, value in pairs(options.headers or {}) do
        request:AddHeader(name, value)
    end
    if method == "GET" then
        request:Get(onResponse)
    else
        request:Post(body, onResponse)
    end
    return true
end

-- True for a request that reached the API and got a 2xx answer; logs anything else.
local function succeeded(what, r)
    if r.successful and r.responseCode >= 200 and r.responseCode < 300 then
        return true
    end
    logger.error("api: {} failed ({} {} {})", what, r.responseCode, r.errorInfo, r.data)
    return false
end

-- The JSON in a response, or nil (logged) when it doesn't parse.
local function decoded(what, r)
    local ok, value = pcall(json.decode, r.data)
    if not ok then
        logger.error("api: {} sent invalid JSON: {}", what, tostring(value))
        return nil
    end
    return value
end

-- Keys as JSON numbers where they're numeric (all of them, in practice): smaller bodies.
local function keyList(keys)
    local list = json.array()
    for i, key in ipairs(keys) do
        list[i] = tonumber(key) or key
    end
    return list
end

-- Uploads everything the player owns in a category (a list of keys; every other key counts
-- as not owned); onUploaded() runs once the API has accepted it.
function api.uploadOwned(category, ownedKeys, onUploaded)
    local what = category .. " upload"
    local body = json.encode({ [category] = keyList(ownedKeys) })
    send(what, "POST", "/owned", body, function(r)
        if succeeded(what, r) then
            logger.info("api: uploaded {} ({} owned, {} bytes)", category, #ownedKeys, #body)
            onUploaded()
        end
    end)
end

-- Sends every key of a category (the API registers new ones); onMissing(keys) gets the keys
-- the API has no label for yet.
function api.checkCatalogue(category, keys, onMissing)
    local what = category .. " catalogue check"
    send(what, "POST", "/catalogue/missing", json.encode({ [category] = keyList(keys) }), function(r)
        local answer = succeeded(what, r) and decoded(what, r)
        if answer then
            onMissing(answer[category] or {})
        end
    end)
end

-- Uploads the labels (display names, labelOf(key)) of these keys; onDone() runs on success.
function api.uploadLabels(category, keys, labelOf, onDone)
    local what = category .. " labels"
    local labels, count = {}, 0
    for _, key in ipairs(keys) do
        local label = labelOf(key)
        if label ~= nil and label ~= "" then
            labels[key] = label
            count = count + 1
        end
    end
    if count == 0 then
        onDone()
        return
    end
    send(what, "POST", "/catalogue", json.encode({ [category] = labels }), function(r)
        if succeeded(what, r) then
            logger.info("api: sent {} {} labels", count, category)
            onDone()
        end
    end)
end

-- The tier map (names and colours), once per session. onDone(ok) runs once either way.
local function fetchTiers(onDone)
    local sent = send("tiers download", "GET", "/tiers", "", function(r)
        local list = succeeded("tiers download", r) and decoded("tiers download", r)
        if list then
            tiers, tierList = {}, list
            for _, tier in ipairs(list) do
                tiers[tier.code] = { name = tier.name, colour = tier.colour }
            end
        end
        onDone(list and true or false)
    end, { public = true })
    if not sent then
        onDone(false)
    end
end

-- The rarity table, only downloaded when it changed (ETag). onDone(outcome) runs once, see
-- api.fetchRarity. A player who hasn't uploaded yet is refused (403): that's expected, so it's
-- logged as info.
local function fetchRarityTable(onDone)
    local headers = rarityETag and { ["If-None-Match"] = rarityETag }
    local sent = send("rarity download", "GET", "/rarity", "", function(r)
        if r.responseCode == 304 then
            logger.info("api: rarity unchanged")
            onDone("unchanged")
            return
        elseif r.responseCode == 403 then
            logger.info("api: no rarity until our first upload")
            onDone("refused")
            return
        end
        local received = succeeded("rarity download", r) and decoded("rarity download", r)
        if received then
            rarity = received
            rarityETag = r.header:match("[Ee][Tt][Aa][Gg]:%s*([^\r\n]+)")
            logger.info("api: rarity downloaded ({} bytes)", #r.data)
            onDone("updated")
        else
            onDone("failed")
        end
    end, { headers = headers })
    if not sent then
        onDone("failed")
    end
end

local waiting = nil -- onDone callbacks of the download in progress; nil while none runs

-- Downloads the rarity table if it changed (and the tier map, first time). onDone(outcome)
-- runs once with "updated" (new data stored), "unchanged" (ours is current), "refused" (no
-- upload from this player yet) or "failed" (logged: no connection, missing permission, ...).
-- A call while a download is on its way (the login sync and a first upload often overlap)
-- waits for that one and gets its outcome, so the table is never downloaded twice at once.
function api.fetchRarity(onDone)
    if waiting ~= nil then
        waiting[#waiting + 1] = onDone
        return
    end
    waiting = { onDone }
    local function finish(outcome)
        local callbacks = waiting
        waiting = nil -- first: a callback may start the next download
        for _, callback in ipairs(callbacks) do
            callback(outcome)
        end
    end
    if tiers == nil then
        fetchTiers(function(ok)
            if ok then
                fetchRarityTable(finish)
            else
                finish("failed")
            end
        end)
    else
        fetchRarityTable(finish)
    end
end

-- The tiers, rarest first, as { code, name, maxPercent, colour }; nil until downloaded (login).
function api.tiers()
    return tierList
end

-- True once a rarity table has been downloaded this session.
function api.hasRarity()
    return rarity ~= nil
end

-- Rarity of an item as { tier = "R", percent = 5.12, owners = 42, tierName = "Rare", colour = "3d8bff" },
-- or nil when unknown (not downloaded yet, or an item the API hasn't seen). owners is the number
-- of players who own it, nil from an API that doesn't send it yet.
function api.rarityOf(category, key)
    local entry = rarity and rarity[category] and rarity[category][key]
    if entry == nil then
        return nil
    end
    local tier = tiers and tiers[entry.tier] or { name = entry.tier, colour = "ffffff" }
    return { tier = entry.tier, percent = entry.percent, owners = entry.owners, tierName = tier.name,
             colour = tier.colour }
end

return api
