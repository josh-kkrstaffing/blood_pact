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
    local _, myClass = UnitClass("player")
    local here = (GetRealZoneText and GetRealZoneText()) or "Orgrimmar"
    byGUID[me] = { name = myName, rankIndex = 0, rank = "Guild Master", online = true, class = myClass,
        level = UnitLevel and UnitLevel("player") or 60, zone = here }
    byName[myName] = me
    for i, f in ipairs(FAKE) do
        local guid = fakeGUID(i)
        -- A spread of last-online days so the activity colors and cleanup tasks show.
        local away = ({ [6] = 35, [9] = 70, [12] = 120, [15] = 95 })[i] or (i % 3 == 0 and 2 or nil)
        local ranks = { [0] = "Guild Master", "Officer", "Team Captain", "Veteran", "Member", "Initiate" }
        -- Every fourth one is a warlock; a few stand in your zone.
        local zones = { here, "Felwood", "Blackrock Mountain" }
        byGUID[guid] = { name = f[1], rankIndex = f[2], rank = ranks[f[2]], level = 60,
            online = away == nil, offlineDays = away,
            class = i % 4 == 0 and "WARLOCK" or "WARRIOR", zone = zones[(i + 1) % 3 + 1] }
        byName[f[1]] = guid
    end
    ns.roster = { byGUID = byGUID, byName = byName, loaded = true, complete = true }
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
    elseif arg == "roster" then
        -- A fake Officer records some guild changes.
        local day = date("!%Y-%m-%d")
        fakeEvent(1, "ROSTER", { ev = "join", who = fakeGUID(18), name = ns.NameForGUID(fakeGUID(18)) or "Newbie", ri = 5, rank = "Initiate", idem = "mj:" .. day, live = true }, true)
        fakeEvent(1, "ROSTER", { ev = "promote", who = fakeGUID(5), name = ns.NameForGUID(fakeGUID(5)) or "Vet", ri = 3, rank = "Veteran", by = "Grimtusk", idem = "mp:" .. day, live = true }, true)
        fakeEvent(1, "ALT_LINK", { alt = fakeGUID(19), main = fakeGUID(4) }, true)
        -- Fake crafting orders: one asked of you, one on the Wanted board.
        fakeEvent(4, "ORDER", { rid = 7418, p = "Enchanting", q = 1, mats = "me", to = ns.MyGUID(), n = "Mock order for you" }, true)
        fakeEvent(6, "ORDER", { rid = 7420, p = "Enchanting", q = 2, mats = "crafter" }, true)
        -- Fake PvP ranks, and a few fake guildmates share their professions and recipes.
        fakeEvent(1, "PVP", { r = 7 }, true)
        fakeEvent(3, "PVP", { r = 2 }, true)
        fakeEvent(5, "PVP", { r = 14 }, true)
        fakeEvent(2, "RECIPES", { p = "Enchanting", ids = ns.U.PackIDs({ 7418, 7420, 7421, 7426, 7428, 7443, 7454, 7457 }), reset = true }, true)
        fakeEvent(1, "PROF", { p1 = "Blacksmithing", l1 = 300, x1 = 300, p2 = "Mining", l2 = 300, x2 = 300, fa = 300, xfa = 300, ck = 225, xck = 300, fi = 150, xfi = 225 }, true)
        fakeEvent(2, "PROF", { p1 = "Enchanting", l1 = 290, x1 = 300, p2 = "Tailoring", l2 = 300, x2 = 300, fa = 225, xfa = 225, ck = 300, xck = 300, fi = 75, xfi = 75 }, true)
        fakeEvent(6, "PROF", { p1 = "Herbalism", l1 = 240, x1 = 300, fa = 150, xfa = 150, ck = 1, xck = 75 }, true)
        fakeEvent(10, "PROF", { p1 = "Alchemy", l1 = 275, x1 = 300, p2 = "Herbalism", l2 = 300, x2 = 300, fa = 300, ck = 300, fi = 300 }, true)
        ns.Print("Grimtusk logged a join, a promotion and an alt link. See Roster > Guild log and Officer tasks.")
    elseif arg == "summon" then
        -- A fake guildmate asks for a summon, and one in your zone offers to click.
        local me, now = ns.MyGUID(), ns.Now()
        ns.Summon.Apply({ t = "SR", z = "Felwood", n = "Blackrock Spire" }, fakeGUID(2), ns.roster.byGUID, me, now)
        ns.Summon.Apply({ t = "SI", to = me }, fakeGUID(5), ns.roster.byGUID, me, now)
        ns.Fire("LOG_CHANGED")
        ns.Print("Velara asked for a summon and Shalendra offered to click. See the Summon tab.")
    elseif arg == "attend" then
        local e, n = ns.Raids.TakeAttendance("mock")
        ns.Print(e and ("Attendance taken for " .. n .. " raiders.") or tostring(n))
    else
        ns.Print("Mock commands: on, off, boss, award, forge, signups, attend, roster, summon, reset")
    end
end
