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
ns.UI = { AddTab = function() end }
ns.W = {}
load("Modules/BiSData.lua")
load("Modules/BiS.lua")
ns.DKP = { GroupGUIDs = function() return {} end }
load("Modules/Raids.lua")

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

test("bis data: every slot has a BiS at score 1 and scores fall", function()
    local list = ns.BiSData.WARLOCK.Demonology
    eq(#list.slots, 17)
    for _, s in ipairs(list.slots) do
        eq(s.items[1].score, 1, s.slot)
        for i = 2, #s.items do
            assert(s.items[i].score <= s.items[i - 1].score, s.slot .. " scores not in order")
            assert(s.items[i].how ~= "", s.slot .. " missing how-to-get")
        end
    end
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

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
