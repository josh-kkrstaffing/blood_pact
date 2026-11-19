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
load("Core/RBAC.lua")
load("Core/Log.lua")
load("Core/Reducer.lua")

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

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
