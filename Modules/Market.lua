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
M.HOWTO = {
    "1. Open the auction house, then press \"Find upgrades for sale\" on the BiS Check tab.",
    "2. Type the least and the most gold you want to pay for one item. Leave a box empty for no limit.",
    "3. Press Scan. Blood Pact looks up every item on your spec's list that ranks above what you own. It takes a moment: the auction house answers one search at a time.",
    "4. The list shows what is for sale in your gold range, biggest upgrade first, with the cheapest buyout for each.",
    "5. Press Buy on a row to buy that one item at the price on the button. Collect it from your mailbox.",
    "One item per click: the game needs your own click for every purchase, so nothing is bought for you.",
    "Only items with a buyout price are listed. Blood Pact never bids.",
    "Quest rewards and Tier 0.5 pieces are skipped, because they can't be sold. Dungeon drops are looked up too, but most of those can't be sold either, so expect them to come back empty.",
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

---------------------------------------------------------------------------
-- Game side
---------------------------------------------------------------------------
local isOpen = false
local found = {}                 -- [name] = { auctions seen for that exact item }
local wantedNow = {}             -- the last scan's list
local scan                       -- running scan, or nil
local done                       -- { checked, spec } after a scan
local buying, bought = nil, {}   -- auction id being bought; ids bought
local lastNote
local token = 0

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

-- Rows to show: one per wanted item that has an auction inside the range.
function M.Rows()
    local lo, hi = M.MyRange()
    local rows = {}
    if not lo then return rows end
    for _, w in ipairs(wantedNow) do
        local a = M.Cheapest(found[w.name], w.name, lo, hi)
        if a then
            rows[#rows + 1] = { id = a.id, name = w.name, slot = w.slot, score = w.score, have = w.have, gain = w.gain,
                buyout = a.buyout, link = a.link, bought = bought[a.id] or false }
        end
    end
    return rows
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
    done = { checked = #scan.queue, spec = scan.spec }
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

local function filters()
    local f, out = Enum and Enum.AuctionHouseFilter, {}
    if not f then return out end
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
    scan.phase = "browse"
    arm()
    send(function()
        api().SendBrowseQuery({ searchString = text, sorts = sorts(), filters = filters() })
    end)
end

local function searchNext()
    local key = table.remove(scan.keys, 1)
    if not key then
        local w = scan.queue[scan.i]
        local base = M.BaseName(w.name)
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

step = function()
    if not scan then return end
    scan.i = scan.i + 1
    scan.retried, scan.keys = false, {}
    local w = scan.queue[scan.i]
    if not w then return finish(nil) end
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
    wantedNow = M.Wanted(list, BiS.Owned())
    found, bought, done, lastNote = {}, {}, nil, nil
    if #wantedNow == 0 then
        done = { checked = 0, spec = key }
        refresh()
        return true
    end
    scan = { queue = wantedNow, i = 0, keys = {}, spec = key }
    scan.skip = function() if scan then searchNext() end end
    step()
    return true
end

function M.Stop()
    if scan then finish("Scan stopped.") end
end

local function onBrowse()
    if not (scan and scan.phase == "browse") then return end
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
    if not (scan and scan.phase == "search") or type(itemKey) ~= "table" then return end
    local a, w = api(), scan.queue[scan.i]
    local ok, n = pcall(a.GetNumItemSearchResults, itemKey)
    local list = found[w.name] or {}
    for i = 1, (ok and type(n) == "number" and n or 0) do
        local ok2, r = pcall(a.GetItemSearchResultInfo, itemKey, i)
        if ok2 and type(r) == "table" and r.auctionID then
            list[#list + 1] = { id = r.auctionID, name = BiS.NameFromLink(r.itemLink), buyout = r.buyoutAmount,
                mine = r.containsOwnerItem or r.containsAccountItem or false, link = r.itemLink }
        end
    end
    found[w.name] = list
    scan.phase = nil
    searchNext()
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
ns.On("AUCTION_HOUSE_BROWSE_FAILURE", function() if scan and scan.phase == "browse" then scan.skip() end end)
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

local function build()
    local f = CreateFrame("Frame", "BloodPactMarket", UIParent)
    f:SetSize(600, 350)
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
    f.title:SetWidth(540)
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
    f.scan = W.Button(f, "Scan", 90, 22, function()
        if scan then
            M.Stop()
        else
            local _, why = M.Scan()
            if why then lastNote = why end
        end
        refresh()
    end)
    f.scan:SetPoint("TOPLEFT", 284, -42)
    f.help = W.Button(f, "How does this work?", 150, 22, function()
        helping = not helping
        refresh()
    end)
    f.help:SetPoint("TOPRIGHT", -12, -42)
    f.status = W.Text(f, "", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", 12, -70)
    f.status:SetWidth(576)
    f.status:SetJustifyH("LEFT")
    f.status:SetWordWrap(false)

    f.heads = {}
    for i, h in ipairs({ { "Slot", 16, 80, "LEFT" }, { "Item", 100, 230, "LEFT" }, { "List score", 334, 70, "RIGHT" },
        { "You have", 408, 60, "RIGHT" } }) do
        local fs = W.Text(f, h[1], "GameFontDisableSmall")
        fs:SetPoint("TOPLEFT", h[2], -92)
        fs:SetWidth(h[3])
        fs:SetJustifyH(h[4])
        f.heads[i] = fs
    end
    f.rows = W.List(f, 576, 190, 20, function(row, r)
        f.rows.Col(row, 1, 4, 80):SetText(U.Safe(r.slot, 20))
        f.rows.Col(row, 2, 88, 230):SetText(U.Safe(r.name, 60))
        f.rows.Col(row, 3, 322, 70, "RIGHT"):SetText(pct(r.score))
        local have = f.rows.Col(row, 4, 396, 60, "RIGHT")
        have:SetText(pct(r.have))
        have:SetTextColor(W.C.muted[1], W.C.muted[2], W.C.muted[3])
        if not row.act then
            row.act = W.Button(row, "", 104, 18)
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
    end)
    f.rows.scroll:SetPoint("TOPLEFT", 12, -108)
    f.rows.scroll:SetSize(576, 190)
    f.helpText = W.Text(f, table.concat(M.HOWTO, "\n\n"), "GameFontHighlightSmall")
    f.helpText:SetPoint("TOPLEFT", 14, -92)
    f.helpText:SetWidth(572)
    f.helpText:SetJustifyH("LEFT")
    f.helpText:SetJustifyV("TOP")
    f.helpText:SetWordWrap(true)
    f.foot = W.Text(f, "", "GameFontDisableSmall")
    f.foot:SetPoint("BOTTOMLEFT", 12, 10)
    f.foot:SetWidth(576)
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
    for _, fs in ipairs(f.heads) do fs:SetShown(not helping) end
    f.rows.scroll:SetShown(not helping)
    f.helpText:SetShown(helping)
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
    elseif scan then
        local w = scan.queue[scan.i]
        f.status:SetText(("Looking up %d of %d: %s"):format(scan.i, #scan.queue, U.Safe(w and w.name or "", 50)))
    elseif not isOpen then
        f.status:SetText("|cffff6040Open the auction house to scan.|r")
    elseif not done then
        f.status:SetText("Set your gold range, then press Scan.")
    elseif done.checked == 0 then
        f.status:SetText("|cff40ff40Nothing to look for: you own the best of every item that can be sold.|r")
    elseif #rows == 0 then
        f.status:SetText(("Looked up %d items. None are for sale %s right now."):format(done.checked, M.RangeText(lo, hi)))
    else
        f.status:SetText(("%d of %d items are for sale %s. One Buy click buys one item."):format(#rows, done.checked, M.RangeText(lo, hi)))
    end
    f.foot:SetText("Ranks are from the BiS Check list for your spec. The price on the Buy button is what you pay.")
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
