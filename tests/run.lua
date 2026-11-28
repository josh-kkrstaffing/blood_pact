-- Blind Tiger unit tests for the pure-Lua core (no game client needed).
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
    chunk("BlindTiger", ns)
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
load("Modules/Shop.lua")
load("Modules/Market.lua")
load("Modules/Kit.lua")
load("Modules/Caller.lua")
ns.Listen = function() end
load("Modules/Advert.lua")
load("Modules/Statics.lua")
load("Modules/Roster.lua")
ns.Sync = { Handle = function() end }
load("Modules/Drinks.lua")
load("Modules/Chips.lua")
load("Modules/Cards.lua")
load("Modules/Casino.lua")
load("Modules/Party.lua")
load("Modules/MiniButton.lua")
load("Modules/Summon.lua")
load("Modules/Recruit.lua")
load("Modules/SummonQueue.lua")
load("Modules/Tickets.lua")
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

test("bis data: 24 lists name their Wowhead author, 4 older lists say why", function()
    local named, old = 0, 0
    for _, lists in pairs(ns.BiSData) do
        for _, list in pairs(lists) do
            if list.old then
                old = old + 1
                assert(ns.BiS.SourceText(list):find("older auto%-ranked list"), "old list is flagged")
            else
                named = named + 1
                assert(list.by and list.asof and list.url:find("wowhead.com/forever/guide", 1, true), "source fields")
                assert(ns.BiS.SourceText(list):find(list.by, 1, true), "title names the author")
            end
        end
    end
    eq(named, 24); eq(old, 4)
    local aff = ns.BiSData.WARLOCK.Affliction
    eq(aff.by, "Zephan")
    eq(aff.slots[2].items[1].name, "Dark Advisor's Pendant")   -- shadow damage neck leads for Affliction
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
        ["Master's Hat of Shadow Wrath"] = "bags",   -- head alt under its other accepted suffix, not worn
        ["Rune Band of Wizardry"] = "equipped",      -- ring 1 BiS
    }
    local rows = ns.BiS.Evaluate(list, owned)
    local by = {}
    for _, r in ipairs(rows) do by[r.slot] = r end
    eq(by.Chest.gap, 0)
    eq(by.Head.have.name, "Master's Hat of Magic"); eq(by.Head.where, "bags")
    eq(by.Head.alt.name, "Crimson Felt Hat")    -- nearest better item
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

test("orders: recipe sort by craft, cost, buy and net; blanks last either way", function()
    local nums = { [1] = { 500, false, 800, 300, 40 }, [2] = { 200, false, 100, -100, 90 }, [3] = { 900, true, 950, nil, nil }, [4] = {} }
    local function numbers(id) local n = nums[id]; return n[1], n[2], n[3], n[4], n[5] end
    local function order(key, desc)
        local list = { { id = 1, name = "Copper Rod" }, { id = 2, name = "Anvil" }, { id = 3, name = "Belt" }, { id = 4, name = "Zed" } }
        ns.Orders.SortRecipes(list, key, desc, numbers)
        local s = ""
        for _, r in ipairs(list) do s = s .. r.id end
        return s
    end
    eq(order("name", false), "2314"); eq(order("name", true), "4132")
    eq(order("cost", false), "2134"); eq(order("cost", true), "3124")
    eq(order("buy", true), "3124")
    eq(order("net", true), "1234")     -- best profit first; no number sinks, by name
    eq(order("net", false), "2134")
    eq(order("vendor", true), "2134"); eq(order("vendor", false), "1234")
end)

-- Raid Caller ---------------------------------------------------------------
test("caller: what is said, when, in what order, and to whom", function()
    local C = ns.Caller
    eq(C.Speech({ what = "swap", who = "tanks" }), "Tanks. Tank swap")
    eq(C.Speech({ what = "move", who = "all", mark = "green" }), "Move to green")
    eq(C.Speech({ what = "move", who = "all" }), "Move to the marker")
    eq(C.Speech({ what = "spread", who = "healers", mark = "red" }), "Healers. Spread out, red marker")
    eq(C.Speech({ text = "Hug the north wall", who = "all" }), "Hug the north wall")
    eq(C.When({ when = "time", v = 95 }), "1:35"); eq(C.When({ when = "hp", v = 65 }), "At 65%")
    eq(C.When({ when = "stack", v = 1 }), "At 1 stack"); eq(C.When({ when = "phase", v = 2 }), "Phase 2"); eq(C.When({ when = "call" }), "On call")
    local plan = { a = { when = "hp", v = 40 }, b = { when = "time", v = 30 }, c = { when = "hp", v = 65 }, d = { when = "call" },
        e = { when = "time", v = 5 }, f = { when = "stack", v = 5 }, g = { when = "phase", v = 2 } }
    local timed, list = C.Split(plan)
    eq(timed[1].id, "e"); eq(timed[2].id, "b")
    eq(list[1].id, "c"); eq(list[2].id, "a"); eq(list[3].id, "g"); eq(list[4].id, "f"); eq(list[5].id, "d")
    eq(#C.Rows(plan), 7); eq(C.Rows(plan)[1].id, "e")
    eq(C.ForMe({ who = "all" }, "caster"), true); eq(C.ForMe({ who = "tanks" }, "tank"), true); eq(C.ForMe({ who = "tanks" }, "healer"), false)
    eq(C.ForMe({ who = "healers" }, "healer"), true); eq(C.ForMe({ who = "dps" }, "agi"), true); eq(C.ForMe({ who = "dps" }, "tank"), false)
    local st = { calls = { ["Onyxia"] = plan, ["Azgalor"] = {} } }
    eq(C.Match(st, "ONYXIA"), "Onyxia"); eq(C.Match(st, "Rage Winterchill"), nil); eq(C.Match(st, nil), nil)
    eq(C.Bosses(st)[1], "Azgalor")
    for _, g in ipairs(C.GROUPS) do
        for _, i in ipairs(g.items) do assert(#i[1] <= 16 and C.PHRASE[i[1]] == i[2]) end
    end
end)

-- Party button ---------------------------------------------------------------
test("party: the sound board, who may press, and the rotation", function()
    local P = ns.Party
    eq(P.Clean("  Take   a drink!  "), "Take a drink!"); eq(P.Clean(""), nil); eq(P.Clean("   "), nil)
    eq(P.Clean("a|cffff0000b|r"), "acffff0000br")                    -- no colour codes or links in a raid warning
    eq(P.Clean(string.rep("x", 61)), nil); eq(#P.Clean(string.rep("x", 60)), 60)
    local lines = P.Lines(nil)
    eq(#lines, #P.DEFAULT); eq(lines[1], "Take a drink!")
    lines = P.Lines({ partyLines = { ["Take a puff!"] = { on = false, t = 5 }, ["For the Horde!"] = { on = true, t = 9 },
        ["Wipe it up!"] = { on = true, t = 7 }, ["Gone"] = { on = false, t = 8 } } })
    eq(table.concat(lines, "|"), "Take a drink!|Take a shot!|Bottoms up!|Cheers, Blind Tiger!|Holler and swaller!|Wipe it up!|For the Horde!")
    eq(P.After(lines, nil), "Take a drink!"); eq(P.After(lines, "Take a drink!"), "Take a shot!")
    eq(P.After(lines, "For the Horde!"), "Take a drink!"); eq(P.After(lines, "not on the list"), "Take a drink!"); eq(P.After({}, "x"), nil)
    eq(P.CanPress(true, true, 99), true)
    eq(select(2, P.CanPress(false, true, 99)), "Join a raid or party first.")
    eq(select(2, P.CanPress(true, false, 99)), "Only the raid leader and assists can press Party, the same as /rw. In a party, the party leader.")
    eq(select(2, P.CanPress(true, true, 3.2)), "Give it 7 more seconds.")
    eq(P.WordLine("murloc"), "The word of the night is: murloc")
    assert(P.Said("Wind", "Wind") and P.Said("oh no, WIND!", "wind") and P.Said("the wind is up", "Wind") and P.Said("wind", "wind"))
    assert(not P.Said("window", "wind") and not P.Said("rewind it", "wind") and not P.Said("", "wind") and not P.Said("wind", ""))
    assert(P.Said("that was my bad, sorry", "My Bad") and not P.Said("my badge", "my bad") and not P.Said(nil, "wind"))
    eq(P.Caught("Whyley", "Wind", "Take a shot!"), "Whyley said Wind. Take a shot!")
    eq(P.Caught(nil, "Wind", "Take a shot!"), "Take a shot!")
    eq(P.Caught(string.rep("n", 40), "Wind", "Cheers, Blind Tiger!"), "Cheers, Blind Tiger!")     -- too long for a raid warning: the line alone
    for _, line in ipairs(P.DEFAULT) do assert(P.Clean(line) == line) end
    local ok = ns.Log.KINDS and ns.Log.KINDS.PARTY_LINE
    if ok then assert(ok[2]({ text = "Hi", on = true }) and not ok[2]({ text = "", on = true }) and not ok[2]({ text = "Hi" })) end
end)

-- Guild chips -----------------------------------------------------------------
test("chips: amounts, the money log match, and balances", function()
    local C = ns.Chips
    eq(C.Amount("1", "", ""), 10000); eq(C.Amount("", "1", ""), 100); eq(C.Amount("", "", "1"), 1); eq(C.Amount("12", "34", "56"), 123456)
    eq(C.Amount("", "", ""), nil); eq(C.Amount("0", "0", "0"), nil); eq(C.Amount("1.5", "", ""), nil); eq(C.Amount("", "100", ""), nil)
    eq(C.Amount("-1", "", ""), nil); eq(C.Amount("x", "", ""), nil)
    eq(C.Text(123456), "12g 34s 56c"); eq(C.Text(10000), "1g"); eq(C.Text(100), "1s"); eq(C.Text(1), "1c"); eq(C.Text(0), "0c"); eq(C.Text(10001), "1g 1c")
    eq(C.Age(0, 0, 0, 0), 0); eq(C.Age(0, 0, 2, 3), 51 * 3600); eq(C.Age(1, 1, 0, 0), 395 * 86400)

    local now = 1000000
    local function buy(id, name, amt, ago, ok) return { id = id, name = name, amt = amt, t = now - ago, ok = ok or false } end
    local function dep(name, amount, hours) return { name = name, amount = amount, age = hours * 3600 } end
    -- One claim, one matching deposit.
    eq(table.concat(C.Verify({ buy("a", "Binky", 10000, 60) }, { dep("Binky", 10000, 0) }, now), ","), "a")
    -- Wrong person, wrong amount, or no deposit near that time: nothing.
    eq(#C.Verify({ buy("a", "Binky", 10000, 60) }, { dep("Lenny", 10000, 0) }, now), 0)
    eq(#C.Verify({ buy("a", "Binky", 10000, 60) }, { dep("Binky", 9999, 0) }, now), 0)
    eq(#C.Verify({ buy("a", "Binky", 10000, 60) }, { dep("Binky", 10000, 48) }, now), 0)      -- a deposit from two days ago doesn't back a claim made now
    eq(#C.Verify({ buy("a", "Binky", 10000, 60) }, {}, now), 0)
    -- Two claims, one deposit: only one is confirmed, the earlier.
    eq(table.concat(C.Verify({ buy("b", "Binky", 10000, 30), buy("a", "Binky", 10000, 90) }, { dep("Binky", 10000, 0) }, now), ","), "a")
    -- A claim already confirmed has used its deposit; a second identical claim needs a second deposit.
    eq(#C.Verify({ buy("a", "Binky", 10000, 90, true), buy("b", "Binky", 10000, 30) }, { dep("Binky", 10000, 0) }, now), 0)
    eq(table.concat(C.Verify({ buy("a", "Binky", 10000, 90, true), buy("b", "Binky", 10000, 30) }, { dep("Binky", 10000, 0), dep("Binky", 10000, 0) }, now), ","), "b")
    -- Days later the log still backs an old claim an Officer never saw.
    eq(table.concat(C.Verify({ buy("a", "Binky", 500, 50 * 3600) }, { dep("Binky", 500, 50) }, now), ","), "a")

    local st = { chipBuys = { a = { id = "a", who = "g1", amt = 10000, t = 1, ok = true }, b = { id = "b", who = "g1", amt = 250, t = 2, ok = false },
        c = { id = "c", who = "g2", amt = 30000, t = 3, ok = true }, d = { id = "d", who = "g3", amt = 5, t = 4, ok = false } } }
    local bal = C.Balances(st)
    eq(bal.g1.ok, 10000); eq(bal.g1.pending, 250); eq(bal.g2.ok, 30000); eq(bal.g3.ok, 0); eq(C.Balances(nil).g1, nil)
    local board = C.Board(st, function(g) return ({ g1 = "Binky", g2 = "Lenny", g3 = "Tip" })[g] end)
    eq(board[1].name .. board[2].name .. board[3].name, "LennyBinkyTip")

    -- The log: anyone may claim; only an Officer's entry confirms, and never the donor's own.
    assert(ns.Log.KINDS.CHIP_BUY[2]({ amt = 1 }) and not ns.Log.KINDS.CHIP_BUY[2]({ amt = 0 }) and not ns.Log.KINDS.CHIP_BUY[2]({ amt = 1.5 }))
    eq(ns.Log.KINDS.CHIP_BUY[1], "signup"); eq(ns.Log.KINDS.CHIP_OK[1], "award")
end)

-- The games floor ---------------------------------------------------------------
test("casino: stakes, the roulette wheel and its house edge", function()
    local G = ns.Casino
    eq(G.Stake("5s"), 500); eq(G.Stake("1g"), 10000); eq(G.Stake("1g 50s"), 15000); eq(G.Stake("75c"), 75); eq(G.Stake(" 2G 3S 4C "), 20304)
    eq(G.Stake("5"), nil); eq(G.Stake(""), nil); eq(G.Stake("abc"), nil); eq(G.Stake("0s"), nil); eq(G.Stake("5x"), nil); eq(G.Stake("-5s"), nil)
    eq(#G.POCKETS, 38); eq(G.Pocket("00"), "00"); eq(G.Pocket("0"), "0"); eq(G.Pocket("36"), "36"); eq(G.Pocket("37"), nil); eq(G.Pocket("x"), nil)
    local reds = 0
    for n = 1, 36 do if G.RED[n] then reds = reds + 1 end end
    eq(reds, 18)
    eq(G.PocketColor("0"), "green"); eq(G.PocketColor("00"), "green"); eq(G.PocketColor("1"), "red"); eq(G.PocketColor("2"), "black")
    assert(G.BetWins({ kind = "num", pick = "17" }, "17") and not G.BetWins({ kind = "num", pick = "17" }, "18") and G.BetWins({ kind = "num", pick = "00" }, "00"))
    assert(G.BetWins({ kind = "red" }, "1") and not G.BetWins({ kind = "red" }, "2") and not G.BetWins({ kind = "red" }, "0") and not G.BetWins({ kind = "black" }, "00"))
    assert(G.BetWins({ kind = "dozen", pick = 2 }, "13") and G.BetWins({ kind = "dozen", pick = 2 }, "24") and not G.BetWins({ kind = "dozen", pick = 2 }, "25"))
    assert(G.BetWins({ kind = "column", pick = 1 }, "34") and G.BetWins({ kind = "column", pick = 3 }, "36") and not G.BetWins({ kind = "column", pick = 3 }, "35"))
    local staked, back = G.RouletteResult({ { kind = "num", pick = "17", stake = 100 }, { kind = "red", stake = 200 }, { kind = "dozen", pick = 1, stake = 50 } }, "17")
    eq(staked, 350); eq(back, 3600)                     -- 17 is black and in the 2nd dozen: only the number pays, 35 to 1 plus the stake back
    -- The house edge, counted over every pocket: 2 in 38 on every kind of bet.
    for _, bet in ipairs({ { kind = "num", pick = "7" }, { kind = "num", pick = "00" }, { kind = "red" }, { kind = "black" }, { kind = "odd" }, { kind = "even" },
        { kind = "low" }, { kind = "high" }, { kind = "dozen", pick = 3 }, { kind = "column", pick = 2 } }) do
        bet.stake = 1
        local total = 0
        for _, p in ipairs(G.POCKETS) do total = total + select(2, G.RouletteResult({ bet }, p)) end
        eq(total, 36)                                    -- 38 chips in, 36 back: the house keeps 2 in 38, 5.26%
        assert(G.BetLabel(bet) ~= nil)
    end
end)

test("minimap button: it sits on the edge of a round or a square minimap", function()
    local B = ns.MiniButton
    local function near(a, b) assert(math.abs(a - b) < 1e-6, a .. " is not " .. b) end
    local x, y = B.Place(0, false, 140, 140)
    near(x, 70 + B.PAD); near(y, 0)
    x, y = B.Place(90, false, 140, 140)
    near(x, 0); near(y, 70 + B.PAD)
    x, y = B.Place(225, false, 140, 140)                 -- on the circle, lower left
    near(math.sqrt(x * x + y * y), 70 + B.PAD); assert(x < 0 and y < 0)
    x, y = B.Place(45, true, 140, 140)                   -- a square minimap: out to the corner
    near(x, 70 + B.PAD); near(y, 70 + B.PAD)
    x, y = B.Place(100, true, 200, 140)                  -- along the top edge
    near(y, 70 + B.PAD); assert(x < 0 and x > -100)
    near(B.AngleTo(1, 0), 0); near(B.AngleTo(0, 1), 90); near(B.AngleTo(-1, -1), 225); near(B.AngleTo(0, 0), B.DEFAULT_ANGLE)
end)

test("casino: the pictures line up with the rules", function()
    local G = ns.Casino
    -- The wheel picture holds every pocket once, and the zeros sit opposite each other.
    eq(#G.WHEEL, 38)
    local seen = {}
    for _, name in ipairs(G.WHEEL) do assert(not seen[name] and G.Pocket(name) == name); seen[name] = true end
    eq(G.WheelAngle("0"), 0); eq(G.WheelAngle("00"), math.pi); eq(G.WheelAngle("37"), nil)
    -- Red and black alternate round the wheel, as on a real one.
    for i = 1, 38 do
        local a, b = G.PocketColor(G.WHEEL[i]), G.PocketColor(G.WHEEL[i % 38 + 1])
        assert(a ~= b, "neighbours differ at " .. G.WHEEL[i])
    end
    -- The card sheet: a row per suit, deuce to ace; the back after the ace of spades.
    local l, r, t, b = G.CardCoords({ r = 2, s = 1 })
    eq(l, 0); eq(r, 72 / 1024); eq(t, 0); eq(b, 102 / 512)
    l, r, t, b = G.CardCoords({ r = 14, s = 4 })
    eq(l, 12 * 72 / 1024); eq(r, 13 * 72 / 1024); eq(t, 3 * 102 / 512); eq(b, 4 * 102 / 512)
    l, r, t, b = G.CardCoords(nil)
    eq(l, 13 * 72 / 1024); eq(t, 0); assert(r <= 1 and b <= 1)
    -- The reel sheet holds every symbol the machine can stop on.
    eq(select(1, G.SymbolCoords("Tiger")), 0); eq(select(3, G.SymbolCoords("Cherry")), 0.5); eq(G.SymbolCoords("Plum"), nil)
    for _, s in ipairs(G.REEL) do assert(G.SymbolCoords(s[1])) end
    assert(G.ChipIcons(12345):find("^1|T") and select(2, G.ChipIcons(12345):gsub("|t", "")) == 3)
    eq(select(2, G.ChipIcons(0):gsub("|t", "")), 1); eq(select(2, G.ChipIcons(20000):gsub("|t", "")), 1)
end)

test("casino: the slot machine pays back exactly what its table says", function()
    local G = ns.Casino
    eq(G.REEL_SIZE, 20)
    eq(G.ReelStop(1), "Tiger"); eq(G.ReelStop(2), "Seven"); eq(G.ReelStop(3), "Seven"); eq(G.ReelStop(4), "Bar"); eq(G.ReelStop(20), "Lemon")
    eq(G.SlotPay("Tiger", "Tiger", "Tiger"), 100); eq(G.SlotPay("Lemon", "Lemon", "Lemon"), 9); eq(G.SlotPay("Cherry", "Cherry", "Cherry"), 16)
    eq(G.SlotPay("Cherry", "Bar", "Cherry"), 3); eq(G.SlotPay("Cherry", "Bar", "Bell"), 0); eq(G.SlotPay("Seven", "Seven", "Bar"), 0)
    local back, outOf = G.SlotReturn()
    eq(back, 7413); eq(outOf, 8000)                      -- a 7.34% edge for the house
    for _, s in ipairs(G.REEL) do assert(G.SLOT_PAYS[s[1]] <= G.MAX_MULT) end
    -- The log refuses a session that claims more than any game can pay, or a loss bigger than the stakes.
    local kind = ns.Log.KINDS.CHIP_SESSION[2]
    assert(kind({ game = "Slots", n = 3, bet = 300, net = -300 }) and kind({ game = "Slots", n = 1, bet = 100, net = 9900 }))
    assert(not kind({ game = "Slots", n = 1, bet = 100, net = 10001 }) and not kind({ game = "Slots", n = 1, bet = 100, net = -101 })
        and not kind({ game = "Slots", n = 0, bet = 100, net = 0 }) and not kind({ game = "Slots", n = 1, bet = 100, net = 1.5 }))
    -- Chips after play: what the floor took comes off, and never below nothing.
    local bal = ns.Chips.Balances({ chipBuys = { a = { id = "a", who = "g1", amt = 1000, t = 1, ok = true } }, chipNets = { g1 = -300, g2 = -50, g3 = 700 } })
    eq(bal.g1.ok, 700); eq(bal.g2.ok, 0); eq(bal.g3.ok, 700)
    -- Chips the ADMIN assigned count like confirmed ones, and only the ADMIN's action may write them.
    bal = ns.Chips.Balances({ chipGrants = { g1 = 500, g4 = 200 }, chipNets = { g1 = -600 } })
    eq(bal.g1.ok, 0); eq(bal.g4.ok, 200)
    eq(ns.Log.KINDS.CHIP_GRANT[1], "devtools"); eq(ns.RBAC.ACTIONS.devtools, "admin")
    local grant = ns.Log.KINDS.CHIP_GRANT[2]
    assert(grant({ to = "Player-1-0000AAAA", amt = 1 }) and not grant({ to = "Player-1-0000AAAA", amt = 0 }) and not grant({ to = "", amt = 5 })
        and not grant({ to = "Player-1-0000AAAA", amt = 1.5 }) and not grant({ amt = 5 }))
    local nets, house = G.Nets({ chipNets = { g1 = -300, g2 = -50, g3 = 700 } })
    eq(nets.g1, -300); eq(house, -350)
end)

test("cards: blackjack totals and what a hand gets back", function()
    local K = ns.Cards
    local function c(text)              -- "As Kh 7d" -> cards
        local out = {}
        for r, su in text:gmatch("(%w+)([shdc])") do
            local rank = ({ A = 14, K = 13, Q = 12, J = 11, T = 10 })[r] or tonumber(r)
            out[#out + 1] = { r = rank, s = ({ s = 1, h = 2, d = 3, c = 4 })[su] }
        end
        return out
    end
    ns._cards = c
    eq(K.Name({ r = 14, s = 1 }), "As"); eq(K.Name({ r = 10, s = 2 }), "10h"); eq(K.Name({ r = 2, s = 4 }), "2c")
    eq((K.Total(c("As Kh"))), 21); eq(select(2, K.Total(c("As 6h"))), true); eq((K.Total(c("As 6h Kd"))), 17); eq(select(2, K.Total(c("As 6h Kd"))), false)
    eq((K.Total(c("As Ah 9d"))), 21); eq((K.Total(c("Ks Qh 5d"))), 25)
    assert(K.IsNatural(c("As Th")) and not K.IsNatural(c("7s 7h 7d")) and not K.IsNatural(c("As 9h")))
    assert(K.DealerHits(c("Ts 6h")) and K.DealerHits(c("As 6h")) and not K.DealerHits(c("Ts 7h")) and not K.DealerHits(c("As 7h")))   -- hits a soft 17 only
    assert(K.CanSplit(c("8s 8h")) and K.CanSplit(c("Ks Th")) and not K.CanSplit(c("8s 9h")) and not K.CanSplit(c("8s 8h 2d")))
    local dealer20, dealerBJ, dealerBust = c("Ts Kh"), c("As Kh"), c("Ts 6h 9d")
    eq(K.BJBack({ cards = c("As Kd"), bet = 500 }, dealer20), 1100)                   -- blackjack pays 6 to 5: 500 back plus 600
    eq(K.BJBack({ cards = c("As Kd"), bet = 500 }, dealerBJ), 500)                    -- two blackjacks push
    eq(K.BJBack({ cards = c("As Kd"), bet = 500, split = true }, dealer20), 1000)     -- 21 after a split is not a blackjack
    eq(K.BJBack({ cards = c("Ts 9d"), bet = 500 }, dealer20), 0); eq(K.BJBack({ cards = c("Ts Qd"), bet = 500 }, dealer20), 500)
    eq(K.BJBack({ cards = c("Ts 9d 2c"), bet = 500 }, dealer20), 1000); eq(K.BJBack({ cards = c("Ts 9d 5c"), bet = 500 }, dealerBust), 0)   -- a bust loses even if the dealer busts
    eq(K.BJBack({ cards = c("Ts 2d"), bet = 500 }, dealerBust), 1000); eq(K.BJBack({ cards = c("5s 6d Tc"), bet = 500 }, dealerBJ), 0)
end)

test("cards: poker hands rank in order, and Hold'em pays by the table", function()
    local K, c = ns.Cards, ns._cards
    local function cat(text) return select(2, K.Rank(c(text))) end
    eq(cat("As Ks Qs Js Ts 2d 3c"), 8); eq(cat("9h 8h 7h 6h 5h Ad Ac"), 8); eq(cat("As 2s 3s 4s 5s Kd Kc"), 8)
    eq(cat("9s 9h 9d 9c Ks 2d 3c"), 7); eq(cat("9s 9h 9d Kc Ks 2d 3c"), 6); eq(cat("9s 9h 9d Kc Ks Kd 3c"), 6)
    eq(cat("As 9s 7s 4s 2s Kd Kc"), 5); eq(cat("9s 8h 7d 6c 5s Ad Ac"), 4); eq(cat("As 2h 3d 4c 5s Kd Qc"), 4)
    eq(cat("9s 9h 9d Kc Qs 2d 3c"), 3); eq(cat("9s 9h Kd Kc Qs 2d 3c"), 2); eq(cat("9s 9h Kd Jc Qs 2d 3c"), 1); eq(cat("9s 7h Kd Jc Qs 2d 3c"), 0)
    local function beats(a, b) return (K.Rank(c(a))) > (K.Rank(c(b))) end
    assert(beats("As Ks Qs Js Ts 2d 3c", "9h 8h 7h 6h 5h Ad Ac") and beats("9s 9h 9d 9c Ks 2d 3c", "As Ah Ad Kc Ks 2d 3c"))
    assert(beats("9s 9h 9d Kc Ks Kd 3c", "9s 9h 9d Qc Qs 2d 3c"))          -- two trips make kings full, not nines full
    assert(beats("As 9s 7s 4s 2s Kd Kc", "9s 8h 7d 6c 5s Ad Ac") and beats("9s 8h 7d 6c 5s Ad Ac", "As 2h 3d 4c 5s Kd Qc"))   -- the wheel is the lowest straight
    assert(beats("As Ah Kd 7c 5s 3d 2c", "Ks Kh Ad Qc Js 3d 2c") and beats("As Ah Kd 7c 5s 3d 2c", "Ac Ad Qd 7h 5h 3s 2s"))  -- kickers decide
    eq((K.Rank(c("As Ah Kd 7c 5s 3d 2c"))), (K.Rank(c("Ac Ad Kh 7h 5h 3s 2s"))))                                               -- suits don't
    assert(beats("Ks Kh 9d 9c As 2d 3c", "Ks Kh 8d 8c As Qd Jc"))
    eq(K.HandName(8, 14), "a royal flush"); eq(K.HandName(8, 9), "a straight flush"); eq(K.HandName(0, 13), "high card")
    eq(K.AntePays(8, 14), 100); eq(K.AntePays(8, 9), 20); eq(K.AntePays(7, 9), 10); eq(K.AntePays(6, 9), 3); eq(K.AntePays(5, 14), 2)
    eq(K.AntePays(4, 9), 1); eq(K.AntePays(0, 14), 1)
    assert(K.DealerQualifies(1, 4) and not K.DealerQualifies(1, 3) and not K.DealerQualifies(0, 14) and K.DealerQualifies(2, 3))
    local board = c("Ks 9h 4d 2c 7s")
    -- ante 100, call 200: 300 staked
    local back, how = K.HoldemBack(c("Kh Qd"), c("9s 8d"), board, 100)
    eq(back, 100 + 100 + 400); eq(how, "win")                         -- kings beat nines: ante 1 to 1, call 1 to 1
    back, how = K.HoldemBack(c("3h 3d"), c("As Qd"), board, 100)
    eq(back, 100 + 100 + 200); eq(how, "nofit")                       -- dealer has ace high: the ante pays, the call comes back
    back, how = K.HoldemBack(c("As Qd"), c("3h 3d"), board, 100)
    eq(back, 100 + 100 + 200); eq(how, "nofit")                       -- and it pays even when your hand is the worse one
    back, how = K.HoldemBack(c("9s 8d"), c("Kh Qd"), board, 100)
    eq(back, 0); eq(how, "lose")
    eq(select(2, K.HoldemBack(c("Ah 3s"), c("Ad 3h"), board, 100)), "nofit")
    back, how = K.HoldemBack(c("Kh 3s"), c("Kd 3h"), board, 100)
    eq(back, 300); eq(how, "tie")
    back, how = K.HoldemBack(c("Ks Kd"), c("9s 9d"), c("Kh Kc 9h 2c 7s"), 100)
    eq(back, 100 + 1000 + 400); eq(how, "win")                        -- four kings: the ante pays 10 to 1
    back = K.HoldemBack(c("As Qs"), c("9d 9c"), c("Ks Js Ts 2c 7h"), 100)
    eq(back, 100 + 10000 + 400)                                       -- a royal flush pays the ante 100 to 1
end)

-- Drink of the Night ----------------------------------------------------------
test("drinks: the menu, a guild's own drink, and tonight's drink", function()
    local D = ns.Drinks
    assert(#D.LIST >= 9)
    local seen = {}
    for _, d in ipairs(D.LIST) do
        local n, r = D.Clean(d.name, d.recipe)
        assert(n == d.name and r == d.recipe, d.name .. " fits a log entry as written")
        assert(not seen[d.name] and d.from, d.name); seen[d.name] = true
    end
    assert(D.Find("Bushwacker") and D.Find("Shirley Temple").zero and not D.Find("Mystery"))
    eq(select(2, D.Clean("", "x")), "Give the drink a name."); eq(select(2, D.Clean("Grog", " ")), "Type the recipe, so raiders know what to buy.")
    eq(D.Clean(string.rep("n", 41), "x"), nil); eq(D.Clean("Grog", string.rep("r", 241)), nil)
    local n, r = D.Clean("  Rum   Punch ", "Rum.|cff00ff00 Lime.")
    eq(n, "Rum Punch"); eq(r, "Rum.cff00ff00 Lime.")
    local mule = D.Find("Tennessee Mule")
    local st = { raidDrinks = { a = { name = mule.name, recipe = mule.recipe }, b = { name = "Grog", recipe = "Rum and water." } } }
    eq(D.For(st, "a").from, mule.from); eq(D.For(st, "b").from, "The guild's own"); eq(D.For(st, "c"), nil); eq(D.For(nil, "a"), nil)
    local raids = { { id = "old", at = 1000 }, { id = "c", at = 50000 }, { id = "a", at = 90000 } }
    eq(D.Tonight(st, raids, 60000), nil)                  -- the raid on now has no drink; a later raid's drink isn't tonight's
    eq(D.Tonight(st, { raids[1], raids[3] }, 60000).name, "Tennessee Mule")
    eq(D.Tonight(st, raids, 200000), nil); eq(D.Tonight(st, {}, 0), nil)
    eq(D.Line(mule), "Drink of the night: Tennessee Mule!")
    local kind = ns.Log.KINDS.RAID_DRINK[2]
    assert(kind({ ev = "x", on = true, name = "Grog", recipe = "Rum." }) and kind({ ev = "x", on = false }))
    assert(not kind({ ev = "x", on = true, name = "Grog" }) and not kind({ ev = "x", on = false, name = "Grog" }) and not kind({ on = true, name = "a", recipe = "b" }))
end)

-- Upgrades for sale ---------------------------------------------------------
test("market: gold range, what to look up, the cheapest auction and the buy button", function()
    local M = ns.Market
    eq(M.Gold("25"), 250000); eq(M.Gold(""), nil); eq(M.Gold(" 0 "), 0); eq(M.Gold("1.5"), nil); eq(M.Gold("-3"), nil); eq(M.Gold("abc"), nil)
    local lo, hi = M.Range("", "")
    eq(lo, 0); eq(hi, nil)
    lo, hi = M.Range("5", "50")
    eq(lo, 50000); eq(hi, 500000)
    eq(M.Range("50", "5"), nil); eq(M.Range("x", "5"), nil)
    eq(M.RangeText(0, nil), "at any price"); eq(M.RangeText(0, 500000), "up to 50g"); eq(M.RangeText(50000, 500000), "between 5g and 50g")
    assert(M.Sellable("World drop") and M.Sellable("Tailoring 290") and M.Sellable("Stratholme, Baron Rivendare"))
    assert(not M.Sellable("Quest: In Dreams") and not M.Sellable("Tier 0.5 questline"))
    eq(M.BaseName("Master's Hat of Shadow Wrath"), "Master's Hat"); eq(M.BaseName("Supreme Crown of the Tiger"), "Supreme Crown")
    eq(M.BaseName("Eye of Rend"), nil); eq(M.BaseName("Helm of Latent Power"), nil); eq(M.BaseName("Felcloth Hood"), nil)

    local list = { slots = {
        { slot = "Head", items = {
            { name = "Crown", how = "World drop", score = 1 },
            { name = "Quest Hat", how = "Quest: A hat", score = 0.75 },
            { name = "Hat of Magic", how = "World drop", score = 0.5, ally = "Hat of Shadow Wrath" },
            { name = "Cap", how = "Tailoring", score = 0.25 } } },
        { slot = "Ring 1", items = { { name = "Band", how = "World drop", score = 1 }, { name = "Loop", how = "Crafted", score = 0.5 } } },
        { slot = "Ring 2", items = { { name = "Band", how = "World drop", score = 1 }, { name = "Loop", how = "Crafted", score = 0.5 } } },
    } }
    local w = M.Wanted(list, { Cap = "equipped", Loop = "bags" })
    local names = {}
    for i, x in ipairs(w) do names[i] = x.name end
    eq(table.concat(names, ","), "Band,Crown,Hat of Magic,Hat of Shadow Wrath")   -- owned and quest items left out; both names of one item looked up
    eq(w[1].slot, "Ring 2"); eq(w[1].gain, 1)                     -- the empty ring slot is the bigger step
    eq(w[2].have, 0.25); eq(w[2].gain, 0.75)
    eq(#M.Wanted(list, { Crown = "equipped", Band = "equipped", Loop = "equipped" }), 0)
    eq(#M.Wanted(list, { ["Hat of Shadow Wrath"] = "equipped", Band = "bags", Loop = "bags" }), 1)   -- owned under its second name; only Crown is better

    local keys = M.Candidates({ { key = "a", name = "Hat" }, { key = "b", name = "Hat of Magic" }, { key = "c", name = "Hatchet" }, { key = "d" } }, "Hat of Magic", "Hat")
    eq(table.concat(keys, ""), "bad")
    eq(#M.Candidates({ { key = 1 }, { key = 2 }, { key = 3 }, { key = 4 }, { key = 5 }, { key = 6 } }, "X", nil), M.MAX_KEYS)

    local auctions = { { id = 1, name = "Hat of Magic", buyout = 300000 }, { id = 2, name = "Hat of the Owl", buyout = 100 },
        { id = 3, name = "Hat of Magic", buyout = 0 }, { id = 4, name = "Hat of Magic", buyout = 200000, mine = true },
        { id = 5, name = "Hat of Magic", buyout = 250000 }, { id = 6, name = "Hat of Magic", buyout = 40000 } }
    eq(M.Cheapest(auctions, "Hat of Magic", 0, nil).id, 6)
    eq(M.Cheapest(auctions, "Hat of Magic", 50000, nil).id, 5)       -- below the range, bid-only and your own auctions are skipped
    eq(M.Cheapest(auctions, "Hat of Magic", 50000, 200000), nil)
    eq(M.Cheapest(nil, "Hat of Magic", 0, nil), nil)

    local row = { id = 5, buyout = 250000 }
    local kind, text = M.ButtonFor(row, true, 250000, nil)
    eq(kind, "buy"); eq(text, "Buy 25g")
    eq(M.ButtonFor(row, true, 249999, nil), "poor"); eq(M.ButtonFor(row, false, 999999, nil), "none")
    eq(M.ButtonFor(row, true, 999999, 9), "wait"); eq(select(2, M.ButtonFor(row, true, 999999, 5)), "Buying...")
    eq(select(2, M.ButtonFor({ id = 5, buyout = 1, bought = true }, true, 9, nil)), "Bought")
    assert(#M.HOWTO >= 6)
end)

test("market: usable gear is Pawn's call, and the list sorts by any column", function()
    local M = ns.Market
    eq(M.Verdict(0.214, 100).text, "+21% Pawn"); eq(M.Verdict(0.214, 100).kind, "pawn"); eq(M.Verdict(0.004, 100).text, "+0% Pawn")
    eq(M.Verdict(100, 100).text, "Pawn: big upgrade"); eq(M.Verdict(250, nil).text, "+25000% Pawn")
    eq(M.Verdict(0, 100), nil); eq(M.Verdict(false, 100), nil); eq(M.Verdict(nil, 100), nil)     -- not an upgrade, or Pawn can't say: not listed

    local ranked = M.UsableRank({ { key = "a", share = 0.1, price = 5 }, { key = "b", share = 0.5, price = 9 }, { key = "c", share = 0.5, price = 2 },
        { key = "d", share = 0.3, price = 1 } }, 3)
    eq(ranked[1].key .. ranked[2].key .. ranked[3].key, "cbd"); eq(#ranked, 3)       -- biggest first, cheapest among equals, capped

    eq(M.MorePages(true, 10, 5, nil, 100), false)       -- the auction house has no more
    eq(M.MorePages(false, 100, 5, nil, 100), false)     -- enough read
    eq(M.MorePages(false, 50, 600, 500, 100), false)    -- cheapest first: prices have passed the most you'll pay
    eq(M.MorePages(false, 50, 400, 500, 100), true); eq(M.MorePages(false, 50, 400, nil, 100), true); eq(M.MorePages(false, 0, nil, 500, 100), true)
    assert(M.EQUIP.INVTYPE_HOLDABLE[1] == "Off hand" and M.EQUIP.INVTYPE_ROBE[1] == "Chest" and M.EQUIP.INVTYPE_BAG == nil)

    local rows = {
        { id = 1, name = "Cowl", slot = "Head", score = 1, have = 0.5, buyout = 500, up = { kind = "list", value = 0.5 } },
        { id = 2, name = "Band", slot = "Ring", buyout = 100, up = { kind = "pawn", value = 0.05 } },
        { id = 3, name = "Amice", slot = "Shoulder", score = 0.5, have = 0, buyout = 900, up = { kind = "list", value = 0.5 } },
        { id = 4, name = "Drape", slot = "Back", buyout = 300, up = { kind = "pawn", value = 0.12 } } }
    local function order(key, desc)
        local out = {}
        for i, r in ipairs(M.Sort(rows, key, desc)) do out[i] = r.name end
        return table.concat(out, ",")
    end
    eq(order("cost", false), "Band,Drape,Cowl,Amice"); eq(order("cost", true), "Amice,Cowl,Drape,Band")
    eq(order("name", false), "Amice,Band,Cowl,Drape"); eq(order("slot", true), "Amice,Band,Cowl,Drape")
    eq(order("score", true), "Cowl,Amice,Band,Drape"); eq(order("score", false), "Amice,Cowl,Band,Drape")   -- rows without a list score stay last
    eq(order("have", true), "Cowl,Amice,Band,Drape")
    eq(order("up", true), "Amice,Cowl,Drape,Band"); eq(order("up", false), "Band,Drape,Amice,Cowl")       -- list items, then Pawn's biggest
end)

-- Buy materials -------------------------------------------------------------
test("shop: plan for 1 to 20 crafts, and what each button does", function()
    local S = ns.Shop
    eq(S.Crafts("1"), 1); eq(S.Crafts("20"), 20); eq(S.Crafts("21"), nil); eq(S.Crafts("0"), nil); eq(S.Crafts("x"), nil); eq(S.Crafts("3.5"), nil)
    local have, price = { [1] = 3, [2] = 50 }, { [1] = 10, [3] = 7 }
    local rows, total, unpriced = S.Plan({ { item = 1, n = 2 }, { item = 2, n = 1 }, { item = 3, n = 4 }, { item = 4, n = 1 } }, 20,
        function(i) return have[i] end, function(i) return price[i] end, function(i) return i == 1 and "Ore" or nil end)
    eq(rows[1].name, "Ore"); eq(rows[1].need, 40); eq(rows[1].buy, 37); eq(rows[1].est, 370)
    eq(rows[2].buy, 0); eq(rows[2].est, nil)                 -- 50 held, 20 needed
    eq(rows[3].name, "item 3"); eq(rows[3].buy, 80); eq(rows[4].buy, 20); eq(rows[4].each, nil)
    eq(total, 370 + 560); eq(unpriced, 1)
    eq(S.Held(3, nil), 3); eq(S.Held(3, { base = 3, qty = 4 }), 7); eq(S.Held(7, { base = 3, qty = 4 }), 7); eq(S.Held(9, { base = 3, qty = 4 }), 9)
    local r = rows[1]
    eq(S.ButtonFor(r, nil, nil, true, true, 0), "price")
    eq(S.ButtonFor(r, nil, nil, false, true, 0), "none"); eq(S.ButtonFor(r, nil, nil, true, false, 0), "none")
    eq(S.ButtonFor(rows[2], nil, nil, true, true, 0), "none")
    eq(S.ButtonFor(r, nil, 1, true, true, 0), "wait")
    eq(S.ButtonFor(r, { item = 1, qty = 37, total = 400 }, nil, true, true, 400), "pay")
    eq(S.ButtonFor(r, { item = 1, qty = 37, total = 400 }, nil, true, true, 399), "poor")
    eq(S.ButtonFor(r, { item = 1, qty = 36, total = 400 }, nil, true, true, 999), "price")   -- a quote for another amount is not used
    assert(#S.HOWTO >= 6)
end)

-- Raid Kit ------------------------------------------------------------------
test("kit: bring enough for the raid; progression doubles potions and runes only", function()
    local K = ns.Kit
    eq(K.Need({ mins = 120 }, 3), 2); eq(K.Need({ mins = 30 }, 3), 6); eq(K.Need({ mins = 15 }, 3), 12)
    eq(K.Need({ mins = 20 }, 3), 9); eq(K.Need({ mins = 30 }, 3, true), 6)
    eq(K.Need({ n = 5 }, 3), 5); eq(K.Need({ n = 5 }, 3, true), 10); eq(K.Need({}, 3, true), nil)
end)

test("kit: list = built-in + captains' changes + this raid's extras", function()
    local K = ns.Kit
    eq(#K.List(nil, "tank"), 6); eq(#K.List(nil, "healer"), 9)
    local st = { kitItems = {
        tank = { ["Savory Turtle Stew"] = { on = false }, ["Greater Stoneshield Potion"] = { on = true, n = 4 },
            ["Elixir of Greater Defense"] = { on = true, mins = 60 } },
        [K.RaidKey("Onyxia's Lair")] = { ["Greater Fire Protection Potion"] = { on = true, n = 3 } },
    } }
    local list = K.List(st, "tank", "Hyjal Summit")
    eq(#list, 6); eq(list[5].item, "Greater Stoneshield Potion"); eq(list[5].n, 4)
    eq(list[6].item, "Elixir of Greater Defense"); eq(list[6].mins, 60)
    list = K.List(st, "tank", "Onyxia's Lair")
    eq(#list, 7); eq(list[7].item, "Greater Fire Protection Potion"); eq(list[7].slot, "This raid")
    eq(#K.List(st, "healer", "Onyxia's Lair"), 10)       -- the raid's extras are for everyone
    local held = { ["Flask of the Titans"] = 2, ["Greater Stoneshield Potion"] = 9, ["Greater Fire Protection Potion"] = 5 }
    local rows, have, need = K.Evaluate(list, 3, true, function(n) return held[n] end)
    eq(need, 7); eq(have, 2)                                -- flask, and 9 potions cover 4 x 2
    eq(rows[7].need, 6); eq(rows[7].short, 1)               -- 3 doubled, 5 held
end)

test("kit: buffs, what is missing, the next raid and the ready-check rows", function()
    local K = ns.Kit
    local c = K.Classify({ "Well Fed", "Flask of the Titans", "Elixir of the Mongoose", "Winterfall Firewater", "Mark of the Wild" }, true)
    eq(c.f, true); eq(c.fd, true); eq(c.w, true); eq(c.e, 2); eq(K.Missing(c), nil)
    eq(K.Missing(K.Classify({}, false)), "flask and food"); eq(K.Missing(K.Classify({ "Well Fed" })), "flask"); eq(K.Missing(nil), nil)
    local st = { raids = {
        a = { at = 5000, signups = { me = { st = "no" } }, picked = {} },
        b = { at = 90000, signups = { me = { st = "yes" } }, picked = {}, prog = true },
        c = { at = 80000, signups = {}, picked = { me = "cap" }, cancelled = true },
        d = { at = 95000, signups = {}, picked = { me = "cap" } },
    }, kitChecks = { ["2026-12-09"] = { x = { f = true, fd = true, w = true, e = 2 }, y = { f = false, fd = true, w = true, e = 0 } },
        ["2026-08-01"] = { x = { f = true, fd = true, w = true, e = 0 } } } }
    eq(K.NextRaid(st, "me", 70000), st.raids.b); eq(K.NextRaid(st, "you", 70000), nil)
    local rows = K.CheckRows(st, "2026-12-09", { "x", "y", "z" }, function(g) return g:upper() end)
    eq(rows[1].guid, "y"); eq(rows[1].missing, "flask"); eq(rows[2].guid, "z"); eq(rows[2].check, nil); eq(rows[3].guid, "x")
    local days = K.Days(st, "2026-12-10")
    eq(#days, 1); eq(days[1], "2026-12-09")                 -- older than 90 days is not shown
    assert(K.ScoreText({ have = 6, need = 6 }):find("kit 6/6", 1, true)); assert(K.ScoreText(nil):find("no kit yet", 1, true))
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

test("/tiger and /blindtiger both open the window", function()
    rawset(_G, "SlashCmdList", {})
    local opened = 0
    ns.UI.Toggle = function() opened = opened + 1 end
    load("Core/Commands.lua")
    eq(rawget(_G, "SLASH_BLINDTIGER1"), "/tiger")
    eq(rawget(_G, "SLASH_BLINDTIGER2"), "/blindtiger")
    local handler = rawget(_G, "SlashCmdList").BLINDTIGER
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

test("activity: best of main and alts, roster or Blind Tiger activity; levels follow settings", function()
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
    eq(body, "Blind Tiger order: here is your Runed Copper Rod x3, made by Binky Bee. When you have it, type /tiger, open Professions > Orders and press \"I received it\".")
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
    eq(S.SuggestText({ "Vela" }), "Could you invite Vela to the group? I'm summoning. (sent with Blind Tiger)")
    eq(S.SuggestText({ "Vela", "Pip", "Grim Tusk" }), "Could you invite Vela, Pip, Grim Tusk to the group? I'm summoning. (sent with Blind Tiger)")
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

test("roster: what an invite will do", function()
    local Ro = ns.Roster
    local solo = { grouped = false }
    eq(Ro.InvitePlan(solo, true, false), "invite")
    eq(select(2, Ro.InvitePlan(solo, false, false)), "They're offline.")
    eq(select(2, Ro.InvitePlan(solo, true, true)), "That's you.")
    eq(Ro.InvitePlan({ grouped = true, lead = true, size = 3 }, true, false), "invite")
    eq(Ro.InvitePlan({ grouped = true, lead = true, size = 5 }, true, false), "raid")          -- a full party becomes a raid
    eq(Ro.InvitePlan({ grouped = true, lead = true, raid = true, size = 12 }, true, false), "invite")
    eq(select(2, Ro.InvitePlan({ grouped = true, lead = true, raid = true, size = 40 }, true, false)), "The raid is full.")
    eq(Ro.InvitePlan({ grouped = true, lead = false, leader = "Grim Tusk", size = 3 }, true, false), "ask")
    eq(Ro.InvitePlan({ grouped = true, lead = false, size = 3 }, true, false), nil)
end)

test("recruit: every zone by level range, split until the game's list fits", function()
    local Rc = ns.Recruit
    eq(select(1, Rc.LevelRange("10", "60")), 10); eq(select(2, Rc.LevelRange("10", "60")), 60)
    eq(select(1, Rc.LevelRange("40", "20")), 20); eq(select(2, Rc.LevelRange("40", "20")), 40)     -- either order
    eq(Rc.LevelRange("", "60"), nil); eq(Rc.LevelRange("0", "10"), nil); eq(Rc.LevelRange("10", "61"), nil)
    local plan = Rc.SweepPlan(1, 60)
    eq(#plan, 12); eq(plan[1].lo, 1); eq(plan[1].hi, 5); eq(plan[12].lo, 56); eq(plan[12].hi, 60)
    for i = 2, #plan do eq(plan[i].lo, plan[i - 1].hi + 1) end                                   -- no gaps, no overlap
    plan = Rc.SweepPlan(58, 60)
    eq(#plan, 1); eq(plan[1].hi, 60)
    eq(#Rc.SweepPlan(30, 30), 1)

    local halves = Rc.SweepSplit({ lo = 56, hi = 60 })
    eq(#halves, 2); eq(halves[1].lo, 56); eq(halves[1].hi, 58); eq(halves[2].lo, 59); eq(halves[2].hi, 60)
    local classes = Rc.SweepSplit({ lo = 60, hi = 60 })
    eq(#classes, 9); eq(classes[1].class, "Warrior"); eq(classes[9].lo, 60)
    eq(Rc.SweepSplit({ lo = 60, hi = 60, class = "Mage" }), nil)                                 -- can't go smaller

    eq(Rc.SweepQuery({ lo = 10, hi = 14 }), "10-14"); eq(Rc.SweepQuery({ lo = 60, hi = 60, class = "Mage" }), 'c-"Mage" 60-60')
    eq(Rc.SweepLabel({ lo = 10, hi = 14 }), "levels 10-14"); eq(Rc.SweepLabel({ lo = 60, hi = 60 }), "level 60")
    eq(Rc.SweepLabel({ lo = 60, hi = 60, class = "Mage" }), "level 60 Mages")

    local sweep = { from = 58, to = 60, queue = Rc.SweepPlan(58, 60), done = 0 }
    eq(Rc.SweepAdvance(sweep, true), "split"); eq(#sweep.queue, 2); eq(sweep.queue[1].hi, 59)   -- cut short: halves go first
    eq(Rc.SweepAdvance(sweep, false), "ok"); eq(#sweep.queue, 1); eq(sweep.queue[1].lo, 60)
    eq(Rc.SweepAdvance(sweep, true), "split"); eq(#sweep.queue, 9)                              -- one level: by class
    eq(Rc.SweepAdvance(sweep, true), "short"); eq(#sweep.queue, 8)                              -- one class of one level: as far as it goes
    for _ = 1, 8 do Rc.SweepAdvance(sweep, false) end
    eq(#sweep.queue, 0); eq(sweep.done, 12)
end)

test("statics: a captain's team of ten, one team per member", function()
    local St = ns.Statics
    local g = newStore()
    local CAP, OFF, A, B, V = "Player-1-CAPT", "Player-1-OFFICER1", "Player-1-MEM1", "Player-1-MEM2", "Player-1-VET"
    insertAll(g, { author(g, CAP, "STATIC", { who = A, on = true, role = "healer" }) })
    insertAll(g, { author(g, CAP, "STATIC", { who = B, on = true }) })
    insertAll(g, { author(g, CAP, "STATIC", { who = CAP, on = true, role = "tank" }) })       -- the captain's own role
    insertAll(g, { author(g, CAP, "STATIC_NAME", { name = "Night Shift" }) })
    local st = Red.Build(g)
    local t = st.statics[CAP]
    eq(t.members[A], "healer"); eq(t.members[B], "dps"); eq(t.n, 2); eq(t.capRole, "tank"); eq(t.name, "Night Shift")
    eq(St.TeamOf(st.statics, A), CAP); eq(St.TeamOf(st.statics, V), nil)

    -- A Member can't edit teams; an Officer edits any captain's team.
    eq(select(2, Log.Insert(g, author(g, A, "STATIC", { who = V, on = true }), true)), "forbidden")
    eq(select(2, Log.Insert(g, author(g, CAP, "STATIC_MOD", { cap = OFF, who = V, on = true }), true)), "forbidden")
    insertAll(g, { author(g, OFF, "STATIC_MOD", { cap = CAP, who = A, on = true, role = "tank" }) })
    eq(Red.Build(g).statics[CAP].members[A], "tank")

    -- One team at a time: a second captain can't take a member who is already on a team.
    insertAll(g, { author(g, OFF, "STATIC", { who = A, on = true }) })
    st = Red.Build(g)
    eq(st.statics[OFF].members[A], nil); eq(st.statics[CAP].members[A], "tank")
    local nameOf = function() return "Cap" end
    eq(select(2, St.CanAdd(st.statics, OFF, A, nameOf)), "They are on Cap's team. Remove them there first.")
    eq(select(2, St.CanAdd(st.statics, CAP, A, nameOf)), "They are already on this team.")
    eq(select(2, St.CanAdd(st.statics, CAP, CAP, nameOf)), "The captain is already on the team.")
    eq(St.CanAdd(st.statics, CAP, V, nameOf), true)

    -- Removed, then free to join another team.
    insertAll(g, { author(g, CAP, "STATIC", { who = A, on = false }) })
    insertAll(g, { author(g, OFF, "STATIC", { who = A, on = true }) })
    st = Red.Build(g)
    eq(st.statics[CAP].members[A], nil); eq(st.statics[CAP].n, 1); eq(st.statics[OFF].members[A], "dps")

    -- Ten at most: the captain and nine more.
    local g2 = newStore()
    for i = 1, 12 do insertAll(g2, { author(g2, CAP, "STATIC", { who = "Player-1-X" .. i, on = true }) }) end
    st = Red.Build(g2)
    eq(st.statics[CAP].n, 9)
    eq(select(2, St.CanAdd(st.statics, CAP, V, nameOf)), "The team has all 10 players.")

    -- The view: a team for every Team Captain, the captain first, then tanks, healers, DPS.
    local roster = {
        c1 = { name = "Zed-Normal", rankIndex = 2, online = true, class = "WARRIOR", level = 60, zone = "Orgrimmar" },
        c2 = { name = "Amy-Normal", rankIndex = 2, online = false },
        m1 = { name = "Heal-Normal", rankIndex = 4, online = true }, m2 = { name = "Tank-Normal", rankIndex = 4, online = false },
        m3 = { name = "Dps-Normal", rankIndex = 5, online = true },
    }
    local statics = { c1 = { members = { m1 = "healer", m2 = "tank", m3 = "dps", gone = "dps" }, capRole = "dps", name = "Alpha" } }
    local teams = St.Teams(statics, roster)
    eq(#teams, 2); eq(teams[1].capName, "Amy"); eq(teams[1].n, 1)                -- a captain with nobody yet still has a team
    local z = teams[2]
    eq(z.name, "Alpha"); eq(z.n, 4); eq(z.tank, 1); eq(z.healer, 1); eq(z.dps, 2); eq(z.online, 3)   -- a member who left the guild isn't counted
    local order = {}
    for i, r in ipairs(z.rows) do order[i] = r.name end
    eq(table.concat(order, ","), "Zed,Tank,Heal,Dps")
    eq(St.NextRole("tank"), "healer"); eq(St.NextRole("dps"), "tank"); eq(St.NextRole(nil), "tank")

    for _, bad in ipairs({ { who = A }, { who = A, on = true, role = "boss" }, { on = true } }) do
        eq(select(2, Log.Insert(g, author(g, CAP, "STATIC", bad), true)), "payload")
    end
    eq(select(2, Log.Insert(g, author(g, CAP, "STATIC_NAME", { name = ("x"):rep(25) }), true)), "payload")
end)

test("advert: the Trade chat line, its links and the channel", function()
    local A = ns.Advert
    eq(A.Text("Enchanting", 225, 300, "Undercity", "Tips appreciated."), "[Enchanting] 225/300 LFW in Undercity. Tips appreciated.")
    eq(A.Text("Alchemy", 94, nil, "", ""), "[Alchemy] 94 LFW.")
    eq(#A.Text("Enchanting", 300, 300, "Orgrimmar", ("x"):rep(200)) <= 30 + A.EXTRA_MAX + 12, true)

    local link = "|cffffd000|Henchant:13538|h[Enchanting: Enchant Chest - Lesser Absorption]|h|r"       -- about 80 letters
    local lines, used = A.Pack("[Enchanting] 225/300 LFW in Undercity. Tips appreciated.", { link, link, link, link })
    eq(#lines, 2); eq(used, 4)                                             -- four links take two lines
    local long = "|cffffd000|Henchant:1|h[" .. ("Enchanting: A Very Long Recipe Name "):rep(4) .. "]|h|r"
    eq(select(2, A.Pack("[Enchanting] 225/300 LFW in Undercity.", { long, long, long, long })), 2)   -- never a third line
    for _, l in ipairs(lines) do eq(#l <= 255, true) end
    lines, used = A.Pack("short", { "[a]", "[b]" })
    eq(#lines, 1); eq(lines[1], "short [a] [b]"); eq(used, 2)
    lines, used = A.Pack("just words", {})
    eq(#lines, 1); eq(used, 0)

    eq(A.TradeChannel(1, "General - Undercity", false, 2, "Trade - City", false, 3, "LocalDefense", false), 2)
    eq(A.TradeChannel(1, "General - The Barrens", false), nil)                  -- no Trade channel outside a city
    eq(A.TradeChannel(2, "Trade - City", true), nil)

    local list = A.Toggle({}, 5)
    eq(#list, 1)
    list = A.Toggle(A.Toggle(A.Toggle(list, 6), 7), 8)
    eq(#list, 4); eq(select(2, A.Toggle(list, 9)), "You can link 4 recipes at most. Untick one first.")
    list = A.Toggle(list, 6)                                               -- untick
    eq(table.concat(list, ","), "5,7,8")
end)

test("recruit: Team Captain and above only", function()
    local RBAC = ns.RBAC
    for _, guid in ipairs({ "Player-1-GM", "Player-1-OFFICER1", "Player-1-CAPT" }) do
        eq(RBAC.Can(guid, "recruit"), true, guid)
    end
    for _, guid in ipairs({ "Player-1-VET", "Player-1-MEM1", "Player-1-INIT", "Player-9-STRANGER" }) do
        eq(RBAC.Can(guid, "recruit"), false, guid)
    end
    eq(RBAC.Can("Player-1-CAPT", "recruitEdit"), false)        -- editing the shared messages is Officer and above
    eq(RBAC.Can("Player-1-OFFICER1", "recruitEdit"), true)
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

test("tickets: what a report must hold, who it may reach, and how staff copies merge", function()
    local T = ns.Tickets
    local d = T.Clean("lang", "  Solo   Kill ", " Kept swearing at   people in raid chat. ")
    eq(d.about, "Solo Kill"); eq(d.text, "Kept swearing at people in raid chat."); eq(d.cat, "lang")
    eq(select(2, T.Clean("nope", "X", "long enough text")), "Pick what kind of problem it is.")
    eq(select(2, T.Clean("loot", "", "long enough text")), "Say who it is about.")
    eq(T.Clean("other", "", "long enough text").about, "")                    -- "Something else" needs no name
    eq(select(2, T.Clean("loot", "X", "short")), "Say what happened, in a sentence or two.")
    eq(T.Clean("loot", "X", ("x"):rep(T.MAX_TEXT + 1)), nil)
    eq(T.Clean("loot", ("n"):rep(T.MAX_ABOUT + 1), "long enough text"), nil)

    local id = T.NewId("Player-1-MEM1", 1000.7)
    eq(id, "Player-1-MEM1/1000"); eq(T.IdBy(id), "Player-1-MEM1"); eq(T.IdBy("nonsense"), nil)

    local function ticket(over)
        local t = { id = id, by = "Player-1-MEM1", byName = "Pip", at = 1000, cat = "lang", about = "Solo Kill", text = "Kept swearing.",
            status = "new", v = 1, ut = 1000, ub = "Player-1-MEM1", notes = {} }
        for k, v in pairs(over or {}) do t[k] = v end
        return t
    end
    eq(T.Sanitize(ticket()).status, "new")
    eq(T.Sanitize(ticket({ by = "Player-1-OTHER" })), nil)                    -- the reporter is part of the id
    eq(T.Sanitize(ticket({ status = "deleted" })), nil); eq(T.Sanitize(ticket({ cat = "x" })), nil)
    eq(T.Sanitize(ticket({ text = ("x"):rep(T.MAX_TEXT + 1) })), nil); eq(T.Sanitize("junk"), nil)
    eq(T.Sanitize(ticket({ outcome = "made up" })).outcome, nil)
    local many = {}
    for i = 1, T.MAX_NOTES + 5 do many[i] = { by = "G", at = i, text = "n" .. i } end
    many[2] = { by = "G", at = 2, text = ("x"):rep(T.MAX_NOTE + 1) }           -- too long: dropped
    eq(#T.Sanitize(ticket({ notes = many })).notes, T.MAX_NOTES - 1)

    -- Two staff copies: the later state wins, and notes from both are kept.
    local store = { [id] = ticket({ notes = { { by = "A", at = 1100, text = "asked the raid leader" } } }) }
    local changed, isNew = T.Merge(store, ticket({ status = "work", owner = "B", v = 2, ut = 1200, ub = "B",
        notes = { { by = "B", at = 1150, text = "spoke to them" } } }))
    eq(changed, true); eq(isNew, false)
    eq(store[id].status, "work"); eq(store[id].owner, "B"); eq(#store[id].notes, 2); eq(store[id].notes[1].by, "A")
    changed = T.Merge(store, ticket({ status = "new", v = 1, ut = 1000 }))    -- an older copy changes nothing
    eq(changed, false); eq(store[id].status, "work")
    eq(select(2, T.Merge(store, ticket({ id = "Player-1-MEM2/5", by = "Player-1-MEM2" }))), true)
    eq(T.Newer({ v = 2, ut = 1, ub = "A" }, { v = 1, ut = 9, ub = "Z" }), true)
    eq(T.Newer({ v = 2, ut = 5, ub = "A" }, { v = 2, ut = 5, ub = "B" }), false)

    -- What one staff member offers another, and never a ticket about that person.
    local s2 = { a = ticket({ id = "a", v = 3, notes = { {}, {} } }), b = ticket({ id = "b", v = 1, aboutGuid = "Player-1-OFFICER1" }) }
    local dg = T.Digest(s2, "Player-1-OFFICER1")
    eq(dg.a, "3:2"); eq(dg.b, nil); eq(T.Digest(s2).b, "1:0")
    local send, want = T.Diff(s2, { a = "2:9" }, "Player-1-OFFICER1")
    eq(table.concat(send, ","), "a"); eq(want, false)                         -- mine is newer; "b" is never offered
    send, want = T.Diff(s2, { a = "3:2", c = "1:0" })
    eq(table.concat(send, ","), "b"); eq(want, true)                          -- they lack b, I lack c
    send, want = T.Diff(s2, { a = "3:3", b = "1:0" })
    eq(#send, 0); eq(want, true)                                              -- they hold a newer note
    local old = { a = ticket({ id = "a", status = "done", ut = 100 }), b = ticket({ id = "b", status = "new", ut = 100 }) }
    eq(T.Digest(old, nil, 500).a, nil); eq(T.Digest(old, nil, 500).b, "1:0")    -- long-settled tickets aren't compared
    send, want = T.Diff(old, { a = "1:0" }, nil, 500)
    eq(table.concat(send, ","), "b"); eq(want, false)

    local roster = {
        gm = { name = "Gm", online = true, rankIndex = 0 }, off = { name = "Off", online = true, rankIndex = 1 },
        cap = { name = "Cap", online = false, rankIndex = 2 }, mem = { name = "Mem", online = true, rankIndex = 4 },
        me = { name = "Me", online = true, rankIndex = 2 },
    }
    local staff = function(g) return roster[g].rankIndex <= 2 end
    local to = T.Recipients(roster, staff, "me", nil)
    eq(#to, 2); eq(to[1].guid, "gm"); eq(to[2].guid, "off")                    -- online staff, highest rank first, never me
    to = T.Recipients(roster, staff, "mem", "off")
    eq(#to, 2); eq(to[1].guid, "gm"); eq(to[2].guid, "me")                     -- never the person the ticket is about

    local q = { a = ticket({ id = "a", at = 5, status = "new" }), b = ticket({ id = "b", at = 9, status = "work", owner = "me" }),
        c = ticket({ id = "c", at = 7, status = "done", ut = 100 }) }
    eq(#T.Rows(q, "open", "me"), 2); eq(T.Rows(q, "open", "me")[1].id, "b")    -- newest first
    eq(#T.Rows(q, "mine", "me"), 1); eq(#T.Rows(q, "done", "me"), 1)
    local c = T.Counts(q, "me")
    eq(c.open, 2); eq(c.new, 1); eq(c.mine, 1); eq(c.done, 1)
    eq(T.Prune(q, 100 + T.KEEP_DONE + 1), 1); eq(q.c, nil); eq(q.a ~= nil, true)   -- old resolved tickets go; open ones never

    -- The queue's columns follow the list's width; the kind of problem is never cut mid-word.
    local narrow, wide = T.Columns(336), T.Columns(736)
    eq(narrow.cat[2] < wide.cat[2], true); eq(wide.about[2], 150)
    for _, cols in ipairs({ narrow, wide, T.Columns(10) }) do
        eq(cols.about[1] + cols.about[2] <= cols.cat[1], true)                 -- columns never overlap
        eq(cols.cat[1] + cols.cat[2] <= cols.status[1], true)
    end
    eq(T.CatText("lang", wide.cat[2]), "Language or harassment"); eq(T.CatText("lang", narrow.cat[2]), "Language")
    eq(T.CatText("loot", wide.cat[2]), "Ninja looting or a loot dispute")
    for _, c2 in ipairs(T.CATS) do eq(#T.CAT_SHORT[c2[1]] * 6.2 <= narrow.cat[2], true) end   -- every short name fits the narrowest list
end)

test("reset: the Guild Master wipes DKP or orders; later records count again", function()
    local g = newStore()
    local GM, OFF, A, B = "Player-1-GM", "Player-1-OFFICER1", "Player-1-MEM1", "Player-1-MEM2"
    local raid = author(g, "Player-1-CAPT", "RAID", { title = "Test", raid = "Barrow Deeps", at = NOW, size = 10 })
    local award = author(g, OFF, "AWARD", { to = { A }, amt = 50, r = "manual" })
    local spend = author(g, OFF, "SPEND", { from = A, amt = 20, item = 1234, tier = "bis" })
    local order = author(g, A, "ORDER", { rid = 7421, p = "Enchanting", q = 1, mats = "crafter" })
    insertAll(g, { raid, award, spend, order })
    insertAll(g, { author(g, OFF, "ATTEND", { who = { A, B }, day = "2026-12-09", idem = "test1" }) })
    local st = Red.Build(g)
    eq(st.pools[A].bal, 30); eq(#st.history, 2); eq(st.orders[order.id] ~= nil, true)
    local attended = st.attendance[A] ~= nil

    -- Only the Guild Master may wipe.
    eq(select(2, Log.Insert(g, author(g, OFF, "RESET", { what = "dkp" }), true)), "forbidden")
    eq(select(2, Log.Insert(g, author(g, GM, "RESET", { what = "everything" }), true)), "payload")

    insertAll(g, { author(g, GM, "RESET", { what = "dkp" }) })
    st = Red.Build(g)
    eq(st.pools[A], nil); eq(#st.history, 0); eq(st.resets.dkp ~= nil, true)
    if attended then eq(st.attendance[A], nil) end                          -- attendance goes with DKP
    eq(st.orders[order.id] ~= nil, true)                                    -- orders are untouched
    eq(st.raids[raid.id] ~= nil, true)                                      -- raids and sign-ups stay

    -- DKP earned after the wipe counts.
    insertAll(g, { author(g, OFF, "AWARD", { to = { B }, amt = 10, r = "manual" }) })
    st = Red.Build(g)
    eq(st.pools[B].bal, 10); eq(st.pools[A], nil)

    insertAll(g, { author(g, GM, "RESET", { what = "orders" }) })
    st = Red.Build(g)
    eq(st.orders[order.id], nil); eq(st.pools[B].bal, 10)
    local fresh = author(g, A, "ORDER", { rid = 7421, p = "Enchanting", q = 2, mats = "crafter" })
    insertAll(g, { fresh })
    eq(Red.Build(g).orders[fresh.id].q, 2)

    -- The records are still in the log: nothing is deleted.
    eq(g.log[award.id] ~= nil and g.log[order.id] ~= nil, true)
end)

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
