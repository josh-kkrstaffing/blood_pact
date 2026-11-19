-- Blood Pact: solo "mock guildmate" test mode. Swaps in a fake guild roster and
-- its own saved store. Nothing in mock mode is ever sent to the real guild.
--   /bp mock on      start, with you as Guild Master of 19 fake guildmates
--   /bp mock boss    simulate a boss kill (auto-award to a fake 10-player raid)
--   /bp mock award   a fake Officer awards DKP (arrives confirmed)
--   /bp mock forge   a fake Member relays a forged Officer award (stays provisional)
--   /bp mock reset   wipe the mock store
--   /bp mock off     back to your real guild
local _, ns = ...
local M = {}
ns.Mock = M

local FAKE = {
    { "Grimtusk", 1 }, { "Velara", 1 }, { "Ozrik", 1 },
    { "Bonecrush", 2 }, { "Shalendra", 2 },
    { "Thokk", 3 }, { "Mirelle", 3 }, { "Zugga", 3 }, { "Kaelos", 3 },
    { "Durnak", 4 }, { "Lirra", 4 }, { "Gorvash", 4 }, { "Tansy", 4 }, { "Rukhar", 4 }, { "Ysolde", 4 },
    { "Pip", 5 }, { "Hask", 5 }, { "Nerith", 5 }, { "Brakka", 5 },
}

local function fakeGUID(i) return ("Player-0000-MOCK%04d"):format(i) end

function M.Start()
    if ns.mock then ns.Print("Mock mode is already on.") return end
    M.realRoster = ns.roster
    ns.mock = true
    local byGUID, byName = {}, {}
    local me, myName = ns.MyGUID(), UnitName("player")
    byGUID[me] = { name = myName, rankIndex = 0 }
    byName[myName] = me
    for i, f in ipairs(FAKE) do
        local guid = fakeGUID(i)
        byGUID[guid] = { name = f[1], rankIndex = f[2] }
        byName[f[1]] = guid
    end
    ns.roster = { byGUID = byGUID, byName = byName, loaded = true }
    ns.Fire("ROSTER_CHANGED")
    ns.Fire("LOG_CHANGED")
    ns.Print("Mock mode ON: you are Guild Master of 19 fake guildmates. Nothing is sent to your real guild.")
end

function M.Stop()
    if not ns.mock then return end
    ns.mock = false
    ns.roster = M.realRoster or { byGUID = {}, byName = {}, loaded = false }
    ns.RebuildRoster()
    ns.Fire("LOG_CHANGED")
    ns.Print("Mock mode OFF.")
end

function M.Reset()
    if ns.db then ns.db.guilds[ns.MOCK_KEY] = nil end
    ns.Fire("LOG_CHANGED")
    ns.Print("Mock data wiped.")
end

function M.RaidGUIDs()
    local out = { ns.MyGUID() }
    for i = 1, 9 do out[#out + 1] = fakeGUID(i) end
    return out
end

local function fakeEvent(authorIndex, kind, data, confirmed)
    local g = ns.G()
    local e = ns.Log.Build(g, fakeGUID(authorIndex), kind, data, ns.Now())
    local res, why = ns.Log.Insert(g, e, confirmed)
    ns.Fire("LOG_CHANGED")
    return res, why
end

function M.Command(arg)
    arg = (arg or ""):lower()
    if arg == "on" then return M.Start() end
    if arg == "off" then return M.Stop() end
    if not ns.mock then ns.Print("Start mock mode first: /bp mock on") return end
    if arg == "reset" then
        M.Reset()
    elseif arg == "boss" then
        ns.DKP.OnBossKill(99999, "Mock Boss", 3)
    elseif arg == "award" then
        local raid = M.RaidGUIDs()
        local res = fakeEvent(1, "AWARD", { to = { raid[2], raid[3], raid[4] }, amt = 7, r = "manual", n = "Mock officer award" }, true)
        ns.Print("Grimtusk (Officer) awarded 7 DKP: " .. tostring(res))
    elseif arg == "forge" then
        -- A Member relays an award that claims Grimtusk wrote it. Not confirmed.
        local res = fakeEvent(1, "AWARD", { to = { fakeGUID(16) }, amt = 500, r = "manual", n = "Forged" }, false)
        ns.Print("Pip relayed a forged 500 DKP award: " .. tostring(res) .. " (provisional, not counted).")
    elseif arg == "signups" then
        -- Fake guildmates sign up for the next raid you scheduled.
        local list = ns.Raids.List(ns.Reducer.State(), ns.Now())
        local r
        for _, x in ipairs(list) do if x.at >= ns.Now() - 6 * 3600 then r = x; break end end
        if not r then ns.Print("Schedule a raid in the Raids tab first.") return end
        local plan = { "tank", "tank", "healer", "healer", "healer", "dps", "dps", "dps", "dps", "dps", "dps" }
        for i, role in ipairs(plan) do fakeEvent(i, "SIGNUP", { ev = r.id, st = "yes", role = role }, true) end
        fakeEvent(12, "SIGNUP", { ev = r.id, st = "maybe", role = "dps" }, true)
        fakeEvent(13, "SIGNUP", { ev = r.id, st = "no" }, true)
        ns.Print("13 fake guildmates answered the sign-up for " .. r.title .. ".")
    elseif arg == "attend" then
        local e, n = ns.Raids.TakeAttendance("mock")
        ns.Print(e and ("Attendance taken for " .. n .. " raiders.") or tostring(n))
    else
        ns.Print("Mock commands: on, off, boss, award, forge, signups, attend, reset")
    end
end
