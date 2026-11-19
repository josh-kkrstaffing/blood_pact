-- Blood Pact: professions on the roster.
-- Each player's own addon reads their skill levels from the game (nobody else
-- can) and shares them with the guild: up to two professions plus First Aid,
-- Cooking and Fishing. Shared when they change, at most once an hour.
-- Skill names are matched in English, like the rest of Blood Pact for now.
local _, ns = ...
local P = {}
ns.Professions = P

P.SECONDARY = { ["First Aid"] = "fa", ["Cooking"] = "ck", ["Fishing"] = "fi" }
-- Skill line ids, the same across WoW versions.
P.SKILL_IDS = {
    [129] = "First Aid", [185] = "Cooking", [356] = "Fishing",
    [171] = "Alchemy", [164] = "Blacksmithing", [333] = "Enchanting", [202] = "Engineering", [182] = "Herbalism",
    [165] = "Leatherworking", [186] = "Mining", [393] = "Skinning", [197] = "Tailoring",
    [755] = "Jewelcrafting", [773] = "Inscription",
}
local PRIMARY = {}
for _, name in pairs(P.SKILL_IDS) do
    if not P.SECONDARY[name] then PRIMARY[name] = true end
end

---------------------------------------------------------------------------
-- Pure logic
---------------------------------------------------------------------------
local function level(n)
    n = tonumber(n)
    if not n or n < 0 then return nil end
    return math.min(1000, math.floor(n))
end

-- skills = { { name = "Tailoring", level = 300, primary = true }, ... }
-- -> the record that is shared: { p1, l1, p2, l2, fa, ck, fi }.
function P.Classify(skills)
    local rec, primaries = {}, {}
    for _, s in ipairs(skills or {}) do
        local lv = type(s.name) == "string" and level(s.level)
        if lv then
            local key = P.SECONDARY[s.name]
            if key then
                rec[key] = lv
            elseif s.primary or PRIMARY[s.name] then
                primaries[#primaries + 1] = { name = s.name:sub(1, 24), level = lv }
            end
        end
    end
    table.sort(primaries, function(a, b) return a.name < b.name end)
    if primaries[1] then rec.p1, rec.l1 = primaries[1].name, primaries[1].level end
    if primaries[2] then rec.p2, rec.l2 = primaries[2].name, primaries[2].level end
    return rec
end

function P.Same(a, b)
    if not a or not b then return false end
    for _, k in ipairs({ "p1", "l1", "p2", "l2", "fa", "ck", "fi" }) do
        if a[k] ~= b[k] then return false end
    end
    return true
end

-- "Tailoring 300" or "-".
function P.Label(name, lv)
    if not name then return "-" end
    return name .. " " .. tostring(lv or 0)
end

-- Rows for the Professions view. filter matches a player or a profession.
function P.Rows(roster, profs, filter, sortBy)
    local rows = {}
    for guid, m in pairs(roster) do
        local r = profs[guid]
        local hay = ((m.name or "") .. " " .. (r and r.p1 or "") .. " " .. (r and r.p2 or "")):lower()
        if not filter or filter == "" or hay:find(filter, 1, true) then
            rows[#rows + 1] = { guid = guid, name = m.name or "?", rec = r }
        end
    end
    local function value(row, key)
        local r = row.rec
        if not r then return -1 end
        if key == "p1" then return r.l1 or -1 end
        if key == "p2" then return r.l2 or -1 end
        return r[key] or -1
    end
    table.sort(rows, function(a, b)
        if sortBy and sortBy ~= "name" then
            local x, y = value(a, sortBy), value(b, sortBy)
            if x ~= y then return x > y end
        elseif (a.rec ~= nil) ~= (b.rec ~= nil) then
            return a.rec ~= nil            -- people who shared theirs first
        end
        return a.name < b.name
    end)
    return rows
end

---------------------------------------------------------------------------
-- Game side: read my skills with whichever API this client has
---------------------------------------------------------------------------
function P.Read()
    local skills = {}
    -- Modern form: slots for two professions, archaeology, fishing, cooking, first aid.
    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        local ok, a, b, c, d, e, f = pcall(GetProfessions)
        if ok then
            for slot, index in pairs({ a, b, c, d, e, f }) do
                local good, name, _, lv = pcall(GetProfessionInfo, index)
                if good and type(name) == "string" then
                    skills[#skills + 1] = { name = name, level = lv, primary = slot <= 2 }
                end
            end
        end
    end
    -- Classic form: the skills list from the character sheet, under its headers.
    if #skills == 0 and type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
        local header
        for i = 1, GetNumSkillLines() or 0 do
            local ok, name, isHeader, _, rank = pcall(GetSkillLineInfo, i)
            if ok and name then
                if isHeader then
                    header = name
                elseif P.SECONDARY[name] or PRIMARY[name] or header == "Professions" then
                    skills[#skills + 1] = { name = name, level = rank, primary = not P.SECONDARY[name] }
                end
            end
        end
    end
    -- By skill line id.
    if #skills == 0 and C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        for id, name in pairs(P.SKILL_IDS) do
            local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, id)
            if ok and type(info) == "table" and (tonumber(info.skillLevel) or 0) > 0 then
                skills[#skills + 1] = { name = name, level = info.skillLevel, primary = not P.SECONDARY[name] }
            end
        end
    end
    return skills
end

function P.Mine() return P.Classify(P.Read()) end

-- Share my skills with the guild when they changed; at most once an hour
-- unless forced.
function P.Publish(force)
    if ns.mock or not ns.RBAC.ICan("signup") then return end
    local c = ns.Char()
    local mine = P.Mine()
    if not next(mine) and not c.profs then return end          -- nothing to say yet
    local now = ns.Now()
    if c.profs and P.Same(c.profs, mine) then return end
    if c.profs and not force and now - (c.profsAt or 0) < 3600 then return end
    if ns.Log.New("PROF", mine) then
        c.profs, c.profsAt = mine, now
    end
end

local queued = false
local function publishSoon(delay)
    if queued or not (C_Timer and C_Timer.After) then return end
    queued = true
    C_Timer.After(delay, function()
        queued = false
        P.Publish(false)
    end)
end
ns.On("SKILL_LINES_CHANGED", function() publishSoon(120) end)
ns.On("CHAT_MSG_SKILL", function() publishSoon(120) end)
ns.Listen("ROSTER_CHANGED", function() if ns.roster.loaded then publishSoon(90) end end)
