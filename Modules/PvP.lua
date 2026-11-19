-- Blood Pact: PvP rank on the roster.
-- The guild roster doesn't carry PvP rank, so each player's own addon reads
-- theirs and shares the number (0 to 14) with the guild when it changes.
-- WoW Forever tracks rank as a 0-14 bar; older clients have UnitPVPRank.
-- Both are tried. /bp pvp shows what the game reported.
local _, ns = ...
local V = {}
ns.PvP = V

V.MAX = 14
V.RANK_FACTION = 2800          -- Forever's "PvP Rank Points" track
V.TITLES = {
    Horde = { "Scout", "Grunt", "Sergeant", "Senior Sergeant", "First Sergeant", "Stone Guard", "Blood Guard",
        "Legionnaire", "Centurion", "Champion", "Lieutenant General", "General", "Warlord", "High Warlord" },
    Alliance = { "Private", "Corporal", "Sergeant", "Master Sergeant", "Sergeant Major", "Knight", "Knight-Lieutenant",
        "Knight-Captain", "Knight-Champion", "Lieutenant Commander", "Commander", "Marshal", "Field Marshal", "Grand Marshal" },
}

---------------------------------------------------------------------------
-- Pure logic
---------------------------------------------------------------------------
-- A rank number that can be shown: 1 to 14, or nil.
function V.Valid(r)
    r = tonumber(r)
    if not r or r ~= math.floor(r) or r < 1 or r > V.MAX then return nil end
    return r
end

function V.Title(r, faction)
    r = V.Valid(r)
    if not r then return nil end
    return (V.TITLES[faction] or V.TITLES.Horde)[r]
end

-- The game's own rank badge, by path. Nothing is bundled.
function V.Icon(r)
    r = V.Valid(r)
    if not r then return nil end
    return ("Interface\\PvPRankBadges\\PvPRank%02d"):format(r)
end

-- The older API counts from 5 for rank 1; 0 means no rank.
function V.FromRankID(id)
    id = tonumber(id)
    if not id then return nil end
    if id < 5 then return 0 end
    return math.min(V.MAX, id - 4)
end

---------------------------------------------------------------------------
-- Game side
---------------------------------------------------------------------------
-- -> my rank (0-14) or nil when the game wouldn't say, plus notes for /bp pvp.
function V.Read()
    local notes, rank = {}, nil
    if type(UnitPVPRank) == "function" then
        local ok, id = pcall(UnitPVPRank, "player")
        notes[#notes + 1] = "UnitPVPRank: " .. (ok and tostring(id) or "failed")
        if ok then rank = V.FromRankID(id) end
    else
        notes[#notes + 1] = "UnitPVPRank: not in this client"
    end
    local mf = C_MajorFactions
    if mf and (mf.GetMajorFactionData or mf.GetCurrentRenownLevel) then
        local level
        if mf.GetMajorFactionData then
            local ok, data = pcall(mf.GetMajorFactionData, V.RANK_FACTION)
            if ok and type(data) == "table" then level = tonumber(data.renownLevel) end
        end
        if not level and mf.GetCurrentRenownLevel then
            local ok, n = pcall(mf.GetCurrentRenownLevel, V.RANK_FACTION)
            if ok then level = tonumber(n) end
        end
        notes[#notes + 1] = "rank track " .. V.RANK_FACTION .. ": " .. tostring(level)
        if level and level >= 0 and level <= V.MAX and (rank == nil or level > rank) then rank = math.floor(level) end
    else
        notes[#notes + 1] = "rank track: not in this client"
    end
    return rank, notes
end

-- Share my rank when it changed. Returns true when something was shared.
function V.Publish()
    if ns.mock or not ns.RBAC.ICan("signup") then return false end
    local st = ns.Reducer.State()
    local rank = V.Read()
    if not st or rank == nil then return false end
    local have = st.pvp[ns.MyGUID()]
    if have and have.r == rank then return false end
    if not have and rank == 0 then return false end          -- nothing to show, nothing to say
    return ns.Log.New("PVP", { r = rank }) ~= nil
end

function V.MyFaction()
    local ok, faction = pcall(UnitFactionGroup, "player")
    return ok and faction or "Horde"
end

-- /bp pvp
function V.Diagnose()
    local rank, notes = V.Read()
    if rank == nil then
        ns.Print("Couldn't read your PvP rank from the game.")
    elseif rank == 0 then
        ns.Print("You have no PvP rank yet.")
    else
        ns.Print(("Your PvP rank: %d, %s."):format(rank, V.Title(rank, V.MyFaction()) or "?"))
    end
    for _, line in ipairs(notes) do ns.Print("  " .. line) end
    if ns.mock then
        ns.Print("Mock mode is on, so nothing is shared.")
    elseif V.Publish() then
        ns.Print("Shared with the guild.")
    end
end

-- Tooltip for a roster row: rank, title, and when it was reported.
function V.Tooltip(owner, name, entry)
    local r = entry and V.Valid(entry.r)
    if not r then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.U.Safe(name or "?", 40))
    GameTooltip:AddLine(("PvP rank %d: %s"):format(r, V.Title(r, V.MyFaction()) or "?"), 1, 0.82, 0)
    GameTooltip:AddLine("Reported by their own Blood Pact on " .. (date or os.date)("%b %d, %Y", entry.t), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local queued = false
local function publishSoon(delay)
    if queued or not (C_Timer and C_Timer.After) then return end
    queued = true
    C_Timer.After(delay, function()
        queued = false
        V.Publish()
    end)
end
for _, event in ipairs({ "PLAYER_PVP_RANK_CHANGED", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "HONOR_LEVEL_UPDATE" }) do
    ns.On(event, function() publishSoon(30) end)
end
ns.Listen("ROSTER_CHANGED", function() if ns.roster.loaded then publishSoon(100) end end)
