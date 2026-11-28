-- Speakeasy: BiS check. Compares your gear with Speakeasy's pre-raid
-- list for your spec (Modules/BiSData.lua, all 28 specs) and ranks your
-- biggest upgrades. Reads only your own equipped items, bags and bank.
-- The one thing shared with the guild is your readiness score: your spec and
-- two percentages (owned, worn), so raid leaders see it on sign-ups.
-- Items match by name, so this works on English clients only for now.
local _, ns = ...
local BiS = {}
ns.BiS = BiS

-- Where a list came from, for the title line. list.old = no expert list was readable, older list kept.
function BiS.SourceText(list)
    if list.old then return "older auto-ranked list: " .. list.old end
    if list.by then return ("from %s's Wowhead guide, updated %s"):format(list.by, list.asof or "?") end
    return "updated " .. (ns.BiSUpdated or "?")
end

-- Item name from an item link: |cff...|Hitem:...|h[Name]|h|r
function BiS.NameFromLink(link)
    if type(link) ~= "string" then return nil end
    return link:match("|h%[(.-)%]|h")
end

-- Pure scoring, no game API. owned = { [name] = "equipped" | "bags" | "bank" }.
-- Ring and trinket slots share items, so one item never fills two slots.
-- An item can also be owned under its Alliance twin's name (it.ally).
-- A two-hander in the main hand (it.two) covers the off hand as well.
function BiS.Evaluate(list, owned)
    local rows, used, usedWorn = {}, {}, {}
    local total, wornTotal = 0, 0
    local function best(items, taken, wornOnly)
        for _, it in ipairs(items) do
            local where = owned[it.name] or (it.ally and owned[it.ally])
            if not where and it.also then
                for _, other in ipairs(it.also) do
                    if owned[other] then where = owned[other]; break end
                end
            end
            if where and not taken[it.name] and (not wornOnly or where == "equipped") then
                taken[it.name] = true
                return it, where
            end
        end
    end
    local mainPick, mainWhere, mainWorn
    for order, s in ipairs(list.slots) do
        local pick, where = best(s.items, used, false)
        local worn = best(s.items, usedWorn, true)
        if s.slot == "Main hand" then mainPick, mainWhere, mainWorn = pick, where, worn end
        local have = pick and pick.score or 0
        local wornScore = worn and worn.score or 0
        if s.slot == "Off hand" then
            if mainPick and mainPick.two and mainPick.score > have then
                pick, where, have = mainPick, mainWhere, mainPick.score
            end
            if mainWorn and mainWorn.two and mainWorn.score > wornScore then wornScore = mainWorn.score end
        end
        local step
        for i = #s.items, 2, -1 do
            if s.items[i].score > have then step = s.items[i]; break end
        end
        total = total + have
        wornTotal = wornTotal + wornScore
        rows[#rows + 1] = {
            order = order, slot = s.slot, have = pick, where = where, score = have,
            gap = 1 - have, bis = s.items[1], alt = step, items = s.items,
        }
    end
    table.sort(rows, function(a, b)
        if a.gap ~= b.gap then return a.gap > b.gap end
        return a.order < b.order
    end)
    local n = #list.slots
    return rows, (n > 0 and total / n or 0), (n > 0 and wornTotal / n or 0)
end

-- Pick the list for a talent build. trees = { { name = "Demonology", points = 31 }, ... }.
-- The tree with the most points wins; Feral has two lists, so cat is the
-- default and the player can pick bear.
function BiS.SpecFromTrees(lists, trees)
    local top
    for _, tr in ipairs(trees or {}) do
        if type(tr.name) == "string" and type(tr.points) == "number" and (not top or tr.points > top.points) then top = tr end
    end
    if not top or top.points <= 0 then return nil end
    if lists[top.name] then return top.name end
    local first
    for key in pairs(lists) do
        if key:sub(1, #top.name) == top.name and (not first or key < first) then first = key end
    end
    if first and lists[top.name .. " (Cat)"] then return top.name .. " (Cat)" end
    return first
end

---------------------------------------------------------------------------
-- Game side: which list applies, and what the player owns
---------------------------------------------------------------------------
local function charStore()
    local guid = ns.MyGUID and ns.MyGUID()
    if not guid or not ns.db then return nil end
    ns.db.chars = ns.db.chars or {}
    ns.db.chars[guid] = ns.db.chars[guid] or {}
    return ns.db.chars[guid]
end

function BiS.Lists()
    local _, class = UnitClass("player")
    return ns.BiSData and ns.BiSData[class], class
end

-- Talent trees from the game, whichever talent API this client has.
local function talentTrees()
    local trees = {}
    if type(GetTalentTabInfo) ~= "function" then return trees end
    for i = 1, (GetNumTalentTabs and GetNumTalentTabs() or 3) do
        local ok, a, b, c, _, e = pcall(GetTalentTabInfo, i)
        if ok then
            -- Older form: name, icon, points. Newer form: id, name, description, icon, points.
            if type(a) == "string" then
                trees[#trees + 1] = { name = a, points = tonumber(c) or 0 }
            elseif type(b) == "string" then
                trees[#trees + 1] = { name = b, points = tonumber(e) or 0 }
            end
        end
    end
    return trees
end

-- The list that applies to you: the one you picked, else the one your talents
-- point to, else the first for your class. Returns key, list, how ("picked",
-- "talents" or "default").
function BiS.CurrentSpec()
    local lists = BiS.Lists()
    if not lists then return nil end
    local c = charStore()
    local key = c and c.bisSpec
    if key and lists[key] then return key, lists[key], "picked" end
    key = BiS.SpecFromTrees(lists, talentTrees())
    if key then return key, lists[key], "talents" end
    local first
    for k in pairs(lists) do if not first or k < first then first = k end end
    if first then return first, lists[first], "default" end
end

-- Your readiness: share of the ranked list you own (bags and bank count) and
-- share you are wearing, as whole percents.
function BiS.MyScore()
    local key, list = BiS.CurrentSpec()
    if not list then return nil end
    local _, owned, worn = BiS.Evaluate(list, BiS.Owned())
    return { spec = key, pre = math.floor(owned * 100 + 0.5), worn = math.floor(worn * 100 + 0.5) }
end

-- Share your score with the guild so raid leaders see it on sign-ups. Only
-- when it changed, and at most once an hour unless you are signing up now.
function BiS.Publish(force)
    if ns.mock or not ns.RBAC.ICan("signup") then return end
    local c = charStore()
    local mine = BiS.MyScore()
    if not c or not mine then return end
    -- "Already shared" is only true if the guild's records still hold it.
    local st = ns.Reducer.State()
    if st and not st.gear[ns.MyGUID()] then c.gear = nil end
    local last = c.gear
    local now = ns.Now()
    if last and last.spec == mine.spec and last.pre == mine.pre and last.worn == mine.worn then return end
    if last and not force and now - (last.at or 0) < 3600 then return end
    if ns.Log.New("GEAR", { spec = mine.spec, pre = mine.pre, worn = mine.worn }) then
        c.gear = { spec = mine.spec, pre = mine.pre, worn = mine.worn, at = now }
    end
end

function BiS.SetSpec(key)
    local c = charStore()
    if c then c.bisSpec = key end
end

local function addLink(owned, link, where)
    local name = BiS.NameFromLink(link)
    if name and (not owned[name] or where == "equipped") then owned[name] = where end
end

local getNumSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
local getLink = C_Container and C_Container.GetContainerItemLink or GetContainerItemLink

local function scanBag(bag, out)
    if not getNumSlots or not getLink then return end
    for slot = 1, (getNumSlots(bag) or 0) do
        local link = getLink(bag, slot)
        local name = BiS.NameFromLink(link)
        if name then out[#out + 1] = name end
    end
end

-- The bank can only be read while it is open, so remember what was there.
local function scanBank()
    local c = charStore()
    if not c then return end
    local names = {}
    scanBag(BANK_CONTAINER or -1, names)
    local first = (NUM_BAG_SLOTS or 4) + 1
    for bag = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do scanBag(bag, names) end
    c.bank = names
end

function BiS.Owned()
    local owned = {}
    for slot = 1, 19 do addLink(owned, GetInventoryItemLink("player", slot), "equipped") end
    local names = {}
    for bag = 0, NUM_BAG_SLOTS or 4 do scanBag(bag, names) end
    for _, n in ipairs(names) do if not owned[n] then owned[n] = "bags" end end
    local c = charStore()
    for _, n in ipairs(c and c.bank or {}) do if not owned[n] then owned[n] = "bank" end end
    return owned
end

ns.On("BANKFRAME_OPENED", scanBank)
ns.On("PLAYERBANKSLOTS_CHANGED", scanBank)
local publishQueued = false
local function publishSoon(delay)
    if publishQueued or not (C_Timer and C_Timer.After) then return end
    publishQueued = true
    C_Timer.After(delay, function()
        publishQueued = false
        BiS.Publish(false)
    end)
end
ns.On("PLAYER_EQUIPMENT_CHANGED", function()
    if ns.UI then ns.UI.RefreshSoon() end
    publishSoon(60)
end)
ns.Listen("ROSTER_CHANGED", function() if ns.roster.loaded then publishSoon(120) end end)

-- Questie's public API (Questie.API) covers readiness, quest updates and
-- nameplate icons. It has no item or map-pin lookups, so we only detect it.
function BiS.QuestieReady()
    return Questie and Questie.API and Questie.API.isReady and true or false
end

---------------------------------------------------------------------------
-- BiS tab (everyone)
---------------------------------------------------------------------------
local W, U = ns.W, ns.U
local WHERE = { equipped = "", bags = " (in bags)", bank = " (in bank)" }

local function pct(x) return math.floor(x * 100 + 0.5) .. "%" end

ns.UI.AddTab("bis", "BiS Check", "view", function(p)
    p.title = W.Text(p, "", "GameFontNormal")
    p.title:SetPoint("TOPLEFT", 0, 0)
    p.summary = W.Text(p, "", "GameFontHighlightSmall")
    p.summary:SetPoint("TOPLEFT", 0, -18)
    p.summary:SetPoint("RIGHT", 0, 0)
    p.summary:SetWordWrap(false)
    p.specButtons = {}

    local header = { { "Slot", 4 }, { "You have", 84 }, { "Score", 262 }, { "Speakeasy BiS", 312 }, { "How to get it", 480 } }
    for _, h in ipairs(header) do
        local fs = W.Text(p, h[1], "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", h[2], -64)
    end
    p.list = W.List(p, 640, 270, 18, function(row, item)
        p.list.Col(row, 1, 4, 78):SetText(item.slot)
        local have = item.have and (item.have.name .. (WHERE[item.where] or "")) or "-"
        p.list.Col(row, 2, 84, 176):SetText(U.Safe(have, 60))
        p.list.Col(row, 3, 262, 46):SetText(pct(item.score))
        local target = item.gap <= 0 and "|cff40ff40Done|r" or U.Safe(item.bis.name, 48)
        p.list.Col(row, 4, 312, 166):SetText(target)
        p.list.Col(row, 5, 480, 160):SetText(item.gap <= 0 and "" or U.Safe(item.bis.how, 80))
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(item.slot)
            for _, it in ipairs(item.items) do
                GameTooltip:AddDoubleLine(U.Safe(it.name, 60), pct(it.score), 1, 1, 1, 1, 0.82, 0)
                GameTooltip:AddLine("  " .. U.Safe(it.how, 100), 0.7, 0.7, 0.7)
                if it.note then GameTooltip:AddLine("  " .. U.Safe(it.note, 120), 0.6, 0.6, 1, true) end
            end
            if item.alt then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Step up: " .. U.Safe(item.alt.name, 60) .. " (" .. pct(item.alt.score) .. ")", 0.4, 1, 0.4)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
    end)
    p.list:Stretch(0, -82, 0, 26)
    p.note = W.Text(p, "Hover a row for every option and a step-up item. Open your bank once so banked items count.", "GameFontDisableSmall")
    p.note:SetPoint("BOTTOMLEFT", 0, 4)
    -- At the auction house: look up the items on this list that rank above what you own.
    p.market = W.Button(p, "Find upgrades for sale", 170, 22, function() ns.Market.Open() end)
    p.market:SetPoint("BOTTOMRIGHT", 0, 0)
end, function(p)
    local lists, class = BiS.Lists()
    for _, b in ipairs(p.specButtons) do b:Hide() end
    if not lists then
        p.title:SetText("BiS Check")
        p.summary:SetText("Speakeasy doesn't have a ranked list for " .. U.Safe(class or "your class", 20) .. " yet.")
        p.list:SetItems({})
        return
    end
    local key, list, how = BiS.CurrentSpec()
    local keys = {}
    for k in pairs(lists) do keys[#keys + 1] = k end
    table.sort(keys)
    for i, k in ipairs(keys) do
        local b = p.specButtons[i]
        if not b then
            b = W.Button(p, "", 130, 20)
            p.specButtons[i] = b
        end
        b:SetText(k)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", (i - 1) * 134, -38)
        b:SetEnabled(k ~= key)
        b:SetScript("OnClick", function() BiS.SetSpec(k); ns.UI.Refresh(); BiS.Publish(true) end)
        b:Show()
    end
    local rows, owned, worn = BiS.Evaluate(list, BiS.Owned())
    p.title:SetText(("Pre-raid BiS: %s  (%s; %s)"):format(list.label,
        how == "picked" and "you picked this list" or (how == "talents" and "from your talents" or "pick your spec below"),
        BiS.SourceText(list)))
    p.summary:SetText("Your readiness score: " .. pct(owned) .. " (wearing " .. pct(worn)
        .. "). Raid leaders see it on your sign-ups. No raid lists yet: the raid loot isn't published.")
    p.list:SetItems(rows)
end)

ns.UI.Need("bis", function() return 82 + 76 + 26 end)
