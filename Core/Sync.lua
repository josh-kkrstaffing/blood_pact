-- Blood Pact: gossip sync over the GUILD channel.
--   H  hello      {v = version vector}                 GUILD, after login jitter
--   W  want       {v = my version vector}              WHISPER to someone ahead of me
--   B  batch      {es = {{e = event, c = confirmed}}}  WHISPER reply to W or C
--   E  event      {e = event}                          GUILD, a new event from its author
--   C  confirm    {ids = {...}}                        WHISPER to an officer, for relayed events
-- An event counts (is "confirmed") only if it came from its author, or from an
-- officer who holds it as confirmed. Events relayed by anyone else stay
-- provisional until an officer confirms them, so a member cannot forge awards.
local _, ns = ...
local S = {}
ns.Sync = S

local U, Log = ns.U, ns.Log
local pending = {}            -- events whose author the roster can't place yet
local heardHelloHash = nil
local lastWantAt, lastBatchAt = 0, 0
local helloScheduled = false

local function send(dist, target, msg)
    ns.Comm.Send(dist, target, U.Encode(msg))
end

local function vvHash(vv) return U.Hash(U.Encode(vv or {})) end

local function canSync()
    return ns.db and not ns.mock and IsInGuild() and ns.roster.loaded
end

local function isOfficer(guid)
    return guid ~= nil and ns.RBAC.Can(guid, "award")
end

function S.Broadcast(e)
    if not canSync() then return end
    send("GUILD", nil, { t = "E", e = Log.Wire(e) })
end

function S.SendHello()
    if not canSync() then return end
    local g = ns.G()
    if g then send("GUILD", nil, { t = "H", v = g.vv }) end
end

-- Login jitter: wait, and skip the hello if someone already announced the
-- same state, so a raid's worth of logins doesn't flood the channel.
function S.ScheduleHello(minDelay, maxDelay)
    if helloScheduled then return end
    helloScheduled = true
    heardHelloHash = nil
    C_Timer.After(minDelay + math.random() * (maxDelay - minDelay), function()
        helloScheduled = false
        local g = ns.G()
        if not g then return end
        if heardHelloHash and heardHelloHash == vvHash(g.vv) then return end
        S.SendHello()
    end)
end

function S.Status()
    if ns.mock then return "Mock mode" end
    if not IsInGuild() then return "Not in a guild" end
    if ns.Comm.IsHeld() and ns.Comm.QueueLength() > 0 then
        return "Waiting to send (" .. ns.Comm.QueueLength() .. ")"
    end
    local now = GetTime()
    if now - lastWantAt < 20 or now - lastBatchAt < 5 then return "Catching up" end
    return "Synced"
end

local function accept(e, confirmed)
    local g = ns.G()
    if not g or type(e) ~= "table" then return end
    local res, why = Log.Insert(g, e, confirmed)
    if res == "new" or res == "confirmed" then
        ns.Fire("LOG_CHANGED")
    elseif res == false and why == "unknownAuthor" and #pending < 500 then
        pending[#pending + 1] = { e = e, c = confirmed }
    end
end

local handlers = {}

handlers.H = function(msg, sender, sguid)
    local g = ns.G()
    if not g or type(msg.v) ~= "table" then return end
    heardHelloHash = vvHash(msg.v)
    local behind = false
    for author, seq in pairs(msg.v) do
        if type(author) == "string" and type(seq) == "number" and seq > (g.vv[author] or 0) then
            behind = true
            break
        end
    end
    local now = GetTime()
    if behind and now - lastWantAt > 20 then
        lastWantAt = now
        send("WHISPER", sender, { t = "W", v = g.vv })
    end
    -- Ask an officer to confirm relayed events it can vouch for.
    if isOfficer(sguid) then
        local ids = {}
        for id, e in pairs(g.log) do
            if not e.ok and (msg.v[e.a] or 0) >= e.s then
                ids[#ids + 1] = id
                if #ids >= 40 then break end
            end
        end
        if #ids > 0 then send("WHISPER", sender, { t = "C", ids = ids }) end
    end
end

local function sendBatches(target, events)
    table.sort(events, function(x, y)
        if x.L ~= y.L then return x.L < y.L end
        return x.id < y.id
    end)
    local batch = {}
    for i = 1, #events do
        local e = events[i]
        batch[#batch + 1] = { e = Log.Wire(e), c = e.ok and true or nil }
        if #batch == 4 or i == #events then
            send("WHISPER", target, { t = "B", es = batch })
            batch = {}
        end
    end
end

handlers.W = function(msg, sender)
    local g = ns.G()
    if not g or type(msg.v) ~= "table" then return end
    local out = {}
    for _, e in pairs(g.log) do
        if e.s > (msg.v[e.a] or 0) then
            out[#out + 1] = e
            if #out >= 400 then break end
        end
    end
    if #out > 0 then sendBatches(sender, out) end
end

handlers.C = function(msg, sender)
    local g = ns.G()
    if not g or type(msg.ids) ~= "table" or not isOfficer(ns.MyGUID()) then return end
    local out = {}
    for i = 1, math.min(#msg.ids, 40) do
        local e = g.log[msg.ids[i]]
        if e and e.ok then out[#out + 1] = e end
    end
    if #out > 0 then sendBatches(sender, out) end
end

handlers.E = function(msg, sender, sguid)
    if type(msg.e) ~= "table" then return end
    accept(msg.e, sguid == msg.e.a)
end

handlers.B = function(msg, sender, sguid)
    if type(msg.es) ~= "table" then return end
    lastBatchAt = GetTime()
    local officer = isOfficer(sguid)
    for i = 1, math.min(#msg.es, 8) do
        local item = msg.es[i]
        if type(item) == "table" and type(item.e) == "table" then
            accept(item.e, sguid == item.e.a or (officer and item.c == true))
        end
    end
end

function S.OnPayload(payload, channel, sender)
    if ns.mock then return end
    local msg = U.Decode(payload)
    if type(msg) ~= "table" or type(msg.t) ~= "string" then return end
    local sguid = ns.GUIDForName(sender)
    if not sguid then return end                 -- not a guildmate we know (yet)
    local h = handlers[msg.t]
    if h then h(msg, sender, sguid) end
end

ns.Listen("ROSTER_CHANGED", function()
    if #pending > 0 then
        local retry = pending
        pending = {}
        for i = 1, #retry do accept(retry[i].e, retry[i].c) end
    end
    if canSync() and not S.started then
        S.started = true
        S.ScheduleHello(15, 90)
        C_Timer.NewTicker(900, function() S.ScheduleHello(0, 60) end)
    end
end)
