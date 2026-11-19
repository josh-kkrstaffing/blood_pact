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
}
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
        if e.ok then list[#list + 1] = e end
    end
    table.sort(list, before)

    -- A void cancels an award or a spend, whenever it arrives.
    for _, e in ipairs(list) do
        if e.k == "VOID" then voided[e.d.target] = true end
    end

    local st = {
        settings = ns.U.Copy(Red.DEFAULTS), pools = {}, alts = {}, idem = {},
        recruitMsgs = nil, history = {}, lastDecay = nil,
    }
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
            for _, p in pairs(st.pools) do
                if p.bal > 0 then
                    p.bal = floor(p.bal * (100 - d.pct) / 100 + 0.5)
                end
            end
            st.lastDecay = e
            st.history[#st.history + 1] = e
        elseif k == "RECRUIT_MSGS" then
            st.recruitMsgs = d.msgs
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

function Red.Balance(guid)
    local st = Red.State()
    if not st then return 0 end
    local p = st.pools[st.alts[guid] or guid]
    return p and p.bal or 0
end

if ns.Listen then
    ns.Listen("LOG_CHANGED", Red.Invalidate)
    ns.Listen("ROSTER_CHANGED", Red.Invalidate)
end
