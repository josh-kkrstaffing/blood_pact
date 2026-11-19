-- Blood Pact: activity and the officer task queue.
-- Everything here is worked out from the synced log plus the guild roster, so
-- every officer sees the same tasks. Only "claimed" and "done" are written to
-- the log. The game blocks addons from changing ranks or removing members on
-- WoW Forever, so a task only prepares the command for an officer to run.
local _, ns = ...
local O = {}
ns.Officer = O

local floor = math.floor

O.LEVEL_LABEL = { active = "Active", watch = "Watch", inactive = "Inactive", cleanup = "Cleanup", unknown = "-" }
O.LEVEL_COLOR = { active = "40ff40", watch = "ffd100", inactive = "ff8040", cleanup = "ff4040", unknown = "808080" }
O.NEW_MEMBER_DAYS = 7

-- A main and its alts.
function O.Group(st, guid)
    local main = st.alts[guid] or guid
    local out = { main }
    for alt, m in pairs(st.alts) do if m == main and alt ~= main then out[#out + 1] = alt end end
    return out, main
end

-- Days since the player (any of their characters) was last active: online now,
-- last online from the roster, or a Blood Pact sign-up or raid attendance.
-- nil = no information.
function O.ActiveDays(st, roster, guid, now)
    local best
    local function take(d) if d and (not best or d < best) then best = d end end
    for _, g in ipairs((O.Group(st, guid))) do
        local m = roster[g]
        if m then
            if m.online then take(0) else take(m.offlineDays) end
        end
        if st.lastSeen[g] then take(floor((now - st.lastSeen[g]) / 86400)) end
    end
    return best
end

function O.Level(days, s)
    if not days then return "unknown" end
    if days >= s.inactCleanup then return "cleanup" end
    if days >= s.inactInactive then return "inactive" end
    if days >= s.inactWatch then return "watch" end
    return "active"
end

local function nameOf(roster, guid) return roster[guid] and roster[guid].name or "?" end

-- The open tasks. roleOf(guid) gives a Blood Pact role ("initiate", ...).
function O.Tasks(st, roster, now, roleOf)
    local s, out = st.settings, {}
    local function add(t)
        local state = st.tasks[t.id]
        if state and state.st == "done" then
            -- A cleanup check that was kept comes back after another Watch period.
            if not (t.kind == "cleanup" and now - state.t > s.inactWatch * 86400) then return end
        end
        if state and state.st == "claim" then t.claimedBy = state.by end
        out[#out + 1] = t
    end
    for guid, m in pairs(roster) do
        local main = st.alts[guid]
        local name = m.name or "?"
        if not main then
            local days = O.ActiveDays(st, roster, guid, now)
            if O.Level(days, s) == "cleanup" then
                local group = O.Group(st, guid)
                local alts = {}
                for i = 2, #group do if roster[group[i]] then alts[#alts + 1] = nameOf(roster, group[i]) end end
                add({ id = "cleanup:" .. guid, kind = "cleanup", who = guid, name = name, order = 4,
                    text = ("Review for removal: %s, last active %d days ago%s"):format(name, days,
                        #alts > 0 and (" (alts: " .. table.concat(alts, ", ") .. ")") or ""),
                    cmd = "/gremove " .. name })
            end
            local known = st.members[guid]
            if s.promoDays > 0 and roleOf(guid) == "initiate" and known and known.joined then
                local inGuild = floor((now - known.joined) / 86400)
                local raids = st.attendance[guid] or 0
                if inGuild >= s.promoDays and raids >= s.promoRaids then
                    add({ id = "promote:" .. guid .. ":" .. tostring(m.rankIndex), kind = "promote", who = guid, name = name, order = 1,
                        text = ("Promote %s: %d days in the guild, %d raids attended"):format(name, inGuild, raids),
                        cmd = "/gpromote " .. name })
                end
            end
            if known and known.joined and known.inGuild ~= false and now - known.joined < O.NEW_MEMBER_DAYS * 86400 then
                local hasAlts = #O.Group(st, guid) > 1
                if not hasAlts then
                    add({ id = "newcheck:" .. guid, kind = "newcheck", who = guid, name = name, order = 3,
                        text = ("New member %s: check whether it's someone's alt, and link it if so"):format(name),
                        cmd = name })
                end
            end
        elseif roster[main] and m.rankIndex and roster[main].rankIndex and m.rankIndex ~= roster[main].rankIndex then
            local want = roster[main].rankIndex
            add({ id = "altrank:" .. guid .. ":" .. want, kind = "altrank", who = guid, name = name, order = 2,
                text = ("Alt %s is %s; main %s is %s"):format(name, m.rank or "?", nameOf(roster, main), roster[main].rank or "?"),
                cmd = (m.rankIndex > want and "/gpromote " or "/gdemote ") .. name })
        end
    end
    table.sort(out, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.name < b.name
    end)
    return out
end

function O.Mark(id, state)
    if not ns.RBAC.ICan("roster") then return nil, "Only Team Captains and above work the task queue." end
    return ns.Log.New("TASK", { id = id, st = state })
end

function O.Current()
    local st = ns.Reducer.State()
    if not st then return {} end
    return O.Tasks(st, ns.roster.byGUID, ns.Now(), ns.RBAC.RoleOf)
end

-- One line at login for officers with work waiting.
ns.On("PLAYER_LOGIN", function()
    if not (C_Timer and C_Timer.After) then return end
    C_Timer.After(30, function()
        if not ns.RBAC.ICan("roster") or not ns.roster.loaded then return end
        local n = #O.Current()
        if n > 0 then ns.Print(("%d officer task%s waiting. Type /bp, then Roster > Officer tasks."):format(n, n == 1 and "" or "s")) end
    end)
end)
