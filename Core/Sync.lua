-- Blind Tiger: gossip sync over the GUILD channel.
--   H  hello      {v = version vector}                 GUILD, after login jitter
--   W  want       {v = my version vector}              WHISPER to someone ahead of me
--   B  batch      {es = {{e = event, c = confirmed}}}  WHISPER reply to W or C
--   E  event      {e = event}                          GUILD, a new event from its author
--   C  confirm    {ids = {...}}                        WHISPER to an officer, for relayed events
-- An event counts (is "confirmed") only if it came from its author, or from an
-- officer who holds it as confirmed. Events relayed by anyone else stay
-- provisional until an officer confirms them, so a member cannot forge awards.
-- Officers are trusted relays: what an Officer vouches for is accepted even if
-- its author has since left the guild or changed rank.
-- Other modules add their own short-lived messages with S.Handle (the summon
-- board does); those are never stored in the log.
local _, ns = ...
local S = {}
ns.Sync = S

local U, Log = ns.U, ns.Log
local pending = {}            -- events whose author the roster can't place yet
local heardHelloHash = nil
local lastWantAt, lastBatchAt = -1000, -1000
local helloScheduled = false
local catchup = nil           -- { peer, v, hash, tries } while pulling from one peer
local batchGen = 0
local toldNewer = false
local lastReactiveHello = -1000

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
    if g then send("GUILD", nil, { t = "H", v = g.vv, ver = ns.VERSION }) end
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

local function accept(e, confirmed, vouched)
    local g = ns.G()
    if not g or type(e) ~= "table" then return end
    -- We know what we wrote. Something in our name counts only when an
    -- Officer vouches for it (our own events from another computer).
    if e.a == ns.MyGUID() and not vouched then return end
    local res, why = Log.Insert(g, e, confirmed, vouched)
    if res == "new" or res == "confirmed" then
        ns.Fire("LOG_CHANGED")
    elseif res == "conflict" and vouched and e.a == ns.MyGUID() then
        -- This character wrote from another computer. Keep the guild's copy
        -- and write ours again under a fresh number.
        local mine = Log.AdoptFork(g, e)
        if mine then
            ns.Fire("LOG_CHANGED")
            if mine.ok and Log.KINDS[mine.k] then Log.New(mine.k, mine.d) end
        end
    elseif res == false and why == "unknownAuthor" and #pending < 500 then
        pending[#pending + 1] = { e = e, c = confirmed }
    end
end
S.Accept = accept

-- Ask the peer we are pulling from for more, as long as each round helps.
local function continueCatchup()
    local g = ns.G()
    if not catchup or not g then return end
    local behind = false
    for author, seq in pairs(catchup.v) do
        if type(author) == "string" and type(seq) == "number" and seq > (g.vv[author] or 0) then
            behind = true
            break
        end
    end
    local hash = vvHash(g.vv)
    if not behind or hash == catchup.hash or catchup.tries >= 20 then
        catchup = nil
        return
    end
    catchup.hash, catchup.tries = hash, catchup.tries + 1
    lastWantAt = GetTime()
    send("WHISPER", catchup.peer, { t = "W", v = g.vv })
end

local handlers = {}

handlers.H = function(msg, sender, sguid)
    local g = ns.G()
    if not g or type(msg.v) ~= "table" then return end
    heardHelloHash = vvHash(msg.v)
    if not toldNewer and type(msg.ver) == "string" and #msg.ver <= 16 and U.VersionNewer(msg.ver, ns.VERSION) then
        toldNewer = true
        ns.Print("A guildmate is on a newer Blind Tiger (" .. U.Safe(msg.ver, 16) .. "). Update yours so nothing is missed.")
    end
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
        catchup = { peer = sender, v = msg.v, hash = vvHash(g.vv), tries = 0 }
        send("WHISPER", sender, { t = "W", v = g.vv })
    end
    -- They are missing something we hold: announce soon so they can ask,
    -- instead of waiting for the next quarter-hour round.
    -- At most once every two minutes, so two clients that each hold something
    -- the other refuses can't keep answering each other.
    if now - lastReactiveHello > 120 then
        for author, seq in pairs(g.vv) do
            if seq > (type(msg.v[author]) == "number" and msg.v[author] or 0) then
                lastReactiveHello = now
                S.ScheduleHello(2, 10)
                break
            end
        end
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
    accept(msg.e, sguid == msg.e.a, false)
end

handlers.B = function(msg, sender, sguid)
    if type(msg.es) ~= "table" then return end
    lastBatchAt = GetTime()
    local officer = isOfficer(sguid)
    for i = 1, math.min(#msg.es, 8) do
        local item = msg.es[i]
        if type(item) == "table" and type(item.e) == "table" then
            local vouched = officer and item.c == true
            accept(item.e, sguid == item.e.a or vouched, vouched)
        end
    end
    -- When the batches stop arriving, see whether this peer has more for us.
    batchGen = batchGen + 1
    local gen = batchGen
    C_Timer.After(8, function()
        if gen == batchGen then continueCatchup() end
    end)
end

-- Register a handler for a short-lived message type (not stored in the log).
function S.Handle(kind, fn) handlers[kind] = fn end

-- Send a short-lived message to the guild. Returns false when it can't go out.
function S.SendLive(msg)
    if not canSync() then return false end
    send("GUILD", nil, msg)
    return true
end

function S.OnPayload(payload, channel, sender)
    if ns.mock then return end
    local msg = U.Decode(payload)
    if type(msg) ~= "table" or type(msg.t) ~= "string" then return end
    local sguid = ns.GUIDForName(sender)
    if not sguid then return end                 -- not a guildmate we know (yet)
    local h = handlers[msg.t]
    if h then h(msg, sender, sguid, channel) end
end

ns.Listen("ROSTER_CHANGED", function()
    if #pending > 0 then
        local retry = pending
        pending = {}
        for i = 1, #retry do accept(retry[i].e, retry[i].c, false) end
    end
    if canSync() and not S.started then
        S.started = true
        -- Events saved by an older version of unknown kinds: check them now.
        local g = ns.G()
        if g and Log.Revalidate(g) > 0 then ns.Fire("LOG_CHANGED") end
        S.ScheduleHello(8, 40)
        C_Timer.NewTicker(900, function() S.ScheduleHello(0, 60) end)
    end
end)
