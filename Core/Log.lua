-- Blood Pact: append-only event log. The only synced data.
-- Every event: id, a (author GUID), s (author sequence), L (Lamport clock),
-- t (server time, display only), prev (hash of author's previous event),
-- k (kind), d (payload), h (hash of all of the above).
local _, ns = ...
local L = {}
ns.Log = L

local U = ns.U
local type, pairs, ipairs, floor = type, pairs, ipairs, math.floor

L.MAX_LAMPORT_JUMP = 10000
L.MAX_NOTE = 120

local function isInt(n, lo, hi)
    return type(n) == "number" and n == floor(n) and n >= lo and n <= hi
end
local function isGUID(s)
    return type(s) == "string" and #s > 0 and #s <= 64
end
local function optNote(n)
    return n == nil or (type(n) == "string" and #n <= L.MAX_NOTE)
end

L.SETTING_KEYS = {
    onTime = true, bossFarm = true, bossProg = true, fullRaid = true, decayPct = true,
    priceBis = true, priceMajor = true, priceMinor = true, priceOff = true,
    inactWatch = true, inactInactive = true, inactCleanup = true, promoDays = true, promoRaids = true,
}
L.TASK_STATES = { claim = true, done = true, open = true }
L.TIERS = { bis = true, major = true, minor = true, off = true }
L.SIGNUP_STATUS = { yes = true, maybe = true, no = true }
L.ROLES = { tank = true, healer = true, dps = true }
L.ROSTER_EVENTS = { join = true, leave = true, kick = true, promote = true, demote = true }

local function str(s, lo, hi) return type(s) == "string" and #s >= lo and #s <= hi end

-- kind -> { action required, payload validator }
L.KINDS = {
    AWARD = { "award", function(d)
        if type(d.to) ~= "table" or #d.to < 1 or #d.to > 60 then return false end
        for _, g in ipairs(d.to) do if not isGUID(g) then return false end end
        return isInt(d.amt, -10000, 10000) and type(d.r) == "string" and #d.r <= 20
            and optNote(d.n) and (d.idem == nil or (type(d.idem) == "string" and #d.idem <= 64))
    end },
    SPEND = { "spend", function(d)
        return isGUID(d.from) and isInt(d.amt, 0, 10000) and L.TIERS[d.tier] ~= nil
            and (d.item == nil or isInt(d.item, 1, 10000000)) and optNote(d.n)
    end },
    VOID = { "void", function(d)
        return type(d.target) == "string" and #d.target <= 80
    end },
    DECAY = { "decay", function(d)
        return isInt(d.pct, 1, 100)
    end },
    SETTINGS = { "settings", function(d)
        local any = false
        for k, v in pairs(d) do
            if not L.SETTING_KEYS[k] or not isInt(v, 0, 10000) then return false end
            any = true
        end
        return any and (d.decayPct == nil or d.decayPct <= 100)
    end },
    ALT_LINK = { "altlink", function(d)
        return isGUID(d.alt) and isGUID(d.main) and d.alt ~= d.main
    end },
    RAID = { "schedule", function(d)
        return str(d.title, 1, 40) and str(d.raid, 1, 30) and isInt(d.at, 1e9, 1e11)
            and isInt(d.size, 5, 40) and optNote(d.n)
            and (d.tz == nil or str(d.tz, 1, 8)) and (d.prog == nil or type(d.prog) == "boolean")
    end },
    RAID_CANCEL = { "schedule", function(d)
        return str(d.ev, 1, 80)
    end },
    SIGNUP = { "signup", function(d)
        return str(d.ev, 1, 80) and L.SIGNUP_STATUS[d.st] ~= nil
            and (d.role == nil or L.ROLES[d.role] ~= nil) and optNote(d.n)
    end },
    ATTEND = { "schedule", function(d)
        if type(d.who) ~= "table" or #d.who < 1 or #d.who > 60 then return false end
        for _, g in ipairs(d.who) do if not isGUID(g) then return false end end
        return type(d.day) == "string" and d.day:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil
            and str(d.idem, 1, 64)
    end },
    ALT_UNLINK = { "altlink", function(d)
        return isGUID(d.alt)
    end },
    ROSTER = { "roster", function(d)
        return L.ROSTER_EVENTS[d.ev] ~= nil and isGUID(d.who) and str(d.name, 1, 48)
            and (d.by == nil or str(d.by, 1, 48)) and (d.rank == nil or str(d.rank, 1, 32))
            and (d.ri == nil or isInt(d.ri, 0, 9)) and str(d.idem, 1, 96)
            and (d.live == nil or type(d.live) == "boolean")
    end },
    TASK = { "roster", function(d)
        return str(d.id, 1, 96) and L.TASK_STATES[d.st] ~= nil
    end },
    RECRUIT_MSGS = { "recruitEdit", function(d)
        if type(d.msgs) ~= "table" or #d.msgs < 1 or #d.msgs > 3 then return false end
        for _, m in ipairs(d.msgs) do
            if type(m) ~= "string" or #m < 1 or #m > 255 then return false end
        end
        return true
    end },
}

function L.Hash(e)
    return U.Hash(U.Encode({ e.id, e.a, e.s, e.L, e.t, e.prev or "", e.k, e.d }))
end

-- The fields that travel on the wire.
function L.Wire(e)
    return { id = e.id, a = e.a, s = e.s, L = e.L, t = e.t, prev = e.prev, k = e.k, d = e.d, h = e.h }
end

-- Shape, hash, size and authorization checks. Returns true, or false + reason.
-- "unknownAuthor" means the roster can't place the author yet (retry later).
function L.Validate(e, g)
    if type(e) ~= "table" then return false, "shape" end
    if not isGUID(e.a) or not isInt(e.s, 1, 1e9) or type(e.id) ~= "string"
        or e.id ~= e.a .. ":" .. e.s then return false, "id" end
    if not isInt(e.L, 1, 1e12) or not isInt(e.t, 0, 1e11) then return false, "clock" end
    if e.prev ~= nil and type(e.prev) ~= "string" then return false, "prev" end
    if e.L > (g.lamport or 0) + L.MAX_LAMPORT_JUMP then return false, "lamportJump" end
    local spec = L.KINDS[e.k]
    if not spec or type(e.d) ~= "table" or not spec[2](e.d) then return false, "payload" end
    if e.h ~= L.Hash(e) then return false, "hash" end
    if not ns.RBAC.RoleOf(e.a) then return false, "unknownAuthor" end
    if not ns.RBAC.Can(e.a, spec[1]) then return false, "forbidden" end
    return true
end

local function advanceVV(g, author)
    local v = g.vv[author] or 0
    while g.log[author .. ":" .. (v + 1)] do v = v + 1 end
    g.vv[author] = v
end

-- Insert a validated event. confirmed = came from its author or an officer.
-- Returns "new", "confirmed", "dup", "conflict" or false + reason.
function L.Insert(g, e, confirmed)
    local ok, why = L.Validate(e, g)
    if not ok then return false, why end
    local have = g.log[e.id]
    if have then
        if have.h ~= e.h then
            g.conflicts = (g.conflicts or 0) + 1
            return "conflict"
        end
        if confirmed and not have.ok then
            have.ok = true
            return "confirmed"
        end
        return "dup"
    end
    local stored = L.Wire(e)
    stored.ok = confirmed and true or nil
    g.log[e.id] = stored
    if e.L > (g.lamport or 0) then g.lamport = e.L end
    advanceVV(g, e.a)
    return "new"
end

-- Build (but don't insert) the next event for an author.
function L.Build(g, author, kind, data, now)
    g.mySeq = g.mySeq or {}
    local seq = math.max(g.vv[author] or 0, g.mySeq[author] or 0) + 1
    while g.log[author .. ":" .. seq] do seq = seq + 1 end
    g.mySeq[author] = seq
    local prevEvent = g.log[author .. ":" .. (seq - 1)]
    local e = {
        id = author .. ":" .. seq, a = author, s = seq, L = (g.lamport or 0) + 1, t = now,
        prev = prevEvent and prevEvent.h or nil, k = kind, d = data,
    }
    e.h = L.Hash(e)
    return e
end

-- Author a new event as the current player.
function L.New(kind, data)
    local g = ns.G()
    if not g then return nil, "no guild" end
    local e = L.Build(g, ns.MyGUID(), kind, data, ns.Now())
    local res, why = L.Insert(g, e, true)
    if res ~= "new" then return nil, why or res end
    ns.Fire("LOG_CHANGED")
    if ns.Sync then ns.Sync.Broadcast(e) end
    return e
end

function L.Count(g)
    local n, pending = 0, 0
    for _, e in pairs(g.log) do
        n = n + 1
        if not e.ok then pending = pending + 1 end
    end
    return n, pending
end
