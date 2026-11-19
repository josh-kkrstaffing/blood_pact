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
load("Modules/Officer.lua")
ns.Char = function() return {} end
load("Modules/Professions.lua")
ns.Listen = function() end
load("Modules/Roster.lua")
ns.Sync = { Handle = function() end }
load("Modules/Summon.lua")

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
    local one = P.Classify({ { name = "Herbalism", level = 240 }, { name = "Cooking", level = 12 } })   -- known by name
    eq(one.p1, "Herbalism"); eq(one.p2, nil); eq(one.ck, 12); eq(one.fa, nil)
    eq(P.Same(rec, P.Classify({ { name = "Enchanting", level = 275 }, { name = "Tailoring", level = 300 },
        { name = "First Aid", level = 225 }, { name = "Cooking", level = 150 }, { name = "Fishing", level = 1 } })), true)
    eq(P.Same(rec, one), false)
    eq(P.Label("Tailoring", 300), "Tailoring 300"); eq(P.Label(nil), "-")
end)

test("professions: each player's own report syncs; rows filter and sort", function()
    local P = ns.Professions
    local g = newStore()
    insertAll(g, {
        author(g, "Player-1-MEM1", "PROF", { p1 = "Alchemy", l1 = 275, p2 = "Herbalism", l2 = 300, fa = 300, ck = 300, fi = 10 }),
        author(g, "Player-1-MEM2", "PROF", { p1 = "Tailoring", l1 = 300, fa = 150 }),
        author(g, "Player-1-MEM1", "PROF", { p1 = "Alchemy", l1 = 300, p2 = "Herbalism", l2 = 300, fa = 300, ck = 300, fi = 10 }),
    })
    eq(select(2, Log.Insert(g, author(g, "Player-1-MEM1", "PROF", { p1 = "Alchemy", l1 = 9999 }), true)), "payload")
    local st = Red.Build(g)
    eq(st.profs["Player-1-MEM1"].l1, 300)                 -- the newer report stands
    local roster = { ["Player-1-MEM1"] = { name = "Zed" }, ["Player-1-MEM2"] = { name = "Amy" }, ["Player-1-VET"] = { name = "Bob" } }
    local rows = P.Rows(roster, st.profs, "", "name")
    eq(#rows, 3); eq(rows[1].name, "Amy"); eq(rows[2].name, "Zed"); eq(rows[3].name, "Bob")   -- not shared yet: last
    rows = P.Rows(roster, st.profs, "", "ck")
    eq(rows[1].name, "Zed")                               -- highest Cooking first
    rows = P.Rows(roster, st.profs, "tailor", "name")
    eq(#rows, 1); eq(rows[1].name, "Amy")                 -- search by profession
end)

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
