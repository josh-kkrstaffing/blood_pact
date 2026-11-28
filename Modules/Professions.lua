-- Speakeasy: professions on the roster.
-- Each player's own addon reads their skill levels from the game (nobody else
-- can) and shares them with the guild: up to two professions plus First Aid,
-- Cooking and Fishing. Shared when they change, at most once an hour.
-- Skill names are matched in English, like the rest of Speakeasy for now.
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

-- The steps a crafter follows to put their recipes in Speakeasy.
P.HOWTO = {
    "1. Open your character's Professions (the Professions button, or Character > Professions).",
    "2. Click the link bubble on a profession to open its recipe window.",
    "3. Speakeasy records the recipes and shares them with the guild. Do it once for each profession.",
    "New recipes are added the next time you open that window.",
}
P.HOWTO_SHORT = "To share your recipes: open Character > Professions, click the link bubble on each profession. Speakeasy syncs them."
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
    -- "Already shared" is only true if the guild's records still hold it. If
    -- they were lost or reset, share again.
    local st = ns.Reducer.State()
    if st and not st.profs[ns.MyGUID()] then c.profs, c.profsAt = nil, nil end
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
        ns.Print(sharedNow and (ns.Comm.QueueLength() > 0 and "Shared. It reaches the guild when the game lets addon messages through (not inside an instance or battleground)."
            or "Shared with the guild.") or (have and "Already shared; nothing changed."
            or ("Not shared. Role: %s. Guild data: %s. Type /bp status and send the lines to the addon's author."):format(
                tostring(ns.RBAC.RoleOf(ns.MyGUID()) or "none yet"), ns.G() and "loaded" or "not loaded")))
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
local date = date or os.date   -- WoW global; os.date in tests
local chosen, search, onlineOnly, showAlts, ascending = nil, "", false, true, false
local viewing = nil            -- guid of the crafter whose recipes are shown
local view = "dir"             -- "dir" (crafters) or "orders"
local picked = nil             -- recipe id chosen for the order bar
local mats = "me"              -- who supplies the materials on a new order
local which, selOrder = nil, nil      -- which Orders list; nil = pick one on first open
local nProf, nPick, nWho, nFilter = nil, nil, nil, ""   -- New order: profession, recipe, crafter asked, search
local BAR_W = 130

-- Sortable headers over a recipe list: Craft, Cost to Craft, Buy It Now, Net
-- Profit. Both recipe lists share one sort. cols = { { key, x, width } }.
local rSortKey, rSortDesc = "name", false
local HEAD_TEXT = { name = "Craft", cost = "Cost to Craft", buy = "Buy It Now", net = "Net Profit", vendor = "Vendor" }
local function recipeHeads(parent, cols, y)
    local heads = {}
    for i, c in ipairs(cols) do
        local b = W.SortButton(parent, HEAD_TEXT[c[1]], c[3], function()
            if rSortKey == c[1] then
                rSortDesc = not rSortDesc
            else
                rSortKey, rSortDesc = c[1], c[1] ~= "name"      -- prices start highest first
            end
            ns.UI.Refresh()
        end)
        b.key = c[1]
        b:SetPoint("TOPLEFT", c[2], y)
        heads[i] = b
    end
    function heads.SetShown(on)
        for _, b in ipairs(heads) do
            b:SetShown(on)
            b:SetSort(b.key == rSortKey and (rSortDesc and "down" or "up") or nil)
        end
    end
    return heads
end

ns.UI.AddTab("profs", "Professions", "view", function(p)
    local Orders = ns.Orders
    p.dirBtn = W.Button(p, "Crafters", 90, 22, function() view = "dir"; ns.UI.Refresh() end)
    p.dirBtn:SetPoint("TOPLEFT", 0, 0)
    p.ordBtn = W.Button(p, "Orders", 110, 22, function() view = "orders"; ns.UI.Refresh() end)
    p.ordBtn:SetPoint("TOPLEFT", 94, 0)

    -- Crafters: the guild by profession, and each crafter's recipes.
    local d = CreateFrame("Frame", nil, p)
    d:SetPoint("TOPLEFT", 0, -28)
    d:SetPoint("BOTTOMRIGHT", 0, 0)
    p.dir = d
    p.searchLabel = W.Text(d, "Search", "GameFontHighlightSmall")
    p.searchLabel:SetPoint("TOPLEFT", 0, -5)
    p.search = W.Edit(d, 130, 30)
    p.search:SetPoint("TOPLEFT", 44, -1)
    p.search:SetScript("OnTextChanged", function(self)
        search = (self:GetText() or ""):lower()
        ns.UI.Refresh()
    end)
    p.online = W.Check(d, "Online only", function(on) onlineOnly = on; ns.UI.Refresh() end)
    p.online:SetPoint("TOPLEFT", 192, -4)
    p.alts = W.Check(d, "Show alts", function(on) showAlts = on; ns.UI.Refresh() end)
    p.alts:SetPoint("TOPLEFT", 296, -4)
    p.alts:SetChecked(true)
    p.count = W.Text(d, "", "GameFontDisableSmall")
    p.count:SetPoint("TOPLEFT", 392, -5)

    -- Left: the professions.
    p.groups = W.List(d, 176, 300, 20, function(row, g)
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
    end, function(g) chosen = g.name; viewing, picked = nil, nil; ns.UI.Refresh() end)
    p.groups:Stretch(0, -30, nil, 22)
    p.groups.key = "name"

    -- Right: who has the chosen profession.
    p.title = W.Text(d, "", "GameFontNormalSmall")
    p.title:SetPoint("TOPLEFT", 212, -33)
    p.sort = W.SortButton(d, "Level", 70, function() ascending = not ascending; ns.UI.Refresh() end)
    p.sort:SetPoint("TOPLEFT", 418, -30)
    p.crafters = W.List(d, 480, 300, 20, function(row, r)
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
        viewing, picked = r.guid, nil
        p.search:SetText("")          -- the box searches recipes now, not players
        ns.UI.Refresh()
    end)
    p.crafters:Stretch(206, -52, 0, 22)
    p.crafters.key = "guid"

    -- Right, after clicking a crafter: the recipes they have shared.
    p.back = W.Button(d, "Back", 60, 18, function()
        viewing, picked = nil, nil
        p.search:SetText("")
        ns.UI.Refresh()
    end)
    p.back:SetPoint("TOPLEFT", 212, -30)
    p.who = W.Text(d, "", "GameFontNormalSmall")
    p.who:SetPoint("TOPLEFT", 282, -33)
    p.recipes = W.List(d, 480, 300, 18, function(row, r)
        p.recipes.Col(row, 1, 8, 184):SetText(U.Safe(r.name, 80))
        local cost = p.recipes.Col(row, 2, 196, 84, "RIGHT")
        cost:SetText(Orders.CostText(r.id, 1) or "")
        cost:SetTextColor(W.C.muted[1], W.C.muted[2], W.C.muted[3])
        local buy = p.recipes.Col(row, 3, 284, 78, "RIGHT")
        buy:SetText(Orders.BuyText(r.id) or "")
        buy:SetTextColor(W.C.muted[1], W.C.muted[2], W.C.muted[3])
        p.recipes.Col(row, 4, 366, 84, "RIGHT"):SetText(Orders.NetText(r.id) or "")
        local vend = p.recipes.Col(row, 5, 454, 72, "RIGHT")
        vend:SetText(Orders.VendorText(r.id) or "")
        vend:SetTextColor(W.C.muted[1], W.C.muted[2], W.C.muted[3])
        if not row.order then
            -- "Order" on the right of every recipe: picks it for the order bar below.
            row.order = W.Button(row, "Order", 54, 16, function()
                if row.item then picked = row.item.id; ns.UI.Refresh() end
            end)
            row.order:SetPoint("RIGHT", -4, 0)
            row:SetScript("OnEnter", function(self)
                local item = self.item
                if not item or not GameTooltip.SetSpellByID then return end
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")      -- to the left, so it stays on screen
                if pcall(GameTooltip.SetSpellByID, GameTooltip, item.id) then GameTooltip:Show() end
            end)
            row:SetScript("OnLeave", GameTooltip_Hide)
        end
        row.order:SetShown(viewing ~= ns.MyGUID())
        -- On my own list: tick the recipes to link when I advertise in Trade chat.
        if not row.link then
            row.link = W.Button(row, "Link", 54, 16, function()
                if not (row.item and chosen) then return end
                local ok, why = ns.Advert.ToggleLink(chosen, row.item.id)
                if not ok then ns.UI.Say(why) end
                ns.UI.Refresh()
            end)
            row.link:SetPoint("RIGHT", -4, 0)
        end
        -- "Mats": what this recipe needs, and buying it at the auction house.
        if not row.mats then
            row.mats = W.Button(row, "Mats", 44, 16, function()
                if row.item and ns.Shop then ns.Shop.Open(row.item.id) end
            end)
            row.mats:SetPoint("RIGHT", -62, 0)
        end
        row.mats:SetShown(ns.Recipes.Reagents(r.id) ~= nil)
        local own = viewing == ns.MyGUID()
        row.link:SetShown(own)
        if own then row.link:SetText(ns.Advert.IsLinked(chosen, r.id) and "|cff40ff40Linked|r" or "Link") end
    end, function(r) picked = r.id; ns.UI.Refresh() end)
    p.recipes:Stretch(206, -72, 0, 100)
    p.recipeHead = recipeHeads(d, { { "name", 208, 186 }, { "cost", 402, 84 }, { "buy", 490, 78 }, { "net", 572, 84 }, { "vendor", 660, 72 } }, -52)
    p.recipes.key = "id"

    -- Under my own recipes: advertise in Trade chat.
    local ad = CreateFrame("Frame", nil, d)
    ad:SetPoint("BOTTOMLEFT", 206, 24)
    ad:SetPoint("BOTTOMRIGHT", 0, 24)
    ad:SetHeight(72)
    p.ad = ad
    p.adPreview = W.Text(ad, "", "GameFontHighlightSmall")
    p.adPreview:SetPoint("TOPLEFT", 0, 0)
    p.adPreview:SetPoint("RIGHT", 0, 0)
    p.adPreview:SetWordWrap(false)
    W.Text(ad, "Extra words", "GameFontDisableSmall"):SetPoint("TOPLEFT", 0, -24)
    p.adExtra = W.Edit(ad, 240, ns.Advert.EXTRA_MAX)
    p.adExtra:SetPoint("TOPLEFT", 70, -20)
    p.adExtra:SetScript("OnTextChanged", function(self, byUser)
        if byUser then ns.Char().adExtra = self:GetText(); ns.UI.RefreshSoon() end
    end)
    p.adPost = W.Button(ad, "Post in Trade chat", 150, 22, function()
        if not (p.adSkill and chosen) then return end
        local line, why = ns.Advert.Post(chosen, p.adSkill)
        ns.UI.Say(line or why or "That didn't work.")
    end, "accent")
    p.adPost:SetPoint("TOPLEFT", 320, -20)
    p.adHint = W.Text(ad, "", "GameFontDisableSmall")
    p.adHint:SetPoint("TOPLEFT", 0, -50)

    -- Order bar under the recipes: quantity, who supplies the mats, a note, send.
    local ob = CreateFrame("Frame", nil, d)
    ob:SetPoint("BOTTOMLEFT", 206, 24)
    ob:SetPoint("BOTTOMRIGHT", 0, 24)
    ob:SetHeight(72)
    p.ob = ob
    p.oCost = W.Text(ob, "", "GameFontDisableSmall")
    p.oCost:SetPoint("TOPLEFT", 0, -56)
    p.oCost:SetWidth(500)
    p.oCost:SetWordWrap(false)
    p.oName = W.Text(ob, "", "GameFontNormalSmall")
    p.oName:SetPoint("TOPLEFT", 0, -4)
    p.oName:SetWidth(250)
    p.oName:SetWordWrap(false)
    W.Text(ob, "Qty", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 258, -4)
    p.qty = W.Edit(ob, 34, 2)
    p.qty:SetPoint("TOPLEFT", 284, 0)
    p.qty:SetText("1")
    p.matsBtn = W.Button(ob, "", 160, 22, function()
        for i, key in ipairs(Orders.MATS_ORDER) do
            if key == mats then mats = Orders.MATS_ORDER[i % #Orders.MATS_ORDER + 1]; break end
        end
        ns.UI.Refresh()
    end)
    p.matsBtn:SetPoint("TOPLEFT", 326, 0)
    W.Text(ob, "Note", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 0, -30)
    p.oNote = W.Edit(ob, 190, 120)
    p.oNote:SetPoint("TOPLEFT", 34, -26)
    local function place(to, okMsg)
        if not picked then ns.UI.Say("Click a recipe first.") return end
        if ns.UI.Try(okMsg, Orders.Create, picked, chosen, tonumber(p.qty:GetText()), mats, p.oNote:GetText(), to) then
            picked = nil
            p.oNote:SetText("")
            p.qty:SetText("1")
            ns.UI.Refresh()
        end
    end
    p.orderBtn = W.Button(ob, "Order", 150, 22, function()
        place(viewing, "Order placed. Track it under Orders.")
    end, "accent")
    p.orderBtn:SetPoint("TOPLEFT", 232, -26)
    p.wantBtn = W.Button(ob, "Post as Wanted", 120, 22, function()
        place(nil, "Posted on the Wanted board for any guild crafter who knows it.")
    end)
    p.wantBtn:SetPoint("TOPLEFT", 386, -26)
    p.empty = W.Text(d, "", "GameFontHighlightSmall")
    p.empty:SetPoint("TOPLEFT", 214, -60)
    p.empty:SetWidth(460)
    p.empty:SetWordWrap(true)

    p.foot = W.Text(d, "", "GameFontDisableSmall")
    p.foot:SetPoint("BOTTOMLEFT", 0, 2)
    -- How a crafter gets their recipes into Speakeasy: hover for the steps.
    p.howTo = W.Button(d, "How do I share my recipes?", 190, 20, function()
        ns.UI.Say(P.HOWTO_SHORT)
    end)
    p.howTo:SetPoint("BOTTOMRIGHT", 0, 0)
    p.howTo:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:AddLine("Share your recipes with the guild")
        for _, l in ipairs(P.HOWTO) do GameTooltip:AddLine(l, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    p.howTo:HookScript("OnLeave", GameTooltip_Hide)

    -- Orders: what I should craft, what I asked for, the Wanted board, history.
    local o = CreateFrame("Frame", nil, p)
    o:SetPoint("TOPLEFT", 0, -28)
    o:SetPoint("BOTTOMRIGHT", 0, 0)
    p.ord = o
    p.filters = {}
    local x = 0
    for _, f in ipairs({ { "new", "New order", 100 }, { "craft", "To craft", 110 }, { "mine", "My requests", 124 }, { "wanted", "Wanted board", 124 }, { "history", "History", 80 } }) do
        local b = W.Button(o, f[2], f[3], 22, function() which = f[1]; selOrder = nil; ns.UI.Refresh() end)
        b:SetPoint("TOPLEFT", x, 0)
        b.key, b.label = f[1], f[2]
        p.filters[#p.filters + 1] = b
        x = x + f[3] + 4
    end
    p.orders = W.List(o, 690, 220, 20, function(row, r)
        local now = ns.Now()
        p.orders.Col(row, 1, 6, 206):SetText(U.Safe(Orders.ItemText(r), 60))
        p.orders.Col(row, 2, 216, 108):SetText(U.Safe(Orders.NameOf(r.by), 30))
        local who = r.crafter or r.to
        local c3 = p.orders.Col(row, 3, 328, 108)
        c3:SetText(who and U.Safe(Orders.NameOf(who), 30) or "anyone")
        local m = W.C[who and "text" or "muted"]
        c3:SetTextColor(m[1], m[2], m[3])
        local text, tone = Orders.StatusText(r, now, Orders.NameOf)
        local c4 = p.orders.Col(row, 4, 440, 160)
        c4:SetText(U.Safe(text, 40))
        if tone == "late" then
            c4:SetTextColor(1, 0.3, 0.3)
        elseif tone == "good" then
            c4:SetTextColor(0.35, 0.9, 0.45)
        elseif tone == "transit" then
            c4:SetTextColor(W.C.gold[1], W.C.gold[2], W.C.gold[3])
        elseif tone == "muted" then
            c4:SetTextColor(W.C.muted[1], W.C.muted[2], W.C.muted[3])
        else
            c4:SetTextColor(W.C.text[1], W.C.text[2], W.C.text[3])
        end
        local c5 = p.orders.Col(row, 5, 604, 90)
        c5:SetText(r.mats == "me" and "their mats" or (r.mats == "crafter" and "crafter's mats" or "bank mats"))
        c5:SetTextColor(W.C.muted[1], W.C.muted[2], W.C.muted[3])
    end, function(r) selOrder = r.id; ns.UI.Refresh() end)
    p.orders:Stretch(0, -28, 0, 88)
    p.orders.key = "id"
    p.oEmpty = W.Text(o, "", "GameFontHighlightSmall")
    p.oEmpty:SetPoint("TOPLEFT", 6, -36)
    p.oEmpty:SetWidth(640)

    local act = CreateFrame("Frame", nil, o)
    p.act = act
    act:SetPoint("BOTTOMLEFT", 0, 0)
    act:SetPoint("BOTTOMRIGHT", 0, 0)
    act:SetHeight(82)
    p.oDetail = W.Text(act, "", "GameFontHighlightSmall")
    p.oDetail:SetPoint("TOPLEFT", 0, 0)
    p.oDetail:SetWidth(690)
    p.oDetail:SetHeight(28)
    p.oDetail:SetJustifyV("TOP")
    W.Text(act, "Note", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 0, -62)
    p.stNote = W.Edit(act, 260, 120)
    p.stNote:SetPoint("TOPLEFT", 34, -58)
    W.Text(act, "Optional. Sent with the next button you press.", "GameFontDisableSmall"):SetPoint("TOPLEFT", 304, -62)
    local function step(action, hours, okMsg)
        return function()
            if not selOrder then return end
            if ns.UI.Try(okMsg, Orders.Update, selOrder, action, hours, p.stNote:GetText()) then
                p.stNote:SetText("")
                ns.UI.Refresh()
            end
        end
    end
    p.steps = {}
    local function add(key, label, width, fn, style)
        local b = W.Button(act, label, width, 22, fn, style)
        b.key = key
        p.steps[#p.steps + 1] = b
        return b
    end
    for _, h in ipairs(Orders.HOURS) do
        add("accept", (h == 2 and "Accept, ready in 2h" or (h .. "h")), h == 2 and 140 or 46,
            step("accept", h, "Accepted. The member who asked can see when you'll have it."))
    end
    add("decline", "Can't make it", 100, step("decline", nil, "Declined. The member who asked is told."))
    add("ready", "Mark ready", 90, step("ready", nil, "Marked ready. Trade or mail it to them."))
    add("release", "Hand back", 84, step("release", nil, "Handed back."))
    add("deliver", "I received it", 100, step("deliver", nil, "Marked delivered. Thanks for confirming."), "accent")
    local cancel = add("cancel", "Cancel order", 110, nil)
    cancel:SetScript("OnClick", ns.UI.Confirm(cancel, step("cancel", nil, "Order cancelled.")))

    -- New order: pick a profession, then any recipe the guild knows, then ask
    -- any guild crafter (Wanted board) or one crafter by name.
    local nf = CreateFrame("Frame", nil, o)
    nf:SetPoint("TOPLEFT", 0, -28)
    nf:SetPoint("BOTTOMRIGHT", 0, 0)
    p.nf = nf
    p.nProfs = W.List(nf, 176, 300, 20, function(row, g)
        if not row.icon then
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(16, 16)
            row.icon:SetPoint("LEFT", 4, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        local icon = P.ICON[g.name]
        row.icon:SetShown(icon ~= nil)
        if icon then row.icon:SetTexture("Interface\\Icons\\" .. icon) end
        p.nProfs.Col(row, 1, 26, 112):SetText(g.name)
        p.nProfs.Col(row, 2, 138, 30, "RIGHT"):SetText(g.count)
    end, function(g) nProf, nPick, nWho = g.name, nil, nil; ns.UI.Refresh() end)
    p.nProfs:Stretch(0, 0, nil, 0)
    p.nProfs.key = "name"
    W.Text(nf, "Search", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 212, -5)
    p.nSearch = W.Edit(nf, 150, 30)
    p.nSearch:SetPoint("TOPLEFT", 256, -1)
    p.nSearch:SetScript("OnTextChanged", function(self)
        nFilter = (self:GetText() or ""):lower()
        ns.UI.Refresh()
    end)
    p.nCount = W.Text(nf, "", "GameFontDisableSmall")
    p.nCount:SetPoint("TOPLEFT", 416, -5)
    p.nRecipes = W.List(nf, 480, 240, 18, function(row, r)
        p.nRecipes.Col(row, 1, 8, 164):SetText(U.Safe(r.name, 80))
        local who = p.nRecipes.Col(row, 2, 176, 106)
        who:SetText(#r.crafters .. (#r.crafters == 1 and " crafter" or " crafters") .. (r.online > 0 and (", " .. r.online .. " online") or ""))
        local tone = r.online > 0 and W.C.text or W.C.muted
        who:SetTextColor(tone[1], tone[2], tone[3])
        local cost = p.nRecipes.Col(row, 3, 284, 84, "RIGHT")
        cost:SetText(Orders.CostText(r.id, 1) or "")
        cost:SetTextColor(W.C.muted[1], W.C.muted[2], W.C.muted[3])
        local buy = p.nRecipes.Col(row, 4, 372, 78, "RIGHT")
        buy:SetText(Orders.BuyText(r.id) or "")
        buy:SetTextColor(W.C.muted[1], W.C.muted[2], W.C.muted[3])
        p.nRecipes.Col(row, 5, 454, 84, "RIGHT"):SetText(Orders.NetText(r.id) or "")
        local vend = p.nRecipes.Col(row, 6, 542, 66, "RIGHT")
        vend:SetText(Orders.VendorText(r.id) or "")
        vend:SetTextColor(W.C.muted[1], W.C.muted[2], W.C.muted[3])
        if not row.hooked then
            row.hooked = true
            row:SetScript("OnEnter", function(self)
                local item = self.item
                if not item or not GameTooltip.SetSpellByID then return end
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                if pcall(GameTooltip.SetSpellByID, GameTooltip, item.id) then GameTooltip:Show() end
            end)
            row:SetScript("OnLeave", GameTooltip_Hide)
        end
    end, function(r) nPick, nWho = r.id, nil; ns.UI.Refresh() end)
    p.nRecipes:Stretch(206, -46, 0, 86)
    p.nRecipeHead = recipeHeads(nf, { { "name", 208, 166 }, { "cost", 490, 84 }, { "buy", 578, 78 }, { "net", 660, 84 }, { "vendor", 748, 66 } }, -26)
    p.nRecipes.key = "id"
    p.nEmpty = W.Text(nf, "", "GameFontHighlightSmall")
    p.nEmpty:SetPoint("TOPLEFT", 214, -50)
    p.nEmpty:SetWidth(460)
    p.nEmpty:SetWordWrap(true)

    local nb = CreateFrame("Frame", nil, nf)
    nb:SetPoint("BOTTOMLEFT", 206, 0)
    nb:SetPoint("BOTTOMRIGHT", 0, 0)
    nb:SetHeight(80)
    p.nb = nb
    p.nName = W.Text(nb, "", "GameFontNormalSmall")
    p.nName:SetPoint("TOPLEFT", 0, -4)
    p.nName:SetWidth(250)
    p.nName:SetWordWrap(false)
    W.Text(nb, "Qty", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 258, -4)
    p.nQty = W.Edit(nb, 34, 2)
    p.nQty:SetPoint("TOPLEFT", 284, 0)
    p.nQty:SetText("1")
    p.nQty:HookScript("OnTextChanged", function() ns.UI.RefreshSoon() end)
    p.nMats = W.Button(nb, "", 160, 22, function()
        for i, key in ipairs(Orders.MATS_ORDER) do
            if key == mats then mats = Orders.MATS_ORDER[i % #Orders.MATS_ORDER + 1]; break end
        end
        ns.UI.Refresh()
    end)
    p.nMats:SetPoint("TOPLEFT", 326, 0)
    W.Text(nb, "Ask", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 0, -32)
    -- Cycles: any guild crafter, then each crafter who knows the recipe.
    p.nWho = W.Button(nb, "", 190, 22, function()
        local list = p.nCrafters or {}
        local at = 0
        for i, guid in ipairs(list) do if guid == nWho then at = i end end
        nWho = list[at + 1]
        ns.UI.Refresh()
    end)
    p.nWho:SetPoint("TOPLEFT", 34, -28)
    W.Text(nb, "Note", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 232, -32)
    p.nNote = W.Edit(nb, 150, 120)
    p.nNote:SetPoint("TOPLEFT", 266, -28)
    p.nCost = W.Text(nb, "", "GameFontDisableSmall")
    p.nCost:SetPoint("TOPLEFT", 0, -60)
    p.nCost:SetWidth(380)
    p.nCost:SetWordWrap(false)
    p.nPlace = W.Button(nb, "Place order", 110, 22, function()
        if not (nPick and nProf) then ns.UI.Say("Click a recipe first.") return end
        local ok = ns.UI.Try(nWho and "Order placed. Track it under My requests."
            or "Posted on the Wanted board. Guild crafters who know it are told.",
            Orders.Create, nPick, nProf, tonumber(p.nQty:GetText()), mats, p.nNote:GetText(), nWho)
        if ok then
            nPick, nWho = nil, nil
            p.nNote:SetText("")
            p.nQty:SetText("1")
            ns.UI.Refresh()
        end
    end, "accent")
    p.nPlace:SetPoint("TOPLEFT", 396, -54)
end, function(p)
    local st = Red.State()
    local Orders = ns.Orders
    local me = ns.MyGUID()
    local needs = Orders.Needs(st, me)
    p.ordBtn:SetText(needs > 0 and ("Orders (" .. needs .. ")") or "Orders")
    p.dirBtn:SetEnabled(view ~= "dir")
    p.ordBtn:SetEnabled(view ~= "orders")
    p.dir:SetShown(view == "dir")
    p.ord:SetShown(view == "orders")

    if view == "orders" then
        local now = ns.Now()
        -- First open: go to what needs me, or straight to placing an order.
        if not which then which = (#Orders.Rows(st, me, "craft") > 0 or #Orders.Rows(st, me, "mine") > 0) and "craft" or "new" end
        local placing = which == "new"
        p.nf:SetShown(placing)
        p.act:SetShown(not placing)
        p.orders.scroll:SetShown(not placing)
        for _, b in ipairs(p.filters) do
            local n = 0
            if b.key ~= "history" and b.key ~= "new" then
                -- An order in the mail is listed under To craft but no longer counts as work to do.
                for _, r in ipairs(Orders.Rows(st, me, b.key)) do
                    if not (b.key == "craft" and Orders.InTransit(r)) then n = n + 1 end
                end
            end
            b:SetText(n > 0 and (b.label .. " (" .. n .. ")") or b.label)
            b:SetEnabled(b.key ~= which)
        end
        if placing then
            p.oEmpty:SetShown(false)
            local roster = ns.roster.byGUID
            local profs = ns.Recipes.GuildProfs(st, roster)
            local pick
            for _, g in ipairs(profs) do if g.name == nProf then pick = g end end
            if not pick then pick, nPick, nWho = profs[1], nil, nil end
            nProf = pick and pick.name or nil
            p.nProfs.selected = pick
            p.nProfs:SetItems(profs)
            local list = nProf and ns.Recipes.GuildRecipes(st, roster, nProf, nFilter, ns.Recipes.Name) or {}
            Orders.SortRecipes(list, rSortKey, rSortDesc, Orders.Numbers)
            local sel
            for _, r in ipairs(list) do if r.id == nPick then sel = r end end
            if not sel then nPick, nWho = nil, nil end
            p.nRecipes.selected = sel
            p.nRecipes:SetItems(list)
            p.nCount:SetText(nProf and (#list .. (#list == 1 and " recipe" or " recipes") .. " the guild can make") or "")
            p.nEmpty:SetShown(#profs == 0)
            p.nRecipeHead.SetShown(#list > 0)
            p.nEmpty:SetText("No recipes shared yet. They appear here once guild crafters open their profession windows with Speakeasy.")
            p.nb:SetShown(#profs > 0)
            -- Who can be asked: every crafter who knows it, except me.
            p.nCrafters = {}
            for _, guid in ipairs(sel and sel.crafters or {}) do
                if guid ~= me then p.nCrafters[#p.nCrafters + 1] = guid end
            end
            local stillThere = false
            for _, guid in ipairs(p.nCrafters) do if guid == nWho then stillThere = true end end
            if not stillThere then nWho = nil end
            local qty = tonumber(p.nQty:GetText()) or 1
            p.nName:SetText(sel and ("Order: " .. U.Safe(sel.name, 60)) or "Click a recipe to order it.")
            p.nMats:SetText(Orders.MATS[mats])
            p.nWho:SetText(nWho and U.Safe(Orders.NameOf(nWho), 22) or "Any guild crafter")
            p.nWho:SetEnabled(sel ~= nil and #p.nCrafters > 0)
            p.nPlace:SetEnabled(sel ~= nil)
            p.nCost:SetText(sel and (Orders.CostText(sel.id, qty, true) or "") or "")
            return
        end
        local rows = Orders.Rows(st, me, which)
        local sel
        for _, r in ipairs(rows) do if r.id == selOrder then sel = r end end
        selOrder = sel and sel.id or nil
        p.orders.selected = sel
        p.orders:SetItems(rows)
        p.oEmpty:SetShown(#rows == 0)
        p.oEmpty:SetText(which == "craft" and "Nothing waiting for you to craft. Orders asked of you, and Wanted orders for recipes you've shared, show here."
            or which == "mine" and "You have no orders open. Find a recipe under Crafters and press Order."
            or which == "wanted" and "The Wanted board is empty. Post a request from any crafter's recipe list."
            or "No finished orders yet.")
        local allowed = {}
        if sel then
            local canCraft = Orders.CanCraft(st, me, sel)
            allowed = Orders.Actions(sel, me, ns.RBAC.ICan("void"), canCraft)
            local parts = { U.Safe(Orders.ItemText(sel), 60) .. " for " .. U.Safe(Orders.NameOf(sel.by), 30) .. ". "
                .. Orders.MATS[sel.mats] .. ". Asked " .. date("%b %d", sel.t) .. "." }
            if sel.ask then parts[#parts + 1] = "They said: " .. U.Safe(sel.ask, 120) end
            if sel.note then parts[#parts + 1] = "Crafter's note: " .. U.Safe(sel.note, 120) end
            if sel.status == "open" and sel.to == nil and sel.by ~= me and not canCraft then
                parts[#parts + 1] = "You haven't shared this recipe, so you can't take it."
            end
            if Orders.IsLate(sel, now) then parts[#parts + 1] = "Past the promised time." end
            if Orders.InTransit(sel) then
                parts[#parts + 1] = sel.by == me and "It's in the mail. Collect it at a mailbox, then press I received it."
                    or "In the mail. It's complete when they press I received it."
            elseif sel.crafter == me and (sel.status == "accepted" or sel.status == "ready") then
                parts[#parts + 1] = "At a mailbox, Speakeasy fills in the mail for this order; you press Send."
            end
            local cost = Orders.IsActive(sel) and Orders.CostText(sel.rid, sel.q)
            if cost then parts[#parts + 1] = "Est. materials " .. cost .. "." end
            p.oDetail:SetText(table.concat(parts, " "))
        else
            p.oDetail:SetText(#rows > 0 and "Click an order to see what you can do with it." or "")
        end
        -- Lay the allowed buttons out left to right.
        local x = 0
        for _, b in ipairs(p.steps) do
            local show = allowed[b.key] or (b.key == "cancel" and allowed.moderate) or false
            b:SetShown(show)
            if show then
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", x, -32)
                x = x + b:GetWidth() + 4
            end
        end
        return
    end

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
    p.recipeHead.SetShown(inRecipes)
    p.empty:SetShown(false)
    p.ob:SetShown(false)
    p.ad:SetShown(false)

    local total = 0
    for _ in pairs(ns.roster.byGUID) do total = total + 1 end
    local line = shared .. " of " .. total .. " members have shared their professions."
    if not ns.mock and not profs[ns.MyGUID()] then
        line = line .. " Yours aren't shared yet: type /bp prof."
    elseif not ns.mock and next(st.recipes[ns.MyGUID()] or {}) == nil then
        line = line .. " Your recipes aren't shared yet: hover the button on the right."
    end
    p.foot:SetText(line)

    if inRecipes then
        local name = U.Safe(ns.roster.byGUID[viewing].name or "?", 40)
        local set = st.recipes[viewing] and st.recipes[viewing][chosen]
        local known = ns.Recipes.Count(st, viewing, chosen)
        local list = ns.Recipes.List(set, search, ns.Recipes.Name)
        Orders.SortRecipes(list, rSortKey, rSortDesc, Orders.Numbers)
        if picked and not (set and set[picked]) then picked = nil end
        local sel
        for _, r in ipairs(list) do if r.id == picked then sel = r end end
        p.recipes.selected = sel
        p.recipes:SetItems(list)
        -- The order bar: not for my own recipes.
        local canOrder = known > 0 and viewing ~= me
        p.ob:SetShown(canOrder)
        if canOrder then
            p.oName:SetText(picked and ("Order: " .. U.Safe(ns.Recipes.Name(picked) or ("Recipe " .. picked), 60)) or "Press Order on a recipe.")
            p.matsBtn:SetText(Orders.MATS[mats])
            p.orderBtn:SetText("Order from " .. name:sub(1, 14))
            p.orderBtn:SetEnabled(picked ~= nil)
            p.wantBtn:SetEnabled(picked ~= nil)
            p.oCost:SetText(picked and (Orders.CostText(picked, tonumber(p.qty:GetText()) or 1, true) or "") or "")
        end
        -- My own recipes: the Trade chat advert.
        local canAd = known > 0 and viewing == me
        p.ad:SetShown(canAd)
        if canAd then
            p.adSkill = crafter
            local lines = ns.Advert.Build(chosen, crafter)
            local n = #ns.Advert.Links(chosen)
            p.adPreview:SetText("Trade chat: " .. ns.Advert.Text(chosen, crafter.level, crafter.max, GetZoneText and GetZoneText() or "", ns.Advert.Extra())
                .. (n > 0 and ("  + %d linked"):format(n) or ""))
            if not p.adExtra:HasFocus() then p.adExtra:SetText(ns.Advert.Extra()) end
            p.adHint:SetText(("Press Link on up to %d recipes to show them in the post%s. One post a minute, in a city."):format(
                ns.Advert.MAX_LINKS, #lines > 1 and " (it goes out as two lines)" or ""))
        end
        p.who:SetText(name .. ": " .. chosen .. " " .. crafter.level .. (crafter.max and (" / " .. crafter.max) or ""))
        if known == 0 then
            p.recipes.scroll:SetShown(false)
            p.recipeHead.SetShown(false)
            p.empty:SetShown(true)
            if P.NO_RECIPES[chosen] then
                p.empty:SetText(chosen .. " has no recipes to list.")
            elseif viewing == ns.MyGUID() then
                p.empty:SetText("To share your " .. chosen .. " recipes: open Character > Professions and click the link bubble on "
                    .. chosen .. ". Speakeasy records them and shares them with the guild.")
            else
                p.empty:SetText(name .. " hasn't shared " .. chosen .. " recipes yet. They're recorded the first time "
                    .. name .. " opens the " .. chosen .. " window with Speakeasy 0.10 or newer.")
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

-- Five price columns need room: the window won't go narrower than this here.
P.MIN_W = 900
ns.UI.Need("profs", function() return nil, P.MIN_W end)
