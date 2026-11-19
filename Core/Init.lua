-- Blood Pact: addon bootstrap, event dispatch, saved data, guild roster cache.
local ADDON, ns = ...
ns.ADDON = ADDON
ns.VERSION = "0.12.0"

local handlers = {}
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then geterrorhandler()(err) end
    end
end)

function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        -- A client that doesn't have this event just never fires it.
        pcall(frame.RegisterEvent, frame, event)
    end
    table.insert(handlers[event], fn)
end

-- Internal callbacks between modules ("LOG_CHANGED", "ROSTER_CHANGED", ...)
local internal = {}
function ns.Listen(name, fn)
    internal[name] = internal[name] or {}
    table.insert(internal[name], fn)
end
function ns.Fire(name, ...)
    local list = internal[name]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then geterrorhandler()(err) end
    end
end

function ns.Print(msg)
    print("|cffb22222Blood Pact:|r " .. msg)
end

function ns.Now() return GetServerTime() end
function ns.MyGUID() return UnitGUID("player") end

---------------------------------------------------------------------------
-- Saved data: one store per guild. Mock mode uses its own store that Sync
-- refuses to send, so test data can never reach a real guild.
---------------------------------------------------------------------------
ns.MOCK_KEY = "__MOCK__"

function ns.GuildKey()
    if ns.mock then return ns.MOCK_KEY end
    local guildName = GetGuildInfo("player")
    if not guildName then return nil end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or ""
    return guildName .. "-" .. (realm or "")
end

function ns.G()
    if not ns.db then return nil end
    local key = ns.GuildKey()
    if not key then return nil end
    local g = ns.db.guilds[key]
    if not g then
        g = { log = {}, vv = {}, lamport = 0, mySeq = {}, conflicts = 0 }
        ns.db.guilds[key] = g
    end
    return g
end

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    BloodPactDB = BloodPactDB or {}
    local db = BloodPactDB
    db.schema = db.schema or 1
    db.guilds = db.guilds or {}
    db.ui = db.ui or { autoBossAward = true, progression = false }
    ns.db = db
    ns.Fire("DB_READY")
end)

-- Settings kept for this character only (never synced).
function ns.Char()
    local guid = ns.MyGUID()
    if not guid or not ns.db then return {} end
    ns.db.chars = ns.db.chars or {}
    ns.db.chars[guid] = ns.db.chars[guid] or {}
    return ns.db.chars[guid]
end

---------------------------------------------------------------------------
-- Guild roster cache: name <-> GUID <-> rank index.
---------------------------------------------------------------------------
ns.roster = { byGUID = {}, byName = {}, loaded = false }

local function addAlias(byName, fullName, guid)
    byName[fullName] = guid
    local short = fullName:match("^[^-]+")
    if short and byName[short] == nil then byName[short] = guid end
end

function ns.RebuildRoster()
    if ns.mock then return end
    local byGUID, byName = {}, {}
    local n = GetNumGuildMembers() or 0
    local seen = 0
    for i = 1, n do
        local name, rankName, rankIndex, level, _, zone, _, _, isOnline, _, class, _, _, _, _, _, guid = GetGuildRosterInfo(i)
        if name and guid then
            seen = seen + 1
            local days
            if not isOnline and GetGuildRosterLastOnline then
                local y, mo, d, h = GetGuildRosterLastOnline(i)
                if y then days = y * 365 + mo * 30 + d + ((h or 0) >= 12 and 1 or 0) end
            end
            -- name is what people see and type; full is the form the game sent.
            byGUID[guid] = { name = ns.U.ShortName(name), full = name, rank = rankName, rankIndex = rankIndex,
                level = level, class = class, online = isOnline, offlineDays = days, zone = zone }
            addAlias(byName, name, guid)
        end
    end
    ns.roster.byGUID, ns.roster.byName = byGUID, byName
    ns.roster.loaded = n > 0
    -- The game sometimes hands over only part of the roster. Anything that
    -- reads "who left" must wait for a complete one.
    ns.roster.complete = n > 0 and seen == n
    ns.Fire("ROSTER_CHANGED")
end

-- Exact match first; then without the realm part; then ignoring capitals,
-- so "binky bee" typed by an officer finds "Binky Bee".
function ns.GUIDForName(name)
    if not name then return nil end
    local byName = ns.roster.byName
    local short = name:match("^[^-]+") or name
    local guid = byName[name] or byName[short]
    if guid then return guid end
    local want, wantShort = name:lower(), short:lower()
    for known, g in pairs(byName) do
        local lower = known:lower()
        if lower == want or lower == wantShort then return g end
    end
    return nil
end

function ns.NameForGUID(guid)
    local r = ns.roster.byGUID[guid]
    return r and r.name or nil
end

ns.On("PLAYER_LOGIN", function()
    ns.Print("v" .. ns.VERSION .. " loaded. Type /bp or /bloodpact to open.")
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
end)
-- The game fires roster updates in bursts; rebuild once per burst.
local rebuildQueued = false
ns.On("GUILD_ROSTER_UPDATE", function()
    if rebuildQueued then return end
    rebuildQueued = true
    C_Timer.After(0.5, function()
        rebuildQueued = false
        ns.RebuildRoster()
    end)
end)

-- WoW Forever blocks some actions for addons. Say so instead of failing silently.
local function blocked(addon, func)
    if addon ~= ADDON then return end
    ns.lastBlocked = tostring(func)
    ns.Print("The game blocked an action for addons (" .. tostring(func) .. "). Do that step by hand.")
    ns.Fire("ACTION_BLOCKED", func)
end
ns.On("ADDON_ACTION_FORBIDDEN", blocked)
ns.On("ADDON_ACTION_BLOCKED", blocked)
ns.On("PLAYER_GUILD_UPDATE", function()
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
end)
