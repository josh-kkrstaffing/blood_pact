-- Blood Pact: Raid Kit. The consumables every raider is expected to bring.
--
-- The rules are the guild leader's (Nov 25, 2026): the kit is required for
-- every rank and every raid; everyone brings a flask, elixirs, food and a
-- weapon buff to last the raid (3 hours); on progression nights potions and
-- runes are doubled; each raider pays for their own; Team Captains and above
-- change the list and see other people's kits; the ready-check result goes
-- to the raid leader only; missing a flask or food can cost 30 DKP.
--
-- What the game allows: an addon can count your own bags and bank and read
-- your own buffs out of combat. It cannot read the combat log, so nothing
-- here records each potion drunk. Nothing is used or bought for the player.
local _, ns = ...
local K = {}
ns.Kit = K

local U, RBAC, Red = ns.U, ns.RBAC, ns.Reducer

K.ROLES = { "tank", "str", "agi", "hunter", "caster", "healer" }
K.ROLE_LABEL = { tank = "Tank", str = "Melee, Strength", agi = "Melee, Agility", hunter = "Hunter",
    caster = "Caster DPS", healer = "Healer" }
K.CLASS_ROLE = { WARRIOR = "str", ROGUE = "agi", HUNTER = "hunter", MAGE = "caster", WARLOCK = "caster",
    PRIEST = "healer", PALADIN = "healer", SHAMAN = "healer", DRUID = "healer" }
K.RAIDS = { "Barrow Deeps", "Hyjal Summit", "Onyxia's Lair" }
K.KEEP_DAYS = 90

-- The lists from the guild's Raid Prep sheet, "Consumables by role".
-- mins = how long one lasts, so the count follows from the raid's length.
-- No mins = carried and used when needed: Team Captains set how many.
local function it(item, slot, mins) return { item = item, slot = slot, mins = mins } end
K.DEFAULT = {
    tank = { it("Flask of the Titans", "Flask", 120), it("Elixir of the Phalanx", "Elixir", 30),
        it("Major Troll's Blood Elixir", "Elixir", 60), it("Elixir of Brute Force", "Elixir", 60),
        it("Savory Turtle Stew", "Food", 15), it("Greater Stoneshield Potion", "Potion") },
    str = { it("Flask of the Titans", "Flask", 120), it("Elixir of the Grizzly", "Elixir", 30),
        it("Distilled Firewater", "Elixir", 20), it("Smoked Desert Dumplings", "Food", 15),
        it("Elemental Sharpening Stone", "Weapon", 30), it("Major Frenzy Potion", "Potion"),
        it("Mighty Rage Potion", "Potion") },
    agi = { it("Flask of the Titans", "Flask", 120), it("Elixir of the Mongoose", "Elixir", 30),
        it("Distilled Firewater", "Elixir", 20), it("Swiftstrike Steak", "Food", 15),
        it("Elemental Sharpening Stone", "Weapon", 30), it("Major Frenzy Potion", "Potion") },
    hunter = { it("Flask of the Titans", "Flask", 120), it("Elixir of the Mongoose", "Elixir", 30),
        it("Swiftstrike Steak", "Food", 15), it("Major Frenzy Potion", "Potion"), it("Major Mana Potion", "Potion") },
    caster = { it("Flask of Supreme Power", "Flask", 120), it("Greater Arcane Elixir", "Elixir", 60),
        it("Elixir of the Owl", "Elixir", 30), it("Elixir of Shadow Power", "Elixir", 30),
        it("Lobster Stew", "Food", 15), it("Brilliant Wizard Oil", "Weapon", 30),
        it("Major Spellblasting Potion", "Potion"), it("Major Mana Potion", "Potion"), it("Demonic Rune", "Rune") },
    healer = { it("Flask of Distilled Wisdom", "Flask", 120), it("Greater Cleric's Elixir", "Elixir", 30),
        it("Greater Mageblood Elixir", "Elixir", 30), it("Elixir of the Owl", "Elixir", 30),
        it("Sage's Tea", "Food", 15), it("Brilliant Mana Oil", "Weapon", 30),
        it("Major Mender's Potion", "Potion"), it("Major Mana Potion", "Potion"), it("Dark Rune", "Rune") },
}

---------------------------------------------------------------------------
-- Pure rules (tested without the game)
---------------------------------------------------------------------------
function K.RaidKey(raid) return raid and ("raid:" .. raid):sub(1, 30) or nil end

-- The kit list for a role: the built-in list, with the Team Captains' changes,
-- plus anything they added for this raid (fire protection for Onyxia, say).
function K.List(st, role, raid)
    local out, at = {}, {}
    for _, d in ipairs(K.DEFAULT[role] or {}) do
        out[#out + 1] = { item = d.item, slot = d.slot, mins = d.mins }
        at[d.item] = #out
    end
    local function apply(changes, extra)
        local names = {}
        for name in pairs(changes or {}) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local c = changes[name]
            local i = at[name]
            if not c.on then
                if i then out[i].off = true end
            elseif i then
                out[i].off = nil
                if c.mins then out[i].mins, out[i].n = c.mins, nil end
                if c.n then out[i].n, out[i].mins = c.n, nil end
            else
                out[#out + 1] = { item = name, slot = extra and "This raid" or "Added", mins = c.mins, n = c.n }
                at[name] = #out
            end
        end
    end
    local items = st and st.kitItems or {}
    apply(items[role], false)
    if raid then apply(items[K.RaidKey(raid)], true) end
    local kept = {}
    for _, e in ipairs(out) do if not e.off then kept[#kept + 1] = e end end
    return kept
end

-- How many to bring. A buff with a duration: enough to last the raid. A
-- potion or rune: the number set by the Team Captains, doubled on a
-- progression night. nil = no number set yet, so it isn't scored.
function K.Need(entry, hours, prog)
    if entry.mins then return math.ceil(hours * 60 / entry.mins) end
    if entry.n then return entry.n * (prog and 2 or 1) end
    return nil
end

-- rows = { item, slot, need, have, short }, and how many scored items are
-- fully stocked out of how many are scored. countOf(name) -> number held.
function K.Evaluate(list, hours, prog, countOf)
    local rows, have, need = {}, 0, 0
    for _, e in ipairs(list) do
        local n = K.Need(e, hours, prog)
        local held = countOf(e.item) or 0
        local short = n and math.max(0, n - held) or nil
        if n then
            need = need + 1
            if short == 0 then have = have + 1 end
        end
        rows[#rows + 1] = { item = e.item, slot = e.slot, need = n, have = held, short = short }
    end
    return rows, have, need
end

-- What a list of buff names says about a kit. Elixirs are a rough count: the
-- game names some elixir buffs differently from the bottle.
function K.Classify(names, weapon)
    local c = { f = false, fd = false, w = weapon and true or false, e = 0 }
    for _, n in ipairs(names) do
        if n:find("^Flask of") then
            c.f = true
        elseif n == "Well Fed" then
            c.fd = true
        elseif n:find("Elixir", 1, true) or n:find("Firewater", 1, true) then
            c.e = c.e + 1
        end
    end
    return c
end

-- The guild's rule is about the flask and the food. -> "flask and food", or nil.
function K.Missing(c)
    if not c then return nil end
    local m = {}
    if not c.f then m[#m + 1] = "flask" end
    if not c.fd then m[#m + 1] = "food" end
    return #m > 0 and table.concat(m, " and ") or nil
end

-- The raid a player's kit should be ready for: the soonest raid they said yes
-- or maybe to, or are selected for. -> the raid record or nil.
function K.NextRaid(st, guid, now)
    local best
    for _, r in pairs(st and st.raids or {}) do
        local s = r.signups and r.signups[guid]
        local mine = (s and s.st ~= "no") or (r.picked and r.picked[guid] ~= nil)
        if mine and not r.cancelled and r.at >= now - 6 * 3600 and (not best or r.at < best.at) then best = r end
    end
    return best
end

-- Ready-check rows for the leader: one per player given, their latest report
-- for that day or none. Missing first, then no report, then ready.
function K.CheckRows(st, day, guids, nameOf)
    local checks = st and st.kitChecks and st.kitChecks[day] or {}
    local rows = {}
    for _, g in ipairs(guids) do
        local c = checks[g]
        rows[#rows + 1] = { guid = g, name = nameOf(g) or g, check = c, missing = K.Missing(c),
            rank = (c and K.Missing(c) and 1) or (not c and 2) or 3 }
    end
    table.sort(rows, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return tostring(a.name) < tostring(b.name)
    end)
    return rows
end

local function dayNumber(day)
    local y, m, d = tostring(day):match("^(%d+)%-(%d+)%-(%d+)$")
    return y and ns.Time.DaysFromCivil(tonumber(y), tonumber(m), tonumber(d)) or 0
end

-- Days with reports, newest first, no older than the guild keeps them (90 days).
function K.Days(st, today)
    local days = {}
    for day in pairs(st and st.kitChecks or {}) do
        if dayNumber(today) - dayNumber(day) <= K.KEEP_DAYS then days[#days + 1] = day end
    end
    table.sort(days, function(a, b) return a > b end)
    return days
end

function K.ScoreText(kit)
    if not kit or (kit.need or 0) == 0 then return "|cff808080no kit yet|r" end
    local color = kit.have >= kit.need and "40ff40" or (kit.have * 2 >= kit.need and "ffd100" or "ff6040")
    return ("|cff%skit %d/%d|r"):format(color, kit.have, kit.need)
end

---------------------------------------------------------------------------
-- Game side
---------------------------------------------------------------------------
local function charStore()
    local guid = ns.MyGUID and ns.MyGUID()
    if not guid or not ns.db then return nil end
    ns.db.chars = ns.db.chars or {}
    ns.db.chars[guid] = ns.db.chars[guid] or {}
    return ns.db.chars[guid]
end

function K.MyRole()
    local c = charStore()
    if c and c.kitRole and K.DEFAULT[c.kitRole] then return c.kitRole end
    local _, class = UnitClass("player")
    return K.CLASS_ROLE[class or ""] or "str"
end

function K.SetRole(role)
    local c = charStore()
    if c and K.DEFAULT[role] then c.kitRole = role end
end

-- Bags and bank together (the guild counts the bank).
function K.Count(name)
    local get = (C_Item and C_Item.GetItemCount) or GetItemCount
    if type(get) ~= "function" then return 0 end
    local ok, n = pcall(get, name, true)
    return ok and type(n) == "number" and n or 0
end

-- My kit against the raid I'm next going to. -> rows, have, need, raid.
function K.Mine()
    local st = Red.State()
    local rules = st and st.kitRules or { hours = 3 }
    local raid = st and K.NextRaid(st, ns.MyGUID(), ns.Now())
    local list = K.List(st, K.MyRole(), raid and raid.raid)
    local rows, have, need = K.Evaluate(list, rules.hours, raid and raid.prog, K.Count)
    return rows, have, need, raid
end

-- Share my count with the guild so the leaders see it on sign-ups. Only when
-- it changed, and at most once an hour unless I'm signing up right now.
function K.Publish(force)
    if ns.mock or not RBAC.ICan("signup") then return end
    local c = charStore()
    local st = Red.State()
    if not c or not st then return end
    local _, have, need = K.Mine()
    local role = K.MyRole()
    if not st.kit[ns.MyGUID()] then c.kit = nil end
    local last, now = c.kit, ns.Now()
    if last and last.role == role and last.have == have and last.need == need then return end
    if last and not force and now - (last.at or 0) < 3600 then return end
    if ns.Log.New("KIT", { role = role, have = have, need = need }) then
        c.kit = { role = role, have = have, need = need, at = now }
    end
end

-- My own buffs. nil when the game won't say (in combat it hides them).
function K.CheckSelf()
    if InCombatLockdown and InCombatLockdown() then return nil end
    local names = {}
    for i = 1, 40 do
        local name
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or not aura then break end
            name = aura.name
        elseif UnitBuff then
            local ok, n = pcall(UnitBuff, "player", i)
            if not ok or not n then break end
            name = n
        else
            break
        end
        if not (issecretvalue and issecretvalue(name)) and type(name) == "string" then names[#names + 1] = name end
    end
    local weapon = false
    if GetWeaponEnchantInfo then
        local ok, main = pcall(GetWeaponEnchantInfo)
        weapon = ok and main == true
    end
    return K.Classify(names, weapon)
end

-- At a ready check in a group: tell me what I'm missing (the warning), and
-- report my buffs so the raid leader's addon can show them. One report per
-- change, so a night of ready checks is a handful of records.
local lastSent
function K.OnReadyCheck()
    if ns.mock or not RBAC.ICan("signup") then return end
    if not (IsInGroup and IsInGroup()) then return end
    local c = K.CheckSelf()
    if not c then return end
    local missing = K.Missing(c)
    if missing then
        ns.Print(("Raid Kit: you're missing your %s. The kit is required: buy from a guildmate or the auction house now."):format(missing))
    end
    local day = ns.Time.RaidDay(ns.Now())
    local sig = table.concat({ day, tostring(c.f), tostring(c.fd), tostring(c.w), c.e }, ":")
    if sig == lastSent then return end
    if ns.Log.New("KIT_CHECK", { day = day, f = c.f, fd = c.fd, w = c.w, e = c.e }) then lastSent = sig end
end
ns.On("READY_CHECK", function() K.OnReadyCheck() end)

local bagTimer
ns.On("BAG_UPDATE_DELAYED", function()
    if bagTimer or not (C_Timer and C_Timer.After) then return end
    bagTimer = true
    C_Timer.After(20, function()
        bagTimer = nil
        K.Publish(false)
        if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
    end)
end)

---------------------------------------------------------------------------
-- Team Captains and above
---------------------------------------------------------------------------
function K.SaveRules(hours, charge)
    if not RBAC.ICan("schedule") then return nil, "Only Team Captains and above can change the kit rules." end
    hours, charge = tonumber(hours), tonumber(charge)
    if not hours or hours ~= math.floor(hours) or hours < 1 or hours > 12 then return nil, "Raid hours must be 1 to 12." end
    if not charge or charge ~= math.floor(charge) or charge < 0 or charge > 10000 then return nil, "The DKP charge must be 0 to 10000." end
    local st = Red.State()
    if st and st.kitRules.hours == hours and st.kitRules.charge == charge then return nil, "Nothing changed." end
    return ns.Log.New("KIT_RULE", { hours = hours, charge = charge })
end

-- Add an item to a list, change its number, or take it off (on = false).
-- Give minutes for a buff that lasts, or a count for something carried.
function K.SetItem(list, item, on, mins, n)
    if not RBAC.ICan("schedule") then return nil, "Only Team Captains and above can change the kit list." end
    item = (item or ""):match("^%s*(.-)%s*$")
    if item == "" or #item > 48 then return nil, "Type the item's name as it shows in the game." end
    if not (K.DEFAULT[list] or (type(list) == "string" and list:sub(1, 5) == "raid:")) then return nil, "Pick a list first." end
    mins, n = tonumber(mins), tonumber(n)
    if on then
        if mins and n then return nil, "Give minutes or a count, not both." end
        if not mins and not n then return nil, "Give how many minutes it lasts, or how many to carry." end
        if mins and (mins ~= math.floor(mins) or mins < 1 or mins > 600) then return nil, "Minutes must be 1 to 600." end
        if n and (n ~= math.floor(n) or n < 1 or n > 200) then return nil, "The count must be 1 to 200." end
    else
        mins, n = nil, nil
    end
    return ns.Log.New("KIT_ITEM", { list = list, item = item, on = on and true or false, mins = mins, n = n })
end

-- The last step of the guild's rule: no flask or food, nothing to buy and
-- nobody to swap in. An Officer presses this; once per player per night.
function K.Charge(guid)
    local st = Red.State()
    if not st then return nil, "No guild data yet." end
    local amount = st.kitRules.charge or 0
    if amount <= 0 then return nil, "The kit charge is set to 0." end
    return ns.DKP.Award({ guid }, -amount, "kit", "Raid kit: no flask or food at the ready check",
        "kit:" .. ns.Time.RaidDay(ns.Now()) .. ":" .. guid)
end

-- A recipe some guildmate has shared that makes this item. -> recipe id, profession.
function K.FindRecipe(st, item)
    if not (st and ns.Recipes and ns.Recipes.Name) then return nil end
    for _, profs in pairs(st.recipes or {}) do
        for prof, set in pairs(profs) do
            for rid in pairs(set) do
                if ns.Recipes.Name(rid) == item then return rid, prof end
            end
        end
    end
    return nil
end

-- Put what I'm short of on the guild's Wanted board. I pay: my materials.
function K.Order(row)
    local st = Red.State()
    local rid, prof = K.FindRecipe(st, row.item)
    if not rid then return nil, "No guildmate has shared a recipe for " .. row.item .. " yet. Try the auction house." end
    return ns.Orders.Create(rid, prof, math.min(99, row.short or 1), "me", "Raid kit", nil)
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
local W = ns.W
local editList = "tank"            -- the list a Team Captain is editing
local showDay                      -- the ready-check day shown; nil = tonight

local function editLists()
    local out = {}
    for _, r in ipairs(K.ROLES) do out[#out + 1] = { key = r, label = K.ROLE_LABEL[r] } end
    for _, raid in ipairs(K.RAIDS) do out[#out + 1] = { key = K.RaidKey(raid), label = "Everyone in " .. raid } end
    return out
end

local function nextOf(list, key)
    for i, e in ipairs(list) do
        if e.key == key then return list[i % #list + 1] end
    end
    return list[1]
end

ns.UI.AddTab("kit", "Raid Kit", "view", function(p)
    p.role = W.Button(p, "", 190, 22, function()
        local roles = {}
        for _, r in ipairs(K.ROLES) do roles[#roles + 1] = { key = r } end
        K.SetRole(nextOf(roles, K.MyRole()).key)
        K.Publish(true)
        ns.UI.Refresh()
    end)
    p.role:SetPoint("TOPLEFT", 8, -8)
    p.rule = W.Text(p, "", "GameFontHighlightSmall")
    p.rule:SetPoint("TOPLEFT", 206, -6)
    p.rule:SetPoint("RIGHT", -8, 0)
    p.rule:SetJustifyH("LEFT")
    p.rule2 = W.Text(p, "", "GameFontDisableSmall")
    p.rule2:SetPoint("TOPLEFT", 206, -20)
    p.rule2:SetPoint("RIGHT", -8, 0)
    p.rule2:SetJustifyH("LEFT")

    local heads = { { "Item", 16, "LEFT" }, { "For", 244, "LEFT" }, { "Bring", 318, "RIGHT" }, { "Have", 372, "RIGHT" },
        { "Short", 426, "RIGHT" }, { "Cost to craft", 484, "RIGHT" } }
    for _, h in ipairs(heads) do
        local fs = W.Text(p, h[1], "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", h[2], -42)
        fs:SetWidth(h[1] == "Item" and 220 or (h[1] == "Cost to craft" and 96 or 50))
        fs:SetJustifyH(h[3])
    end
    p.rows = W.List(p, 700, 200, 18, function(row, r)
        p.rows.Col(row, 1, 8, 224):SetText(U.Safe(r.item, 48))
        local slot = p.rows.Col(row, 2, 236, 76)
        slot:SetText(r.slot)
        slot:SetTextColor(W.C.muted[1], W.C.muted[2], W.C.muted[3])
        p.rows.Col(row, 3, 310, 50, "RIGHT"):SetText(r.need and tostring(r.need) or "|cff808080not set|r")
        p.rows.Col(row, 4, 364, 50, "RIGHT"):SetText(tostring(r.have))
        local short = p.rows.Col(row, 5, 418, 50, "RIGHT")
        short:SetText(not r.short and "" or (r.short == 0 and "|cff40ff40ready|r" or ("|cffff6040" .. r.short .. "|r")))
        local st = Red.State()
        local rid = (r.short or 0) > 0 and K.FindRecipe(st, r.item) or nil
        local cost = p.rows.Col(row, 6, 476, 96, "RIGHT")
        cost:SetText(rid and ns.Orders.CostText(rid, r.short) or "")
        cost:SetTextColor(W.C.muted[1], W.C.muted[2], W.C.muted[3])
        if not row.order then
            row.order = W.Button(row, "Order", 54, 16)
            row.order:SetPoint("RIGHT", -4, 0)
        end
        row.order:SetShown(rid ~= nil)
        row.order:SetScript("OnClick", function()
            ns.UI.Try(("%s x%d is on the Wanted board. Tips appreciated."):format(r.item, math.min(99, r.short)), K.Order, r)
            ns.UI.Refresh()
        end)
    end)

    -- Team Captains and above: the rules, the list, and the ready checks.
    function p.place()
        local open = RBAC.ICan("schedule")
        p.fold:SetShown(open)
        local foldH = open and (p.fold:Height() + 8) or 0
        if open then
            p.fold:ClearAllPoints()
            p.fold:SetPoint("BOTTOMLEFT", 8, 8 + (p.fold.open and (p.fold.bodyHeight + 6) or 0))
        end
        p.rows:Stretch(8, -58, 8, foldH + 8)
        if ns.UI.FitWindow then ns.UI.FitWindow() end
    end
    p.fold = W.Accordion(p, "Kit rules and ready checks (Team Captain and above)", 700, 176, "kitLeader", function() p.place() end)
    local s = p.fold.body
    W.Text(s, "Raid hours", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 0, -6)
    s.hours = W.Edit(s, 34, 2)
    s.hours:SetPoint("TOPLEFT", 66, -2)
    W.Text(s, "DKP charge for no flask or food", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 112, -6)
    s.charge = W.Edit(s, 50, 5)
    s.charge:SetPoint("TOPLEFT", 296, -2)
    s.save = W.Button(s, "Save rules", 90, 22, function()
        ns.UI.Try("Kit rules saved for the guild.", K.SaveRules, s.hours:GetText(), s.charge:GetText())
        ns.UI.Refresh()
    end)
    s.save:SetPoint("TOPLEFT", 356, -2)

    s.list = W.Button(s, "", 170, 22, function()
        editList = nextOf(editLists(), editList).key
        ns.UI.Refresh()
    end)
    s.list:SetPoint("TOPLEFT", 0, -30)
    s.item = W.Edit(s, 170, 48)
    s.item:SetPoint("TOPLEFT", 176, -30)
    W.Text(s, "lasts (min)", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 352, -34)
    s.mins = W.Edit(s, 36, 3)
    s.mins:SetPoint("TOPLEFT", 414, -30)
    W.Text(s, "or carry", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 456, -34)
    s.n = W.Edit(s, 36, 3)
    s.n:SetPoint("TOPLEFT", 504, -30)
    s.add = W.Button(s, "Add / set", 70, 22, function()
        if ns.UI.Try("Kit list updated for the guild.", K.SetItem, editList, s.item:GetText(), true, s.mins:GetText(), s.n:GetText()) then
            s.item:SetText(""); s.mins:SetText(""); s.n:SetText("")
        end
        ns.UI.Refresh()
    end)
    s.add:SetPoint("TOPLEFT", 546, -30)
    s.remove = W.Button(s, "Remove", 64, 22, function()
        if ns.UI.Try("Removed from the kit list.", K.SetItem, editList, s.item:GetText(), false) then s.item:SetText("") end
        ns.UI.Refresh()
    end)
    s.remove:SetPoint("TOPLEFT", 620, -30)

    s.day = W.Button(s, "", 170, 20, function()
        local st = Red.State()
        local days = K.Days(st, ns.Time.RaidDay(ns.Now()))
        local list = { { key = false } }
        for _, d in ipairs(days) do list[#list + 1] = { key = d } end
        showDay = nextOf(list, showDay or false).key or nil
        ns.UI.Refresh()
    end)
    s.day:SetPoint("TOPLEFT", 0, -60)
    s.dayNote = W.Text(s, "", "GameFontDisableSmall")
    s.dayNote:SetPoint("TOPLEFT", 176, -64)
    s.checks = W.List(s, 700, 92, 16, function(row, r)
        s.checks.Col(row, 1, 4, 150):SetText(U.Safe(r.name, 40))
        local c = r.check
        local function mark(v) return v and "|cff40ff40yes|r" or "|cffff6040NO|r" end
        s.checks.Col(row, 2, 158, 70):SetText(c and ("Flask " .. mark(c.f)) or "|cff808080no report|r")
        s.checks.Col(row, 3, 232, 70):SetText(c and ("Food " .. mark(c.fd)) or "")
        s.checks.Col(row, 4, 306, 80):SetText(c and ("Weapon " .. mark(c.w)) or "")
        s.checks.Col(row, 5, 390, 80):SetText(c and ("Elixirs " .. c.e .. "+") or "")
        local kit = Red.State() and Red.State().kit[r.guid]
        s.checks.Col(row, 6, 474, 80):SetText(K.ScoreText(kit))
        if not row.charge then
            row.charge = W.Button(row, "", 96, 14)
            row.charge:SetPoint("RIGHT", -4, 0)
        end
        local st = Red.State()
        local can = r.missing ~= nil and not showDay and RBAC.ICan("award") and st ~= nil
        row.charge:SetShown(can)
        if can then
            row.charge:SetText("Charge " .. (st.kitRules.charge or 0) .. " DKP")
            row.charge:SetScript("OnClick", function()
                ns.UI.Try(("Charged %s %d DKP for the raid kit."):format(U.Safe(r.name, 40), st.kitRules.charge or 0), K.Charge, r.guid)
                ns.UI.Refresh()
            end)
        end
    end)
    s.checks.scroll:SetPoint("TOPLEFT", 0, -84)
    p.place()
end, function(p)
    local st = Red.State()
    local rules = st and st.kitRules or { hours = 3, charge = 30 }
    local rows, have, need, raid = K.Mine()
    p.role:SetText("My role: " .. K.ROLE_LABEL[K.MyRole()])
    p.rule:SetText(("Required for every raid. %d of %d ready, for a %d-hour raid.%s"):format(have, need, rules.hours,
        raid and ("  Next: " .. U.Safe(raid.title, 40) .. (raid.prog and " (progression: potions and runes doubled)" or "")) or ""))
    p.rule2:SetText("Counts your bags and bank. You pay for your own kit; order from guild crafters here, tips appreciated."
        .. (need < #rows and "  \"Not set\" = your Team Captains haven't set how many yet." or ""))
    p.rows:SetItems(rows)
    K.Publish(false)

    if RBAC.ICan("schedule") then
        local s = p.fold.body
        if not s.hours:HasFocus() then s.hours:SetText(tostring(rules.hours)) end
        if not s.charge:HasFocus() then s.charge:SetText(tostring(rules.charge)) end
        local label = editList
        for _, e in ipairs(editLists()) do if e.key == editList then label = e.label end end
        s.list:SetText("List: " .. label)
        local today = ns.Time.RaidDay(ns.Now())
        local day = showDay or today
        local guids = {}
        if showDay then
            for g in pairs(st and st.kitChecks[day] or {}) do guids[#guids + 1] = g end
        else
            guids = ns.DKP.GroupGUIDs()
        end
        local list = K.CheckRows(st, day, guids, ns.NameForGUID)
        local missing = 0
        for _, r in ipairs(list) do if r.missing or not r.check then missing = missing + 1 end end
        s.day:SetText(showDay and ("Ready checks: " .. showDay) or "Ready checks: tonight")
        s.dayNote:SetText(showDay and (#list .. " reports. Kept " .. K.KEEP_DAYS .. " days. Click to change the night.")
            or (#list .. " in your group, " .. missing .. " missing or not reported. Shown to you only, not raid chat."))
        s.checks:SetItems(list)
        p.fold.note:SetText(missing > 0 and not showDay and (missing .. " to check") or "")
    end
    p.place()
end)

ns.UI.Need("kit", function(p)
    return 58 + 8 * 18 + (RBAC.ICan("schedule") and (p.fold:Height() + 16) or 8)
end)
