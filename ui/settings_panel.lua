-- Settings panel: what the game shows when RarityScape's cog is clicked in the Plugin Hub's
-- Manage tab ("hasSettingsIcon" in plugin.json). Tabs: Display (what gets a tier code and what
-- its tooltip says), Tiers (which tiers) and Sync (when we synchronize, and a button to do it
-- now). Rows are laid out like the game's own settings: shaded, tickbox on the right, the whole
-- row clickable. The game hands us an empty layer each time it opens the panel. The choices
-- themselves live in data/settings.lua.

local common = require("ui/common")
local logger = require("lib/logger")
local settings = require("data/settings")

local settingsPanel = {}

-- The tabs, in order, each with headed sections of tickboxes (item names are data/settings.lua
-- names). The tiers section lists the API's tiers, so only after they're downloaded.
local TABS = {
    { label = "Display", sections = {
        { heading = "Show tier codes for", items = {
            { name = "titles", label = "Titles" },
            { name = "animations", label = "Animations" },
            { name = "pets", label = "Pets" },
            { name = "achievements", label = "Achievements" },
        } },
        { heading = "Options", items = {
            { name = "owned_only", label = "Only what I own or completed" },
            { name = "player_counts", label = "Player counts in tooltips" },
        } },
    } },
    { label = "Tiers", sections = {
        { heading = "Show tiers (share of players who own the item)", tiers = true },
    } },
    { label = "Sync", sync = true },
}

-- What main.lua's sync does and when (keep in step with its HOUR_TICKS and the API's recompute)
local SYNC_LINES = {
    "Rarity: downloaded when you log in and every hour, or now with the button.",
    "Achievements: sent when you log in, then hourly if you completed more.",
    "Titles, animations and pets: sent when you open their tab, at most hourly.",
    "The server recalculates rarity every few minutes.",
}
-- Beside the Synchronize button: what syncNow() answered, then how the download ended
local SYNC_RESULTS = {
    started = "Downloading...",
    not_logged_in = "Log in first.",
    updated = "Downloaded the latest rarity.",
    unchanged = "Already up to date.",
    refused = "Not yet: rarity comes after your first upload.",
    failed = "Download failed: see the console (Alt+`).",
}

local TAB_BAR_HEIGHT, MARGIN = 32, 8
local ROW_HEIGHT, ROW_GAP, PADDING = 26, 4, 5 -- as in the game's settings rows, a little tighter
local ROW_PITCH = ROW_HEIGHT + ROW_GAP
local BUTTON_WIDTH = 160
local ROW_SHADES = { -- the game's settings rows alternate these two: 0x24211E, 0x2E2825
    Vector4.new(0x24 / 255, 0x21 / 255, 0x1E / 255, 1.0),
    Vector4.new(0x2E / 255, 0x28 / 255, 0x25 / 255, 1.0),
}
-- After a press the Synchronize button is disabled this long (a press is a small cached call on
-- the server; this only stops rapid clicking). Counted in logic ticks (50 per second) at module
-- level, so reopening the panel doesn't cut it short.
local SYNC_COOLDOWN_TICKS = 50 * 10
local cooldownLeft = 0 -- ticks until the button works again
local syncButton = nil -- the button in the panel drawn last

-- The tiers most common first, each with the share of players it stands for, e.g.
-- "Rare: 5%-15%". tierList is the API's (rarest first, see api.tiers), and a tier covers the
-- shares above the next rarer tier's maxPercent up to its own.
local function tierItems(tierList)
    local items = {}
    for i = #tierList, 1, -1 do
        local tier, rarer = tierList[i], tierList[i - 1]
        local share
        if rarer == nil then
            share = common.formatPercent(tier.maxPercent) .. " or less"
        elseif tier.maxPercent >= 100 then
            share = "over " .. common.formatPercent(rarer.maxPercent)
        else
            share = common.formatPercent(rarer.maxPercent) .. "-" .. common.formatPercent(tier.maxPercent)
        end
        items[#items + 1] = { name = settings.tierSetting(tier.code), code = tier.code, colour = tier.colour,
                              label = formatStr("{}: {}", tier.name, share) }
    end
    return items
end

-- A line of text from x (and widthOffset plus widthPercent of the parent wide). Clicks pass
-- through to what's underneath.
local function addText(parent, x, y, widthOffset, widthPercent, content)
    local text = ui.Text.new(parent)
    text.font = common.FONT
    text.isShadowed = true
    text.colour = common.TEXT_COLOUR
    text.content = content
    text.clickthrough = true
    text:SetPos(x, y)
    text:SetSize(widthOffset, ROW_HEIGHT, widthPercent, 0)
    text:AlignTo(ui.AlignMode.TOPLEFT, ui.AlignMode.CENTRE)
    return text
end

local function addHeading(parent, y, content)
    addText(parent, MARGIN, y, -2 * MARGIN, 1.0, formatStr("<col=ff981f>{}</col>", content))
end

-- The game calls hooks directly, outside main.lua's error handling
local function hook(fn)
    return function()
        local ok, err = pcall(fn)
        if not ok then
            logger.error("settings: {}", tostring(err))
        end
        return true
    end
end

-- One row: shaded background, tier code column (tiers only), label, tickbox at the right end.
local function addRow(parent, index, y, item, env)
    local background = ui.Rectangle.new(parent)
    background:SetPos(MARGIN, y)
    background:SetSize(-2 * MARGIN, ROW_HEIGHT, 1.0, 0)
    background.colour = ROW_SHADES[(index - 1) % 2 + 1]
    background.fill = true

    local x = MARGIN + PADDING
    if item.code ~= nil then
        local code = common.newCode(parent, item.code, item.colour, ROW_HEIGHT)
        code:SetPos(x, y)
        code.clickthrough = true -- clicks reach the row underneath
        x = x + common.CODE_WIDTH
    end
    addText(parent, x, y, -(x + MARGIN + ROW_HEIGHT), 1.0, item.label)

    -- Spans the row, so its box sits at the row's right end; created last, so it's on top
    local check = ui.Check.new(parent)
    check:SetPos(MARGIN, y)
    check:SetSize(-(2 * MARGIN + PADDING), ROW_HEIGHT, 1.0, 0)
    check.stylesheetID = id.StyleSheet.CHECKBOX_DEFAULT -- the game's tickbox look; without one it draws nothing
    check.label = ""
    check.value = settings.get(item.name) -- before subscribing: setting it may count as a press
    local function changed()
        if settings.set(item.name, check.value) then
            env.onChange()
        end
    end
    check:Subscribe(ui.Hook.ONBUTTONPRESSED, hook(changed))
    background:Subscribe(ui.Hook.ONCLICK, hook(function() -- the rest of the row, if the box doesn't take it
        check.value = not check.value
        changed()
    end))
end

-- A heading and its rows from y; returns the y below them.
local function addSection(parent, y, section, env)
    addHeading(parent, y, section.heading)
    y = y + ROW_PITCH
    local items = section.tiers and tierItems(env.tiers() or {}) or section.items
    if #items == 0 then
        addText(parent, MARGIN + PADDING, y, -2 * MARGIN, 1.0, "Shown after logging in")
        y = y + ROW_PITCH
    end
    for row, item in ipairs(items) do
        addRow(parent, row, y, item, env)
        y = y + ROW_PITCH
    end
    return y
end

-- Disables the Synchronize button for SYNC_COOLDOWN_TICKS, counting down on every logic tick.
local function startCooldown()
    cooldownLeft = SYNC_COOLDOWN_TICKS
    syncButton.enabled = false
    Event.Logic.Subscribe("rarity_sync_cooldown", function()
        cooldownLeft = cooldownLeft - 1
        if cooldownLeft <= 0 then
            Event.Logic.Unsubscribe("rarity_sync_cooldown")
            if common.alive(syncButton) then
                syncButton.enabled = true
            end
        end
    end)
end

-- The Sync tab: when we synchronize, and the button to do it now with its result beside it.
local function addSync(parent, y, env)
    addHeading(parent, y, "When RarityScape synchronizes")
    y = y + ROW_PITCH
    for _, line in ipairs(SYNC_LINES) do
        addText(parent, MARGIN + PADDING, y, -(2 * MARGIN + PADDING), 1.0, line)
        y = y + ROW_HEIGHT
    end
    y = y + ROW_PITCH

    local button = ui.Button.new(parent)
    button:SetPos(MARGIN, y)
    button:SetSize(BUTTON_WIDTH, ROW_HEIGHT + 4)
    button.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
    button.label = "Synchronize now"
    button.enabled = cooldownLeft <= 0
    syncButton = button
    local status = addText(parent, MARGIN + BUTTON_WIDTH + 12, y + 2, -(2 * MARGIN + BUTTON_WIDTH + 12), 1.0, "")
    button:Subscribe(ui.Hook.ONBUTTONPRESSED, hook(function()
        status.content = SYNC_RESULTS.started -- first: the outcome can arrive before syncNow returns
        local answer = env.syncNow(function(outcome)
            if common.alive(status) then -- the panel may have been closed meanwhile
                status.content = SYNC_RESULTS[outcome]
            end
        end)
        if answer == "started" then
            startCooldown()
        else
            status.content = SYNC_RESULTS[answer]
        end
    end))
end

local function draw(layer, env)
    local pages = ui.PagedLayer.new(layer)
    pages.stylesheetID = id.StyleSheet.PAGED_LAYER_DEFAULT
    pages:SetPos(0, TAB_BAR_HEIGHT)
    pages:SetSize(0, -TAB_BAR_HEIGHT, 1.0, 1.0)
    pages.numPages = #TABS
    for i, tab in ipairs(TABS) do
        pages.activePage = i - 1 -- components created now belong to this page
        pages:SetPageLabel(i - 1, tab.label)
        if tab.sync then
            addSync(pages, MARGIN, env)
        else
            local y = MARGIN
            for _, section in ipairs(tab.sections) do
                y = addSection(pages, y, section, env)
            end
        end
    end
    pages.activePage = 0
    local tabBar = pages:AddHeader(layer) -- the tab buttons, above the pages
    tabBar:SetSize(0, TAB_BAR_HEIGHT, 1.0, 0)
end

-- Draws the panel whenever the game opens it. env, from main.lua:
--   onChange()        after every change of a setting
--   syncNow(onDone)   for the Synchronize button (see main.lua)
--   tiers()           the API's tier list, rarest first, or nil before it's downloaded
-- Without the event (an older client) the plugin runs on without a panel.
function settingsPanel.subscribe(env)
    local ok, err = pcall(function()
        Event.SettingsLayerReady.Subscribe("rarity", function(e)
            local drawn, drawErr = pcall(draw, e.component, env)
            if not drawn then
                logger.error("settings panel: {}", tostring(drawErr))
            end
        end)
    end)
    if not ok then
        logger.error("settings panel unavailable: {}", tostring(err))
    end
end

return settingsPanel
