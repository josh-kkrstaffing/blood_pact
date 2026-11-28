-- Speakeasy: buy a recipe's materials at the auction house.
--
-- Pick a recipe, say how many crafts (1 to 20), and the window lists each
-- material: needed, held, still to buy. Each material is bought with its own
-- two clicks: "Get price" asks the auction house what that quantity costs at
-- the lowest prices right now, then the button shows that total and a second
-- click pays it.
--
-- One click never buys more than one material. The game requires a real click
-- for every purchase, and Speakeasy does not act for the player.
local _, ns = ...
local S = {}
ns.Shop = S

local U, Orders = ns.U, ns.Orders

S.MAX_CRAFTS = 20
S.HOWTO = {
    "1. Open the auction house, then press Mats on a recipe.",
    "2. Type how many you want to craft, 1 to 20.",
    "3. The list shows each material: how many you need, how many you have (bags and bank), and how many are left to buy.",
    "4. Press Get price on a material. The auction house answers with the real cost of that many at the lowest prices right now.",
    "5. The button changes to Buy with that total. Press it to pay, then collect the materials from your mailbox.",
    "One material at a time: the game needs your own click for every purchase, so nothing is bought for you.",
    "\"Each\" is Auctionator's last scan and can be out of date. The price on the Buy button is the one you pay.",
    "No button on a row means the auction house doesn't sell it in bulk, or you already have enough. Vendor items have to be bought from a vendor.",
}

---------------------------------------------------------------------------
-- Pure rules
---------------------------------------------------------------------------
-- "3" -> 3. Whole numbers 1 to 20 only.
function S.Crafts(text)
    local n = tonumber(text)
    if not n or n ~= math.floor(n) or n < 1 or n > S.MAX_CRAFTS then
        return nil, ("Type a whole number from 1 to %d."):format(S.MAX_CRAFTS)
    end
    return n
end

-- reagents = { { item, n } }. -> rows { item, name, need, have, buy, each, est },
-- the estimated cost of what is left to buy, and how many of those have no price.
function S.Plan(reagents, crafts, countOf, priceOf, nameOf)
    local rows, total, unpriced = {}, 0, 0
    for _, r in ipairs(reagents or {}) do
        local need = r.n * crafts
        local have = countOf(r.item) or 0
        local buy = math.max(0, need - have)
        local each = priceOf(r.item)
        if buy > 0 then
            if each then total = total + each * buy else unpriced = unpriced + 1 end
        end
        rows[#rows + 1] = { item = r.item, name = nameOf(r.item) or ("item " .. r.item), need = need, have = have,
            buy = buy, each = each, est = each and buy > 0 and each * buy or nil }
    end
    return rows, total, unpriced
end

-- What a row's button does right now. quote = { item, qty, total } or nil.
-- -> "none" | "price" | "wait" | "pay" | "poor", and the button's text.
function S.ButtonFor(row, quote, busy, open, bulk, money)
    if row.buy <= 0 or not open or not bulk then return "none", "" end
    if busy == row.item then return "wait", "Waiting..." end
    if quote and quote.item == row.item and quote.qty == row.buy then
        if money < quote.total then return "poor", "Need " .. Orders.Money(quote.total) end
        return "pay", "Buy " .. Orders.Money(quote.total)
    end
    return "price", "Get price"
end

---------------------------------------------------------------------------
-- Game side
---------------------------------------------------------------------------
local rid, crafts = nil, 1
local quote, busy, isOpen, lastNote = nil, nil, false, nil

local function api() return C_AuctionHouse end

function S.Supported()
    local a = api()
    return a ~= nil and a.StartCommoditiesPurchase ~= nil and a.ConfirmCommoditiesPurchase ~= nil
end

local function held(item)
    local get = (C_Item and C_Item.GetItemCount) or GetItemCount
    if type(get) ~= "function" then return 0 end
    local ok, n = pcall(get, item, true)
    return ok and type(n) == "number" and n or 0
end

-- What was bought goes to the mailbox, so bags don't show it yet. Count it
-- as held from the moment it is paid for, or the same thing gets bought twice.
-- pending[item] = { base = held when bought, qty = bought since }.
local pending, paying = {}, nil
function S.Held(have, p)
    if not p then return have end
    return math.max(have, p.base + p.qty)
end
local function count(item) return S.Held(held(item), pending[item]) end

local function itemName(item)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if type(get) ~= "function" then return nil end
    local ok, name = pcall(get, item)
    return ok and type(name) == "string" and name or nil
end

-- Sold in bulk (a "commodity")? Unknown counts as yes: the auction house says no itself.
local function bulk(item)
    local a = api()
    if not (a and a.GetItemCommodityStatus) then return true end
    local ok, status = pcall(a.GetItemCommodityStatus, item)
    return not (ok and status == 1)
end

local function dropQuote()
    local a = api()
    if (quote or busy) and a and a.CancelCommoditiesPurchase then pcall(a.CancelCommoditiesPurchase) end
    quote, busy = nil, nil
end

function S.Rows()
    if not rid then return {}, 0, 0 end
    return S.Plan(ns.Recipes.Reagents(rid), crafts, count, Orders.PriceOf, itemName)
end

function S.State() return { rid = rid, crafts = crafts, quote = quote, busy = busy, open = isOpen, note = lastNote } end

function S.SetCrafts(text)
    local n, why = S.Crafts(text)
    if not n then return nil, why end
    if n ~= crafts then
        crafts = n
        dropQuote()
    end
    return n
end

-- First click on a material: ask the auction house what that many cost now.
function S.Quote(row)
    if not S.Supported() then return nil, "This auction house can't sell materials in bulk to addons." end
    if not isOpen then return nil, "Open the auction house first." end
    if row.buy <= 0 then return nil, "You already have enough." end
    if busy then return nil, "Still waiting for the auction house. One material at a time." end
    dropQuote()
    busy, lastNote = row.item, nil
    local ok = pcall(api().StartCommoditiesPurchase, row.item, row.buy)
    if not ok then
        busy = nil
        return nil, "The auction house didn't take that. Search for it in the auction window instead."
    end
    return true
end

-- Second click: pay the price the auction house quoted, for that one material.
function S.Confirm(row)
    if not (quote and quote.item == row.item and quote.qty == row.buy) then return nil, "Press Get price first." end
    if not isOpen then return nil, "Open the auction house first." end
    if (GetMoney and GetMoney() or 0) < quote.total then return nil, "You don't have " .. Orders.Money(quote.total) .. "." end
    local q = quote
    quote, busy, paying = nil, q.item, q
    local ok = pcall(api().ConfirmCommoditiesPurchase, q.item, q.qty)
    if not ok then
        busy = nil
        return nil, "The auction house didn't take that. Try Get price again."
    end
    return true
end

local function refresh() if S.Refresh then S.Refresh() end end

ns.On("AUCTION_HOUSE_SHOW", function() isOpen = true; refresh() end)
ns.On("AUCTION_HOUSE_CLOSED", function() isOpen = false; quote, busy = nil, nil; refresh() end)
ns.On("COMMODITY_PRICE_UPDATED", function(_, total)
    if not busy then return end
    local item = busy
    busy = nil
    for _, row in ipairs((S.Rows())) do
        if row.item == item and row.buy > 0 and type(total) == "number" then
            quote = { item = item, qty = row.buy, total = total }
        end
    end
    refresh()
end)
ns.On("COMMODITY_PRICE_UNAVAILABLE", function()
    if busy then lastNote = "The auction house doesn't have that many for sale right now." end
    busy, quote = nil, nil
    refresh()
end)
ns.On("COMMODITY_PURCHASE_SUCCEEDED", function()
    if paying then
        local p = pending[paying.item]
        local have = held(paying.item)
        if p and have < p.base + p.qty then p.qty = p.qty + paying.qty else pending[paying.item] = { base = have, qty = paying.qty } end
    end
    paying = nil
    if busy then lastNote = "Bought. Collect it from your mailbox." end
    busy, quote = nil, nil
    refresh()
end)
ns.On("COMMODITY_PURCHASE_FAILED", function()
    paying = nil
    if busy then lastNote = "The auction house didn't complete that purchase. Try Get price again." end
    busy, quote = nil, nil
    refresh()
end)
ns.On("BAG_UPDATE_DELAYED", function() if S.frame and S.frame:IsShown() then refresh() end end)

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local W = ns.W
local helping = false

local function build()
    local f = CreateFrame("Frame", "SpeakeasyShop", UIParent)
    f:SetSize(560, 330)
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
    f.title:SetWidth(500)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    W.Button(f, "X", 22, 20, function() f:Hide() end):SetPoint("TOPRIGHT", -6, -6)
    W.Line(f, -32)

    W.Text(f, "How many to craft?", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 12, -46)
    f.crafts = W.Edit(f, 34, 2)
    f.crafts:SetPoint("TOPLEFT", 130, -42)
    f.crafts:HookScript("OnTextChanged", function(self)
        if S.SetCrafts(self:GetText()) then refresh() end
    end)
    W.Text(f, "1 to " .. S.MAX_CRAFTS, "GameFontDisableSmall"):SetPoint("TOPLEFT", 172, -46)
    f.help = W.Button(f, "How does this work?", 150, 22, function()
        helping = not helping
        refresh()
    end)
    f.help:SetPoint("TOPRIGHT", -12, -42)
    f.status = W.Text(f, "", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", 12, -70)
    f.status:SetWidth(536)
    f.status:SetJustifyH("LEFT")
    f.status:SetWordWrap(false)

    f.heads = {}
    for i, h in ipairs({ { "Material", 16, 190, "LEFT" }, { "Need", 210, 44, "RIGHT" }, { "Have", 258, 44, "RIGHT" },
        { "To buy", 306, 50, "RIGHT" }, { "Each (last scan)", 360, 84, "RIGHT" } }) do
        local fs = W.Text(f, h[1], "GameFontDisableSmall")
        fs:SetPoint("TOPLEFT", h[2], -92)
        fs:SetWidth(h[3])
        fs:SetJustifyH(h[4])
        f.heads[i] = fs
    end
    f.rows = W.List(f, 536, 170, 20, function(row, r)
        f.rows.Col(row, 1, 4, 194):SetText(U.Safe(r.name, 60))
        f.rows.Col(row, 2, 198, 44, "RIGHT"):SetText(tostring(r.need))
        f.rows.Col(row, 3, 246, 44, "RIGHT"):SetText(tostring(r.have))
        f.rows.Col(row, 4, 294, 50, "RIGHT"):SetText(r.buy > 0 and ("|cffffd100" .. r.buy .. "|r") or "|cff40ff40enough|r")
        local each = f.rows.Col(row, 5, 348, 84, "RIGHT")
        each:SetText(r.each and Orders.Money(r.each) or (r.buy > 0 and "no price" or ""))
        each:SetTextColor(W.C.muted[1], W.C.muted[2], W.C.muted[3])
        if not row.act then
            row.act = W.Button(row, "", 92, 18)
            row.act:SetPoint("RIGHT", -4, 0)
        end
        local kind, text = S.ButtonFor(r, quote, busy, isOpen and S.Supported(), bulk(r.item), GetMoney and GetMoney() or 0)
        row.act:SetShown(kind ~= "none")
        row.act:SetText(text)
        row.act:SetEnabled(kind == "price" or kind == "pay")
        row.act:SetScript("OnClick", function()
            local ok, why
            if kind == "pay" then ok, why = S.Confirm(r) else ok, why = S.Quote(r) end
            if not ok then lastNote = why end
            refresh()
        end)
    end)
    f.rows.scroll:SetPoint("TOPLEFT", 12, -108)
    f.rows.scroll:SetSize(536, 170)
    f.helpText = W.Text(f, table.concat(S.HOWTO, "\n\n"), "GameFontHighlightSmall")
    f.helpText:SetPoint("TOPLEFT", 14, -92)
    f.helpText:SetWidth(532)
    f.helpText:SetJustifyH("LEFT")
    f.helpText:SetJustifyV("TOP")
    f.helpText:SetWordWrap(true)
    f.foot = W.Text(f, "", "GameFontDisableSmall")
    f.foot:SetPoint("BOTTOMLEFT", 12, 10)
    f.foot:SetWidth(536)
    f.foot:SetJustifyH("LEFT")
    f.foot:SetWordWrap(false)
    f:SetScript("OnHide", function() dropQuote() end)
    f:Hide()
    S.frame = f
    return f
end

function S.Refresh()
    local f = S.frame
    if not (f and f:IsShown()) then return end
    local rows, total, unpriced = S.Rows()
    f.title:SetText("Buy materials: " .. U.Safe(rid and ns.Recipes.Name(rid) or "?", 60))
    f.help:SetText(helping and "Back to the list" or "How does this work?")
    for _, fs in ipairs(f.heads) do fs:SetShown(not helping) end
    f.rows.scroll:SetShown(not helping)
    f.helpText:SetShown(helping)
    if not f.crafts:HasFocus() then f.crafts:SetText(tostring(crafts)) end
    local left = 0
    for _, r in ipairs(rows) do if r.buy > 0 then left = left + 1 end end
    if lastNote then
        f.status:SetText("|cffffd100" .. lastNote .. "|r")
    elseif #rows == 0 then
        f.status:SetText("The game hasn't told Speakeasy what this recipe needs. Open that profession's window once.")
    elseif not S.Supported() then
        f.status:SetText("This auction house can't sell materials in bulk to addons, so this is a shopping list only.")
    elseif not isOpen then
        f.status:SetText("|cffff6040Open the auction house to buy.|r This is your shopping list until then.")
    elseif left == 0 then
        f.status:SetText("|cff40ff40You have everything for " .. crafts .. (crafts == 1 and " craft." or " crafts.") .. "|r")
    else
        f.status:SetText(left .. (left == 1 and " material" or " materials") .. " left to buy. Get price, then Buy, one at a time.")
    end
    f.foot:SetText(left == 0 and "" or (("About %s for what's left, from Auctionator's last scan%s. You pay the price on the Buy button."):format(
        Orders.Money(total), unpriced > 0 and (", plus " .. unpriced .. " with no price") or "")))
    if not helping then f.rows:SetItems(rows) end
end

-- Open the window for a recipe.
function S.Open(recipe)
    local f = S.frame or build()
    if recipe ~= rid then
        dropQuote()
        rid, crafts, lastNote = recipe, 1, nil
    end
    helping = false
    f:Show()
    f.crafts:SetText(tostring(crafts))
    S.Refresh()
end
