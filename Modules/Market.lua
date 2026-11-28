-- Speakeasy: find pre-raid BiS upgrades on the auction house.
--
-- Works for every class and spec: it takes the list the BiS Check tab is
-- showing, keeps the items that rank above what you own, and looks each one
-- up at the auction house. You set a gold range; the window lists what is
-- for sale inside it, cheapest buyout first, with one Buy button per item.
--
-- One click buys one item at the buyout price printed on its button. The
-- game needs a real click for every purchase, and Speakeasy does not act
-- for the player. Bids are never placed below the buyout.
local _, ns = ...
local M = {}
ns.Market = M

local U, BiS, Orders = ns.U, ns.BiS, ns.Orders

M.MAX_GOLD = 999999
M.WAIT = 8          -- seconds to wait for one answer from the auction house
M.MAX_KEYS = 4      -- variants of one item looked at per search
M.MAX_BROWSE = 2000 -- kinds of usable gear read from the auction house in one scan
M.MAX_USABLE = 40   -- upgrades priced in one scan, biggest first
M.HOWTO = {
    "1. Open the auction house, then press \"Find upgrades for sale\" on the BiS Check tab.",
    "2. Type the least and the most gold you want to pay for one item. Leave a box empty for no limit.",
    "3. Two boxes choose what is scanned: \"BiS list\" and \"Usable gear\". Tick one or both, then press Scan.",
    "\"BiS list\" looks up every item on your spec's list that ranks above what you own. It takes a moment: the auction house answers one search at a time.",
    "\"Usable gear\" needs the Pawn addon. Speakeasy reads the weapons and armor you can equip, cheapest first, and asks Pawn about each one. Pawn compares the item's real stats with what you are wearing, using its stat weights for your spec, so a higher item level alone doesn't count and a two-hander is compared properly with a main hand and off-hand. Only what Pawn calls an upgrade is listed, with Pawn's percentage.",
    "A most-gold limit makes the usable scan much faster: it stops reading once prices pass it. Up to 40 upgrades are priced per scan, biggest first.",
    "4. Click a column heading to sort; click it again to reverse. Click a row to show that item in the auction window.",
    "5. Press Buy to buy that one item at the price on the button, then collect it from your mailbox. One item per click: the game needs your own click for every purchase. Only items with a buyout are listed; Speakeasy never bids.",
    "Quest rewards and Tier 0.5 pieces are skipped on the BiS list, because they can't be sold. The list follows the spec picked on the BiS Check tab; Pawn follows the scales you have turned on in Pawn.",
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

-- Pawn's answer for one item, as a row's "Upgrade" entry. share = Pawn's best
-- upgrade over the scales the player has on (0.21 = +21%). At or above Pawn's
-- own "big upgrade" mark (an empty slot, usually) Pawn shows no number either.
function M.Verdict(share, big)
    if type(share) ~= "number" or share <= 0 then return nil end
    if big and share >= big then return { kind = "pawn", value = share, text = "Pawn: big upgrade" } end
    return { kind = "pawn", value = share, text = ("+%d%% Pawn"):format(math.floor(share * 100 + 0.5)) }
end

-- Which upgrades get priced: the biggest first, cheapest first among equals.
function M.UsableRank(cands, cap)
    table.sort(cands, function(a, b)
        if (a.share or 0) ~= (b.share or 0) then return (a.share or 0) > (b.share or 0) end
        return (a.price or 0) < (b.price or 0)
    end)
    while #cands > (cap or M.MAX_USABLE) do cands[#cands] = nil end
    return cands
end

-- Keep asking the auction house for more usable gear? The list comes
-- cheapest first, so it can stop once prices pass the most you'll pay.
function M.MorePages(full, count, lastPrice, hi, max)
    if full or count >= (max or M.MAX_BROWSE) then return false end
    if hi and lastPrice and lastPrice > hi then return false end
    return true
end

-- Sort the result rows by a column. Blanks go last either way; ties by name.
-- "up" ranks list items above Pawn upgrades.
local KIND = { list = 2, pawn = 1 }
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
                query = e.name, bought = bought[a.id] or false }
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
    if not note and scan.noPawn then note = "BiS list scanned. Usable gear was skipped: it needs the Pawn addon." end
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
function M.PawnInstalled()
    return type(PawnGetItemData) == "function" and type(PawnIsItemAnUpgrade) == "function"
end

local function pawnReady()
    if not M.PawnInstalled() then return false end
    if type(PawnIsReady) ~= "function" then return true end
    local ok, ready = pcall(PawnIsReady)
    return ok and ready and true or false
end

-- Pawn's verdict on one item link: its best upgrade share over the scales the
-- player has on, false for "not an upgrade", nil when the game hasn't loaded
-- the item yet (ask again shortly).
local function pawnSays(link)
    if type(PawnCanItemHaveStats) == "function" then
        local ok, can = pcall(PawnCanItemHaveStats, link)
        if ok and not can then return false end
    end
    local ok, item = pcall(PawnGetItemData, link)
    if not ok then return false end
    if type(item) ~= "table" then return nil end
    local ok2, ups = pcall(PawnIsItemAnUpgrade, item)
    if not ok2 or type(ups) ~= "table" then return false end
    local best = 0
    for _, u in ipairs(ups) do
        if type(u) == "table" and type(u.PercentUpgrade) == "number" and u.PercentUpgrade > best then best = u.PercentUpgrade end
    end
    return best > 0 and best or false
end

local function slotOf(itemID)
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if type(instant) ~= "function" or not itemID then return nil end
    local ok, _, _, _, equipLoc = pcall(instant, itemID)
    local slot = ok and M.EQUIP[equipLoc]
    return slot and slot[1] or nil
end

local function usableNext()
    local c = table.remove(scan.cands, 1)
    if not c then return finish(nil) end
    scan.cand = c
    scan.priced = scan.priced + 1
    scan.phase = "usearch"
    refresh()
    arm()
    send(function() api().SendSearchQuery(c.key, sorts(), false) end)
end

-- One kind of gear from the auction house's list: ask Pawn about it.
local function judgeRow(r)
    local a, key = api(), r.itemKey
    local _, hi = M.MyRange()
    if type(key) ~= "table" or (hi and (r.minPrice or 0) > hi) then return end
    local slot = slotOf(key.itemID)
    if not slot then return end
    if not a.GetItemKeySampleLink then
        -- No link for a kind on this client: Pawn judges each auction's own link instead.
        scan.cands[#scan.cands + 1] = { key = key, slot = slot, price = r.minPrice or 0 }
        return
    end
    local ok, link = pcall(a.GetItemKeySampleLink, key)
    local share
    if ok and type(link) == "string" then
        local name = BiS.NameFromLink(link)
        if name and scan.onList[name] then return end
        share = pawnSays(link)
    end
    if share == nil then
        scan.unknown[#scan.unknown + 1] = r
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, key.itemID) end
    elseif share then
        scan.cands[#scan.cands + 1] = { key = key, slot = slot, price = r.minPrice or 0, share = share }
    end
end

-- Pawn reads every item's stats, so the list is worked through a few dozen
-- at a time to keep the game smooth. Items the game hadn't loaded yet get
-- two more tries a second apart.
local function judgeSome()
    if not (scan and scan.phase == "judge") then return end
    local n = 0
    while scan.ji < #scan.rows and n < 40 do
        scan.ji = scan.ji + 1
        n = n + 1
        judgeRow(scan.rows[scan.ji])
    end
    refresh()
    if scan.ji < #scan.rows then
        return C_Timer.After(0.02, judgeSome)
    end
    if #scan.unknown > 0 and scan.pass < 3 then
        scan.pass = scan.pass + 1
        scan.rows, scan.unknown, scan.ji = scan.unknown, {}, 0
        return C_Timer.After(1, judgeSome)
    end
    scan.cands = M.UsableRank(scan.cands, M.MAX_USABLE)
    scan.ofUsable = #scan.cands
    usableNext()
end

local function usableJudge()
    local ok, results = pcall(api().GetBrowseResults)
    scan.rows = {}
    for i, r in ipairs(ok and type(results) == "table" and results or {}) do scan.rows[i] = r end
    scan.looked = #scan.rows
    scan.phase, scan.ji, scan.pass, scan.unknown, scan.cands = "judge", 0, 1, {}, {}
    token = token + 1
    judgeSome()
end

local function usableBrowse()
    scan.stage, scan.phase, scan.looked, scan.priced, scan.cands = "usable", "ubrowse", 0, 0, {}
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
    local _, hi = M.MyRange()
    scan.looked = n
    if a.RequestMoreBrowseResults and M.MorePages(full, n, n > 0 and results[n].minPrice or nil, hi, M.MAX_BROWSE) then
        refresh()
        arm()
        return send(function() a.RequestMoreBrowseResults() end)
    end
    usableJudge()
end

local function onUsableSearch(itemKey)
    local a, c = api(), scan.cand
    local big = type(PawnBigUpgradeThreshold) == "number" and PawnBigUpgradeThreshold or nil
    local ok, n = pcall(a.GetNumItemSearchResults, itemKey)
    for i = 1, (ok and type(n) == "number" and n or 0) do
        local ok2, r = pcall(a.GetItemSearchResultInfo, itemKey, i)
        local name = ok2 and type(r) == "table" and BiS.NameFromLink(r.itemLink)
        if name and r.auctionID and not scan.onList[name] then
            local e = extraByName[name]
            if e == nil then
                local up = M.Verdict(c.share or pawnSays(r.itemLink), big)
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
    if not list then return nil, "Speakeasy has no list for your class yet." end
    if not M.Ideal() and not M.Usable() then return nil, "Tick BiS list, Usable gear, or both." end
    local usable = M.Usable() and pawnReady()
    if M.Usable() and not usable and not M.Ideal() then
        return nil, M.PawnInstalled() and "Pawn is still starting up. Try again in a moment." or "Usable gear needs the Pawn addon. Install Pawn, then type /reload."
    end
    local owned = BiS.Owned()
    wantedNow = M.Ideal() and M.Wanted(list, owned) or {}
    found, queryOf, extra, extraByName, bought, done, lastNote = {}, {}, {}, {}, {}, nil, nil
    -- The usable pass leaves out everything the list already covers, and what you own.
    local onList = {}
    for name in pairs(owned) do onList[name] = true end
    for _, s in ipairs(list.slots) do
        for _, it in ipairs(s.items) do
            onList[it.name] = true
            if it.ally then onList[it.ally] = true end
        end
    end
    scan = { queue = wantedNow, i = 0, keys = {}, spec = key, usable = usable, onList = onList, looked = 0, priced = 0, stage = "list",
        noPawn = M.Usable() and not usable }
    scan.skip = function()
        if not scan then return end
        if scan.phase == "judge" then return end
        if scan.phase == "ubrowse" then return usableJudge() end
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
        return nil, "Speakeasy can't drive this auction window. Search there for: " .. row.query
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
    local _, list = BiS.CurrentSpec()
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
        f.status:SetText("Speakeasy doesn't have a list for your class yet.")
    elseif not M.Supported() then
        f.status:SetText("This auction house can't be searched by addons.")
    elseif scan and scan.phase == "ubrowse" then
        f.status:SetText(("Reading the usable gear on the auction house, cheapest first: %d kinds so far"):format(scan.looked))
    elseif scan and scan.phase == "judge" then
        f.status:SetText(("Pawn is checking usable gear: %d of %d%s"):format(scan.ji, #scan.rows, scan.pass > 1 and " (another look)" or ""))
    elseif scan and scan.stage == "usable" then
        f.status:SetText(("Pricing the upgrades Pawn found: %d of %d"):format(scan.priced, scan.ofUsable or scan.priced))
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
    f.foot:SetText(M.Usable() and (M.PawnInstalled() and "Usable gear is judged by Pawn's stat weights for the scales you have on. The price on the Buy button is what you pay."
        or "|cffff6040Usable gear needs the Pawn addon.|r Install Pawn, type /reload, then scan again. The BiS list works without it.")
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
