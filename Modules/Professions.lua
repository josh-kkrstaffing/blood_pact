-- Blood Pact: professions on the roster.
-- Each player's own addon reads their skill levels from the game (nobody else
-- can) and shares them with the guild: up to two professions plus First Aid,
-- Cooking and Fishing. Shared when they change, at most once an hour.
-- Skill names are matched in English, like the rest of Blood Pact for now.
-- The Professions tab lists the guild by profession: pick one on the left,
-- see who has it on the right, best first. Click a crafter to see the
-- recipes they have shared (see Recipes.lua).
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
-- Shown on the left even when nobody has shared one yet.
P.STANDARD = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism", "Leatherworking", "Mining",
    "Skinning", "Tailoring" }
P.SECONDARY_ORDER = { "Cooking", "First Aid", "Fishing" }
-- The game's own icons, by path. Nothing is bundled with the addon.
P.ICON = {
    Alchemy = "Trade_Alchemy", Blacksmithing = "Trade_BlackSmithing", Enchanting = "Trade_Engraving",
    Engineering = "Trade_Engineering", Herbalism = "Trade_Herbalism", Leatherworking = "Trade_LeatherWorking",
    Mining = "Trade_Mining", Skinning = "INV_Misc_Pelt_Wolf_01", Tailoring = "Trade_Tailoring",
    Cooking = "INV_Misc_Food_15", ["First Aid"] = "Spell_Holy_SealOfSacrifice", Fishing = "Trade_Fishing",
    Jewelcrafting = "INV_Misc_Gem_01", Inscription = "INV_Inscription_Tradeskill01",
}
-- Nothing to craft in these, so there is no recipe list to wait for.
P.NO_RECIPES = { Herbalism = true, Skinning = true, Fishing = true }
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

local FIELDS = { "p1", "l1", "x1", "p2", "l2", "x2", "fa", "xfa", "ck", "xck", "fi", "xfi" }
local MAX_KEY = { fa = "xfa", ck = "xck", fi = "xfi" }

-- skills = { { name = "Tailoring", level = 300, max = 300, primary = true }, ... }
-- -> the record that is shared: two professions (p1/l1/x1, p2/l2/x2: name,
-- level, cap) and fa, ck, fi with their caps xfa, xck, xfi.
function P.Classify(skills)
    local rec, primaries, seen = {}, {}, {}
    for _, s in ipairs(skills or {}) do
        local lv = type(s.name) == "string" and level(s.level)
        if lv then
            local cap = level(s.max)
            if cap and cap < lv then cap = nil end
            local key = P.SECONDARY[s.name]
            if key then
                if not rec[key] or lv > rec[key] then rec[key], rec[MAX_KEY[key]] = lv, cap end
            elseif s.primary or PRIMARY[s.name] then
                local name = s.name:sub(1, 24)
                local had = seen[name]
                if not had then
                    had = { name = name, level = lv, max = cap }
                    seen[name] = had
                    primaries[#primaries + 1] = had
                elseif lv > had.level then
                    had.level, had.max = lv, cap
                end
            end
        end
    end
    table.sort(primaries, function(a, b) return a.name < b.name end)
    if primaries[1] then rec.p1, rec.l1, rec.x1 = primaries[1].name, primaries[1].level, primaries[1].max end
    if primaries[2] then rec.p2, rec.l2, rec.x2 = primaries[2].name, primaries[2].level, primaries[2].max end
    return rec
end

function P.Same(a, b)
    if not a or not b then return false end
    for _, k in ipairs(FIELDS) do
        if a[k] ~= b[k] then return false end
    end
    return true
end

-- "Tailoring 300" or "-".
function P.Label(name, lv)
    if not name then return "-" end
    return name .. " " .. tostring(lv or 0)
end

-- A shared record as a list: { { name, level, max }, ... }.
function P.Skills(rec)
    local out = {}
    if not rec then return out end
    if rec.p1 then out[#out + 1] = { name = rec.p1, level = rec.l1 or 0, max = rec.x1 } end
    if rec.p2 then out[#out + 1] = { name = rec.p2, level = rec.l2 or 0, max = rec.x2 } end
    for _, name in ipairs(P.SECONDARY_ORDER) do
        local key = P.SECONDARY[name]
        if rec[key] then out[#out + 1] = { name = name, level = rec[key], max = rec[MAX_KEY[key]] } end
    end
    return out
end

-- opts = { online = only people online, hideAlts = leave alts out, alts = alt guid -> main guid }
local function passes(guid, m, opts)
    if opts.online and not m.online then return false end
    if opts.hideAlts and opts.alts and opts.alts[guid] then return false end
    return true
end

-- The left side: every profession and how many members have it. The standard
-- professions always show; Cooking, First Aid and Fishing come last.
-- Returns the list and how many members have shared anything.
function P.Groups(roster, profs, opts)
    opts = opts or {}
    local count, shared = {}, 0
    for guid, m in pairs(roster) do
        local rec = profs[guid]
        if rec and passes(guid, m, opts) then
            shared = shared + 1
            for _, s in ipairs(P.Skills(rec)) do count[s.name] = (count[s.name] or 0) + 1 end
        end
    end
    local names, listed = {}, {}
    for _, name in ipairs(P.STANDARD) do names[#names + 1] = name; listed[name] = true end
    for _, name in ipairs(P.SECONDARY_ORDER) do listed[name] = true end
    for name in pairs(count) do
        if not listed[name] then names[#names + 1] = name; listed[name] = true end
    end
    table.sort(names)
    for _, name in ipairs(P.SECONDARY_ORDER) do names[#names + 1] = name end
    local groups = {}
    for _, name in ipairs(names) do
        groups[#groups + 1] = { name = name, count = count[name] or 0, secondary = P.SECONDARY[name] ~= nil }
    end
    return groups, shared
end

-- The right side: who has this profession. opts adds filter (part of a
-- player's name) and asc (lowest level first; highest first otherwise).
function P.Crafters(roster, profs, prof, opts)
    opts = opts or {}
    local rows = {}
    local filter = opts.filter
    for guid, m in pairs(roster) do
        local rec = profs[guid]
        if rec and passes(guid, m, opts) and (not filter or filter == "" or (m.name or ""):lower():find(filter, 1, true)) then
            for _, s in ipairs(P.Skills(rec)) do
                if s.name == prof then
                    rows[#rows + 1] = { guid = guid, name = m.name or "?", class = m.class, online = m.online and true or false,
                        level = s.level, max = s.max, alt = opts.alts and opts.alts[guid] ~= nil or false }
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.level ~= b.level then
            if opts.asc then return a.level < b.level end
            return a.level > b.level
        end
        return a.name < b.name
    end)
    return rows
end

---------------------------------------------------------------------------
-- Game side: read my skills with whichever API this client has
---------------------------------------------------------------------------
-- Returns the skills and a note per API about what it gave, for /bp prof.
function P.Read()
    local skills, notes = {}, {}
    local function note(api, text) notes[#notes + 1] = api .. ": " .. text end

    -- Modern form: slots for two professions, archaeology, fishing, cooking, first aid.
    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        local ok, a, b, c, d, e, f = pcall(GetProfessions)
        if ok then
            for slot, index in pairs({ a, b, c, d, e, f }) do
                local good, name, _, lv, cap = pcall(GetProfessionInfo, index)
                if good and type(name) == "string" then
                    skills[#skills + 1] = { name = name, level = lv, max = cap, primary = slot <= 2 }
                end
            end
        end
        note("GetProfessions", ok and (#skills .. " found") or "failed")
    else
        note("GetProfessions", "not in this client")
    end

    -- Classic form: the skills list from the character sheet, under its headers.
    if #skills == 0 then
        if type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
            local header
            local okN, lines = pcall(GetNumSkillLines)
            for i = 1, okN and tonumber(lines) or 0 do
                local ok, name, isHeader, _, rank, _, _, cap = pcall(GetSkillLineInfo, i)
                if ok and name then
                    if isHeader then
                        header = name
                    elseif P.SECONDARY[name] or PRIMARY[name] or header == "Professions" then
                        skills[#skills + 1] = { name = name, level = rank, max = cap, primary = not P.SECONDARY[name] }
                    end
                end
            end
            note("skill list", #skills .. " found in " .. tostring(okN and lines or "?") .. " lines")
        else
            note("skill list", "not in this client")
        end
    end

    -- By skill line id: the known ids plus whatever lines the game lists.
    if #skills == 0 then
        local api = C_TradeSkillUI
        if api and api.GetProfessionInfoBySkillLineID then
            local ids = {}
            for id, name in pairs(P.SKILL_IDS) do ids[id] = name end
            if api.GetAllProfessionTradeSkillLines then
                local ok, lines = pcall(api.GetAllProfessionTradeSkillLines)
                if ok and type(lines) == "table" then
                    for _, id in ipairs(lines) do ids[id] = ids[id] or true end
                end
            end
            for id, known in pairs(ids) do
                local ok, info = pcall(api.GetProfessionInfoBySkillLineID, id)
                if ok and type(info) == "table" and (tonumber(info.skillLevel) or 0) > 0 then
                    local name = known ~= true and known or info.parentProfessionName or info.professionName
                    if type(name) == "string" and (P.SECONDARY[name] or PRIMARY[name]) then
                        skills[#skills + 1] = { name = name, level = info.skillLevel, max = info.maxSkillLevel,
                            primary = not P.SECONDARY[name] }
                    end
                end
            end
            note("by skill id", #skills .. " found")
        else
            note("by skill id", "not in this client")
        end
    end
    return skills, notes
end

function P.Mine() return P.Classify((P.Read())) end

-- Share my skills with the guild when they changed; at most once an hour
-- unless forced. Returns true when something was shared.
function P.Publish(force)
    if ns.mock or not ns.RBAC.ICan("signup") then return false end
    local c = ns.Char()
    local mine = P.Mine()
    if not next(mine) and not c.profs then return false end       -- nothing to say yet
    local now = ns.Now()
    if c.profs and P.Same(c.profs, mine) then return false end
    if c.profs and not force and now - (c.profsAt or 0) < 3600 then return false end
    if ns.Log.New("PROF", mine) then
        c.profs, c.profsAt = mine, now
        return true
    end
    return false
end

-- /bp prof: read now, share now, and say what the game gave us. When the
-- Professions tab stays empty for someone, this output shows why.
function P.Diagnose()
    local skills, notes = P.Read()
    local mine = P.Classify(skills)
    local parts = {}
    for _, s in ipairs(P.Skills(mine)) do
        parts[#parts + 1] = s.name .. " " .. s.level .. (s.max and ("/" .. s.max) or "")
    end
    if #parts == 0 then
        ns.Print("Couldn't read any professions from the game.")
    else
        ns.Print("Your professions: " .. table.concat(parts, ", "))
    end
    for _, line in ipairs(notes) do ns.Print("  " .. line) end
    if ns.mock then
        ns.Print("Mock mode is on, so nothing is shared.")
    elseif #parts > 0 then
        local st = ns.Reducer.State()
        local sharedNow = P.Publish(true)
        local have = st and st.profs[ns.MyGUID()]
        ns.Print(sharedNow and "Shared with the guild." or (have and "Already shared; nothing changed." or "Not shared: your role can't post yet, or no guild data is loaded."))
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

---------------------------------------------------------------------------
-- Professions tab
---------------------------------------------------------------------------
local W, U, Red = ns.W, ns.U, ns.Reducer
local chosen, search, onlineOnly, showAlts, ascending = nil, "", false, true, false
local viewing = nil            -- guid of the crafter whose recipes are shown
local BAR_W = 130

ns.UI.AddTab("profs", "Professions", "view", function(p)
    p.searchLabel = W.Text(p, "Search", "GameFontHighlightSmall")
    p.searchLabel:SetPoint("TOPLEFT", 0, -5)
    p.search = W.Edit(p, 130, 30)
    p.search:SetPoint("TOPLEFT", 44, -1)
    p.search:SetScript("OnTextChanged", function(self)
        search = (self:GetText() or ""):lower()
        ns.UI.Refresh()
    end)
    p.online = W.Check(p, "Online only", function(on) onlineOnly = on; ns.UI.Refresh() end)
    p.online:SetPoint("TOPLEFT", 192, -4)
    p.alts = W.Check(p, "Show alts", function(on) showAlts = on; ns.UI.Refresh() end)
    p.alts:SetPoint("TOPLEFT", 296, -4)
    p.alts:SetChecked(true)
    p.count = W.Text(p, "", "GameFontDisableSmall")
    p.count:SetPoint("TOPLEFT", 392, -5)

    -- Left: the professions.
    p.groups = W.List(p, 176, 300, 20, function(row, g)
        if not row.icon then
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(16, 16)
            row.icon:SetPoint("LEFT", 4, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        local icon = P.ICON[g.name]
        row.icon:SetShown(icon ~= nil)
        if icon then row.icon:SetTexture("Interface\\Icons\\" .. icon) end
        local name = p.groups.Col(row, 1, 26, 112)
        name:SetText(g.name)
        local n = p.groups.Col(row, 2, 138, 30, "RIGHT")
        n:SetText(g.count)
        local c = g.count > 0 and W.C.text or W.C.muted
        name:SetTextColor(c[1], c[2], c[3])
        n:SetTextColor(c[1], c[2], c[3])
    end, function(g) chosen = g.name; viewing = nil; ns.UI.Refresh() end)
    p.groups:Stretch(0, -30, nil, 22)
    p.groups.key = "name"

    -- Right: who has the chosen profession.
    p.title = W.Text(p, "", "GameFontNormalSmall")
    p.title:SetPoint("TOPLEFT", 212, -33)
    p.sort = W.SortButton(p, "Level", 70, function() ascending = not ascending; ns.UI.Refresh() end)
    p.sort:SetPoint("TOPLEFT", 418, -30)
    p.crafters = W.List(p, 480, 300, 20, function(row, r)
        if not row.dot then
            row.dot = row:CreateTexture(nil, "ARTWORK")
            row.dot:SetSize(6, 6)
            row.dot:SetPoint("LEFT", 6, 0)
            row.barBack = row:CreateTexture(nil, "ARTWORK")
            row.barBack:SetColorTexture(1, 1, 1, 0.07)
            row.barBack:SetSize(BAR_W, 8)
            row.barBack:SetPoint("LEFT", 212, 0)
            row.bar = row:CreateTexture(nil, "OVERLAY")
            row.bar:SetHeight(8)
            row.bar:SetPoint("LEFT", 212, 0)
        end
        if r.online then row.dot:SetColorTexture(0.25, 0.85, 0.35, 1) else row.dot:SetColorTexture(1, 1, 1, 0.15) end
        local name = p.crafters.Col(row, 1, 20, 184)
        name:SetText(U.Safe(r.name, 40) .. (r.alt and " |cff808080(alt)|r" or ""))
        local cc = RAID_CLASS_COLORS and r.class and RAID_CLASS_COLORS[r.class]
        if cc then name:SetTextColor(cc.r, cc.g, cc.b) else name:SetTextColor(W.C.text[1], W.C.text[2], W.C.text[3]) end
        -- The bar fills against the cap this player's game reported.
        local cap = r.max and r.max > 0 and r.max or nil
        row.barBack:SetShown(cap ~= nil)
        row.bar:SetShown(cap ~= nil and r.level > 0)
        if cap then
            local full = r.level >= cap
            row.bar:SetWidth(math.max(1, BAR_W * math.min(1, r.level / cap)))
            if full then
                row.bar:SetColorTexture(W.C.gold[1], W.C.gold[2], W.C.gold[3], 0.9)
            else
                row.bar:SetColorTexture(W.C.accent[1], W.C.accent[2], W.C.accent[3], 0.9)
            end
        end
        p.crafters.Col(row, 2, 350, 70):SetText(cap and (r.level .. " / " .. cap) or tostring(r.level))
        local n = p.crafters.Col(row, 3, 424, 80)
        n:SetText(r.recipes > 0 and (r.recipes .. (r.recipes == 1 and " recipe" or " recipes")) or "")
        n:SetTextColor(W.C.muted[1], W.C.muted[2], W.C.muted[3])
    end, function(r)
        viewing = r.guid
        p.search:SetText("")          -- the box searches recipes now, not players
        ns.UI.Refresh()
    end)
    p.crafters:Stretch(206, -52, 0, 22)
    p.crafters.key = "guid"

    -- Right, after clicking a crafter: the recipes they have shared.
    p.back = W.Button(p, "Back", 60, 18, function()
        viewing = nil
        p.search:SetText("")
        ns.UI.Refresh()
    end)
    p.back:SetPoint("TOPLEFT", 212, -30)
    p.who = W.Text(p, "", "GameFontNormalSmall")
    p.who:SetPoint("TOPLEFT", 282, -33)
    p.recipes = W.List(p, 480, 300, 18, function(row, r)
        p.recipes.Col(row, 1, 8, 440):SetText(U.Safe(r.name, 80))
        row:SetScript("OnEnter", function(self)
            local item = self.item
            if not item or not GameTooltip.SetSpellByID then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if pcall(GameTooltip.SetSpellByID, GameTooltip, item.id) then GameTooltip:Show() end
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
    end)
    p.recipes:Stretch(206, -52, 0, 22)
    p.recipes.key = "id"
    p.empty = W.Text(p, "", "GameFontHighlightSmall")
    p.empty:SetPoint("TOPLEFT", 214, -60)
    p.empty:SetWidth(460)
    p.empty:SetWordWrap(true)

    p.foot = W.Text(p, "", "GameFontDisableSmall")
    p.foot:SetPoint("BOTTOMLEFT", 0, 2)
end, function(p)
    local st = Red.State()
    local profs = st and st.profs or {}
    local opts = { online = onlineOnly, hideAlts = not showAlts, alts = st and st.alts or {}, filter = search, asc = ascending }
    local groups, shared = P.Groups(ns.roster.byGUID, profs, opts)
    if not chosen then
        for _, g in ipairs(groups) do
            if g.count > 0 then chosen = g.name; break end
        end
        chosen = chosen or groups[1].name
    end
    local pick
    for _, g in ipairs(groups) do if g.name == chosen then pick = g end end
    p.groups.selected = pick
    p.groups:SetItems(groups)

    -- Recipes of one crafter, when one is picked and still has this profession.
    local crafter
    if viewing then
        for _, s in ipairs(P.Skills(profs[viewing])) do
            if s.name == chosen then crafter = s end
        end
        if not (crafter and ns.roster.byGUID[viewing]) then viewing, crafter = nil, nil end
    end
    local inRecipes = crafter ~= nil
    p.title:SetShown(not inRecipes)
    p.sort:SetShown(not inRecipes)
    p.crafters.scroll:SetShown(not inRecipes)
    p.back:SetShown(inRecipes)
    p.who:SetShown(inRecipes)
    p.recipes.scroll:SetShown(inRecipes)
    p.empty:SetShown(false)

    local total = 0
    for _ in pairs(ns.roster.byGUID) do total = total + 1 end
    local line = shared .. " of " .. total .. " members have shared their professions."
    if not ns.mock and not profs[ns.MyGUID()] then
        line = line .. " Yours aren't shared yet: type /bp prof."
    end
    p.foot:SetText(line)

    if inRecipes then
        local name = U.Safe(ns.roster.byGUID[viewing].name or "?", 40)
        local set = st.recipes[viewing] and st.recipes[viewing][chosen]
        local known = ns.Recipes.Count(st, viewing, chosen)
        local list = ns.Recipes.List(set, search, ns.Recipes.Name)
        p.recipes:SetItems(list)
        p.who:SetText(name .. ": " .. chosen .. " " .. crafter.level .. (crafter.max and (" / " .. crafter.max) or ""))
        if known == 0 then
            p.recipes.scroll:SetShown(false)
            p.empty:SetShown(true)
            if P.NO_RECIPES[chosen] then
                p.empty:SetText(chosen .. " has no recipes to list.")
            elseif viewing == ns.MyGUID() then
                p.empty:SetText("Open your " .. chosen .. " window once. Blood Pact records your recipes then and shares them with the guild.")
            else
                p.empty:SetText(name .. " hasn't shared " .. chosen .. " recipes yet. They're recorded the first time "
                    .. name .. " opens the " .. chosen .. " window with Blood Pact 0.10 or newer.")
            end
            p.count:SetText("")
        else
            p.count:SetText(#list == known and (known .. (known == 1 and " recipe" or " recipes")) or (#list .. " of " .. known .. " recipes"))
        end
        return
    end

    local rows = P.Crafters(ns.roster.byGUID, profs, chosen, opts)
    for _, r in ipairs(rows) do r.recipes = ns.Recipes.Count(st, r.guid, chosen) end
    p.crafters:SetItems(rows)
    p.title:SetText(chosen)
    p.sort:SetSort(ascending and "up" or "down")
    p.count:SetText(#rows .. (#rows == 1 and " member" or " members") .. " with " .. chosen)
end)
