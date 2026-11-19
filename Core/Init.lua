-- Blood Pact: addon bootstrap, event dispatch, saved data, guild roster cache.
local ADDON, ns = ...
ns.ADDON = ADDON
ns.VERSION = "0.1.1"

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
        frame:RegisterEvent(event)
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
    for i = 1, n do
        local name, _, rankIndex, level, _, _, _, _, isOnline, _, class, _, _, _, _, _, guid = GetGuildRosterInfo(i)
        if name and guid then
            byGUID[guid] = { name = name, rankIndex = rankIndex, level = level, class = class, online = isOnline }
            addAlias(byName, name, guid)
        end
    end
    ns.roster.byGUID, ns.roster.byName = byGUID, byName
    ns.roster.loaded = n > 0
    ns.Fire("ROSTER_CHANGED")
end

function ns.GUIDForName(name)
    if not name then return nil end
    return ns.roster.byName[name] or ns.roster.byName[name:match("^[^-]+") or name]
end

function ns.NameForGUID(guid)
    local r = ns.roster.byGUID[guid]
    return r and r.name or nil
end

ns.On("PLAYER_LOGIN", function()
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
end)
ns.On("GUILD_ROSTER_UPDATE", function() ns.RebuildRoster() end)
ns.On("PLAYER_GUILD_UPDATE", function()
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
end)
