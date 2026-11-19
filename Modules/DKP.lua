-- Blood Pact: DKP actions. Every action writes one log event; balances come
-- from the reducer. Permission checks here are for the UI; every client
-- enforces them again when the event arrives.
local _, ns = ...
local D = {}
ns.DKP = D

local Log, Red, RBAC = ns.Log, ns.Reducer, ns.RBAC

local function cut(s, n)
    if type(s) ~= "string" then return nil end
    local ok, r = pcall(string.sub, s, 1, n)
    return ok and r or nil
end

-- GUIDs of guild members in your group (raid or party), including you.
function D.GroupGUIDs()
    if ns.mock then return ns.Mock.RaidGUIDs() end
    local out, n = {}, GetNumGroupMembers()
    local function add(unit)
        local guid = UnitGUID(unit)
        if guid and ns.roster.byGUID[guid] then out[#out + 1] = guid end
    end
    if n == 0 then
        add("player")
    elseif IsInRaid() then
        for i = 1, n do add("raid" .. i) end
    else
        add("player")
        for i = 1, n - 1 do add("party" .. i) end
    end
    return out
end

function D.Award(guids, amount, reason, note, idem)
    if not RBAC.ICan("award") then return nil, "Only Officers and above can award DKP." end
    amount = tonumber(amount)
    if not amount or amount ~= math.floor(amount) or amount == 0 then return nil, "Enter a whole number." end
    if #guids == 0 then return nil, "Nobody to award." end
    local last
    for i = 1, #guids, 60 do
        local slice = {}
        for j = i, math.min(i + 59, #guids) do slice[#slice + 1] = guids[j] end
        local e, why = Log.New("AWARD", { to = slice, amt = amount, r = reason, n = cut(note, Log.MAX_NOTE), idem = idem })
        if not e then return nil, why end
        last = e
    end
    return last
end

function D.AwardGroup(kind)
    local st = Red.State()
    if not st then return nil, "Not in a guild." end
    local amount = kind == "ontime" and st.settings.onTime or st.settings.fullRaid
    local idem = kind .. ":" .. date("%Y-%m-%d")
    return D.Award(D.GroupGUIDs(), amount, kind, nil, idem)
end

function D.OnBossKill(encounterID, encounterName, difficultyID)
    if not (ns.db and ns.db.ui.autoBossAward) then return end
    if not RBAC.ICan("award") then return end
    if not ns.mock and not UnitIsGroupLeader("player") then return end
    local st = Red.State()
    if not st then return end
    local amount = ns.db.ui.progression and st.settings.bossProg or st.settings.bossFarm
    local idem = ("boss:%s:%s:%s"):format(tostring(encounterID), tostring(difficultyID or 0), date("%Y-%m-%d"))
    local e = D.Award(D.GroupGUIDs(), amount, "boss", cut(encounterName, 60), idem)
    if e then ns.Print(("Awarded %d DKP to the raid for the kill."):format(amount)) end
end

ns.On("ENCOUNTER_END", function(encounterID, encounterName, difficultyID, _, success)
    if success == 1 or success == true then D.OnBossKill(encounterID, encounterName, difficultyID) end
end)

function D.ItemIDFrom(text)
    if type(text) ~= "string" then return nil end
    return tonumber(text:match("item:(%d+)")) or tonumber(text:match("^%s*(%d+)%s*$"))
end

function D.Spend(guid, tier, itemID)
    if not RBAC.ICan("spend") then return nil, "Only Officers and above can charge DKP." end
    local price = Red.Price(tier)
    if not price then return nil, "Unknown price tier." end
    if price > Red.Balance(guid) then return nil, "Not enough DKP (balances can't go negative)." end
    return Log.New("SPEND", { from = guid, amt = price, tier = tier, item = itemID })
end

function D.Decay()
    if not RBAC.ICan("decay") then return nil, "Only the Guild Master can run decay." end
    local st = Red.State()
    return Log.New("DECAY", { pct = st.settings.decayPct })
end

function D.SaveSettings(values)
    if not RBAC.ICan("settings") then return nil, "Only the Guild Master can change settings." end
    local st, changed, any = Red.State(), {}, false
    for k, v in pairs(values) do
        v = tonumber(v)
        if Log.SETTING_KEYS[k] and v and v == math.floor(v) and v >= 0 and st.settings[k] ~= v then
            changed[k] = v
            any = true
        end
    end
    if not any then return nil, "Nothing changed." end
    return Log.New("SETTINGS", changed)
end

-- Void the most recent award or spend you authored.
function D.UndoMine()
    if not RBAC.ICan("void") then return nil, "Only Officers and above can undo." end
    local g, me = ns.G(), ns.MyGUID()
    local voided = {}
    for _, e in pairs(g.log) do
        if e.k == "VOID" then voided[e.d.target] = true end
    end
    local best
    for _, e in pairs(g.log) do
        if e.a == me and (e.k == "AWARD" or e.k == "SPEND") and not voided[e.id] then
            if not best or e.s > best.s then best = e end
        end
    end
    if not best then return nil, "Nothing of yours to undo." end
    return Log.New("VOID", { target = best.id })
end

function D.LinkAlt(altGUID, mainGUID)
    if not RBAC.ICan("altlink") then return nil, "Only Officers and above can link alts." end
    return Log.New("ALT_LINK", { alt = altGUID, main = mainGUID })
end

-- Standings: every guild member's pool, highest first. Alts fold into mains.
function D.Standings()
    local st = Red.State()
    if not st then return {} end
    local rows, seen = {}, {}
    local function add(guid)
        local main = st.alts[guid] or guid
        if seen[main] then return end
        seen[main] = true
        local p = st.pools[main] or { bal = 0, earned = 0, spent = 0 }
        rows[#rows + 1] = { guid = main, name = ns.NameForGUID(main) or "(left guild)", bal = p.bal, earned = p.earned, spent = p.spent }
    end
    for guid in pairs(ns.roster.byGUID) do add(guid) end
    for guid in pairs(st.pools) do add(guid) end
    table.sort(rows, function(a, b)
        if a.bal ~= b.bal then return a.bal > b.bal end
        return a.name < b.name
    end)
    return rows
end
