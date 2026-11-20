-- Blood Pact unit tests for the pure-Lua core (no game client needed).
-- Run from the repo root:  lua tests/run.lua   (Lua 5.1+; CI uses 5.1)
local ns = {}
ns.Listen = function() end
ns.Fire = function() end
ns.roster = { byGUID = {}, byName = {}, loaded = true }
local NOW = 1763503200
ns.Now = function() return NOW end
local ME = "Player-1-OFFICER1"
ns.MyGUID = function() return ME end
ns.G = function() return nil end   -- tests pass stores explicitly

local function load(path)
    local chunk = assert(loadfile(path))
    chunk("BloodPact", ns)
end
load("Core/Util.lua")
load("Core/Time.lua")
load("Core/RBAC.lua")
load("Core/Log.lua")
load("Core/Reducer.lua")
ns.On = function() end
ns.UI = { AddTab = function() end, Need = function() end }
ns.W = {}
load("Modules/BiSData.lua")
load("Modules/BiS.lua")
ns.DKP = { GroupGUIDs = function() return {} end }
load("Modules/Raids.lua")
load("Modules/Officer.lua")
ns.Char = function() return {} end
load("Modules/PvP.lua")
load("Modules/Loot.lua")
load("Modules/Recipes.lua")
load("Modules/Orders.lua")
load("Modules/Mail.lua")
load("Modules/Professions.lua")
ns.Listen = function() end
load("Modules/Roster.lua")
ns.Sync = { Handle = function() end }
load("Modules/Summon.lua")
load("Modules/Recruit.lua")
load("Modules/SummonQueue.lua")
load("Modules/SummonCall.lua")

local U, Log, Red, R = ns.U, ns.Log, ns.Reducer, ns.RBAC
local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local function newStore() return { log = {}, vv = {}, lamport = 0, mySeq = {}, conflicts = 0 } end

-- Roster: GM, two officers, a captain, members.
local roster = {
    ["Player-1-GM"] = 0, ["Player-1-OFFICER1"] = 1, ["Player-1-OFFICER2"] = 1,
    ["Player-1-CAPT"] = 2, ["Player-1-VET"] = 3, ["Player-1-MEM1"] = 4, ["Player-1-MEM2"] = 4, ["Player-1-INIT"] = 5,
}
for guid, rank in pairs(roster) do ns.roster.byGUID[guid] = { name = guid:sub(10), rankIndex = rank } end

test("encode/decode round trip", function()
    local v = { a = 1, b = "x|y:z", c = { 1, 2, 3 }, d = true, e = -12.5, f = { nested = { deep = "ok" } } }
    local s = U.Encode(v)
    local back = assert(U.Decode(s))
    eq(back.a, 1); eq(back.b, "x|y:z"); eq(back.c[3], 3); eq(back.d, true); eq(back.e, -12.5); eq(back.f.nested.deep, "ok")
end)

test("encoding is deterministic", function()
    local a, b = {}, {}
    a.x = 1; a.y = 2; a.z = 3
    b.z = 3; b.y = 2; b.x = 1
    eq(U.Encode(a), U.Encode(b))
end)

test("decode rejects garbage", function()
    eq(U.Decode("s999:abc"), nil)
    eq(U.Decode("{s1:a"), nil)
    eq(U.Decode("#abc;"), nil)
    eq(U.Decode(""), nil)
end)

test("Safe escapes WoW codes and cuts length", function()
    eq(U.Safe("|cffff0000red|r"), "||cffff0000red||r")
    eq(U.Safe("abcdef", 3), "abc")
end)

test("roles from rank index, root admin", function()
    eq(R.RoleOf("Player-1-GM"), "gm")
    eq(R.RoleOf("Player-1-CAPT"), "captain")
    eq(R.RoleOf("Player-1-INIT"), "initiate")
    eq(R.RoleOf("Player-1-NOBODY"), nil)
    eq(R.Can("Player-1-OFFICER1", "award"), true)
    eq(R.Can("Player-1-CAPT", "award"), false)
    eq(R.Can("Player-1-CAPT", "recruit"), true)
    eq(R.Can("Player-1-OFFICER1", "settings"), false)
    R.ROOT_ADMINS[1] = "Player-9-DEV"
    eq(R.RoleOf("Player-9-DEV"), "admin")
    eq(R.Can("Player-9-DEV", "settings"), true)
    R.ROOT_ADMINS[1] = nil
end)

local function author(g, who, kind, data)
    local e = Log.Build(g, who, kind, data, NOW)
    return e
end

test("officer award accepted; member award forbidden; tampering rejected", function()
    local g = newStore()
    local e = author(g, "Player-1-OFFICER1", "AWARD", { to = { "Player-1-MEM1" }, amt = 10, r = "boss" })
    eq(Log.Insert(g, e, true), "new")
    local bad = author(g, "Player-1-MEM1", "AWARD", { to = { "Player-1-MEM1" }, amt = 500, r = "manual" })
    local res, why = Log.Insert(g, bad, true)
    eq(res, false); eq(why, "forbidden")
    local t = author(g, "Player-1-OFFICER1", "AWARD", { to = { "Player-1-MEM2" }, amt = 5, r = "boss" })
    t.d.amt = 5000
    res, why = Log.Insert(g, t, true)
    eq(res, false); eq(why, "hash")
end)

test("lamport jump is refused", function()
    local g = newStore()
    local e = author(g, "Player-1-OFFICER1", "AWARD", { to = { "Player-1-MEM1" }, amt = 1, r = "boss" })
    e.L = 999999; e.h = Log.Hash(e)
    local res, why = Log.Insert(g, e, true)
    eq(res, false); eq(why, "lamportJump")
end)

-- Build one shared history, then feed it to two stores in different orders.
local function history()
    local g = newStore()
    local evs = {}
    local function add(who, kind, data)
        local e = author(g, who, kind, data)
        assert(Log.Insert(g, e, true) == "new", kind)
        evs[#evs + 1] = e
    end
    add("Player-1-GM", "SETTINGS", { decayPct = 10 })
    add("Player-1-OFFICER1", "AWARD", { to = { "Player-1-MEM1", "Player-1-MEM2", "Player-1-VET" }, amt = 15, r = "boss", idem = "boss:1:3:d" })
    add("Player-1-OFFICER2", "AWARD", { to = { "Player-1-MEM1", "Player-1-MEM2" }, amt = 15, r = "boss", idem = "boss:1:3:d" })
    add("Player-1-OFFICER1", "ALT_LINK", { alt = "Player-1-INIT", main = "Player-1-MEM2" })
    add("Player-1-OFFICER1", "AWARD", { to = { "Player-1-INIT" }, amt = 7, r = "manual" })
    add("Player-1-OFFICER2", "SPEND", { from = "Player-1-MEM1", amt = 10, tier = "minor" })
    add("Player-1-OFFICER1", "AWARD", { to = { "Player-1-VET" }, amt = 100, r = "manual" })
    add("Player-1-OFFICER1", "VOID", { target = evs[#evs].id })
    add("Player-1-GM", "DECAY", { pct = 10 })
    return evs
end

test("reducer: same events in any order give the same balances", function()
    local evs = history()
    local results = {}
    for run = 1, 20 do
        local order = {}
        for i = 1, #evs do order[i] = evs[i] end
        math.randomseed(run * 7919)
        for i = #order, 2, -1 do
            local j = math.random(i)
            order[i], order[j] = order[j], order[i]
        end
        local g = newStore()
        for _, e in ipairs(order) do
            Log.Insert(g, e, true)  -- out-of-order inserts are fine
        end
        local st = Red.Build(g)
        results[run] = U.Encode(st.pools)
    end
    for run = 2, 20 do eq(results[run], results[1], "run " .. run) end
end)

test("reducer: dedupe, alts, void, spend, decay", function()
    local g = newStore()
    for _, e in ipairs(history()) do Log.Insert(g, e, true) end
    local st = Red.Build(g)
    -- MEM1: 15 boss (duplicate award skipped) - 10 spend = 5, decay 10% -> 5*0.9=4.5 -> 5 (round half up)
    eq(st.pools["Player-1-MEM1"].bal, 5, "MEM1")
    -- MEM2: 15, plus alt INIT's 7 after link = 22, decay -> 19.8 -> 20
    eq(st.pools["Player-1-MEM2"].bal, 20, "MEM2")
    -- VET: 15 (100 voided), decay -> 13.5 -> 14
    eq(st.pools["Player-1-VET"].bal, 14, "VET")
    eq(st.settings.decayPct, 10)
end)

test("provisional events don't count until confirmed", function()
    local g = newStore()
    local e = author(g, "Player-1-OFFICER1", "AWARD", { to = { "Player-1-MEM1" }, amt = 500, r = "manual" })
    eq(Log.Insert(g, e, false), "new")
    eq(Red.Build(g).pools["Player-1-MEM1"], nil)
    eq(Log.Insert(g, e, true), "confirmed")
    eq(Red.Build(g).pools["Player-1-MEM1"].bal, 500)
end)

test("conflicting event with a reused id is kept out", function()
    local g = newStore()
    local e1 = author(g, "Player-1-OFFICER1", "AWARD", { to = { "Player-1-MEM1" }, amt = 1, r = "boss" })
    Log.Insert(g, e1, true)
    local e2 = { id = e1.id, a = e1.a, s = e1.s, L = e1.L, t = e1.t, prev = e1.prev, k = "AWARD",
                 d = { to = { "Player-1-MEM1" }, amt = 2, r = "boss" } }
    e2.h = Log.Hash(e2)
    eq(Log.Insert(g, e2, true), "conflict")
    eq(g.log[e1.id].d.amt, 1)
end)

test("version vector advances only over contiguous sequences", function()
    local g = newStore()
    local src = newStore()
    local a = author(src, "Player-1-OFFICER1", "AWARD", { to = { "Player-1-MEM1" }, amt = 1, r = "boss" }); Log.Insert(src, a, true)
    local b = author(src, "Player-1-OFFICER1", "AWARD", { to = { "Player-1-MEM1" }, amt = 1, r = "boss" }); Log.Insert(src, b, true)
    Log.Insert(g, b, true)
    eq(g.vv["Player-1-OFFICER1"], 0)
    Log.Insert(g, a, true)
    eq(g.vv["Player-1-OFFICER1"], 2)
end)

test("bis data: 28 specs in 9 classes; every slot has a BiS at score 1 and scores fall", function()
    local classes, specs = 0, 0
    for class, lists in pairs(ns.BiSData) do
        classes = classes + 1
        for key, list in pairs(lists) do
            specs = specs + 1
            assert(#list.slots >= 16 and #list.slots <= 17, class .. " " .. key .. " has " .. #list.slots .. " slots")
            assert(type(list.label) == "string" and (list.guides or 0) >= 1, key .. " label/guides")
            for _, s in ipairs(list.slots) do
                eq(s.items[1].score, 1, class .. " " .. key .. " " .. s.slot)
                for i = 1, #s.items do
                    local it = s.items[i]
                    assert(type(it.name) == "string" and it.name ~= "" and not it.name:find("%(A%)"), s.slot .. " bad name")
                    assert(type(it.how) == "string" and it.how ~= "", s.slot .. " missing how-to-get")
                    assert(i == 1 or it.score <= s.items[i - 1].score, key .. " " .. s.slot .. " scores not in order")
                    assert(it.score > 0 and it.score <= 1, s.slot .. " score out of range")
                end
            end
        end
    end
    eq(classes, 9); eq(specs, 28)
    eq(#ns.BiSData.WARLOCK.Demonology.slots, 17)
end)

test("bis: name from item link", function()
    eq(ns.BiS.NameFromLink("|cffa335ee|Hitem:12345::::::::60:::::|h[Robe of the Void]|h|r"), "Robe of the Void")
    eq(ns.BiS.NameFromLink(nil), nil)
end)

test("bis: empty gear ranks every slot as a full upgrade", function()
    local rows, owned, worn = ns.BiS.Evaluate(ns.BiSData.WARLOCK.Demonology, {})
    eq(#rows, 17); eq(owned, 0); eq(worn, 0)
    eq(rows[1].slot, "Head")   -- ties keep slot order
    eq(rows[1].gap, 1)
end)

test("bis: owned items, bag vs worn, step-up, one ring per slot", function()
    local list = ns.BiSData.WARLOCK.Demonology
    local owned = {
        ["Robe of the Void"] = "equipped",          -- chest BiS worn
        ["Crimson Felt Hat"] = "bags",               -- head alt, not worn
        ["Rune Band of Wizardry"] = "equipped",      -- ring 1 BiS
    }
    local rows = ns.BiS.Evaluate(list, owned)
    local by = {}
    for _, r in ipairs(rows) do by[r.slot] = r end
    eq(by.Chest.gap, 0)
    eq(by.Head.have.name, "Crimson Felt Hat"); eq(by.Head.where, "bags")
    eq(by.Head.alt.name, "Deathmist Mask")      -- nearest better item
    eq(by["Ring 1"].score, 1)
    eq(by["Ring 2"].score, 0)
    assert(rows[1].gap >= rows[#rows].gap, "sorted by biggest upgrade first")
    eq(rows[#rows].gap, 0)
end)

test("bis: an item counts once across shared slots", function()
    local list = { slots = {
        { slot = "Ring 1", items = { { name = "A", how = "x", score = 1 } } },
        { slot = "Ring 2", items = { { name = "A", how = "x", score = 1 }, { name = "B", how = "y", score = 0.5 } } },
    } }
    local rows = ns.BiS.Evaluate(list, { A = "equipped" })
    local by = {}
    for _, r in ipairs(rows) do by[r.slot] = r end
    eq(by["Ring 1"].score, 1); eq(by["Ring 2"].score, 0)
end)

-- Raids ---------------------------------------------------------------------
local function insertAll(g, list) for _, e in ipairs(list) do assert(Log.Insert(g, e, true) == "new") end end

test("raid: captain schedules, member can't; bad payloads refused", function()
    local g = newStore()
    local ok = author(g, "Player-1-CAPT", "RAID", { title = "BD night", raid = "Barrow Deeps", at = NOW + 86400, size = 10 })
    eq(Log.Insert(g, ok, true), "new")
    local no = author(g, "Player-1-MEM1", "RAID", { title = "x", raid = "Hyjal Summit", at = NOW + 86400, size = 20 })
    local res, why = Log.Insert(g, no, true)
    eq(res, false); eq(why, "forbidden")
    local bad = author(g, "Player-1-CAPT", "RAID", { title = "x", raid = "y", at = NOW, size = 99 })
    eq(select(2, Log.Insert(g, bad, true)), "payload")
    local badSign = author(g, "Player-1-MEM1", "SIGNUP", { ev = ok.id, st = "yes", role = "bard" })
    eq(select(2, Log.Insert(g, badSign, true)), "payload")
end)

test("raid: latest sign-up wins, counts by role, cancel hides it", function()
    local g = newStore()
    local r = author(g, "Player-1-CAPT", "RAID", { title = "BD", raid = "Barrow Deeps", at = NOW + 3600, size = 10 })
    Log.Insert(g, r, true)
    insertAll(g, {
        author(g, "Player-1-MEM1", "SIGNUP", { ev = r.id, st = "yes", role = "dps" }),
        author(g, "Player-1-MEM2", "SIGNUP", { ev = r.id, st = "yes", role = "healer" }),
        author(g, "Player-1-INIT", "SIGNUP", { ev = r.id, st = "maybe" }),
    })
    local change = author(g, "Player-1-MEM1", "SIGNUP", { ev = r.id, st = "yes", role = "tank" })
    Log.Insert(g, change, true)
    local st = Red.Build(g)
    local c = ns.Raids.Summary(st, st.raids[r.id])
    eq(c.yes, 2); eq(c.maybe, 1); eq(c.tank, 1); eq(c.dps, 0); eq(c.healer, 1)
    eq(#ns.Raids.List(st, NOW), 1)
    Log.Insert(g, author(g, "Player-1-OFFICER1", "RAID_CANCEL", { ev = r.id }), true)
    st = Red.Build(g)
    eq(#ns.Raids.List(st, NOW), 0)
end)

test("attendance: nights counted once, idem dedupes, alts fold, window of 10", function()
    local g = newStore()
    Log.Insert(g, author(g, "Player-1-OFFICER1", "ALT_LINK", { alt = "Player-1-MEM2", main = "Player-1-MEM1" }), true)
    -- Night 1: two boss kills; MEM1's alt joins for the second one.
    insertAll(g, {
        author(g, "Player-1-CAPT", "ATTEND", { who = { "Player-1-MEM1", "Player-1-VET" }, day = "2026-12-09", idem = "boss1" }),
        author(g, "Player-1-CAPT", "ATTEND", { who = { "Player-1-MEM2", "Player-1-VET" }, day = "2026-12-09", idem = "boss2" }),
    })
    -- The same idem relayed again by another officer counts once.
    Log.Insert(g, author(g, "Player-1-OFFICER2", "ATTEND", { who = { "Player-1-INIT" }, day = "2026-12-10", idem = "boss1" }), true)
    Log.Insert(g, author(g, "Player-1-CAPT", "ATTEND", { who = { "Player-1-VET" }, day = "2026-12-11", idem = "boss3" }), true)
    local st = Red.Build(g)
    eq(st.raidNights, 2)
    eq(st.attendance["Player-1-MEM1"], 1)
    eq(st.attendance["Player-1-MEM2"], nil)
    eq(st.attendance["Player-1-VET"], 2)
    eq(st.attendance["Player-1-INIT"], nil)
    for i = 1, 12 do
        Log.Insert(g, author(g, "Player-1-CAPT", "ATTEND", { who = { "Player-1-INIT" },
            day = ("2027-01-%02d"):format(i), idem = "n" .. i }), true)
    end
    st = Red.Build(g)
    eq(st.raidNights, 10)
    eq(st.attendance["Player-1-INIT"], 10)
    eq(st.attendance["Player-1-VET"], nil)
end)

test("raid: member can't take attendance; sign-up shows who was there", function()
    local g = newStore()
    local memberAttend = author(g, "Player-1-MEM1", "ATTEND", { who = { "Player-1-MEM1" }, day = "2026-12-09", idem = "x" })
    eq(select(2, Log.Insert(g, memberAttend, true)), "forbidden")
    local at = 1797019200   -- 2026-12-09 20:00 UTC
    local r = author(g, "Player-1-CAPT", "RAID", { title = "BD", raid = "Barrow Deeps", at = at, size = 10 })
    Log.Insert(g, r, true)
    insertAll(g, {
        author(g, "Player-1-MEM1", "SIGNUP", { ev = r.id, st = "yes", role = "dps" }),
        author(g, "Player-1-VET", "SIGNUP", { ev = r.id, st = "yes", role = "tank" }),
        author(g, "Player-1-CAPT", "ATTEND", { who = { "Player-1-VET" }, day = ns.Raids.RaidDay(at), idem = "b" }),
    })
    local st = Red.Build(g)
    local _, rows = ns.Raids.Summary(st, st.raids[r.id])
    local by = {}
    for _, row in ipairs(rows) do by[row.guid] = row end
    eq(by["Player-1-VET"].showed, true)
    eq(by["Player-1-MEM1"].showed, nil)
end)

test("/bp and /bloodpact both open the window", function()
    rawset(_G, "SlashCmdList", {})
    local opened = 0
    ns.UI.Toggle = function() opened = opened + 1 end
    load("Core/Commands.lua")
    eq(rawget(_G, "SLASH_BLOODPACT1"), "/bp")
    eq(rawget(_G, "SLASH_BLOODPACT2"), "/bloodpact")
    local handler = rawget(_G, "SlashCmdList").BLOODPACT
    handler("")
    handler("   ")
    eq(opened, 2)
end)

test("time zones: Central 8 PM in winter and summer, DST switch days", function()
    local T = ns.Time
    local u = T.FromZone("CT", 2026, 12, 9, 20, 0)
    eq(os.date("!%Y-%m-%d %H:%M", u), "2026-12-10 02:00")
    eq(T.Format("ET", u), "9:00 PM Eastern")
    eq(T.Format("PT", u), "6:00 PM Pacific")
    eq(T.Format("AZ", u), "7:00 PM Arizona")
    eq(os.date("!%H:%M", T.FromZone("CT", 2026, 7, 1, 20, 0)), "01:00")
    eq(os.date("!%H:%M", T.FromZone("ET", 2026, 3, 8, 3, 0)), "07:00")   -- DST began Mar 8
    eq(os.date("!%H:%M", T.FromZone("ET", 2026, 3, 7, 3, 0)), "08:00")
    eq(os.date("!%H:%M", T.FromZone("ET", 2026, 11, 1, 12, 0)), "17:00") -- DST ended Nov 1
    eq(ns.Raids.ParseWhen("2026-12-09", "20:00", "CT"), u)
    eq(ns.Raids.ParseWhen("2026-12-09", "25:00", "CT"), nil)
end)

test("raid: time zone and progression travel with the raid", function()
    local g = newStore()
    local r = author(g, "Player-1-CAPT", "RAID", { title = "Prog", raid = "Hyjal Summit", at = NOW + 3600, size = 20, tz = "CT", prog = true })
    eq(Log.Insert(g, r, true), "new")
    local bad = author(g, "Player-1-CAPT", "RAID", { title = "x", raid = "y", at = NOW + 3600, size = 20, prog = "yes" })
    eq(select(2, Log.Insert(g, bad, true)), "payload")
    local st = Red.Build(g)
    eq(st.raids[r.id].tz, "CT"); eq(st.raids[r.id].prog, true)
    eq(ns.Raids.Current(st, NOW + 1800).id, r.id)       -- 30 min before start
    eq(ns.Raids.Current(st, NOW + 3600 * 5).id, r.id)   -- 4 hours in
    eq(ns.Raids.Current(st, NOW - 3600), nil)           -- 2 hours before
end)

test("reminders: 30 and 15 minutes before, once each, only if signed up", function()
    local g = newStore()
    local r = author(g, "Player-1-CAPT", "RAID", { title = "BD", raid = "Barrow Deeps", at = NOW + 3600, size = 10 })
    Log.Insert(g, r, true)
    insertAll(g, {
        author(g, "Player-1-MEM1", "SIGNUP", { ev = r.id, st = "yes", role = "dps" }),
        author(g, "Player-1-MEM2", "SIGNUP", { ev = r.id, st = "no" }),
    })
    local st = Red.Build(g)
    local done = {}
    eq(#ns.Raids.DueReminders(st, "Player-1-MEM1", NOW, done), 0)            -- an hour out
    local due = ns.Raids.DueReminders(st, "Player-1-MEM1", NOW + 1800, done)  -- 30 min out
    eq(#due, 1); eq(due[1].mark, 30)
    done[due[1].key] = true
    eq(#ns.Raids.DueReminders(st, "Player-1-MEM1", NOW + 1860, done), 0)     -- not twice
    due = ns.Raids.DueReminders(st, "Player-1-MEM1", NOW + 2700, done)        -- 15 min out
    eq(#due, 1); eq(due[1].mark, 15)
    eq(#ns.Raids.DueReminders(st, "Player-1-MEM2", NOW + 1800, {}), 0)        -- said no
    eq(#ns.Raids.DueReminders(st, "Player-1-VET", NOW + 1800, {}), 0)         -- never signed up
end)

test("roster: guild system messages parse, names with dashes and spaced ranks", function()
    local P = ns.Roster.ParseSystem
    local j = P("Binky has joined the guild."); eq(j.ev, "join"); eq(j.name, "Binky")
    local l = P("Binky-Forever has left the guild."); eq(l.ev, "leave"); eq(l.name, "Binky-Forever")
    local k = P("Pip has been kicked out of the guild by Grimtusk."); eq(k.ev, "kick"); eq(k.name, "Pip"); eq(k.by, "Grimtusk")
    local pr = P("Grimtusk has promoted Pip to Team Captain."); eq(pr.ev, "promote"); eq(pr.name, "Pip"); eq(pr.by, "Grimtusk")
    local dm = P("Grimtusk has demoted Pip to Member."); eq(dm.ev, "demote"); eq(dm.name, "Pip")
    eq(P("Pip says hello."), nil)
    eq(P("50% of the guild (joined) the guild."), nil)
end)

test("roster: diff finds joins, leaves, promotions; skips what's logged; refuses partial rosters", function()
    local old = {
        A = { name = "Alpha", ri = 4 }, B = { name = "Bravo", ri = 4 }, C = { name = "Charlie", ri = 2 }, D = { name = "Delta", ri = 5 },
    }
    local new = {
        A = { name = "Alpha", ri = 3, rank = "Veteran" }, C = { name = "Charlie", ri = 4, rank = "Member" },
        D = { name = "Delta", ri = 5 }, E = { name = "Echo", ri = 5, rank = "Initiate" },
    }
    local out = ns.Roster.Diff(old, new, { members = {} })
    local by = {}
    for _, c in ipairs(out) do by[c.name] = c.ev end
    eq(by.Alpha, "promote"); eq(by.Bravo, "leave"); eq(by.Charlie, "demote"); eq(by.Echo, "join"); eq(by.Delta, nil)
    -- Another officer already logged Bravo leaving and Echo joining.
    out = ns.Roster.Diff(old, new, { members = { B = { inGuild = false }, E = { inGuild = true }, A = { ri = 3 } } })
    eq(#out, 1); eq(out[1].name, "Charlie")
    -- A roster that suddenly lost most people is treated as incomplete.
    local big, few = {}, {}
    for i = 1, 50 do big["G" .. i] = { name = "N" .. i, ri = 4 } end
    for i = 1, 10 do few["G" .. i] = { name = "N" .. i, ri = 4 } end
    eq(ns.Roster.Diff(big, few, { members = {} }), nil)
    eq(ns.Roster.Diff(big, {}, { members = {} }), nil)
end)

test("roster: log builds join dates and history once; members can't write it; alts unlink", function()
    local g = newStore()
    local j = { ev = "join", who = "Player-1-MEM1", name = "MEM1", ri = 5, rank = "Initiate", idem = "join:Player-1-MEM1:5:2026-12-01" }
    Log.Insert(g, author(g, "Player-1-CAPT", "ROSTER", j), true)
    Log.Insert(g, author(g, "Player-1-OFFICER1", "ROSTER", j), true)   -- same change seen twice
    Log.Insert(g, author(g, "Player-1-OFFICER1", "ROSTER", { ev = "promote", who = "Player-1-MEM1", name = "MEM1",
        ri = 4, rank = "Member", by = "Officer1", idem = "promote:Player-1-MEM1:4:2026-12-05" }), true)
    eq(select(2, Log.Insert(g, author(g, "Player-1-MEM2", "ROSTER", { ev = "join", who = "Player-1-MEM2", name = "MEM2",
        idem = "x" }), true)), "forbidden")
    Log.Insert(g, author(g, "Player-1-OFFICER1", "ALT_LINK", { alt = "Player-1-MEM2", main = "Player-1-MEM1" }), true)
    local st = Red.Build(g)
    local m = st.members["Player-1-MEM1"]
    eq(#m.history, 2); eq(m.joined, NOW); eq(m.rank, "Member"); eq(m.inGuild, true)
    eq(#st.rosterLog, 3)
    eq(st.alts["Player-1-MEM2"], "Player-1-MEM1")
    Log.Insert(g, author(g, "Player-1-OFFICER1", "ALT_UNLINK", { alt = "Player-1-MEM2" }), true)
    st = Red.Build(g)
    eq(st.alts["Player-1-MEM2"], nil)
end)

test("activity: best of main and alts, roster or Blood Pact activity; levels follow settings", function()
    local O = ns.Officer
    local st = { alts = { ALT = "MAIN" }, lastSeen = {}, settings = Red.DEFAULTS }
    local roster = { MAIN = { name = "Main", offlineDays = 100 }, ALT = { name = "Alt", offlineDays = 4 } }
    eq(O.ActiveDays(st, roster, "MAIN", NOW), 4)
    roster.ALT.offlineDays = 120
    st.lastSeen.MAIN = NOW - 10 * 86400                 -- signed up for a raid 10 days ago
    eq(O.ActiveDays(st, roster, "MAIN", NOW), 10)
    roster.ALT.online = true
    eq(O.ActiveDays(st, roster, "MAIN", NOW), 0)
    eq(O.Level(29, Red.DEFAULTS), "active"); eq(O.Level(30, Red.DEFAULTS), "watch")
    eq(O.Level(60, Red.DEFAULTS), "inactive"); eq(O.Level(90, Red.DEFAULTS), "cleanup")
    eq(O.Level(nil, Red.DEFAULTS), "unknown")
end)

test("tasks: cleanup, promotion rule, alt rank, new member; claim and done", function()
    local O = ns.Officer
    local g = newStore()
    local function st()
        local s = Red.Build(g)
        return s
    end
    -- MEM1 joined 40 days ago as an Initiate and raided 3 times; MEM2 is long gone.
    Log.Insert(g, Log.Build(g, "Player-1-CAPT", "ROSTER", { ev = "join", who = "Player-1-INIT", name = "Init",
        ri = 5, idem = "j1" }, NOW - 40 * 86400), true)
    for i = 1, 3 do
        Log.Insert(g, author(g, "Player-1-CAPT", "ATTEND", { who = { "Player-1-INIT" }, day = ("2026-11-0%d"):format(i), idem = "a" .. i }), true)
    end
    Log.Insert(g, author(g, "Player-1-OFFICER1", "ALT_LINK", { alt = "Player-1-MEM2", main = "Player-1-VET" }), true)
    local roster = {
        ["Player-1-INIT"] = { name = "Init", rankIndex = 5, online = true },
        ["Player-1-MEM1"] = { name = "Gone", rankIndex = 4, offlineDays = 200 },
        ["Player-1-VET"] = { name = "Vet", rankIndex = 3, rank = "Veteran", online = true },
        ["Player-1-MEM2"] = { name = "VetAlt", rankIndex = 4, rank = "Member", online = true },
    }
    local roleOf = function(guid) return guid == "Player-1-INIT" and "initiate" or "member" end
    local tasks = O.Tasks(st(), roster, NOW, roleOf)
    local kinds = {}
    for _, t in ipairs(tasks) do kinds[t.kind] = t end
    eq(kinds.cleanup.name, "Gone"); eq(kinds.cleanup.cmd, "/gremove Gone")
    eq(kinds.altrank.cmd, "/gpromote VetAlt")
    eq(kinds.promote, nil)                        -- promotion rule is off by default
    Log.Insert(g, author(g, "Player-1-GM", "SETTINGS", { promoDays = 30, promoRaids = 3 }), true)
    tasks = O.Tasks(st(), roster, NOW, roleOf)
    kinds = {}
    for _, t in ipairs(tasks) do kinds[t.kind] = t end
    eq(kinds.promote.cmd, "/gpromote Init")
    eq(tasks[1].kind, "promote")                  -- promotions sort first
    -- Claim shows who; done hides it for everyone.
    Log.Insert(g, author(g, "Player-1-CAPT", "TASK", { id = kinds.altrank.id, st = "claim" }), true)
    Log.Insert(g, author(g, "Player-1-CAPT", "TASK", { id = kinds.promote.id, st = "done" }), true)
    tasks = O.Tasks(st(), roster, NOW, roleOf)
    kinds = {}
    for _, t in ipairs(tasks) do kinds[t.kind] = t end
    eq(kinds.altrank.claimedBy, "Player-1-CAPT")
    eq(kinds.promote, nil)
    -- A dismissed cleanup comes back after another Watch period.
    Log.Insert(g, author(g, "Player-1-CAPT", "TASK", { id = kinds.cleanup.id, st = "done" }), true)
    eq(#O.Tasks(st(), roster, NOW, roleOf), 1)
    local later = O.Tasks(st(), roster, NOW + 31 * 86400, roleOf)
    local back = false
    for _, t in ipairs(later) do if t.kind == "cleanup" then back = true end end
    eq(back, true)
    -- Members can't touch the queue.
    eq(select(2, Log.Insert(g, author(g, "Player-1-MEM1", "TASK", { id = "x", st = "done" }), true)), "forbidden")
end)

test("new member check shows for a week, not for alts", function()
    local O = ns.Officer
    local g = newStore()
    Log.Insert(g, author(g, "Player-1-CAPT", "ROSTER", { ev = "join", who = "Player-1-MEM1", name = "Fresh", ri = 5, idem = "j" }), true)
    local roster = { ["Player-1-MEM1"] = { name = "Fresh", rankIndex = 5, online = true } }
    local any = function() return "member" end
    local tasks = O.Tasks(Red.Build(g), roster, NOW + 86400, any)
    eq(#tasks, 1); eq(tasks[1].kind, "newcheck")
    eq(#O.Tasks(Red.Build(g), roster, NOW + 8 * 86400, any), 0)
end)

-- Review fixes ---------------------------------------------------------------
test("log: a kind from a newer version is stored and passed on, but not counted", function()
    local g = newStore()
    local e = author(g, "Player-1-OFFICER1", "FUTURE_KIND", { x = 1 })
    eq(Log.Insert(g, e, true), "new")
    eq(g.log[e.id].u, true)
    eq(g.vv["Player-1-OFFICER1"], 1)                 -- sync keeps moving
    local after = author(g, "Player-1-OFFICER1", "AWARD", { to = { "Player-1-MEM1" }, amt = 5, r = "boss" })
    Log.Insert(g, after, true)
    eq(Red.Build(g).pools["Player-1-MEM1"].bal, 5)
    eq(select(2, Log.Insert(g, author(g, "Player-1-OFFICER1", "BIG", { x = ("y"):rep(3000) }), true)), "payload")
    -- After an update that knows the kind, it is checked once.
    Log.KINDS.FUTURE_KIND = { "settings", function(d) return d.x == 1 end }
    eq(Log.Revalidate(g), 1)
    eq(g.log[e.id].u, nil); eq(g.log[e.id].bad, true)   -- an Officer may not do a Guild Master action
    Log.KINDS.FUTURE_KIND = nil
end)

test("log: an Officer can vouch for history whose author left the guild", function()
    local g = newStore()
    ns.roster.byGUID["Player-1-GONE"] = { name = "Gone", rankIndex = 1 }
    local src = newStore()
    local e = author(src, "Player-1-GONE", "AWARD", { to = { "Player-1-MEM1" }, amt = 9, r = "boss" })
    ns.roster.byGUID["Player-1-GONE"] = nil            -- they left
    eq(select(2, Log.Insert(g, e, true)), "unknownAuthor")
    eq(Log.Insert(g, e, true, true), "new")            -- relayed and vouched for by an Officer
    eq(Red.Build(g).pools["Player-1-MEM1"].bal, 9)
end)

test("log: two computers, one character - the guild's copy wins and ours is kept", function()
    local pc1, pc2 = newStore(), newStore()
    local a = author(pc1, "Player-1-OFFICER1", "AWARD", { to = { "Player-1-MEM1" }, amt = 10, r = "boss" })
    Log.Insert(pc1, a, true)
    local b = author(pc2, "Player-1-OFFICER1", "AWARD", { to = { "Player-1-MEM2" }, amt = 20, r = "boss" })
    Log.Insert(pc2, b, true)
    eq(a.id, b.id)
    eq(Log.Insert(pc2, a, true), "conflict")
    local mine = Log.AdoptFork(pc2, a)
    eq(mine.d.amt, 20)
    local again = Log.Build(pc2, "Player-1-OFFICER1", mine.k, mine.d, NOW)
    eq(again.s, 2)
    eq(Log.Insert(pc2, again, true), "new")
    local st = Red.Build(pc2)
    eq(st.pools["Player-1-MEM1"].bal, 10); eq(st.pools["Player-1-MEM2"].bal, 20)
    eq(Log.AdoptFork(pc2, a), nil)                      -- nothing to do twice
end)

test("log: an unconfirmed fake can't hold an Officer's event number", function()
    local victim, peer = newStore(), newStore()
    local fake = author(newStore(), "Player-1-OFFICER1", "AWARD", { to = { "Player-1-MEM1" }, amt = 5000, r = "manual" })
    eq(Log.Insert(peer, fake, false), "new")                 -- relayed by a member: provisional
    local real = author(victim, "Player-1-OFFICER1", "AWARD", { to = { "Player-1-MEM1" }, amt = 7, r = "boss" })
    Log.Insert(victim, real, true)
    eq(real.id, fake.id)
    eq(Log.Insert(peer, real, true), "new")                  -- the confirmed one replaces it
    eq(Red.Build(peer).pools["Player-1-MEM1"].bal, 7)
    eq(Log.Insert(peer, fake, false), "conflict")            -- and the fake can't come back
    eq(Red.Build(peer).pools["Player-1-MEM1"].bal, 7)
end)

test("decay can be undone by the Guild Master only", function()
    local g = newStore()
    Log.Insert(g, author(g, "Player-1-OFFICER1", "AWARD", { to = { "Player-1-MEM1" }, amt = 100, r = "boss" }), true)
    local d = author(g, "Player-1-GM", "DECAY", { pct = 15 })
    Log.Insert(g, d, true)
    local st = Red.Build(g)
    eq(st.pools["Player-1-MEM1"].bal, 85); eq(st.lastDecay.id, d.id)
    eq(select(2, Log.Insert(g, author(g, "Player-1-OFFICER1", "UNDECAY", { target = d.id }), true)), "forbidden")
    Log.Insert(g, author(g, "Player-1-GM", "UNDECAY", { target = d.id }), true)
    st = Red.Build(g)
    eq(st.pools["Player-1-MEM1"].bal, 100); eq(st.lastDecay, nil)
end)

test("a roster record can't block a DKP award by reusing its key", function()
    local g = newStore()
    Log.Insert(g, author(g, "Player-1-CAPT", "ROSTER", { ev = "join", who = "Player-1-MEM1", name = "M", idem = "boss:1:3:2026-12-09" }), true)
    Log.Insert(g, author(g, "Player-1-OFFICER1", "AWARD", { to = { "Player-1-MEM1" }, amt = 5, r = "boss", idem = "boss:1:3:2026-12-09" }), true)
    eq(Red.Build(g).pools["Player-1-MEM1"].bal, 5)
end)

test("raid times: 8pm, 8:30 PM, 20:00; dates 12/9, 12/9/2026, 2026-12-09", function()
    local R = ns.Raids
    local function clock(s) local h, m = R.ParseClock(s); return h and (h * 100 + m) or nil end
    eq(clock("8pm"), 2000); eq(clock("8:30 PM"), 2030); eq(clock("20:00"), 2000); eq(clock("12am"), 0)
    eq(clock("12:15pm"), 1215); eq(clock("7 p.m."), 1900); eq(clock("13pm"), nil); eq(clock("20"), nil); eq(clock("soon"), nil)
    local function day(s) local y, m, d = R.ParseDay(s, NOW); return y and (y * 10000 + m * 100 + d) or nil end
    eq(day("2026-12-09"), 20261209); eq(day("12/9/2026"), 20261209); eq(day("12/9/26"), 20261209)
    eq(day("12/9"), 20251209)                 -- the test clock (NOW) is Nov 18, 2025
    eq(day("1/5"), 20260105)                  -- already past this year: next year
    eq(day("2/30"), nil); eq(day("13/1"), nil); eq(day("tomorrow"), nil)
    eq(R.ParseWhen("12/9", "8pm", "CT"), ns.Time.FromZone("CT", 2025, 12, 9, 20, 0))
end)

test("raid day: an evening raid is one day in every time zone; back-to-back nights stay apart", function()
    local T = ns.Time
    local tue = T.FromZone("CT", 2026, 12, 8, 20, 0)     -- Tue 8 PM Central = Wed 02:00 UTC
    local wed = T.FromZone("CT", 2026, 12, 9, 17, 30)    -- Wed 5:30 PM Central = Wed 23:30 UTC
    eq(T.RaidDay(tue), "2026-12-08"); eq(T.RaidDay(tue + 4 * 3600), "2026-12-08")
    eq(T.RaidDay(wed), "2026-12-09")
end)

test("versions and message patterns", function()
    eq(U.VersionNewer("0.10.0", "0.9.9"), true); eq(U.VersionNewer("0.6.0", "0.6.0"), false)
    eq(U.VersionNewer("0.5.9", "0.6.0"), false); eq(U.VersionNewer("1.0", "0.9.9"), true)
    eq(("No player named 'Pip Bee' is currently playing."):match(U.FormatPattern("No player named '%s' is currently playing.")), "Pip Bee")
end)

test("summon: warlocks with clickers in their zone come first; helpers are picked from the zone", function()
    local S = ns.Summon
    local roster = {
        L1 = { name = "Lock One", class = "WARLOCK", level = 60, online = true, zone = "Felwood" },
        L2 = { name = "Lock Two", class = "WARLOCK", level = 60, online = true, zone = "Orgrimmar" },
        L3 = { name = "Baby Lock", class = "WARLOCK", level = 12, online = true, zone = "Orgrimmar" },
        L4 = { name = "Away Lock", class = "WARLOCK", level = 60, online = false, zone = "Orgrimmar" },
        A = { name = "A", class = "MAGE", level = 60, online = true, zone = "Orgrimmar" },
        B = { name = "B", class = "MAGE", level = 60, online = true, zone = "Orgrimmar" },
        C = { name = "C", class = "MAGE", level = 60, online = true, zone = "Orgrimmar" },
        D = { name = "D", class = "MAGE", level = 60, online = false, zone = "Orgrimmar" },
        ASK = { name = "Asker", class = "ROGUE", level = 40, online = true, zone = "Tanaris" },
    }
    local locks = S.Warlocks(roster)
    eq(#locks, 2); eq(locks[1].guid, "L2"); eq(locks[1].ready, true); eq(#locks[1].near, 4)
    eq(locks[2].guid, "L1"); eq(locks[2].ready, false)
    local picks = S.PickHelpers(roster, "L2", "ASK", { L2 = true }, { C = 1 }, 2)
    eq(#picks, 2); eq(picks[1], "C")                      -- offered first
    eq(#S.PickHelpers(roster, "L2", "ASK", { L2 = true, A = true, B = true }, nil, 0), 0)
    eq(#S.PickHelpers(roster, "L1", "ASK", { L1 = true }, nil, 2), 0)   -- nobody in Felwood
end)

test("summon: request, claim, close and expiry", function()
    local S = ns.Summon
    local roster = { L = { class = "WARLOCK", online = true }, M = { class = "MAGE", online = true }, ASK = { class = "ROGUE" } }
    S.requests, S.offers, S.calls = {}, {}, {}
    eq((S.Apply({ t = "SR", z = "Tanaris", n = "Blackrock Spire" }, "ASK", roster, "L", 1000)), "request")
    eq(S.Apply({ t = "SR", z = ("x"):rep(100) }, "M", roster, "L", 1000), nil)       -- oversized: ignored
    eq(#S.Open(1000), 1)
    S.Apply({ t = "SA", who = "ASK" }, "M", roster, "ASK", 1001)                      -- a mage can't claim
    eq(S.requests.ASK.by, nil)
    eq((S.Apply({ t = "SA", who = "ASK" }, "L", roster, "ASK", 1002)), "claimed")
    eq(S.requests.ASK.by, "L")
    S.Apply({ t = "SX", who = "ASK" }, "M", roster, "L", 1003)                        -- a bystander can't close it
    eq(#S.Open(1003), 1)
    eq((S.Apply({ t = "SH", z = "Orgrimmar" }, "L", roster, "M", 1004)), "call")
    eq((S.Apply({ t = "SI", to = "L" }, "M", roster, "L", 1005)), "offer")
    S.Apply({ t = "SX", who = "ASK" }, "ASK", roster, "L", 1006)
    eq(#S.Open(1006), 0)
    S.Apply({ t = "SR", z = "Tanaris" }, "ASK", roster, "L", 2000)
    eq(#S.Open(2000 + S.TTL + 1), 0)                                                  -- expired
end)

test("bis: a two-hander covers the off hand; an Alliance twin counts", function()
    local list = { slots = {
        { slot = "Legs", items = { { name = "Outrider's Silk Leggings", ally = "Sentinel's Silk Leggings", how = "x", score = 1 } } },
        { slot = "Main hand", items = { { name = "Sword", how = "x", score = 1 }, { name = "Big Staff", how = "x", score = 0.6, two = true } } },
        { slot = "Off hand", items = { { name = "Orb", how = "x", score = 1 }, { name = "Book", how = "x", score = 0.25 } } },
    } }
    local rows, owned, worn = ns.BiS.Evaluate(list, { ["Big Staff"] = "equipped", ["Sentinel's Silk Leggings"] = "bags", ["Book"] = "bags" })
    local by = {}
    for _, r in ipairs(rows) do by[r.slot] = r end
    eq(by.Legs.score, 1); eq(by.Legs.where, "bags")
    eq(by["Main hand"].score, 0.6)
    eq(by["Off hand"].score, 0.6)                       -- the staff, not the 25% book
    eq(by["Off hand"].have.name, "Big Staff")
    assert(math.abs(owned - (1 + 0.6 + 0.6) / 3) < 1e-9)
    assert(math.abs(worn - (0 + 0.6 + 0.6) / 3) < 1e-9)
    -- With a one-hander, the off hand stands on its own.
    rows = ns.BiS.Evaluate(list, { Sword = "equipped", Book = "equipped" })
    by = {}
    for _, r in ipairs(rows) do by[r.slot] = r end
    eq(by["Off hand"].score, 0.25)
end)

test("bis: the list follows the talent tree with the most points", function()
    local S = ns.BiS.SpecFromTrees
    eq(S(ns.BiSData.WARLOCK, { { name = "Affliction", points = 5 }, { name = "Demonology", points = 40 }, { name = "Destruction", points = 6 } }), "Demonology")
    eq(S(ns.BiSData.DRUID, { { name = "Balance", points = 0 }, { name = "Feral", points = 31 }, { name = "Restoration", points = 20 } }), "Feral (Cat)")
    eq(S(ns.BiSData.WARRIOR, { { name = "Arms", points = 0 }, { name = "Fury", points = 0 } }), nil)   -- no points spent
    eq(S(ns.BiSData.MAGE, {}), nil)
end)

test("readiness: each player reports their own score; sign-ups sort by it", function()
    local g = newStore()
    local r = author(g, "Player-1-CAPT", "RAID", { title = "BD", raid = "Barrow Deeps", at = NOW + 3600, size = 10 })
    Log.Insert(g, r, true)
    insertAll(g, {
        author(g, "Player-1-MEM1", "SIGNUP", { ev = r.id, st = "yes", role = "dps" }),
        author(g, "Player-1-MEM2", "SIGNUP", { ev = r.id, st = "yes", role = "dps" }),
        author(g, "Player-1-VET", "SIGNUP", { ev = r.id, st = "yes", role = "tank" }),
        author(g, "Player-1-INIT", "SIGNUP", { ev = r.id, st = "maybe" }),
        author(g, "Player-1-MEM1", "GEAR", { spec = "Fury", pre = 12, worn = 10 }),
        author(g, "Player-1-MEM2", "GEAR", { spec = "Fire", pre = 80, worn = 71 }),
        author(g, "Player-1-INIT", "GEAR", { spec = "Holy", pre = 95, worn = 95 }),
        author(g, "Player-1-MEM1", "GEAR", { spec = "Fury", pre = 35, worn = 30 }),     -- a newer report replaces the old
    })
    eq(select(2, Log.Insert(g, author(g, "Player-1-MEM1", "GEAR", { spec = "Fury", pre = 140, worn = 0 }), true)), "payload")
    local st = Red.Build(g)
    eq(st.gear["Player-1-MEM1"].pre, 35); eq(st.gear["Player-1-VET"], nil)
    local _, rows = ns.Raids.Summary(st, st.raids[r.id])
    eq(rows[1].guid, "Player-1-MEM2")       -- coming, 80%
    eq(rows[2].guid, "Player-1-MEM1")       -- coming, 35%
    eq(rows[3].guid, "Player-1-VET")        -- coming, no score yet: last among those coming
    eq(rows[4].guid, "Player-1-INIT")       -- maybe, even at 95%
end)

test("professions: two professions plus First Aid, Cooking and Fishing, with real levels", function()
    local P = ns.Professions
    local rec = P.Classify({
        { name = "Tailoring", level = 300, primary = true }, { name = "Enchanting", level = 275, primary = true },
        { name = "First Aid", level = 225 }, { name = "Cooking", level = 150.0 }, { name = "Fishing", level = 1 },
        { name = "Archaeology", level = 50 }, { name = "Riding", level = 75 }, { name = "Swords", level = 300 },
    })
    eq(rec.p1, "Enchanting"); eq(rec.l1, 275); eq(rec.p2, "Tailoring"); eq(rec.l2, 300)
    eq(rec.fa, 225); eq(rec.ck, 150); eq(rec.fi, 1)
    -- Caps come along; the same profession listed twice keeps its best level; a cap below the level is dropped.
    local caps = P.Classify({ { name = "Mining", level = 75, max = 75 }, { name = "Mining", level = 240, max = 300 },
        { name = "Cooking", level = 150, max = 225 }, { name = "Fishing", level = 90, max = 75 } })
    eq(caps.p1, "Mining"); eq(caps.l1, 240); eq(caps.x1, 300); eq(caps.p2, nil)
    eq(caps.ck, 150); eq(caps.xck, 225); eq(caps.fi, 90); eq(caps.xfi, nil)
    eq(#P.Skills(caps), 3); eq(P.Skills(caps)[2].name, "Cooking"); eq(P.Skills(caps)[2].max, 225)
    local one = P.Classify({ { name = "Herbalism", level = 240 }, { name = "Cooking", level = 12 } })   -- known by name
    eq(one.p1, "Herbalism"); eq(one.p2, nil); eq(one.ck, 12); eq(one.fa, nil)
    eq(P.Same(rec, P.Classify({ { name = "Enchanting", level = 275 }, { name = "Tailoring", level = 300 },
        { name = "First Aid", level = 225 }, { name = "Cooking", level = 150 }, { name = "Fishing", level = 1 } })), true)
    eq(P.Same(rec, one), false)
    eq(P.Label("Tailoring", 300), "Tailoring 300"); eq(P.Label(nil), "-")
end)

test("professions: each player's own report syncs; the guild is listed by profession", function()
    local P = ns.Professions
    local g = newStore()
    insertAll(g, {
        author(g, "Player-1-MEM1", "PROF", { p1 = "Alchemy", l1 = 275, p2 = "Herbalism", l2 = 300, fa = 300, ck = 300, fi = 10 }),
        author(g, "Player-1-MEM2", "PROF", { p1 = "Tailoring", l1 = 300, x1 = 300, fa = 150, xfa = 225 }),
        author(g, "Player-1-MEM1", "PROF", { p1 = "Alchemy", l1 = 300, x1 = 300, p2 = "Herbalism", l2 = 300, fa = 300, ck = 300, fi = 10 }),
        author(g, "Player-1-OFFICER1", "PROF", { p1 = "Alchemy", l1 = 120, x1 = 150, ck = 40, xck = 75 }),
    })
    eq(select(2, Log.Insert(g, author(g, "Player-1-MEM1", "PROF", { p1 = "Alchemy", l1 = 9999 }), true)), "payload")
    eq(select(2, Log.Insert(g, author(g, "Player-1-MEM1", "PROF", { p1 = "Alchemy", l1 = 10, x1 = "lots" }), true)), "payload")
    local st = Red.Build(g)
    eq(st.profs["Player-1-MEM1"].l1, 300)                 -- the newer report stands
    eq(st.profs["Player-1-MEM2"].xfa, 225)                -- the cap travels with the level
    local roster = {
        ["Player-1-MEM1"] = { name = "Zed", class = "MAGE", online = true }, ["Player-1-MEM2"] = { name = "Amy", online = false },
        ["Player-1-OFFICER1"] = { name = "Cal", online = true }, ["Player-1-VET"] = { name = "Bob", online = true },
    }
    local groups, shared = P.Groups(roster, st.profs, {})
    eq(shared, 3)                                         -- Bob hasn't shared
    eq(groups[1].name, "Alchemy"); eq(groups[1].count, 2)
    eq(groups[#groups].name, "Fishing"); eq(groups[#groups].count, 1); eq(groups[#groups].secondary, true)
    eq(groups[#groups - 2].name, "Cooking"); eq(groups[#groups - 2].count, 2)
    local seen = {}
    for _, grp in ipairs(groups) do seen[grp.name] = grp.count end
    eq(seen.Mining, 0); eq(seen.Tailoring, 1); eq(#groups, 12)   -- every standard profession is listed

    local rows = P.Crafters(roster, st.profs, "Alchemy", {})
    eq(#rows, 2); eq(rows[1].name, "Zed"); eq(rows[1].level, 300); eq(rows[1].max, 300); eq(rows[1].class, "MAGE")
    eq(rows[2].name, "Cal"); eq(rows[2].max, 150)
    rows = P.Crafters(roster, st.profs, "Alchemy", { asc = true })
    eq(rows[1].name, "Cal")                               -- lowest first
    rows = P.Crafters(roster, st.profs, "First Aid", {})
    eq(#rows, 2); eq(rows[1].name, "Zed"); eq(rows[2].name, "Amy"); eq(rows[2].max, 225)
    eq(#P.Crafters(roster, st.profs, "First Aid", { online = true }), 1)
    eq(#P.Crafters(roster, st.profs, "First Aid", { filter = "am" }), 1)
    eq(#P.Crafters(roster, st.profs, "First Aid", { hideAlts = true, alts = { ["Player-1-MEM2"] = "Player-1-MEM1" } }), 1)
    eq(P.Crafters(roster, st.profs, "First Aid", { alts = { ["Player-1-MEM2"] = "Player-1-MEM1" } })[2].alt, true)
    eq(P.Groups(roster, st.profs, { online = true })[1].count, 2)
    eq(select(2, P.Groups(roster, st.profs, { online = true })), 2)
    eq(#P.Crafters(roster, st.profs, "Mining", {}), 0)
end)

test("recipes: id lists pack small and only well-formed ones unpack", function()
    local ids = { 7421, 7418, 13380, 7420, 7418 }
    local s = U.PackIDs(ids)
    eq(s, "5q2.2.1.4lj")
    local back = U.UnpackIDs(s)
    eq(#back, 4); eq(back[1], 7418); eq(back[2], 7420); eq(back[3], 7421); eq(back[4], 13380)
    local many = {}
    for i = 1, 100 do many[i] = 20000 + i * 7 end
    eq(#U.PackIDs(many) < 220, true)                     -- 100 recipes fit in one addon message
    eq(#U.UnpackIDs(U.PackIDs(many)), 100)
    for _, bad in ipairs({ "", ".", "5q2..2", ".5q2", "5q2.", "5Q2", "5q2,2", "0", "5q2.0", "zzzzzz", "zzzzz.zzzzz" }) do
        eq(U.UnpackIDs(bad), nil)
    end
    eq(U.UnpackIDs("1.1.1", 2), nil)                      -- more ids than allowed
    eq(U.UnpackIDs(12), nil)
end)

test("recipes: each player shares their own; later scans only add; a reset replaces", function()
    local Rc = ns.Recipes
    local g = newStore()
    insertAll(g, {
        author(g, "Player-1-MEM1", "RECIPES", { p = "Enchanting", ids = U.PackIDs({ 7418, 7420, 7421 }), reset = true }),
        author(g, "Player-1-MEM1", "RECIPES", { p = "Enchanting", ids = U.PackIDs({ 13380 }) }),
        author(g, "Player-1-MEM1", "RECIPES", { p = "Tailoring", ids = U.PackIDs({ 2385, 2387 }) }),
        author(g, "Player-1-MEM2", "RECIPES", { p = "Enchanting", ids = U.PackIDs({ 7418 }) }),
    })
    for _, bad in ipairs({ { p = "Enchanting", ids = "5q2..2" }, { p = "", ids = "5q2" }, { p = "Enchanting" },
        { p = "Enchanting", ids = "5q2", reset = "yes" }, { p = ("x"):rep(25), ids = "5q2" } }) do
        eq(select(2, Log.Insert(g, author(g, "Player-1-MEM1", "RECIPES", bad), true)), "payload")
    end
    local st = Red.Build(g)
    eq(Rc.Count(st, "Player-1-MEM1", "Enchanting"), 4); eq(Rc.Count(st, "Player-1-MEM1", "Tailoring"), 2)
    eq(Rc.Count(st, "Player-1-MEM2", "Enchanting"), 1); eq(Rc.Count(st, "Player-1-VET", "Enchanting"), 0)

    -- What a new scan would send.
    local have = st.recipes["Player-1-MEM1"].Enchanting
    local adds, gone = Rc.Diff({ 7418, 7420, 7421, 13380 }, have)
    eq(#adds, 0); eq(gone, false)                         -- nothing new: nothing is sent
    adds, gone = Rc.Diff({ 7418, 7420, 7421, 13380, 13419, 13419 }, have)
    eq(#adds, 1); eq(adds[1], 13419); eq(gone, false)     -- one new recipe: one id is sent
    adds, gone = Rc.Diff({ 7418, 7420 }, have)
    eq(#adds, 0); eq(gone, true)                                        -- a shared recipe is gone: replace the list
    eq(#Rc.Diff({ 5, 6 }, nil), 2)
    local parts = Rc.Chunks({ 1, 2, 3, 4, 5 }, 2)
    eq(#parts, 3); eq(#parts[3], 1); eq(parts[2][1], 3)

    insertAll(g, { author(g, "Player-1-MEM1", "RECIPES", { p = "Enchanting", ids = U.PackIDs({ 7418, 7420 }), reset = true }) })
    st = Red.Build(g)
    eq(Rc.Count(st, "Player-1-MEM1", "Enchanting"), 2); eq(Rc.Count(st, "Player-1-MEM1", "Tailoring"), 2)

    local names = { [7418] = "Enchant Bracer - Minor Health", [7420] = "Enchant Chest - Minor Health" }
    local rows = Rc.List({ [7420] = true, [7418] = true, [99] = true }, "", function(id) return names[id] end)
    eq(#rows, 3); eq(rows[1].name, "Enchant Bracer - Minor Health"); eq(rows[3].name, "Recipe 99")
    eq(#Rc.List({ [7420] = true, [7418] = true }, "chest", function(id) return names[id] end), 1)
end)

test("roster: any column sorts both ways; empty values stay at the bottom", function()
    local rows = {
        { guid = "a", name = "Zed", ri = 1, level = 60, joined = 300, lastKey = 4 },
        { guid = "b", name = "amy", ri = 3, level = 20, joined = nil, lastKey = -1 },
        { guid = "c", name = "Bob", ri = 3, level = 44, joined = 100, lastKey = nil },
        { guid = "d", name = "Cal", ri = 0, level = 44, joined = 200, lastKey = 0 },
    }
    local function order(key, desc)
        local out = {}
        for _, r in ipairs(ns.Roster.Sort(rows, key, desc)) do out[#out + 1] = r.name end
        return table.concat(out, " ")
    end
    eq(order("name", false), "amy Bob Cal Zed")           -- capitals don't matter
    eq(order("name", true), "Zed Cal Bob amy")
    eq(order("rank", false), "Cal Zed amy Bob")           -- ties go by name
    eq(order("rank", true), "amy Bob Zed Cal")
    eq(order("level", true), "Zed Bob Cal amy")
    eq(order("level", false), "amy Bob Cal Zed")
    eq(order("joined", false), "Bob Cal Zed amy")         -- no join date: last
    eq(order("joined", true), "Zed Cal Bob amy")          -- ...either way
    eq(order("last", false), "amy Cal Zed Bob")           -- online first, never seen last
    eq(order("last", true), "Zed Cal amy Bob")
end)

test("loot: charges become a history, by person and by raid night; voided ones are gone", function()
    local Loot = ns.Loot
    local g = newStore()
    insertAll(g, { author(g, "Player-1-OFFICER1", "AWARD", { to = { "Player-1-MEM1", "Player-1-MEM2", "Player-1-VET" }, amt = 500, r = "manual" }) })
    local first = Log.Build(g, "Player-1-OFFICER1", "SPEND", { from = "Player-1-MEM1", amt = 60, tier = "major", item = 1001 }, NOW)
    insertAll(g, { first })
    insertAll(g, { Log.Build(g, "Player-1-OFFICER1", "SPEND", { from = "Player-1-MEM2", amt = 30, tier = "minor", item = 1002 }, NOW + 60) })
    insertAll(g, { Log.Build(g, "Player-1-OFFICER2", "SPEND", { from = "Player-1-VET", amt = 10, tier = "off" }, NOW + 7 * 86400) })
    local mistake = Log.Build(g, "Player-1-OFFICER1", "SPEND", { from = "Player-1-VET", amt = 100, tier = "bis", item = 1003 }, NOW + 7 * 86400 + 5)
    insertAll(g, { mistake })
    insertAll(g, { author(g, "Player-1-OFFICER1", "VOID", { target = mistake.id }) })
    insertAll(g, { author(g, "Player-1-OFFICER1", "ALT_LINK", { alt = "Player-1-MEM2", main = "Player-1-MEM1" }) })
    local st = Red.Build(g)
    local all = Loot.Entries(st)
    eq(#all, 3)                                           -- the voided charge isn't history
    eq(all[1].to, "Player-1-VET"); eq(all[1].item, nil); eq(all[1].amt, 10); eq(all[1].by, "Player-1-OFFICER2")
    eq(all[3].item, 1001); eq(all[3].tier, "major")       -- newest first
    eq(#Loot.For(st, all, "Player-1-MEM1"), 2)            -- a main's loot includes the linked alt's
    eq(#Loot.For(st, all, "Player-1-MEM2"), 2)            -- and the other way round
    eq(#Loot.For(st, all, "Player-1-VET"), 1); eq(#Loot.For(st, all, "Player-1-INIT"), 0)

    local names = { ["Player-1-MEM1"] = "Zed", ["Player-1-MEM2"] = "Amy", ["Player-1-VET"] = "Bob" }
    local items = { [1001] = "Test Blade", [1002] = "Test Cloak" }
    local function who(guid) return names[guid] end
    local function what(id) return items[id] end
    local rows = Loot.Nights(all, "", who, what)
    eq(#rows, 5)                                          -- two nights: a header each, three items
    eq(rows[1].header, true); eq(rows[1].count, 1); eq(rows[1].total, 10)
    eq(rows[3].header, true); eq(rows[3].count, 2); eq(rows[3].total, 90)
    eq(rows[3].night, ns.Time.RaidDay(NOW))
    rows = Loot.Nights(all, "cloak", who, what)
    eq(#rows, 2); eq(rows[2].item, 1002)                  -- search by item
    rows = Loot.Nights(all, "bob", who, what)
    eq(#rows, 2); eq(rows[2].to, "Player-1-VET")          -- or by player
    eq(#Loot.Nights(all, "nobody", who, what), 0)
    eq(Loot.NightLabel("2026-11-07"), "Nov 7, 2026"); eq(Loot.NightLabel("soon"), "soon")
    eq(#Loot.Entries(nil), 0)
end)

test("pvp: ranks 1 to 14 have a title and a badge; each player's own report syncs", function()
    local V = ns.PvP
    eq(V.Title(1, "Horde"), "Scout"); eq(V.Title(14, "Horde"), "High Warlord"); eq(V.Title(7, "Horde"), "Blood Guard")
    eq(V.Title(1, "Alliance"), "Private"); eq(V.Title(14, "Alliance"), "Grand Marshal")
    eq(#V.TITLES.Horde, 14); eq(#V.TITLES.Alliance, 14)
    eq(V.Title(0, "Horde"), nil); eq(V.Title(15, "Horde"), nil); eq(V.Title(2.5, "Horde"), nil); eq(V.Title(nil), nil)
    eq(V.Icon(7), "Interface\\PvPRankBadges\\PvPRank07"); eq(V.Icon(14), "Interface\\PvPRankBadges\\PvPRank14"); eq(V.Icon(0), nil)
    eq(V.FromRankID(0), 0); eq(V.FromRankID(4), 0); eq(V.FromRankID(5), 1); eq(V.FromRankID(18), 14); eq(V.FromRankID(nil), nil)

    local g = newStore()
    insertAll(g, {
        author(g, "Player-1-MEM1", "PVP", { r = 3 }),
        author(g, "Player-1-MEM2", "PVP", { r = 0 }),
        author(g, "Player-1-MEM1", "PVP", { r = 4 }),
    })
    for _, bad in ipairs({ { r = 15 }, { r = -1 }, { r = 2.5 }, { r = "7" }, {} }) do
        eq(select(2, Log.Insert(g, author(g, "Player-1-MEM1", "PVP", bad), true)), "payload")
    end
    local st = Red.Build(g)
    eq(st.pvp["Player-1-MEM1"].r, 4); eq(st.pvp["Player-1-MEM2"].r, 0); eq(st.pvp["Player-1-VET"], nil)
end)

test("orders: only the right person can take each step; turnaround, late, delivered", function()
    local O = ns.Orders
    local g = newStore()
    local A, B, V, OFF = "Player-1-MEM1", "Player-1-MEM2", "Player-1-VET", "Player-1-OFFICER1"
    local function names(guid) return guid:sub(10) end
    local order = author(g, A, "ORDER", { rid = 7418, p = "Enchanting", q = 2, mats = "me", to = B, n = "for raid" })
    insertAll(g, { order })
    local id = order.id
    local function stepBy(who, data) data.id = data.id or id; insertAll(g, { author(g, who, "ORDER_ST", data) }) end
    local function one() return Red.Build(g).orders[id] end
    eq(one().status, "open"); eq(one().by, A); eq(one().to, B); eq(one().q, 2); eq(one().ask, "for raid")
    stepBy(V, { st = "accept", h = 8 })                   -- not the crafter who was asked
    stepBy(A, { st = "accept", h = 8 })                   -- can't accept your own order
    stepBy(B, { st = "ready" })                           -- not accepted yet
    eq(one().status, "open")
    stepBy(B, { st = "accept", h = 8, n = "after raid" })
    local o = one()
    eq(o.status, "accepted"); eq(o.crafter, B); eq(o.due, NOW + 8 * 3600); eq(o.note, "after raid")
    eq(select(1, O.StatusText(o, NOW + 3600, names)), "Due in 7h")
    local text, tone = O.StatusText(o, NOW + 9 * 3600, names)
    eq(text, "Late by 1h"); eq(tone, "late"); eq(O.IsLate(o, NOW + 9 * 3600), true); eq(O.IsLate(o, NOW), false)
    eq(O.Needs(Red.Build(g), B), 1); eq(O.Needs(Red.Build(g), A), 0)
    stepBy(B, { st = "deliver" })                         -- the crafter can't confirm their own delivery
    eq(one().status, "accepted")
    stepBy(B, { st = "ready" })
    eq(one().status, "ready"); eq(O.Needs(Red.Build(g), A), 1)      -- now the requester has something to collect
    stepBy(V, { st = "deliver" })
    eq(one().status, "ready")
    stepBy(A, { st = "deliver" })
    eq(one().status, "delivered"); eq(one().lastBy, A)
    stepBy(A, { st = "cancel" })                          -- finished orders don't change
    eq(one().status, "delivered")

    -- Wanted board: anyone but the requester may take it; handing back reopens it.
    local wanted = author(g, V, "ORDER", { rid = 7420, p = "Enchanting", q = 1, mats = "crafter" })
    insertAll(g, { wanted })
    stepBy(B, { id = wanted.id, st = "accept", h = 24 })
    eq(Red.Build(g).orders[wanted.id].crafter, B)
    stepBy(B, { id = wanted.id, st = "release" })
    local w = Red.Build(g).orders[wanted.id]
    eq(w.status, "open"); eq(w.crafter, nil); eq(w.due, nil)
    eq(select(2, Log.Insert(g, author(g, A, "ORDER_MOD", { id = wanted.id, st = "cancel" }), true)), "forbidden")
    insertAll(g, { author(g, OFF, "ORDER_MOD", { id = wanted.id, st = "cancel" }) })
    eq(Red.Build(g).orders[wanted.id].status, "cancelled")

    -- Asked of one crafter: declining or handing back closes it as declined.
    local d1 = author(g, A, "ORDER", { rid = 7421, p = "Enchanting", q = 1, mats = "bank", to = B })
    local d2 = author(g, A, "ORDER", { rid = 7421, p = "Enchanting", q = 1, mats = "bank", to = B })
    local selfOrder = author(g, A, "ORDER", { rid = 7421, p = "Enchanting", q = 1, mats = "me", to = A })
    insertAll(g, { d1, d2, selfOrder })
    stepBy(B, { id = d1.id, st = "decline" })
    stepBy(B, { id = d2.id, st = "accept", h = 2 })
    stepBy(B, { id = d2.id, st = "release" })
    local st = Red.Build(g)
    eq(st.orders[d1.id].status, "declined"); eq(st.orders[d2.id].status, "declined"); eq(st.orders[selfOrder.id], nil)

    for _, bad in ipairs({ { rid = 7418, p = "Enchanting", q = 0, mats = "me" }, { rid = 7418, p = "Enchanting", q = 100, mats = "me" },
        { rid = 7418, p = "Enchanting", q = 1, mats = "gold" }, { rid = 0, p = "Enchanting", q = 1, mats = "me" }, { rid = 7418, q = 1, mats = "me" } }) do
        eq(select(2, Log.Insert(g, author(g, A, "ORDER", bad), true)), "payload")
    end
    for _, bad in ipairs({ { id = id, st = "accept" }, { id = id, st = "accept", h = 5 }, { id = id, st = "ready", h = 8 },
        { id = id, st = "steal" }, { st = "ready" } }) do
        eq(select(2, Log.Insert(g, author(g, B, "ORDER_ST", bad), true)), "payload")
    end

    -- Lists and what each person may do.
    local live = author(g, A, "ORDER", { rid = 7426, p = "Enchanting", q = 1, mats = "me" })
    insertAll(g, { live })
    st = Red.Build(g)
    eq(#O.Rows(st, A, "mine"), 1); eq(#O.Rows(st, B, "craft"), 0); eq(#O.Rows(st, V, "wanted"), 1)
    eq(#O.Rows(st, A, "history"), 4); eq(O.ActiveCount(st, A), 1)
    local lo = st.orders[live.id]
    eq(O.Actions(lo, B, false, true).accept, true)        -- knows the recipe
    eq(O.Actions(lo, B, false, false).accept, nil)        -- doesn't
    eq(O.Actions(lo, A, false, true).accept, nil); eq(O.Actions(lo, A, false, true).cancel, true)
    eq(O.Actions(lo, OFF, true, false).moderate, true); eq(O.Actions(lo, V, false, false).moderate, nil)
    eq(next(O.Actions(st.orders[id], A, true, true)), nil)          -- finished: nothing to do
    eq(O.Span(90), "2m"); eq(O.Span(3 * 3600), "3h"); eq(O.Span(3 * 86400), "3d")
end)

test("orders: guild recipe lists, Wanted orders matched to crafters, cost estimates", function()
    local O, Rc = ns.Orders, ns.Recipes
    local g = newStore()
    local A, B, V = "Player-1-MEM1", "Player-1-MEM2", "Player-1-VET"
    insertAll(g, {
        author(g, B, "RECIPES", { p = "Enchanting", ids = U.PackIDs({ 7418, 7420 }) }),
        author(g, V, "RECIPES", { p = "Enchanting", ids = U.PackIDs({ 7420, 7421 }) }),
        author(g, V, "RECIPES", { p = "Tailoring", ids = U.PackIDs({ 2385 }) }),
        author(g, "Player-1-INIT", "RECIPES", { p = "Alchemy", ids = U.PackIDs({ 2329 }) }),
    })
    local wanted = author(g, A, "ORDER", { rid = 7420, p = "Enchanting", q = 1, mats = "me" })
    local other = author(g, A, "ORDER", { rid = 7421, p = "Enchanting", q = 1, mats = "me" })
    insertAll(g, { wanted, other })
    local st = Red.Build(g)
    local roster = { [A] = { name = "Amy", online = true }, [B] = { name = "Bob", online = false }, [V] = { name = "Vee", online = true } }

    local profs = Rc.GuildProfs(st, roster)                 -- the member who left (INIT) doesn't count
    eq(#profs, 2); eq(profs[1].name, "Enchanting"); eq(profs[1].count, 3); eq(profs[2].name, "Tailoring")
    local names = { [7418] = "Bracer", [7420] = "Chest", [7421] = "Rod" }
    local rows = Rc.GuildRecipes(st, roster, "Enchanting", "", function(id) return names[id] end)
    eq(#rows, 3); eq(rows[1].name, "Bracer"); eq(#rows[1].crafters, 1); eq(rows[1].online, 0)
    eq(rows[2].name, "Chest"); eq(#rows[2].crafters, 2); eq(rows[2].online, 1); eq(rows[2].crafters[1], V)   -- online first
    eq(#Rc.GuildRecipes(st, roster, "Enchanting", "ro", function(id) return names[id] end), 1)
    eq(#Rc.GuildRecipes(st, roster, "Alchemy", "", function(id) return names[id] end), 0)

    -- A Wanted order shows in To craft for every crafter who shared that recipe, and nobody else.
    eq(O.CanCraft(st, B, st.orders[wanted.id]), true); eq(O.CanCraft(st, B, st.orders[other.id]), false)
    eq(#O.Rows(st, B, "craft"), 1); eq(#O.Rows(st, V, "craft"), 2); eq(#O.Rows(st, A, "craft"), 0)
    eq(O.Needs(st, B), 1); eq(O.Needs(st, V), 2); eq(O.Needs(st, A), 0)
    eq(O.Matches(st, A, st.orders[wanted.id]), false)       -- never your own

    eq(O.Money(0), "0c"); eq(O.Money(45), "45c"); eq(O.Money(300), "3s"); eq(O.Money(15925), "1g 59s"); eq(O.Money(120000), "12g")
    eq(O.Money(1259), "12s 59c")
    local prices = { [10] = 150, [11] = 2000 }
    local function priceOf(item) return prices[item] end
    local total, missing, all = O.Estimate({ { item = 10, n = 1 }, { item = 11, n = 3 }, { item = 12, n = 2 } }, 2, priceOf)
    eq(total, (150 + 6000) * 2); eq(missing, 1); eq(all, 3)
    eq(select(1, O.Estimate(nil, 1, priceOf)), 0)
end)

test("mail: which stacks to attach, and what the letter says", function()
    local M = ns.Mail
    local function bags(...)
        local list = {}
        for i, n in ipairs({ ... }) do list[i] = { bag = 0, slot = i, count = n } end
        return list
    end
    local function counts(picks)
        local out = {}
        for i, s in ipairs(picks) do out[i] = s.count end
        return table.concat(out, ",")
    end
    local picks, total = M.Plan(bags(1, 1, 1, 1), 3)
    eq(total, 3); eq(#picks, 3)                                   -- single items, only as many as owed
    picks, total = M.Plan(bags(20, 5), 5)
    eq(total, 5); eq(counts(picks), "5")                          -- the exact stack, not the big one
    picks, total = M.Plan(bags(5, 4, 4), 8)
    eq(total, 8); eq(counts(picks), "4,4")                        -- exact beats biggest-first
    picks, total = M.Plan(bags(20, 5), 7)
    eq(total, 5); eq(counts(picks), "5")                          -- never over: 2 are left for a hand split
    picks, total = M.Plan(bags(20), 7)
    eq(total, 0); eq(#picks, 0)                                   -- a stack is never split
    picks, total = M.Plan(bags(10, 5, 5), 20)
    eq(total, 20); eq(#picks, 3)
    picks, total = M.Plan(bags(1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1), 15)
    eq(total, 12); eq(#picks, 12)                                 -- one mail carries 12 attachments
    picks, total = M.Plan(bags(5, 1, 1, 1), 6, 2)
    eq(total, 6); eq(#picks, 2)                                   -- fewest slots first
    eq(select(2, M.Plan({}, 4)), 0); eq(select(2, M.Plan(bags(3), 0)), 0)

    local st = { orders = {
        a = { id = "a", crafter = "X", status = "accepted", t = 5, due = 90, q = 1 },
        b = { id = "b", crafter = "X", status = "ready", t = 1, due = 50, q = 2 },
        c = { id = "c", crafter = "Y", status = "accepted", t = 2, due = 10, q = 1 },   -- someone else's
        d = { id = "d", crafter = "X", status = "delivered", t = 3, due = 20, q = 1 },  -- finished
        e = { id = "e", to = "X", status = "open", t = 4, q = 1 },                      -- not accepted yet
    } }
    local rows = M.Orders(st, "X")
    eq(#rows, 2); eq(rows[1].id, "b"); eq(rows[2].id, "a")        -- soonest due first
    eq(#M.Orders(nil, "X"), 0)

    eq(M.Subject("Runed Copper Rod", 1), "Runed Copper Rod")      -- the item is the subject
    eq(M.Subject("Elixir of Minor Defense", 5), "Elixir of Minor Defense x5")
    eq(#M.Subject(("long "):rep(40), 3), M.SUBJECT_MAX)
    local body = M.Body("Runed Copper Rod", 3, 3, "Binky Bee")
    eq(body, "Blood Pact order: here is your Runed Copper Rod x3, made by Binky Bee. When you have it, type /bp, open Professions > Orders and press \"I received it\".")
    eq(M.Body("Rod", 12, 15, "Bee"):find("That is 12 of the 15 still owed; the rest will follow.", 1, true) ~= nil, true)
    eq(#M.Body(("long "):rep(200), 1, 1, "Bee") <= M.BODY_MAX, true)
end)

test("orders: mailed items make an order In transit until it is confirmed", function()
    local g = newStore()
    local A, B, V = "Player-1-MEM1", "Player-1-VET", "Player-1-MEM2"
    local O = ns.Orders
    local order = author(g, A, "ORDER", { rid = 7421, p = "Enchanting", q = 3, mats = "crafter" })
    insertAll(g, { order })
    local id = order.id
    local function nameOf() return "someone" end
    -- Nobody is crafting it yet, so a mail report counts for nothing.
    insertAll(g, { author(g, B, "ORDER_MAIL", { id = id, n = 3 }) })
    eq(Red.Build(g).orders[id].mailed, nil)
    insertAll(g, { author(g, B, "ORDER_ST", { id = id, st = "accept", h = 24 }) })
    insertAll(g, { author(g, V, "ORDER_MAIL", { id = id, n = 3 }) })          -- not the crafter
    insertAll(g, { author(g, A, "ORDER_MAIL", { id = id, n = 3 }) })          -- nor the requester
    local o = Red.Build(g).orders[id]
    eq(o.mailed, nil); eq(O.InTransit(o), false)
    insertAll(g, { author(g, B, "ORDER_MAIL", { id = id, n = 2 }) })          -- part of it
    o = Red.Build(g).orders[id]
    eq(o.mailed, 2); eq(O.InTransit(o), false); eq(ns.Mail.Left(o), 1)
    eq(O.StatusText(o, o.t, nameOf):find(", 2 of 3 mailed", 1, true) ~= nil, true)
    insertAll(g, { author(g, B, "ORDER_MAIL", { id = id, n = 5 }) })          -- never more than was ordered
    local st = Red.Build(g)
    o = st.orders[id]
    eq(o.mailed, 3); eq(O.InTransit(o), true); eq(ns.Mail.Left(o), 0)
    local text, tone = O.StatusText(o, o.due + 99999, nameOf)                 -- in the mail is never "late"
    eq(text:sub(1, 18), "In transit, mailed"); eq(tone, "transit"); eq(O.IsLate(o, o.due + 99999), false)
    eq(O.Needs(st, B), 0); eq(O.Needs(st, A), 1)                              -- now it waits on the requester
    eq(#O.Rows(st, B, "craft"), 1)
    -- Marked ready as well: still In transit.
    insertAll(g, { author(g, B, "ORDER_ST", { id = id, st = "ready", n = "In your mailbox" }) })
    o = Red.Build(g).orders[id]
    eq(o.status, "ready"); eq(O.InTransit(o), true)
    -- Confirmed: complete, and no longer in transit.
    insertAll(g, { author(g, A, "ORDER_ST", { id = id, st = "deliver" }) })
    o = Red.Build(g).orders[id]
    eq(o.status, "delivered"); eq(O.InTransit(o), false)
    eq(O.StatusText(o, o.t, nameOf):sub(1, 9), "Delivered")
    insertAll(g, { author(g, B, "ORDER_MAIL", { id = id, n = 1 }) })          -- nothing changes after that
    eq(Red.Build(g).orders[id].mailed, 3)

    -- Handing a part-mailed order back clears the count for the next crafter.
    local g2 = newStore()
    local second = author(g2, A, "ORDER", { rid = 7421, p = "Enchanting", q = 2, mats = "crafter" })
    insertAll(g2, { second })
    insertAll(g2, { author(g2, B, "ORDER_ST", { id = second.id, st = "accept", h = 2 }) })
    insertAll(g2, { author(g2, B, "ORDER_MAIL", { id = second.id, n = 1 }) })
    insertAll(g2, { author(g2, B, "ORDER_ST", { id = second.id, st = "release" }) })
    o = Red.Build(g2).orders[second.id]
    eq(o.status, "open"); eq(o.mailed, nil)

    for _, bad in ipairs({ { id = id }, { id = id, n = 0 }, { id = id, n = 100 }, { id = id, n = 1.5 }, { n = 1 } }) do
        eq(select(2, Log.Insert(g, author(g, B, "ORDER_MAIL", bad), true)), "payload")
    end
end)

test("summon queue: the keyword, one place per name, and group units", function()
    local Q = ns.SummonQueue
    for _, yes in ipairs({ "123", " 123 ", "123 please", "123!", "123 pls ty", "123, at the stone" }) do
        eq(Q.Matches(yes, "123"), true, yes)
    end
    for _, no in ipairs({ "1234", "12", "need 123", "0123", "", "123 is what you type when you want a summon", "sum" }) do
        eq(Q.Matches(no, "123"), false, no)
    end
    eq(Q.Matches("SUM", "sum"), true); eq(Q.Matches("summon", "sum"), false); eq(Q.Matches(nil, "123"), false)
    eq(Q.Matches("123", ""), false)
    eq(Q.CleanKey(" Sum "), "sum"); eq(Q.CleanKey("two words"), nil); eq(Q.CleanKey(""), nil)
    eq(Q.CleanKey(("x"):rep(13)), nil); eq(Q.CleanKey(42), nil)

    local list = {}
    local a, new = Q.Add(list, "Pip", "G-PIP", 100, "raid")
    eq(new, true); eq(a.name, "Pip")
    eq(select(2, Q.Add(list, "Pip", "G-PIP", 130, "raid")), false)          -- asking twice is one place
    eq(select(2, Q.Add(list, "pip", nil, 130, "whisper")), false)           -- same name, no id given
    eq(select(2, Q.Add(list, "Vela", nil, 140, "whisper")), true)
    eq(select(2, Q.Add(list, "Grim Tusk", "G-GRIM", 150, "party")), true)   -- names can have spaces
    eq(#list, 3); eq(list[1].name, "Pip"); eq(list[3].name, "Grim Tusk")   -- first come, first served

    Q.Assign(list, { { unit = "raid4", guid = "G-PIP", name = "Pip" }, { unit = "raid9", guid = "G-VELA", name = "Vela" } })
    eq(list[1].unit, "raid4"); eq(list[2].unit, "raid9"); eq(list[2].guid, "G-VELA"); eq(list[3].unit, nil)
    Q.Assign(list, {})                                                      -- they left the group
    eq(list[1].unit, nil)

    eq(Q.Prune(list, 100 + Q.TTL + 1), 1); eq(#list, 2); eq(list[1].name, "Vela")
    eq(Q.Remove(list, list[1]), true); eq(Q.Remove(list, {}), false); eq(#list, 1)
end)

test("recruit: starting zones by region, level bands, unguilded only", function()
    local Rc = ns.Recruit
    local function zones(faction)
        local out = {}
        for _, g in ipairs(Rc.Regions(faction)) do out[#out + 1] = g.region .. "=" .. table.concat(g.zones, "+") end
        return table.concat(out, " | ")
    end
    eq(zones("Horde"), "Kalimdor=Durotar+Mulgore | Eastern Kingdoms=Tirisfal Glades | Skyborne=Zephras Isle")
    eq(zones("Alliance"), "Kalimdor=Teldrassil | Eastern Kingdoms=Elwynn Forest+Dun Morogh | Skyborne=Zephras Isle")
    eq(zones(nil), zones("Horde"))
    local all = {}                                           -- seven starting zones in all
    for _, f in ipairs({ "Horde", "Alliance" }) do
        for _, g in ipairs(Rc.Regions(f)) do for _, z in ipairs(g.zones) do all[z] = true end end
    end
    local n = 0
    for _ in pairs(all) do n = n + 1 end
    eq(n, 7)

    eq(Rc.Query("Durotar"), 'z-"Durotar"'); eq(Rc.Query("Tirisfal Glades", { 5, 8 }), 'z-"Tirisfal Glades" 5-8')
    eq(Rc.NextBand(nil, nil, "Durotar"), 1); eq(Rc.NextBand("Durotar", 1, "Durotar"), 2)
    eq(Rc.NextBand("Durotar", #Rc.BANDS, "Durotar"), 1)      -- after the last band, start over
    eq(Rc.NextBand("Durotar", 2, "Mulgore"), 1)              -- a new zone starts at the first band
    eq(Rc.BANDS[1][1], 1); eq(Rc.BANDS[#Rc.BANDS][2], 12)    -- level 1 to 12, no gaps
    for i = 2, #Rc.BANDS do eq(Rc.BANDS[i][1], Rc.BANDS[i - 1][2] + 1) end

    local list = {}
    eq(Rc.Merge(list, { { name = "A", guild = "" }, { name = "B", guild = "Some Guild" }, { name = "C" }, { guild = "" } }), 2)
    eq(Rc.Merge(list, { { name = "A" }, { name = "D", level = 7, class = "Mage", area = "Durotar" } }), 1)
    eq(#list, 3); eq(list[1].name, "A"); eq(list[2].name, "C"); eq(list[3].level, 7)
end)

test("raid: a sign-up asks for a spot; a Team Captain or above selects who gets one", function()
    local g = newStore()
    local Rd = ns.Raids
    local r = author(g, "Player-1-CAPT", "RAID", { title = "BD", raid = "Barrow Deeps", at = NOW + 3600, size = 5 })
    insertAll(g, { r })
    local A, B, V, I = "Player-1-MEM1", "Player-1-MEM2", "Player-1-VET", "Player-1-INIT"
    insertAll(g, {
        author(g, A, "SIGNUP", { ev = r.id, st = "yes", role = "tank" }),
        author(g, B, "SIGNUP", { ev = r.id, st = "yes", role = "healer" }),
        author(g, V, "SIGNUP", { ev = r.id, st = "maybe", role = "dps" }),
        author(g, I, "SIGNUP", { ev = r.id, st = "no" }),
    })
    local st = Red.Build(g)
    local raid = st.raids[r.id]
    local c = Rd.Summary(st, raid)
    eq(c.yes, 2); eq(c.picked, 0); eq(c.waiting, 2); eq(c.sel.tank, 0)        -- nobody holds a spot yet
    eq(Rd.CanPick(raid, A, true, NOW), true)
    eq(Rd.CanPick(raid, V, true, NOW), true)                                 -- a Maybe can be selected
    eq(select(2, Rd.CanPick(raid, I, true, NOW)), "They haven't signed up for this raid.")
    eq(select(2, Rd.CanPick(raid, "Player-1-GM", true, NOW)), "They haven't signed up for this raid.")
    eq(select(2, Rd.CanPick(raid, A, false, NOW)), "They aren't selected.")
    eq(select(2, Rd.CanPick(nil, A, true, NOW)), "That raid is gone.")
    eq(select(2, Rd.CanPick(raid, A, true, NOW + 3600 + 7 * 3600)), "That raid is over.")

    -- A Member can't select; a Team Captain can.
    eq(select(2, Log.Insert(g, author(g, A, "RAID_PICK", { ev = r.id, who = A, on = true }), true)), "forbidden")
    insertAll(g, { author(g, "Player-1-CAPT", "RAID_PICK", { ev = r.id, who = A, on = true }) })
    insertAll(g, { author(g, "Player-1-OFFICER1", "RAID_PICK", { ev = r.id, who = V, on = true }) })
    st = Red.Build(g); raid = st.raids[r.id]
    local rows
    c, rows = Rd.Summary(st, raid)
    eq(c.picked, 2); eq(c.waiting, 1); eq(c.sel.tank, 1); eq(c.sel.dps, 1); eq(c.sel.healer, 0)
    eq(rows[1].picked, true); eq(rows[2].picked, true); eq(rows[3].guid, B); eq(rows[3].picked, false)   -- selected first
    eq(Rd.IsPicked(raid, A), true); eq(Rd.IsPicked(raid, B), false)
    eq(select(2, Rd.CanPick(raid, A, true, NOW)), "They are already selected.")

    -- Reminders go to the selected once the raid has been selected.
    eq(#Rd.DueReminders(st, A, NOW + 1800, {}), 1); eq(#Rd.DueReminders(st, B, NOW + 1800, {}), 0)

    -- Answering "Can't" gives the spot back; unselecting does too.
    insertAll(g, { author(g, A, "SIGNUP", { ev = r.id, st = "no" }) })
    insertAll(g, { author(g, "Player-1-CAPT", "RAID_PICK", { ev = r.id, who = V, on = false }) })
    st = Red.Build(g); raid = st.raids[r.id]
    c = Rd.Summary(st, raid)
    eq(c.picked, 0); eq(Rd.IsPicked(raid, A), false); eq(Rd.IsPicked(raid, V), false); eq(Rd.PickedCount(raid), 0)
    eq(#Rd.DueReminders(st, B, NOW + 1800, {}), 1)                           -- nobody selected: everyone signed up again

    -- A full raid takes no more.
    local g2 = newStore()
    local small = author(g2, "Player-1-CAPT", "RAID", { title = "BD", raid = "Barrow Deeps", at = NOW + 3600, size = 5 })
    insertAll(g2, { small })
    local five = { "Player-1-GM", "Player-1-OFFICER1", "Player-1-OFFICER2", "Player-1-CAPT", "Player-1-VET" }
    for _, who in ipairs(five) do
        insertAll(g2, { author(g2, who, "SIGNUP", { ev = small.id, st = "yes", role = "dps" }) })
        insertAll(g2, { author(g2, "Player-1-CAPT", "RAID_PICK", { ev = small.id, who = who, on = true }) })
    end
    insertAll(g2, { author(g2, A, "SIGNUP", { ev = small.id, st = "yes", role = "dps" }) })
    st = Red.Build(g2)
    eq(Rd.PickedCount(st.raids[small.id]), 5)
    eq(select(2, Rd.CanPick(st.raids[small.id], A, true, NOW)), "All 5 spots are taken. Unselect someone first.")
    eq(Rd.CanPick(st.raids[small.id], "Player-1-VET", false, NOW), true)

    for _, bad in ipairs({ { ev = r.id, who = A }, { ev = r.id, on = true }, { who = A, on = true }, { ev = r.id, who = A, on = "yes" } }) do
        eq(select(2, Log.Insert(g, author(g, "Player-1-CAPT", "RAID_PICK", bad), true)), "payload")
    end
end)

test("summon: the whisper that asks a group leader to invite", function()
    local S = ns.Summon
    eq(S.SuggestText({ "Vela" }), "Could you invite Vela to the group? I'm summoning. (sent with Blood Pact)")
    eq(S.SuggestText({ "Vela", "Pip", "Grim Tusk" }), "Could you invite Vela, Pip, Grim Tusk to the group? I'm summoning. (sent with Blood Pact)")
    eq(#S.SuggestText({ ("x"):rep(120), ("y"):rep(120), ("z"):rep(120) }) <= 255, true)
end)

test("summon messages: who is called out, and long whispers cut to fit", function()
    local C = ns.SummonCall
    eq(C.Names({}), "all"); eq(C.Names({ "Solo" }), "Solo"); eq(C.Names({ "Solo", "Holly" }), "Solo & Holly")
    eq(C.Names({ "A", "B", "C" }), "A, B & C"); eq(C.Names({ "A", "B", "C", "D", "E" }), "A, B & C")   -- three at most
    eq(C.Callout(C.DEFAULT_CALL, { "Solo", "Holly" }), "Yo! Click the purple oval! I see you Solo & Holly doing nothing!")
    eq(C.Callout(C.DEFAULT_CALL, {}), "Yo! Click the purple oval! I see you all doing nothing!")
    eq(C.Callout("No placeholder here", { "Solo" }), "No placeholder here")
    eq(C.Callout("{names}: %s and %d stay as typed", { "Solo" }), "Solo: %s and %d stay as typed")
    eq(#C.Callout(("x"):rep(400), {}), 255)

    local idle, clicking = C.Idle({
        { name = "Solo", near = true, clicking = false },
        { name = "Holly", near = true, clicking = false },
        { name = "Clicker", near = true, clicking = true },
        { name = "Far Away", near = false, clicking = false },
        { name = "Summoned", near = true, clicking = false, summoned = true },
    })
    eq(table.concat(idle, ","), "Holly,Solo"); eq(clicking, 1)        -- near, not clicking, not the one being summoned

    local parts = C.Split(C.DEFAULT_TELL)
    eq(#parts, 2)
    eq(parts[1], "Abra-cadabra-fel-o-rama, bibbidi-bobbidi-doom, get your pixelated posterior out of the tavern and into this room!")
    eq(parts[2]:sub(1, 18), "Shazam-a-ling-ding"); eq(parts[2]:sub(-17), "angry elite mobs!")
    for _, part in ipairs(parts) do eq(#part <= 255, true) end
    eq(#C.Split("short"), 1); eq(#C.Split(""), 0)
    local long = C.Split(("word "):rep(120))                          -- no sentence end: cut at a space
    eq(#long, 3); eq(long[1]:sub(-4), "word"); eq(#long[1] <= 255, true)
    eq(#C.Split(("x"):rep(600)), 3)                                   -- no spaces at all: cut anyway
end)

test("recruit: who is asking for an invite", function()
    local Rc = ns.Recruit
    for _, yes in ipairs({ "inv", "Inv", " INV ", "invite", "inv pls", "Invite me!", "inv?", "inv please ty" }) do
        eq(Rc.IsInviteReply(yes), true, yes)
    end
    for _, no in ipairs({ "", "no thanks", "invest in gold", "what guild", "can I get an inv", "inventory full", "1nv", "inv" .. (" please"):rep(6) }) do
        eq(Rc.IsInviteReply(no), false, no)
    end
    eq(Rc.IsInviteReply(nil), false)

    local list = {}
    local a, new = Rc.AddReply(list, "Moldy L\195\182cks", "inv", 100)
    eq(new, true); eq(a.name, "Moldy L\195\182cks")                 -- the name is kept byte for byte
    eq(select(2, Rc.AddReply(list, "Moldy L\195\182cks", "inv", 130)), false)
    Rc.AddReply(list, "Second", "invite", 140)
    eq(#list, 2); eq(list[1].name, "Second")                        -- newest first
    for i = 1, Rc.MAX_REPLIES + 5 do Rc.AddReply(list, "P" .. i, "inv", 200 + i) end
    eq(#list, Rc.MAX_REPLIES)
end)

test("roster: classes counted, sliced for the pie, sorted and messaged", function()
    local Ro = ns.Roster
    eq(Ro.ClassLabel("WARLOCK"), "Warlock"); eq(Ro.ClassLabel("MAGE", "Magier"), "Magier"); eq(Ro.ClassLabel(nil), "Unknown")
    local roster = {
        a = { class = "MAGE", classLabel = "Mage", online = true }, b = { class = "MAGE", online = false },
        c = { class = "MAGE", online = true }, d = { class = "WARLOCK", online = true },
        e = { class = "ROGUE", online = false }, f = { online = true },
    }
    local counts, total = Ro.ClassCounts(roster, false)
    eq(total, 6); eq(#counts, 4)
    eq(counts[1].class, "MAGE"); eq(counts[1].n, 3); eq(counts[1].pct, 50); eq(counts[1].label, "Mage")
    eq(counts[2].label, "Rogue"); eq(counts[3].label, "Unknown"); eq(counts[4].label, "Warlock")   -- ties by name
    counts, total = Ro.ClassCounts(roster, true)                       -- online only
    eq(total, 4); eq(counts[1].n, 2); eq(#counts, 3)
    eq(select(2, Ro.ClassCounts({}, false)), 0)

    -- The pie: every wedge has a class, in the legend's order, in proportion.
    counts, total = Ro.ClassCounts(roster, false)
    local slices = Ro.Slices(counts, total, 120)
    eq(#slices, 120); eq(slices[1], "MAGE"); eq(slices[60], "MAGE"); eq(slices[61], "ROGUE"); eq(slices[120], "WARLOCK")
    local n = {}
    for _, c in ipairs(slices) do n[c] = (n[c] or 0) + 1 end
    eq(n.MAGE, 60); eq(n.ROGUE, 20); eq(n.UNKNOWN, 20); eq(n.WARLOCK, 20)
    local tiny = Ro.Slices({ { class = "A", n = 999 }, { class = "B", n = 1 } }, 1000, 120)
    eq(#tiny, 120); eq(tiny[120], "B")                                 -- one member in a thousand still shows
    eq(#Ro.Slices({}, 0, 120), 0)

    local rows = { { guid = "1", name = "Zed", classLabel = "Mage" }, { guid = "2", name = "Amy", classLabel = "Warlock" },
        { guid = "3", name = "Bob", classLabel = "Mage" } }
    local order = {}
    for i, r in ipairs(Ro.Sort(rows, "class", false)) do order[i] = r.name end
    eq(table.concat(order, ","), "Bob,Zed,Amy")                         -- by class, then by name

    local names = Ro.Audience(rows, { ["1"] = true, ["2"] = true }, "2", 40)
    eq(table.concat(names, ","), "Zed")                                 -- online, and never yourself
    eq(#Ro.Audience(rows, { ["1"] = true, ["2"] = true, ["3"] = true }, "x", 2), 2)   -- capped
end)

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
