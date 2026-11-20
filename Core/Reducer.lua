-- Blood Pact: replays the log into DKP state. Deterministic: any client with
-- the same confirmed events computes the same balances, whatever the order
-- the events arrived in.
local _, ns = ...
local Red = {}
ns.Reducer = Red

local floor, pairs, ipairs = math.floor, pairs, ipairs

-- Defaults follow a published example DKP setup (Raidium, "How to Build a Fair
-- DKP System"). The Guild Master or ADMIN changes them in Settings.
Red.DEFAULTS = {
    onTime = 10, bossFarm = 5, bossProg = 15, fullRaid = 10, decayPct = 15,
    priceBis = 100, priceMajor = 60, priceMinor = 30, priceOff = 10,
    -- Inactivity days: Watch / Inactive / Cleanup. Starting values are the
    -- defaults ForeverGuildManager publishes (30/60/90).
    inactWatch = 30, inactInactive = 60, inactCleanup = 90,
    -- Initiate -> Member rule: days in the guild and raids attended. 0 = off.
    promoDays = 0, promoRaids = 0,
}
Red.ATTEND_WINDOW = 10
Red.TIER_KEY = { bis = "priceBis", major = "priceMajor", minor = "priceMinor", off = "priceOff" }

local function before(x, y)
    if x.L ~= y.L then return x.L < y.L end
    if x.a ~= y.a then return x.a < y.a end
    return x.s < y.s
end

local cache, dirty = nil, true
function Red.Invalidate() dirty = true end

function Red.Build(g)
    local list, voided = {}, {}
    for _, e in pairs(g.log) do
        if e.ok and not e.u and not e.bad then list[#list + 1] = e end
    end
    table.sort(list, before)

    -- A void cancels an award or a spend, whenever it arrives. An undo-decay
    -- (Guild Master only) cancels a decay the same way.
    local undecayed = {}
    for _, e in ipairs(list) do
        if e.k == "VOID" then voided[e.d.target] = true end
        if e.k == "UNDECAY" then undecayed[e.d.target] = true end
    end

    local st = {
        settings = ns.U.Copy(Red.DEFAULTS), pools = {}, alts = {}, idem = {},
        recruitMsgs = nil, history = {}, lastDecay = nil,
        raids = {}, attendDays = {}, attendance = {}, raidNights = 0,
        members = {}, rosterLog = {}, tasks = {}, lastSeen = {}, gear = {}, profs = {}, recipes = {}, pvp = {}, orders = {},
    }
    local signups, picks, attIdem, rosterIdem = {}, {}, {}, {}
    local function mainOf(guid) return st.alts[guid] or guid end
    local function pool(guid)
        local key = mainOf(guid)
        local p = st.pools[key]
        if not p then
            p = { bal = 0, earned = 0, spent = 0 }
            st.pools[key] = p
        end
        return p
    end

    for _, e in ipairs(list) do
        local d, k = e.d, e.k
        if voided[e.id] and (k == "AWARD" or k == "SPEND") then
            -- skipped
        elseif k == "SETTINGS" then
            for key, v in pairs(d) do st.settings[key] = v end
        elseif k == "ALT_LINK" then
            st.alts[d.alt] = d.main
            st.rosterLog[#st.rosterLog + 1] = e
        elseif k == "ALT_UNLINK" then
            st.alts[d.alt] = nil
            st.rosterLog[#st.rosterLog + 1] = e
        elseif k == "ROSTER" then
            -- Several officers may see the same change; the idem key counts it once.
            if not rosterIdem[d.idem] then
                rosterIdem[d.idem] = true
                local m = st.members[d.who]
                if not m then
                    m = { name = d.name, history = {} }
                    st.members[d.who] = m
                end
                m.name = d.name
                if d.ev == "join" then
                    m.joined = m.joined or e.t
                    m.rejoined = (m.left and e.t) or m.rejoined
                    m.inGuild = true
                elseif d.ev == "leave" or d.ev == "kick" then
                    m.inGuild = false
                    m.left = e.t
                end
                if d.ri then m.ri = d.ri end
                if d.rank then m.rank = d.rank end
                m.history[#m.history + 1] = e
                st.rosterLog[#st.rosterLog + 1] = e
            end
        elseif k == "AWARD" then
            if not (d.idem and st.idem[d.idem]) then
                if d.idem then st.idem[d.idem] = e.id end
                local seen = {}
                for _, guid in ipairs(d.to) do
                    local key = mainOf(guid)
                    if not seen[key] then
                        seen[key] = true
                        local p = pool(guid)
                        p.bal = p.bal + d.amt
                        if d.amt > 0 then p.earned = p.earned + d.amt end
                    end
                end
                st.history[#st.history + 1] = e
            end
        elseif k == "SPEND" then
            local p = pool(d.from)
            p.bal = p.bal - d.amt
            p.spent = p.spent + d.amt
            st.history[#st.history + 1] = e
        elseif k == "DECAY" then
            if not undecayed[e.id] then
                for _, p in pairs(st.pools) do
                    if p.bal > 0 then
                        p.bal = floor(p.bal * (100 - d.pct) / 100 + 0.5)
                    end
                end
                st.lastDecay = e
                st.history[#st.history + 1] = e
            end
        elseif k == "GEAR" then
            -- Each player reports their own; the latest one stands.
            st.gear[e.a] = { spec = d.spec, pre = d.pre, worn = d.worn, raid = d.raid, t = e.t }
        elseif k == "PROF" then
            st.profs[e.a] = { p1 = d.p1, l1 = d.l1, x1 = d.x1, p2 = d.p2, l2 = d.l2, x2 = d.x2,
                fa = d.fa, xfa = d.xfa, ck = d.ck, xck = d.xck, fi = d.fi, xfi = d.xfi, t = e.t }
        elseif k == "ORDER" then
            if d.to ~= e.a then
                st.orders[e.id] = { id = e.id, by = e.a, to = d.to, rid = d.rid, p = d.p, q = d.q, mats = d.mats,
                    ask = d.n, status = "open", t = e.t, lastBy = e.a }
            end
        elseif k == "ORDER_ST" or k == "ORDER_MOD" then
            -- Only the right person can take each step; anything else is ignored.
            local o = st.orders[d.id]
            local step, who = d.st, e.a
            local live = o and (o.status == "open" or o.status == "accepted" or o.status == "ready")
            local done = false
            if not live then
                done = false
            elseif k == "ORDER_MOD" then
                o.status, o.doneAt, done = "cancelled", e.t, true
            elseif step == "accept" then
                if o.status == "open" and who ~= o.by and (o.to == nil or o.to == who) then
                    o.status, o.crafter, o.hours, o.due, done = "accepted", who, d.h, e.t + d.h * 3600, true
                end
            elseif step == "decline" then
                if o.status == "open" and o.to == who then o.status, o.doneAt, done = "declined", e.t, true end
            elseif step == "ready" then
                if o.status == "accepted" and o.crafter == who then o.status, done = "ready", true end
            elseif step == "release" then
                -- Handed back: a Wanted order reopens; one asked of a single crafter is declined.
                if o.status ~= "open" and o.crafter == who then
                    o.crafter, o.due, o.hours, o.mailed, o.mailedAt = nil, nil, nil, nil, nil
                    if o.to then o.status, o.doneAt = "declined", e.t else o.status = "open" end
                    done = true
                end
            elseif step == "deliver" then
                if o.status ~= "open" and o.by == who then o.status, o.doneAt, done = "delivered", e.t, true end
            elseif step == "cancel" then
                if o.by == who then o.status, o.doneAt, done = "cancelled", e.t, true end
            end
            if done then
                o.lastBy = who
                if d.n and who ~= o.by then o.note = d.n end
            end
        elseif k == "ORDER_MAIL" then
            -- Only the crafter, and only while the order is theirs to finish.
            local o = st.orders[d.id]
            if o and o.crafter == e.a and (o.status == "accepted" or o.status == "ready") then
                o.mailed = math.min(o.q, (o.mailed or 0) + d.n)
                o.mailedAt, o.lastBy = e.t, e.a
            end
        elseif k == "PVP" then
            st.pvp[e.a] = { r = d.r, t = e.t }
        elseif k == "RECIPES" then
            -- Each player reports their own. Bounded so nobody can bloat the guild's data.
            local mine = st.recipes[e.a]
            if not mine then mine = {}; st.recipes[e.a] = mine end
            local kinds = 0
            for _ in pairs(mine) do kinds = kinds + 1 end
            if mine[d.p] or kinds < 8 then
                local set = (not d.reset) and mine[d.p] or {}
                mine[d.p] = set
                local n = 0
                for _ in pairs(set) do n = n + 1 end
                for _, id in ipairs(ns.U.UnpackIDs(d.ids, 400) or {}) do
                    if not set[id] and n < 2000 then set[id] = true; n = n + 1 end
                end
            end
        elseif k == "TASK" then
            st.tasks[d.id] = { st = d.st, by = e.a, t = e.t }
        elseif k == "RECRUIT_MSGS" then
            st.recruitMsgs = d.msgs
        elseif k == "RAID" then
            st.raids[e.id] = { id = e.id, title = d.title, raid = d.raid, at = d.at, size = d.size,
                n = d.n, tz = d.tz, prog = d.prog or false, author = e.a, signups = {}, picked = {} }
        elseif k == "RAID_CANCEL" then
            if st.raids[d.ev] then st.raids[d.ev].cancelled = true end
        elseif k == "SIGNUP" then
            -- Latest sign-up per person per raid wins (events are in Lamport order).
            if e.t > (st.lastSeen[e.a] or 0) then st.lastSeen[e.a] = e.t end
            signups[d.ev] = signups[d.ev] or {}
            signups[d.ev][e.a] = { st = d.st, role = d.role, n = d.n }
        elseif k == "RAID_PICK" then
            -- The latest word on each player wins.
            picks[d.ev] = picks[d.ev] or {}
            picks[d.ev][d.who] = d.on and e.a or nil
        elseif k == "ATTEND" then
            if not attIdem[d.idem] then
                attIdem[d.idem] = true
                local day = st.attendDays[d.day] or {}
                st.attendDays[d.day] = day
                for _, guid in ipairs(d.who) do
                    day[guid] = true
                    if e.t > (st.lastSeen[guid] or 0) then st.lastSeen[guid] = e.t end
                end
            end
        end
    end

    for ev, people in pairs(signups) do
        local r = st.raids[ev]
        if r then r.signups = people end
    end
    for ev, chosen in pairs(picks) do
        local r = st.raids[ev]
        if r then r.picked = chosen end       -- [guid] = who selected them
    end

    -- Each main's alts, for activity checks.
    st.altsOf = {}
    for alt, main in pairs(st.alts) do
        local t = st.altsOf[main]
        if not t then
            t = {}
            st.altsOf[main] = t
        end
        t[#t + 1] = alt
    end

    -- Attendance: share of the last ATTEND_WINDOW raid nights each main was at.
    -- Alts count for their main.
    local days = {}
    for day in pairs(st.attendDays) do days[#days + 1] = day end
    table.sort(days, function(x, y) return x > y end)
    local held = math.min(#days, Red.ATTEND_WINDOW)
    st.raidNights = held
    for i = 1, held do
        local seen = {}
        for guid in pairs(st.attendDays[days[i]]) do
            local main = mainOf(guid)
            if not seen[main] then
                seen[main] = true
                st.attendance[main] = (st.attendance[main] or 0) + 1
            end
        end
    end
    return st
end

function Red.State()
    local g = ns.G()
    if not g then return nil end
    if dirty or not cache or cache.g ~= g then
        cache = Red.Build(g)
        cache.g = g
        dirty = false
    end
    return cache
end

function Red.Price(tier)
    local st = Red.State()
    local key = Red.TIER_KEY[tier]
    return st and key and st.settings[key] or nil
end

-- Attendance over the last raid nights: present, held (both 0 if none yet).
function Red.Attendance(guid)
    local st = Red.State()
    if not st or st.raidNights == 0 then return 0, 0 end
    return st.attendance[st.alts[guid] or guid] or 0, st.raidNights
end

function Red.Balance(guid)
    local st = Red.State()
    if not st then return 0 end
    local p = st.pools[st.alts[guid] or guid]
    return p and p.bal or 0
end

-- Balances depend only on the log, so roster updates don't force a replay.
if ns.Listen then
    ns.Listen("LOG_CHANGED", Red.Invalidate)
end
