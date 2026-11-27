-- Blood Pact: find pre-raid BiS upgrades on the auction house.
--
-- Works for every class and spec: it takes the list the BiS Check tab is
-- showing, keeps the items that rank above what you own, and looks each one
-- up at the auction house. You set a gold range; the window lists what is
-- for sale inside it, cheapest buyout first, with one Buy button per item.
--
-- One click buys one item at the buyout price printed on its button. The
-- game needs a real click for every purchase, and Blood Pact does not act
-- for the player. Bids are never placed below the buyout.
local _, ns = ...
local M = {}
ns.Market = M

local U, BiS, Orders = ns.U, ns.BiS, ns.Orders

M.MAX_GOLD = 999999
M.WAIT = 8          -- seconds to wait for one answer from the auction house
M.MAX_KEYS = 4      -- variants of one item looked at per search
M.MAX_BROWSE = 1000 -- kinds of usable gear read from the auction house
M.MAX_USABLE = 40   -- kinds of usable gear looked at closely, biggest item-level step first
M.HOWTO = {
    "1. Open the auction house, then press \"Find upgrades for sale\" on the BiS Check tab.",
    "2. Type the least and the most gold you want to pay for one item. Leave a box empty for no limit.",
    "3. Press Scan. Blood Pact looks up every item on your spec's list that ranks above what you own. It takes a moment: the auction house answers one search at a time.",
    "4. Two boxes choose what is scanned: \"BiS list\" and \"Usable gear\". Tick one or both. Usable gear alone is the quicker scan.",
    "\"Usable gear\" finds affordable upgrades: greens and other gear you can equip that isn't on the list. Blood Pact knows which endings each class and spec wants: \"of Shadow Wrath\" for an Affliction Warlock or Shadow Priest, \"of Healing\" for healers, \"of the Tiger\" for a Fury Warrior, and so on. The line at the bottom of the window names yours. A green with one of those endings is listed when it is a higher item level than what you wear, or when what you wear there is neither on the list nor has one of those endings. Greens with any other ending are left out.",
    "Gear with no such ending, or a spec whose list names none, is judged by the Pawn addon's stat weights if Pawn is installed, and otherwise by item level in your class's armor type. Item level doesn't know which stats your spec wants, so read the tooltip before you buy.",
    "5. The list shows what is for sale in your gold range with the cheapest buyout for each. Click a column heading to sort; click it again to reverse.",
    "6. Click a row to show that item in the auction window. Press Buy to buy that one item at the price on the button, then collect it from your mailbox.",
    "One item per click: the game needs your own click for every purchase, so nothing is bought for you. Only items with a buyout are listed; Blood Pact never bids.",
    "Quest rewards and Tier 0.5 pieces are skipped, because they can't be sold. The usable pass looks closely at up to 40 kinds of gear, biggest item-level step first.",
    "The list follows the spec picked on the BiS Check tab. Pick another spec there and scan again.",
}

---------------------------------------------------------------------------
-- Pure rules
---------------------------------------------------------------------------
-- "25" -> 250000 copper. "" -> nil (no limit). Whole gold only.
function M.Gold(text)
    text = tostring(text or ""):gsub("%s", "")
    if text == "" then return nil end
    local n = tonumber(text)
    if not n or n ~= math.floor(n) or n < 0 or n > M.MAX_GOLD then
        return nil, ("Type whole gold from 0 to %d, or leave it empty."):format(M.MAX_GOLD)
    end
    return n * 10000
end

-- -> least, most in copper (most may be nil = no limit), or nil and why.
function M.Range(minText, maxText)
    local lo, why = M.Gold(minText)
    if why then return nil, why end
    local hi, why2 = M.Gold(maxText)
    if why2 then return nil, why2 end
    lo = lo or 0
    if hi and hi < lo then return nil, "The most you'll pay is below the least." end
    return lo, hi
end

-- "61 list items and 12 kinds of usable gear"
function M.LookedText(listed, usable)
    local parts = {}
    if listed > 0 then parts[#parts + 1] = listed .. " list items" end
    if usable > 0 then parts[#parts + 1] = usable .. " kinds of usable gear" end
    return #parts > 0 and table.concat(parts, " and ") or "nothing"
end

function M.RangeText(lo, hi)
    if (lo or 0) == 0 and not hi then return "at any price" end
    if not hi then return "from " .. Orders.Money(lo) .. " up" end
    if (lo or 0) == 0 then return "up to " .. Orders.Money(hi) end
    return "between " .. Orders.Money(lo) .. " and " .. Orders.Money(hi)
end

-- Sources that are never on the auction house. Everything else is looked up.
function M.Sellable(how)
    how = tostring(how or "")
    return not (how:find("^Quest") or how:find("^Tier 0%.5"))
end

-- Random-enchantment endings ("Master's Hat of Shadow Wrath"). Some auction
-- houses file those under the plain name, so the search falls back to it.
local SUFFIX = {}
for _, s in ipairs({ "the Monkey", "the Eagle", "the Bear", "the Whale", "the Owl", "the Gorilla", "the Falcon", "the Boar",
    "the Wolf", "the Tiger", "Spirit", "Stamina", "Strength", "Agility", "Intellect", "Power", "Defense", "Healing", "Magic",
    "Regeneration", "Concentration", "Marksmanship", "Eluding", "Blocking", "Striking", "Sorcery", "Restoration", "Nimbleness",
    "Protection", "Arcane Wrath", "Fiery Wrath", "Frozen Wrath", "Nature's Wrath", "Shadow Wrath", "Holy Wrath",
    "Arcane Resistance", "Fire Resistance", "Frost Resistance", "Nature Resistance", "Shadow Resistance" }) do
    SUFFIX[s] = true
end
function M.BaseName(name)
    local base, tail = tostring(name or ""):match("^(.+) of (.+)$")
    if base and SUFFIX[tail] then return base end
    return nil
end
-- "Master's Hat of Shadow Wrath" -> "Shadow Wrath". nil when there is no such ending.
function M.Tail(name)
    local base, tail = tostring(name or ""):match("^(.+) of (.+)$")
    if base and SUFFIX[tail] then return (tail:gsub("^the ", "")), tail end
    return nil
end

-- The endings each class and spec wants on a green, by what the ending gives:
-- Shadow Wrath is shadow spell damage, Healing is bonus healing, the Tiger is
-- Strength and Agility, the Monkey Agility and Stamina, the Bear Strength and
-- Stamina, Power is attack power. Damage casters get their spell school only:
-- plain Intellect endings (the Eagle, the Owl) are left out on purpose.
M.ENDINGS = {
    WARRIOR = { Arms = { "Tiger", "Power", "Strength" }, Fury = { "Tiger", "Power", "Strength" }, Protection = { "Bear", "Defense", "Stamina" } },
    PALADIN = { Holy = { "Healing" }, Protection = { "Bear", "Defense", "Stamina" }, Retribution = { "Tiger", "Power", "Strength" } },
    HUNTER = { ["Beast Mastery"] = { "Monkey", "Agility", "Falcon", "Marksmanship" }, Marksmanship = { "Monkey", "Agility", "Falcon", "Marksmanship" },
        Survival = { "Monkey", "Agility", "Falcon", "Marksmanship" } },
    ROGUE = { Assassination = { "Tiger", "Monkey", "Agility", "Power" }, Combat = { "Tiger", "Monkey", "Agility", "Power" },
        Subtlety = { "Tiger", "Monkey", "Agility", "Power" } },
    PRIEST = { Discipline = { "Healing" }, Holy = { "Healing" }, Shadow = { "Shadow Wrath" } },
    SHAMAN = { Elemental = { "Nature's Wrath" }, Enhancement = { "Tiger", "Power", "Strength" }, Restoration = { "Healing" } },
    MAGE = { Arcane = { "Arcane Wrath" }, Fire = { "Fiery Wrath" }, Frost = { "Frozen Wrath" } },
    WARLOCK = { Affliction = { "Shadow Wrath" }, Demonology = { "Shadow Wrath" }, Destruction = { "Shadow Wrath", "Fiery Wrath" } },
    DRUID = { Balance = { "Nature's Wrath", "Arcane Wrath" }, ["Feral (Bear)"] = { "Bear", "Stamina", "Monkey" },
        ["Feral (Cat)"] = { "Tiger", "Monkey", "Agility", "Power" }, Restoration = { "Healing" } },
}

-- The endings wanted for one spec: the table above, plus any ending the spec's
-- own guide list names on a world-drop green ("Master's Hat of Magic").
-- -> { ["Shadow Wrath"] = true }, or nil when there are none.
function M.Endings(list, class, key)
    local set, any = {}, false
    for _, tail in ipairs(M.ENDINGS[class] and M.ENDINGS[class][key] or {}) do set[tail], any = true, true end
    for _, s in ipairs(list and list.slots or {}) do
        for _, it in ipairs(s.items) do
            if tostring(it.how or ""):find("^World drop") then
                for _, name in ipairs({ it.name, it.ally }) do
                    local tail = M.Tail(name)
                    if tail then set[tail], any = true, true end
                end
            end
        end
    end
    return any and set or nil
end

function M.EndingsText(set)
    local names = {}
    for k in pairs(set or {}) do names[#names + 1] = k end
    table.sort(names)
    return table.concat(names, ", ")
end

-- What to look for: every item on the list that ranks above what you own in
-- its slot and could be on the auction house. Biggest step up first. An item's
-- second accepted name (it.ally: the other faction's twin, or another random
-- enchantment) is looked up as well.
-- -> { { slot, name, score, have, gain, how, order } }
function M.Wanted(list, owned)
    local rows = BiS.Evaluate(list, owned)
    local byName, out = {}, {}
    local function want(name, it, r)
        local gain = it.score - r.score
        local w = byName[name]
        if not w then
            w = { slot = r.slot, name = name, score = it.score, have = r.score, gain = gain, how = it.how, order = r.order }
            byName[name] = w
            out[#out + 1] = w
        elseif gain > w.gain then
            w.slot, w.score, w.have, w.gain, w.how, w.order = r.slot, it.score, r.score, gain, it.how, r.order
        end
    end
    for _, r in ipairs(rows) do
        for _, it in ipairs(r.items) do
            local mine = owned[it.name] or (it.ally and owned[it.ally])
            if it.score > r.score and not mine and M.Sellable(it.how) then
                want(it.name, it, r)
                if it.ally then want(it.ally, it, r) end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.gain ~= b.gain then return a.gain > b.gain end
        if a.order ~= b.order then return a.order < b.order end
        return a.name < b.name
    end)
    return out
end

-- Which browse results could be the item. keys = { { key, name } } (name may
-- be nil while the game is still loading it). Exact names first.
function M.Candidates(keys, wanted, base)
    local exact, loose = {}, {}
    for _, k in ipairs(keys or {}) do
        if k.name == wanted then exact[#exact + 1] = k.key
        elseif k.name == nil or (base and k.name == base) then loose[#loose + 1] = k.key end
    end
    for _, k in ipairs(loose) do exact[#exact + 1] = k end
    while #exact > M.MAX_KEYS do exact[#exact] = nil end
    return exact
end

-- The cheapest auction for this exact item inside the gold range.
-- auctions = { { id, name, buyout, mine } }. No buyout = not listed.
function M.Cheapest(auctions, wanted, lo, hi)
    local best
    for _, a in ipairs(auctions or {}) do
        if a.name == wanted and not a.mine and type(a.buyout) == "number" and a.buyout > 0
            and a.buyout >= (lo or 0) and (not hi or a.buyout <= hi) and (not best or a.buyout < best.buyout) then
            best = a
        end
    end
    return best
end

-- What a row's button does. -> "none" | "wait" | "poor" | "buy", and its text.
function M.ButtonFor(row, open, money, buying)
    if row.bought then return "none", "Bought" end
    if not open then return "none", "" end
    if buying then return "wait", buying == row.id and "Buying..." or "Buy " .. Orders.Money(row.buyout) end
    if money < row.buyout then return "poor", "Need " .. Orders.Money(row.buyout) end
    return "buy", "Buy " .. Orders.Money(row.buyout)
end

-- Where a piece of gear goes: the game's equip location -> slot label and
-- the character-sheet slots it is compared with.
M.EQUIP = {
    INVTYPE_HEAD = { "Head", { 1 } }, INVTYPE_NECK = { "Neck", { 2 } }, INVTYPE_SHOULDER = { "Shoulder", { 3 } },
    INVTYPE_CHEST = { "Chest", { 5 } }, INVTYPE_ROBE = { "Chest", { 5 } }, INVTYPE_WAIST = { "Waist", { 6 } },
    INVTYPE_LEGS = { "Legs", { 7 } }, INVTYPE_FEET = { "Feet", { 8 } }, INVTYPE_WRIST = { "Wrist", { 9 } },
    INVTYPE_HAND = { "Hands", { 10 } }, INVTYPE_FINGER = { "Ring", { 11, 12 } }, INVTYPE_TRINKET = { "Trinket", { 13, 14 } },
    INVTYPE_CLOAK = { "Back", { 15 } }, INVTYPE_WEAPON = { "Main hand", { 16 } }, INVTYPE_2HWEAPON = { "Main hand", { 16 } },
    INVTYPE_WEAPONMAINHAND = { "Main hand", { 16 } }, INVTYPE_WEAPONOFFHAND = { "Off hand", { 17 } },
    INVTYPE_HOLDABLE = { "Off hand", { 17 } }, INVTYPE_SHIELD = { "Off hand", { 17 } }, INVTYPE_RANGED = { "Ranged", { 18 } },
    INVTYPE_RANGEDRIGHT = { "Ranged", { 18 } }, INVTYPE_THROWN = { "Ranged", { 18 } }, INVTYPE_RELIC = { "Ranged", { 18 } },
}

-- The heaviest armor a class wears: 1 cloth, 2 leather, 3 mail, 4 plate.
-- Mail and plate open up at level 40.
function M.ArmorType(class, level)
    local late = (level or 60) >= 40
    if class == "WARRIOR" or class == "PALADIN" then return late and 4 or 3 end
    if class == "HUNTER" or class == "SHAMAN" then return late and 3 or 2 end
    if class == "ROGUE" or class == "DRUID" then return 2 end
    return 1
end

-- Without stat weights, only armor of the class's own type counts. Cloaks,
-- jewelry, shields, off-hands and weapons are left to the game's "usable" rule.
function M.Fits(class, level, classID, subClassID, equipLoc)
    if classID ~= 4 or equipLoc == "INVTYPE_CLOAK" then return true end
    if type(subClassID) == "number" and subClassID >= 1 and subClassID <= 4 then return subClassID == M.ArmorType(class, level) end
    return true
end

-- Which kinds of usable gear are worth a closer look.
-- results = { { itemKey, minPrice } }; info(itemKey) -> { equipLoc, ilvl, fits } or nil;
-- haveOf(slots) -> item level worn there (0 = empty). loose = stat weights
-- will judge later, so an equal item level is let through. open(slots) = what
-- is worn there is neither on the list nor carries a wanted ending, so a green
-- with a wanted ending may beat it at any item level.
function M.UsablePick(results, info, haveOf, hi, cap, loose, open)
    local out = {}
    for _, r in ipairs(results or {}) do
        local i = r.itemKey and info(r.itemKey)
        local slot = i and M.EQUIP[i.equipLoc]
        if slot and (loose or i.fits) and (not hi or (r.minPrice or 0) <= hi) then
            local have = haveOf(slot[2]) or 0
            local isOpen = open and open(slot[2]) or false
            if i.ilvl and (isOpen or i.ilvl > have or (loose and i.ilvl >= have)) then
                out[#out + 1] = { key = r.itemKey, slot = slot[1], ilvl = i.ilvl, have = have, gain = i.ilvl - have,
                    price = r.minPrice or 0, open = isOpen }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.gain ~= b.gain then return a.gain > b.gain end
        return a.price < b.price
    end)
    while #out > (cap or M.MAX_USABLE) do out[#out] = nil end
    return out
end

-- Is one auction an upgrade? pawn = Pawn's best upgrade share for the item
-- (0 = Pawn says no; nil = Pawn isn't there or doesn't know the item).
-- wanted = the spec's endings (nil = its list names none). An item with an
-- ending is judged by that first: a wanted ending is an affordable upgrade
-- when it is a higher item level or the slot is open; any other ending is out.
function M.Verdict(pawn, ilvl, have, tail, wanted, open)
    if wanted and tail then
        if not wanted[tail] then return nil end
        if open or (ilvl and ilvl > (have or 0)) then
            return { kind = "match", value = ilvl or 0, text = tail .. (ilvl and (", ilvl " .. ilvl) or "") }
        end
        return nil
    end
    if pawn then
        if pawn <= 0 then return nil end
        return { kind = "pawn", value = pawn, text = ("+%d%% Pawn"):format(math.floor(pawn * 100 + 0.5)) }
    end
    if not ilvl or ilvl <= (have or 0) then return nil end
    return { kind = "ilvl", value = ilvl - (have or 0),
        text = (have or 0) > 0 and ("ilvl %d over %d"):format(ilvl, have) or ("ilvl %d, slot empty"):format(ilvl) }
end

-- Sort the result rows by a column. Blanks go last either way; ties by name.
-- "up" ranks ideal (list) items, then greens with a wanted ending, then Pawn
-- upgrades, then item-level ones.
local KIND = { list = 4, match = 3, pawn = 2, ilvl = 1 }
function M.Sort(rows, key, desc)
    local function val(r)
        if key == "slot" then return r.slot end
        if key == "name" then return r.name end
        if key == "score" then return r.score end
        if key == "have" then return r.have end
        if key == "cost" then return r.buyout end
        return r.up and (KIND[r.up.kind] or 0) * 1000000 + r.up.value or nil
    end
    table.sort(rows, function(a, b)
        local x, y = val(a), val(b)
        if x == nil or y == nil then
            if x ~= nil or y ~= nil then return x ~= nil end
        elseif x ~= y then
            if desc then return x > y end
            return x < y
        end
        if a.name ~= b.name then return a.name < b.name end
        return (a.id or 0) < (b.id or 0)
    end)
    return rows
end

---------------------------------------------------------------------------
-- Game side
---------------------------------------------------------------------------
local isOpen = false
local found = {}                 -- [name] = { auctions seen for that exact list item }
local queryOf = {}               -- [name] = the search text that found it
local wantedNow = {}             -- the last scan's list
local extra, extraByName = {}, {}   -- usable gear that isn't on the list: { name, slot, up, auctions }
local scan                       -- running scan, or nil
local done                       -- { checked, spec, usable } after a scan
local buying, bought = nil, {}   -- auction id being bought; ids bought
local lastNote
local token = 0
local sortKey, sortDesc = "up", true

local function api() return C_AuctionHouse end
local function refresh() if M.Refresh then M.Refresh() end end

function M.Supported()
    local a = api()
    return a ~= nil and a.SendBrowseQuery ~= nil and a.SendSearchQuery ~= nil and a.PlaceBid ~= nil
end

local function prefs() return ns.Char() end

function M.MyRange()
    local c = prefs()
    return M.Range(c.marketMin, c.marketMax)
end

function M.SetRange(minText, maxText)
    local lo, hi = M.Range(minText, maxText)
    if not lo then return nil, hi end
    local c = prefs()
    c.marketMin, c.marketMax = minText, maxText
    return lo, hi
end

function M.Usable() return prefs().marketUsable and true or false end
function M.SetUsable(on) prefs().marketUsable = on and true or nil end
-- The BiS list pass is on until the player unticks it.
function M.Ideal() return prefs().marketNoBis ~= true end
function M.SetIdeal(on) prefs().marketNoBis = (not on) and true or nil end

function M.SortBy(key)
    if sortKey == key then sortDesc = not sortDesc else sortKey, sortDesc = key, (key ~= "slot" and key ~= "name" and key ~= "cost") end
end
function M.SortState() return sortKey, sortDesc end

-- Rows to show: one per item that has an auction inside the range.
function M.Rows()
    local lo, hi = M.MyRange()
    local rows = {}
    if not lo then return rows end
    for _, w in ipairs(wantedNow) do
        local a = M.Cheapest(found[w.name], w.name, lo, hi)
        if a then
            rows[#rows + 1] = { id = a.id, name = w.name, slot = w.slot, score = w.score, have = w.have, gain = w.gain,
                up = { kind = "list", value = w.gain, text = ("Ideal, +%d%% on list"):format(math.floor(w.gain * 100 + 0.5)) },
                buyout = a.buyout, link = a.link, query = queryOf[w.name] or w.name, bought = bought[a.id] or false }
        end
    end
    for _, e in ipairs(extra) do
        local a = M.Cheapest(e.auctions, e.name, lo, hi)
        if a then
            rows[#rows + 1] = { id = a.id, name = e.name, slot = e.slot, up = e.up, buyout = a.buyout, link = a.link,
                query = M.BaseName(e.name) or e.name, bought = bought[a.id] or false }
        end
    end
    return M.Sort(rows, sortKey, sortDesc)
end

function M.State()
    return { open = isOpen, scanning = scan ~= nil, at = scan and scan.i or 0, total = scan and #scan.queue or #wantedNow,
        done = done, buying = buying, note = lastNote }
end

-- The auction house answers one request at a time and says when it is ready.
local waitingToSend
local function send(fn)
    local a = api()
    if a.IsThrottledMessageSystemReady and not a.IsThrottledMessageSystemReady() then
        waitingToSend = fn
        return
    end
    waitingToSend = nil
    if not pcall(fn) and scan then scan.skip() end
end

local function finish(note)
    if not scan then return end
    done = { checked = #scan.queue, spec = scan.spec, usable = scan.looked }
    scan, waitingToSend = nil, nil
    token = token + 1
    lastNote = note
    refresh()
end

local function sorts()
    local order = Enum and Enum.AuctionHouseSortOrder
    if order and order.Price then return { { sortOrder = order.Price, reverseSort = false } } end
    return {}
end

local function filters(usable)
    local f, out = Enum and Enum.AuctionHouseFilter, {}
    if not f then return out end
    if usable and f.UsableOnly then out[#out + 1] = f.UsableOnly end
    for _, k in ipairs({ "UncommonQuality", "RareQuality", "EpicQuality" }) do
        if f[k] then out[#out + 1] = f[k] end
    end
    return out
end

local step

-- Give up on one answer after M.WAIT seconds and move on.
local function arm()
    token = token + 1
    local mine = token
    if C_Timer and C_Timer.After then
        C_Timer.After(M.WAIT, function()
            if scan and token == mine then scan.skip() end
        end)
    end
end

local function browse(text)
    scan.phase, scan.text = "browse", text
    arm()
    send(function()
        api().SendBrowseQuery({ searchString = text, sorts = sorts(), filters = filters(false) })
    end)
end

local function searchNext()
    local key = table.remove(scan.keys, 1)
    if not key then
        local w = scan.queue[scan.i]
        local base = w and M.BaseName(w.name)
        if base and not scan.retried and #(found[w.name] or {}) == 0 then
            scan.retried = true
            return browse(base)
        end
        return step()
    end
    scan.phase = "search"
    arm()
    send(function() api().SendSearchQuery(key, sorts(), false) end)
end

---------------------------------------------------------------------------
-- The usable pass: gear you can equip that isn't on the list
---------------------------------------------------------------------------
local function itemLevelOf(item)
    local get = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
    if type(get) == "function" then
        local ok, n = pcall(get, item)
        if ok and type(n) == "number" and n > 0 then return n end
    end
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if type(info) == "function" then
        local ok, _, _, _, n = pcall(info, item)
        if ok and type(n) == "number" and n > 0 then return n end
    end
    return nil
end

-- Item level worn in a set of character-sheet slots: the lowest, 0 if one is empty.
local function wornLevel(slots)
    local low
    for _, slot in ipairs(slots) do
        local link = GetInventoryItemLink("player", slot)
        local n = link and itemLevelOf(link) or 0
        if not low or n < low then low = n end
    end
    return low or 0
end

-- Is everything worn in these slots already right for the spec: on its list,
-- or carrying one of its endings? An empty slot is not.
local function wornRight(slots)
    for _, slot in ipairs(slots) do
        local name = BiS.NameFromLink(GetInventoryItemLink("player", slot))
        if not name then return false end
        local tail = M.Tail(name)
        if not (scan.listNames[name] or (tail and scan.endings[tail])) then return false end
    end
    return true
end

local function pawnReady() return type(PawnGetItemData) == "function" and type(PawnIsItemAnUpgrade) == "function" end

-- Pawn's verdict on one item link: best upgrade share over the player's
-- scales, 0 for "not an upgrade", nil when Pawn isn't there or can't say.
local function pawnSays(link)
    if not (pawnReady() and link) then return nil end
    local ok, item = pcall(PawnGetItemData, link)
    if not ok or type(item) ~= "table" then return nil end
    local ok2, ups = pcall(PawnIsItemAnUpgrade, item)
    if not ok2 then return nil end
    local best = 0
    for _, u in ipairs(type(ups) == "table" and ups or {}) do
        if type(u) == "table" and type(u.PercentUpgrade) == "number" and u.PercentUpgrade > best then best = u.PercentUpgrade end
    end
    return best
end

local function keyInfo(key)
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if type(instant) ~= "function" or not key.itemID then return nil end
    local ok, _, _, _, equipLoc, _, classID, subClassID = pcall(instant, key.itemID)
    if not ok or type(equipLoc) ~= "string" then return nil end
    local _, class = UnitClass("player")
    local ilvl = type(key.itemLevel) == "number" and key.itemLevel > 0 and key.itemLevel or itemLevelOf(key.itemID)
    return { equipLoc = equipLoc, ilvl = ilvl, fits = M.Fits(class, UnitLevel and UnitLevel("player") or 60, classID, subClassID, equipLoc) }
end

local function usableNext()
    local c = table.remove(scan.cands, 1)
    if not c then return finish(nil) end
    scan.cand = c
    scan.looked = scan.looked + 1
    scan.phase = "usearch"
    refresh()
    arm()
    send(function() api().SendSearchQuery(c.key, sorts(), false) end)
end

local function usablePicked()
    local a = api()
    local ok, results = pcall(a.GetBrowseResults)
    local _, hi = M.MyRange()
    scan.cands = M.UsablePick(ok and type(results) == "table" and results or {}, keyInfo, wornLevel, hi, M.MAX_USABLE, pawnReady(),
        scan.endings and function(slots) return not wornRight(slots) end or nil)
    scan.ofUsable = #scan.cands
    usableNext()
end

local function usableBrowse()
    scan.stage, scan.phase, scan.looked, scan.cands = "usable", "ubrowse", 0, {}
    refresh()
    arm()
    send(function()
        api().SendBrowseQuery({ searchString = "", sorts = sorts(), filters = filters(true),
            itemClassFilters = { { classID = 2 }, { classID = 4 } } })
    end)
end

local function onUsableBrowse()
    local a = api()
    local ok, results = pcall(a.GetBrowseResults)
    local n = ok and type(results) == "table" and #results or 0
    local full = true
    if a.HasFullBrowseResults then
        local ok2, v = pcall(a.HasFullBrowseResults)
        full = not ok2 or v ~= false
    end
    if not full and n < M.MAX_BROWSE and a.RequestMoreBrowseResults then
        arm()
        return send(function() a.RequestMoreBrowseResults() end)
    end
    usablePicked()
end

local function onUsableSearch(itemKey)
    local a, c = api(), scan.cand
    local ok, n = pcall(a.GetNumItemSearchResults, itemKey)
    for i = 1, (ok and type(n) == "number" and n or 0) do
        local ok2, r = pcall(a.GetItemSearchResultInfo, itemKey, i)
        local name = ok2 and type(r) == "table" and BiS.NameFromLink(r.itemLink)
        if name and r.auctionID and not scan.onList[name] then
            local e = extraByName[name]
            if not e then
                local up = M.Verdict(pawnSays(r.itemLink), c.ilvl, c.have, M.Tail(name), scan.endings, c.open)
                if up then
                    e = { name = name, slot = c.slot, up = up, auctions = {} }
                    extraByName[name] = e
                    extra[#extra + 1] = e
                else
                    extraByName[name] = false
                end
            end
            if e then
                e.auctions[#e.auctions + 1] = { id = r.auctionID, name = name, buyout = r.buyoutAmount,
                    mine = r.containsOwnerItem or r.containsAccountItem or false, link = r.itemLink }
            end
        end
    end
    scan.phase = nil
    usableNext()
end

step = function()
    if not scan then return end
    scan.i = scan.i + 1
    scan.retried, scan.keys = false, {}
    local w = scan.queue[scan.i]
    if not w then
        if scan.usable then return usableBrowse() end
        return finish(nil)
    end
    refresh()
    browse(w.name)
end

-- Start a scan for the list the BiS Check tab is showing.
function M.Scan()
    if not M.Supported() then return nil, "This auction house can't be searched by addons." end
    if not isOpen then return nil, "Open the auction house first." end
    if scan then return nil, "Already scanning." end
    if buying then return nil, "Wait for the purchase to finish." end
    local lo, why = M.MyRange()
    if not lo then return nil, why end
    local key, list = BiS.CurrentSpec()
    if not list then return nil, "Blood Pact has no list for your class yet." end
    if not M.Ideal() and not M.Usable() then return nil, "Tick BiS list, Usable gear, or both." end
    local owned = BiS.Owned()
    wantedNow = M.Ideal() and M.Wanted(list, owned) or {}
    found, queryOf, extra, extraByName, bought, done, lastNote = {}, {}, {}, {}, {}, nil, nil
    -- The usable pass leaves out everything the list already covers, and what you own.
    local onList, listNames = {}, {}
    for name in pairs(owned) do onList[name] = true end
    for _, s in ipairs(list.slots) do
        for _, it in ipairs(s.items) do
            onList[it.name], listNames[it.name] = true, true
            if it.ally then onList[it.ally], listNames[it.ally] = true, true end
        end
    end
    scan = { queue = wantedNow, i = 0, keys = {}, spec = key, usable = M.Usable(), onList = onList, listNames = listNames,
        endings = M.Endings(list, select(2, UnitClass("player")), key), looked = 0, stage = "list" }
    scan.skip = function()
        if not scan then return end
        if scan.phase == "ubrowse" then return usablePicked() end
        if scan.stage == "usable" then return usableNext() end
        searchNext()
    end
    step()
    return true
end

function M.Stop()
    if scan then finish("Scan stopped.") end
end

local function onBrowse()
    if not scan then return end
    if scan.phase == "ubrowse" then return onUsableBrowse() end
    if scan.phase ~= "browse" then return end
    local a, w = api(), scan.queue[scan.i]
    local ok, results = pcall(a.GetBrowseResults)
    local keys = {}
    for _, r in ipairs(ok and type(results) == "table" and results or {}) do
        local name
        if a.GetItemKeyInfo and r.itemKey then
            local ok2, info = pcall(a.GetItemKeyInfo, r.itemKey)
            name = ok2 and type(info) == "table" and info.itemName or nil
        end
        if r.itemKey then keys[#keys + 1] = { key = r.itemKey, name = name } end
    end
    scan.keys = M.Candidates(keys, w.name, M.BaseName(w.name))
    scan.phase = nil
    searchNext()
end

local function onSearch(itemKey)
    if not scan or type(itemKey) ~= "table" then return end
    if scan.phase == "usearch" then return onUsableSearch(itemKey) end
    if scan.phase ~= "search" then return end
    local a, w = api(), scan.queue[scan.i]
    local ok, n = pcall(a.GetNumItemSearchResults, itemKey)
    local list = found[w.name] or {}
    for i = 1, (ok and type(n) == "number" and n or 0) do
        local ok2, r = pcall(a.GetItemSearchResultInfo, itemKey, i)
        if ok2 and type(r) == "table" and r.auctionID then
            local name = BiS.NameFromLink(r.itemLink)
            if name == w.name then queryOf[w.name] = scan.text end
            list[#list + 1] = { id = r.auctionID, name = name, buyout = r.buyoutAmount,
                mine = r.containsOwnerItem or r.containsAccountItem or false, link = r.itemLink }
        end
    end
    found[w.name] = list
    scan.phase = nil
    searchNext()
end

-- Click a row: show that item in the game's own auction window.
function M.Show(row)
    if not isOpen then return nil, "Open the auction house first." end
    if scan then return nil, "Wait for the scan to finish." end
    local f = AuctionHouseFrame
    local bar = f and f.SearchBar
    local box = bar and bar.SearchBox
    if not (box and box.SetText and bar.StartSearch) then
        return nil, "Blood Pact can't drive this auction window. Search there for: " .. row.query
    end
    local ok = pcall(function()
        if f.SetDisplayMode and AuctionHouseFrameDisplayMode and AuctionHouseFrameDisplayMode.Buy then
            f:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
        end
        box:SetText(row.query)
        bar:StartSearch()
    end)
    if not ok then return nil, "The auction window didn't take that. Search there for: " .. row.query end
    return true
end

-- One click, one item, at the buyout shown on the button.
function M.Buy(row)
    if not M.Supported() then return nil, "This auction house can't be used by addons." end
    if not isOpen then return nil, "Open the auction house first." end
    if scan then return nil, "Wait for the scan to finish." end
    if buying then return nil, "Still buying the last one. One item at a time." end
    if row.bought or bought[row.id] then return nil, "You already bought that one." end
    if (GetMoney and GetMoney() or 0) < row.buyout then return nil, "You don't have " .. Orders.Money(row.buyout) .. "." end
    buying, lastNote = row.id, nil
    if not pcall(api().PlaceBid, row.id, row.buyout) then
        buying = nil
        return nil, "The auction house didn't take that. Scan again."
    end
    token = token + 1
    local mine = token
    if C_Timer and C_Timer.After then
        C_Timer.After(M.WAIT, function()
            if buying == row.id and token == mine then
                buying, lastNote = nil, "No answer from the auction house. Check your mailbox before buying it again."
                refresh()
            end
        end)
    end
    return true
end

ns.On("AUCTION_HOUSE_SHOW", function() isOpen = true; refresh() end)
ns.On("AUCTION_HOUSE_CLOSED", function()
    isOpen, buying = false, nil
    if scan then finish("The auction house closed, so the scan stopped.") else refresh() end
end)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", onBrowse)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function() if scan and scan.phase == "ubrowse" then onUsableBrowse() end end)
ns.On("AUCTION_HOUSE_BROWSE_FAILURE", function() if scan and (scan.phase == "browse" or scan.phase == "ubrowse") then scan.skip() end end)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", onSearch)
ns.On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
    local fn = waitingToSend
    if fn then send(fn) end
end)
ns.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function(id)
    if not buying then return end
    if id == nil or id == buying then
        bought[buying] = true
        buying, lastNote = nil, "Bought. Collect it from your mailbox."
        refresh()
    end
end)
ns.On("AUCTION_HOUSE_SHOW_ERROR", function()
    if not buying then return end
    buying, lastNote = nil, "The auction house refused that. It may have just sold. Scan again."
    refresh()
end)

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local W = ns.W
local helping = false

local function pct(x) return math.floor(x * 100 + 0.5) .. "%" end

local HEADS = { { "slot", "Slot", 12, 74 }, { "name", "Item", 88, 214 }, { "score", "List score", 304, 74 },
    { "have", "You have", 380, 70 }, { "up", "Upgrade", 452, 154 }, { "cost", "Cost", 608, 100 } }

local function build()
    local f = CreateFrame("Frame", "BloodPactMarket", UIParent)
    f:SetSize(720, 360)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:EnableMouse(true)
    W.Glass(f, true)
    f.title = W.Text(f, "", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -9)
    f.title:SetWidth(660)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    W.Button(f, "X", 22, 20, function() f:Hide() end):SetPoint("TOPRIGHT", -6, -6)
    W.Line(f, -32)

    W.Text(f, "Gold per item: from", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 12, -46)
    f.lo = W.Edit(f, 60, 6)
    f.lo:SetPoint("TOPLEFT", 124, -42)
    W.Text(f, "to", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 192, -46)
    f.hi = W.Edit(f, 60, 6)
    f.hi:SetPoint("TOPLEFT", 210, -42)
    local function typed()
        local lo, why = M.SetRange(f.lo:GetText(), f.hi:GetText())
        lastNote = (not lo) and why or nil
        refresh()
    end
    f.lo:HookScript("OnTextChanged", typed)
    f.hi:HookScript("OnTextChanged", typed)
    f.scan = W.Button(f, "Scan", 80, 22, function()
        if scan then
            M.Stop()
        else
            local _, why = M.Scan()
            if why then lastNote = why end
        end
        refresh()
    end)
    f.scan:SetPoint("TOPLEFT", 284, -42)
    f.ideal = W.Check(f, "BiS list", function(on)
        M.SetIdeal(on)
        lastNote = "Press Scan to search again."
        refresh()
    end)
    f.ideal:SetPoint("TOPLEFT", 378, -45)
    f.usable = W.Check(f, "Usable gear", function(on)
        M.SetUsable(on)
        lastNote = "Press Scan to search again."
        refresh()
    end)
    f.usable:SetPoint("TOPLEFT", 458, -45)
    f.help = W.Button(f, "How does this work?", 150, 22, function()
        helping = not helping
        refresh()
    end)
    f.help:SetPoint("TOPRIGHT", -12, -42)
    f.status = W.Text(f, "", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", 12, -70)
    f.status:SetWidth(696)
    f.status:SetJustifyH("LEFT")
    f.status:SetWordWrap(false)

    f.heads = {}
    for i, h in ipairs(HEADS) do
        local b = W.SortButton(f, h[2], h[4], function()
            M.SortBy(h[1])
            refresh()
        end)
        b.key = h[1]
        b:SetPoint("TOPLEFT", h[3], -90)
        f.heads[i] = b
    end
    f.rows = W.List(f, 696, 196, 20, function(row, r)
        f.rows.Col(row, 1, 4, 72):SetText(U.Safe(r.slot, 20))
        f.rows.Col(row, 2, 80, 212):SetText(U.Safe(r.name, 60))
        f.rows.Col(row, 3, 296, 72):SetText(r.score and pct(r.score) or "-")
        local have = f.rows.Col(row, 4, 372, 68)
        have:SetText(r.have and pct(r.have) or "-")
        have:SetTextColor(W.C.muted[1], W.C.muted[2], W.C.muted[3])
        f.rows.Col(row, 5, 444, 152):SetText(r.up and r.up.text or "")
        if not row.act then
            row.act = W.Button(row, "", 96, 18)
            row.act:SetPoint("RIGHT", -4, 0)
        end
        local kind, text = M.ButtonFor(r, isOpen and M.Supported() and not scan, GetMoney and GetMoney() or 0, buying)
        row.act:SetShown(text ~= "")
        row.act:SetText(text)
        row.act:SetEnabled(kind == "buy")
        row.act:SetScript("OnClick", function()
            local ok, why = M.Buy(r)
            if not ok then lastNote = why end
            refresh()
        end)
    end, function(r)
        local ok, why = M.Show(r)
        lastNote = ok and ("Showing " .. r.query .. " in the auction window. Drag this window aside if it is in the way.") or why
        refresh()
    end)
    f.rows.scroll:SetPoint("TOPLEFT", 12, -112)
    f.rows.scroll:SetSize(696, 196)
    f.helpText = W.Text(f, table.concat(M.HOWTO, "\n\n"), "GameFontHighlightSmall")
    f.helpText:SetPoint("TOPLEFT", 14, -92)
    f.helpText:SetWidth(692)
    f.helpText:SetJustifyH("LEFT")
    f.helpText:SetJustifyV("TOP")
    f.helpText:SetWordWrap(true)
    f.foot = W.Text(f, "", "GameFontDisableSmall")
    f.foot:SetPoint("BOTTOMLEFT", 12, 10)
    f.foot:SetWidth(696)
    f.foot:SetJustifyH("LEFT")
    f.foot:SetWordWrap(false)
    f:SetScript("OnHide", function() M.Stop() end)
    f:Hide()
    M.frame = f
    return f
end

function M.Refresh()
    local f = M.frame
    if not (f and f:IsShown()) then return end
    local specKey, list = BiS.CurrentSpec()
    f.title:SetText("Upgrades for sale: " .. U.Safe(list and list.label or "no list for your class", 50))
    f.help:SetText(helping and "Back to the list" or "How does this work?")
    for _, b in ipairs(f.heads) do
        b:SetShown(not helping)
        b:SetSort(b.key == sortKey and (sortDesc and "down" or "up") or nil)
    end
    f.rows.scroll:SetShown(not helping)
    f.helpText:SetShown(helping)
    f.usable:SetChecked(M.Usable())
    f.ideal:SetChecked(M.Ideal())
    f.scan:SetText(scan and "Stop" or "Scan")
    f.scan:SetEnabled(scan ~= nil or (isOpen and M.Supported() and list ~= nil and not buying))
    local lo, hi = M.MyRange()
    local rows = M.Rows()
    if lastNote then
        f.status:SetText("|cffffd100" .. lastNote .. "|r")
    elseif not list then
        f.status:SetText("Blood Pact doesn't have a list for your class yet.")
    elseif not M.Supported() then
        f.status:SetText("This auction house can't be searched by addons.")
    elseif scan and scan.phase == "ubrowse" then
        f.status:SetText("Reading the usable gear on the auction house...")
    elseif scan and scan.stage == "usable" then
        f.status:SetText(("Checking usable gear, %d of %d kinds"):format(scan.looked, scan.ofUsable or scan.looked))
    elseif scan then
        local w = scan.queue[scan.i]
        f.status:SetText(("Looking up %d of %d: %s"):format(scan.i, #scan.queue, U.Safe(w and w.name or "", 50)))
    elseif not isOpen then
        f.status:SetText("|cffff6040Open the auction house to scan.|r")
    elseif not done then
        f.status:SetText("Set your gold range, tick BiS list, Usable gear or both, then press Scan.")
    elseif #rows == 0 then
        f.status:SetText(("Looked up %s. Nothing is for sale %s right now."):format(M.LookedText(done.checked, done.usable), M.RangeText(lo, hi)))
    else
        f.status:SetText(("%d for sale %s, from %s. Click a row to see it in the auction window."):format(#rows,
            M.RangeText(lo, hi), M.LookedText(done.checked, done.usable)))
    end
    local ends = list and M.Endings(list, select(2, UnitClass("player")), specKey)
    f.foot:SetText(M.Usable() and (ends and ("Affordable = greens ending in: " .. U.Safe(M.EndingsText(ends), 70) .. ". Other gear: "
            .. (pawnReady() and "Pawn's stat weights." or "item level only, check the tooltip."))
        or (pawnReady() and "Usable gear is judged by Pawn's stat weights."
            or "Usable gear is judged by item level only. Check the tooltip first."))
        or "Ranks are from the BiS Check list for your spec. The price on the Buy button is what you pay.")
    if not helping then f.rows:SetItems(rows) end
end

function M.Open()
    local f = M.frame or build()
    helping, lastNote = false, nil
    f:Show()
    local c = prefs()
    f.lo:SetText(tostring(c.marketMin or ""))
    f.hi:SetText(tostring(c.marketMax or ""))
    M.Refresh()
end
