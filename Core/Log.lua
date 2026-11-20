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
    UNDECAY = { "decay", function(d)
        return str(d.target, 1, 80)
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
    -- A Team Captain or above gives a signed-up player a raid spot, or takes
    -- it back. Its own kind, so older versions keep it without counting it.
    RAID_PICK = { "schedule", function(d)
        return str(d.ev, 1, 80) and isGUID(d.who) and type(d.on) == "boolean"
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
    -- A player's own readiness score against the ranked BiS list (whole percents).
    GEAR = { "signup", function(d)
        return str(d.spec, 1, 24) and isInt(d.pre, 0, 100) and isInt(d.worn, 0, 100)
            and (d.raid == nil or isInt(d.raid, 0, 100))
    end },
    -- A player's own profession levels, read from their character.
    PROF = { "signup", function(d)
        local function lv(n) return n == nil or isInt(n, 0, 1000) end
        return (d.p1 == nil or str(d.p1, 1, 24)) and (d.p2 == nil or str(d.p2, 1, 24))
            and lv(d.l1) and lv(d.l2) and lv(d.fa) and lv(d.ck) and lv(d.fi)
            and lv(d.x1) and lv(d.x2) and lv(d.xfa) and lv(d.xck) and lv(d.xfi)       -- skill caps
    end },
    -- Recipes a player knows in one profession, as packed ids. reset = this
    -- replaces what they shared before; otherwise it adds to it.
    RECIPES = { "signup", function(d)
        return str(d.p, 1, 24) and str(d.ids, 1, 1200) and ns.U.UnpackIDs(d.ids, 400) ~= nil
            and (d.reset == nil or d.reset == true)
    end },
    -- Crafting orders, inside the guild. to = the crafter asked, or nil for
    -- the Wanted board. mats = who supplies the materials.
    ORDER = { "signup", function(d)
        return isInt(d.rid, 1, 9999999) and str(d.p, 1, 24) and isInt(d.q, 1, 99)
            and (d.to == nil or isGUID(d.to)) and (d.mats == "me" or d.mats == "crafter" or d.mats == "bank") and optNote(d.n)
    end },
    -- A step on an order by the crafter or the member who asked. The
    -- reducer decides whether that person may take that step.
    ORDER_ST = { "signup", function(d)
        local step = d.st
        if not (step == "accept" or step == "decline" or step == "ready" or step == "release" or step == "deliver" or step == "cancel") then
            return false
        end
        if step == "accept" then
            if not (d.h == 2 or d.h == 8 or d.h == 24 or d.h == 48) then return false end
        elseif d.h ~= nil then
            return false
        end
        return str(d.id, 1, 80) and optNote(d.n)
    end },
    -- The crafter mailed n of the items for an order they are making. Its own
    -- kind, so versions from before it existed keep it without counting it.
    ORDER_MAIL = { "signup", function(d) return str(d.id, 1, 80) and isInt(d.n, 1, 99) end },
    -- An Officer cancelling someone else's order to keep the board tidy.
    ORDER_MOD = { "void", function(d) return str(d.id, 1, 80) and d.st == "cancel" end },
    -- A player's own PvP rank, 0 (none) to 14.
    PVP = { "signup", function(d) return isInt(d.r, 0, 14) end },
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

L.MAX_UNKNOWN_BYTES = 2000

-- Shape, hash, size and authorization checks. Returns true, or false + reason.
-- "unknownAuthor" means the roster can't place the author yet (retry later).
-- vouched: an Officer relayed it as confirmed, so the author's rank isn't
--   checked again. That keeps history intact after its author is demoted or
--   leaves the guild.
-- A kind this version doesn't know (from a newer Blood Pact) passes as
--   true, "unknownKind": it is stored and passed on, but never counted.
function L.Validate(e, g, vouched)
    if type(e) ~= "table" then return false, "shape" end
    if not isGUID(e.a) or not isInt(e.s, 1, 1e9) or type(e.id) ~= "string"
        or e.id ~= e.a .. ":" .. e.s then return false, "id" end
    if not isInt(e.L, 1, 1e12) or not isInt(e.t, 0, 1e11) then return false, "clock" end
    if e.prev ~= nil and type(e.prev) ~= "string" then return false, "prev" end
    if e.L > (g.lamport or 0) + L.MAX_LAMPORT_JUMP then return false, "lamportJump" end
    if type(e.k) ~= "string" or #e.k < 1 or #e.k > 24 or type(e.d) ~= "table" then return false, "payload" end
    local spec = L.KINDS[e.k]
    if spec and not spec[2](e.d) then return false, "payload" end
    if e.h ~= L.Hash(e) then return false, "hash" end
    if not spec then
        local ok, enc = pcall(U.Encode, e.d)
        if not ok or #enc > L.MAX_UNKNOWN_BYTES then return false, "payload" end
        if not vouched and not ns.RBAC.RoleOf(e.a) then return false, "unknownAuthor" end
        return true, "unknownKind"
    end
    if vouched then return true end
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
function L.Insert(g, e, confirmed, vouched)
    local ok, why = L.Validate(e, g, vouched)
    if not ok then return false, why end
    local have = g.log[e.id]
    if have then
        if have.h ~= e.h then
            -- An unconfirmed copy never blocks a confirmed one. Otherwise anyone
            -- could reserve an Officer's next event number with a fake.
            if confirmed and not have.ok then
                local stored = L.Wire(e)
                stored.ok = true
                stored.u = (why == "unknownKind") and true or nil
                g.log[e.id] = stored
                if e.L > (g.lamport or 0) then g.lamport = e.L end
                return "new"
            end
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
    stored.u = (why == "unknownKind") and true or nil   -- held until an update knows the kind
    g.log[e.id] = stored
    if e.L > (g.lamport or 0) then g.lamport = e.L end
    advanceVV(g, e.a)
    return "new"
end

-- After an update: events of kinds this version now knows were stored
-- unchecked. Check them once; ones that fail are kept (so sync stays whole)
-- but marked bad and never counted. Returns how many were checked.
function L.Revalidate(g)
    local n = 0
    for _, e in pairs(g.log) do
        local spec = e.u and L.KINDS[e.k]
        if spec then
            n = n + 1
            e.u = nil
            if not spec[2](e.d) then
                e.bad = true
            elseif ns.RBAC.RoleOf(e.a) and not ns.RBAC.Can(e.a, spec[1]) then
                e.bad = true
            end
        end
    end
    return n
end

-- Two computers, one character: if this PC wrote an event under a number the
-- guild already holds from the other PC, take the guild's copy and hand back
-- ours so it can be written again under a fresh number.
function L.AdoptFork(g, e)
    local mine = g.log[e.id]
    if not mine or mine.h == e.h then return nil end
    local stored = L.Wire(e)
    stored.ok = true
    g.log[e.id] = stored
    if e.L > (g.lamport or 0) then g.lamport = e.L end
    return mine
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
