-- Speakeasy: mailing a finished crafting order.
-- At a mailbox, the crafter picks one of their orders and Speakeasy fills in
-- the game's own Send Mail form: the guild member who asked, the item as the
-- subject, a short message, and the crafted items from the crafter's bags.
-- The player checks it and presses the game's Send button themselves, and the
-- game charges the postage then. Speakeasy never sends mail on its own and
-- only ever addresses a member of the guild.
local _, ns = ...
local Mail = {}
ns.Mail = Mail

local U, W = ns.U, ns.W

Mail.MAX_SLOTS = 12            -- attachments one mail can carry
Mail.SUBJECT_MAX = 64
Mail.BODY_MAX = 500
Mail.READY_NOTE = "In your mailbox"

---------------------------------------------------------------------------
-- Pure logic
---------------------------------------------------------------------------
-- Which whole stacks to attach so the mail carries as close to `want` items
-- as it can without going over, using the fewest attachment slots.
--   stacks = { { bag =, slot =, count = }, ... }
--   -> the stacks to attach, and how many items that is
-- Stacks are never split: a stack bigger than what is still needed is left
-- alone, and the player is told to split it by hand.
function Mail.Plan(stacks, want, maxSlots)
    maxSlots = maxSlots or Mail.MAX_SLOTS
    want = math.floor(tonumber(want) or 0)
    local pool = {}
    for _, s in ipairs(stacks or {}) do
        if s.count >= 1 and s.count <= want then pool[#pool + 1] = s end
    end
    table.sort(pool, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    -- reach[n] = fewest stacks that add up to exactly n items.
    local reach, took = { [0] = 0 }, {}
    for i, s in ipairs(pool) do
        took[i] = {}
        for sum = want, s.count, -1 do
            local from = reach[sum - s.count]
            if from and from + 1 <= maxSlots and (reach[sum] == nil or from + 1 < reach[sum]) then
                reach[sum] = from + 1
                took[i][sum] = true
            end
        end
    end
    local best = 0
    for sum = want, 1, -1 do
        if reach[sum] then best = sum; break end
    end
    local picks, sum = {}, best
    for i = #pool, 1, -1 do
        if sum > 0 and took[i][sum] then
            table.insert(picks, 1, pool[i])
            sum = sum - pool[i].count
        end
    end
    return picks, best
end

-- Orders this member is crafting and could mail: accepted or ready.
function Mail.Orders(st, me)
    local rows = {}
    for _, o in pairs(st and st.orders or {}) do
        if o.crafter == me and (o.status == "accepted" or o.status == "ready") then rows[#rows + 1] = o end
    end
    table.sort(rows, function(a, b)
        local x, y = a.due or (a.t + 1e9), b.due or (b.t + 1e9)
        if x ~= y then return x < y end
        return a.id < b.id
    end)
    return rows
end

function Mail.Subject(item, n)
    return (item .. (n > 1 and (" x" .. n) or "")):sub(1, Mail.SUBJECT_MAX)
end

-- n = how many are in this mail, left = how many the order still needed.
function Mail.Body(item, n, left, crafter)
    local text = ("Speakeasy order: here is your %s%s, made by %s."):format(item, n > 1 and (" x" .. n) or "", crafter)
    if n < left then
        text = text .. (" That is %d of the %d still owed; the rest will follow."):format(n, left)
    end
    text = text .. " When you have it, type /bp, open Professions > Orders and press \"I received it\"."
    return text:sub(1, Mail.BODY_MAX)
end

---------------------------------------------------------------------------
-- Game side: bags and the Send Mail form
---------------------------------------------------------------------------
Mail.open = false
local pending          -- the mail Speakeasy filled in and the player hasn't sent yet
local hooked = false   -- do we get to see what the player actually sends?
local panel

-- How many of an order's items are still to be mailed. What has been mailed
-- is in the guild's log, so everyone sees the same count.
function Mail.Left(o) return math.max(0, o.q - (o.mailed or 0)) end

-- Unbound, unlocked stacks of an item in the bags, and how many items in all.
local function bagStacks(itemID)
    local c = C_Container
    local stacks, have = {}, 0
    if not (c and c.GetContainerNumSlots and c.GetContainerItemInfo) then return stacks, 0 end
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
        local ok, n = pcall(c.GetContainerNumSlots, bag)
        for slot = 1, (ok and tonumber(n)) or 0 do
            local good, info = pcall(c.GetContainerItemInfo, bag, slot)
            if good and type(info) == "table" and info.itemID == itemID and not info.isBound and not info.isLocked then
                local count = tonumber(info.stackCount) or 1
                stacks[#stacks + 1] = { bag = bag, slot = slot, count = count }
                have = have + count
            end
        end
    end
    return stacks, have
end

local function maxSlots() return math.min(tonumber(ATTACHMENTS_MAX_SEND) or Mail.MAX_SLOTS, Mail.MAX_SLOTS) end

-- What is attached to the mail being written: slots in use, and how many of one item.
local function attached(itemID)
    local used, count = 0, 0
    if type(GetSendMailItem) ~= "function" then return 0, 0 end
    for i = 1, maxSlots() do
        local ok, name, id, _, n = pcall(GetSendMailItem, i)
        if ok and name then
            used = used + 1
            if id == itemID then count = count + (tonumber(n) or 1) end
        end
    end
    return used, count
end

local function setText(box, text)
    if type(box) ~= "table" or type(box.SetText) ~= "function" then return false end
    return (pcall(box.SetText, box, text))
end

-- The message box has had two names across game versions.
local function bodyBox()
    if SendMailBodyEditBox then return SendMailBodyEditBox end
    if type(MailEditBox) == "table" then
        if type(MailEditBox.GetEditBox) == "function" then
            local ok, box = pcall(MailEditBox.GetEditBox, MailEditBox)
            if ok and box then return box end
        end
        return MailEditBox
    end
    return nil
end

local function itemName(o, item)
    return (item and ns.Loot.ItemName(item)) or ns.Recipes.Name(o.rid) or ("Recipe " .. o.rid)
end

-- One row per order I could mail, with what is in my bags for it.
--   why = the reason it can't be mailed right now, or nil when it can
function Mail.Rows()
    local st = ns.Reducer.State()
    local rows = {}
    for _, o in ipairs(Mail.Orders(st, ns.MyGUID())) do
        local item = ns.Recipes.Output(o.rid)
        local m = ns.roster.byGUID[o.by]
        local row = { id = o.id, o = o, item = item, name = itemName(o, item), to = m and m.name or nil,
            left = Mail.Left(o), have = 0, stacks = {} }
        if item then row.stacks, row.have = bagStacks(item) end
        if not m then row.why = "They are no longer in the guild."
        elseif row.left == 0 then row.why = "In transit. It's complete when they confirm they have it."
        elseif not item then row.why = "This recipe makes no item that can be mailed."
        elseif row.have == 0 then row.why = "None in your bags yet (bound items can't be mailed)."
        end
        rows[#rows + 1] = row
    end
    return rows
end

local function postage()
    if type(GetSendMailPrice) ~= "function" then return nil end
    local ok, copper = pcall(GetSendMailPrice)
    if ok and type(copper) == "number" and copper > 0 then return ns.Orders.Money(copper) end
    return nil
end

-- Fill in the game's Send Mail form for one order. Nothing is sent.
-- -> a line for the player, or nil and why not
function Mail.Prepare(orderId)
    if ns.mock then return nil, "Test mode is on, so no mail is filled in." end
    if not Mail.open then return nil, "Open a mailbox first." end
    local row
    for _, r in ipairs(Mail.Rows()) do if r.id == orderId then row = r end end
    if not row then return nil, "That order isn't yours to mail any more." end
    if row.why then return nil, row.why end
    local pickUp = C_Container and C_Container.PickupContainerItem
    if type(pickUp) ~= "function" or type(ClickSendMailItemButton) ~= "function" then
        return nil, "This game version doesn't let addons attach items. Mail it by hand."
    end
    if attached(row.item) > 0 then
        return nil, "The mail you're writing already has items attached. Send or clear it first."
    end
    local picks, total = Mail.Plan(row.stacks, row.left, maxSlots())
    if total == 0 then
        return nil, ("Your stacks are bigger than the %d still owed. Split one by hand (Shift-click), then press this again."):format(row.left)
    end

    -- The Send Mail tab of the game's mail window.
    if type(MailFrameTab_OnClick) == "function" then
        pcall(MailFrameTab_OnClick, nil, 2)
    elseif type(MailFrameTab2) == "table" and type(MailFrameTab2.Click) == "function" then
        pcall(MailFrameTab2.Click, MailFrameTab2)
    end
    local subject = Mail.Subject(row.name, total)
    local body = Mail.Body(row.name, total, row.left, ns.NameForGUID(ns.MyGUID()) or "a guild crafter")
    local to = U.ShortName(row.to)
    if not (setText(SendMailNameEditBox, to) and setText(SendMailSubjectEditBox, subject)) then
        return nil, "Speakeasy couldn't find the game's Send Mail form. Mail it by hand."
    end
    local wrote = setText(bodyBox(), body)

    if type(ClearCursor) == "function" then pcall(ClearCursor) end
    for i, s in ipairs(picks) do
        pcall(pickUp, s.bag, s.slot)
        pcall(ClickSendMailItemButton, i)
    end
    if type(ClearCursor) == "function" then pcall(ClearCursor) end

    pending = { id = orderId, to = to, item = row.item, name = row.name, count = total }
    local line = ("Filled in: %d %s for %s."):format(total, row.name, row.to)
    if total < row.left then
        line = line .. (" %d more to go"):format(row.left - total)
            .. (row.have > total and ": the rest is in bigger stacks or won't fit in one mail." or ": craft the rest.")
    end
    if not wrote then line = line .. " The message box couldn't be filled in; type one if you want." end
    local cost = postage()
    return line .. (cost and (" Postage " .. cost .. ".") or "") .. " Check it, then press Send."
end

-- What the player actually sent: only a mail to the same guild member counts.
local function onSendMail(to)
    if not pending then return end
    pending.sent = type(to) == "string" and U.ShortName(to):lower() == pending.to:lower()
    if pending.sent then
        local _, n = attached(pending.item)
        if n > 0 then pending.count = n end       -- the player may have taken some out
    end
end
if type(hooksecurefunc) == "function" then
    hooked = pcall(hooksecurefunc, "SendMail", onSendMail)
end

local function onSent()
    local p = pending
    pending = nil
    if not p or (hooked and not p.sent) then return end
    local st = ns.Reducer.State()
    local o = st and st.orders[p.id]
    if not o then return end
    local who = U.Safe(ns.Orders.NameOf(o.by), 40)
    local wasAccepted = o.status == "accepted"
    local e, why = ns.Orders.Mailed(p.id, p.count)
    if not e then
        ns.Print(("Mailed %d %s to %s, but the order couldn't be updated: %s"):format(p.count, p.name, who, tostring(why)))
        return
    end
    local fresh = ns.Reducer.State()
    fresh = fresh and fresh.orders[p.id]
    local total = fresh and fresh.mailed or p.count
    if total >= o.q then
        if wasAccepted then ns.Orders.Update(p.id, "ready", nil, Mail.READY_NOTE) end
        ns.Print(("Mailed %d %s to %s. The order is now In transit; it's complete when they confirm they have it."):format(p.count, p.name, who))
    else
        ns.Print(("Mailed %d %s to %s. %d more to go."):format(p.count, p.name, who, o.q - total))
    end
end

-- Version 0.17.0 kept what had been mailed on this character only. Put any
-- such count in the guild's log once, so those orders show as In transit too.
local migrated = false
local function migrate(again)
    if (migrated and again ~= true) or ns.mock or not ns.roster.loaded then return end
    local st = ns.Reducer.State()
    local old = ns.Char().mailed
    if not st then return end
    migrated = true
    if type(old) ~= "table" then return end
    for id, n in pairs(old) do
        local o = st.orders[id]
        if o and type(n) == "number" and n > (o.mailed or 0) then ns.Orders.Mailed(id, n - (o.mailed or 0)) end
    end
    ns.Char().mailed = nil
end
Mail.Migrate = migrate
ns.Listen("ROSTER_CHANGED", function() migrate() end)

---------------------------------------------------------------------------
-- The panel beside the mailbox window
---------------------------------------------------------------------------
local chosen

local function refresh(note)
    if not (panel and panel:IsShown()) then return end
    local rows = Mail.Rows()
    local sel
    for _, r in ipairs(rows) do if r.id == chosen then sel = r end end
    chosen = sel and sel.id or nil
    panel.list.selected = sel
    panel.list:SetItems(rows)
    panel.empty:SetShown(#rows == 0)
    panel.go:SetEnabled(sel ~= nil and sel.why == nil and not ns.mock)
    if note then
        panel.status:SetText(note)
    elseif pending then
        local cost = postage()
        panel.status:SetText(("Filled in for %s.%s Check it, then press Send."):format(pending.to, cost and (" Postage " .. cost .. ".") or ""))
    elseif sel then
        panel.status:SetText(sel.why or ("Press the button and Speakeasy writes the mail to %s and attaches the items. You press Send."):format(sel.to))
    else
        panel.status:SetText(#rows > 0 and "Click an order to mail it." or "")
    end
end

local function build()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(400, 236)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    if MailFrame then f:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 8, 0) else f:SetPoint("CENTER", 320, 0) end
    W.Glass(f)
    W.Text(f, "Speakeasy: orders to mail", "GameFontNormal"):SetPoint("TOPLEFT", 10, -9)
    W.Button(f, "X", 22, 20, function() f:Hide() end):SetPoint("TOPRIGHT", -6, -6)
    W.Line(f, -32)

    f.list = W.List(f, 366, 100, 20, function(row, r)
        local ok = r.why == nil
        local name = f.list.Col(row, 1, 6, 170)
        name:SetText(U.Safe(r.name, 40) .. (r.o.q > 1 and (" x" .. r.o.q) or ""))
        name:SetTextColor(ok and W.C.text[1] or W.C.muted[1], ok and W.C.text[2] or W.C.muted[2], ok and W.C.text[3] or W.C.muted[3])
        f.list.Col(row, 2, 180, 100):SetText(U.Safe(r.to or "?", 30))
        local bags = f.list.Col(row, 3, 284, 80, "RIGHT")
        bags:SetText(r.left == 0 and "mailed" or (r.item and (r.have .. " of " .. r.left .. " in bags") or "no item"))
        bags:SetTextColor(W.C.muted[1], W.C.muted[2], W.C.muted[3])
    end, function(r)
        chosen = r and r.id or nil
        refresh()
    end)
    f.list.key = "id"
    f.list.scroll:SetPoint("TOPLEFT", 10, -40)

    f.empty = W.Text(f, "No accepted orders to mail. Orders you accept show here.", "GameFontDisableSmall")
    f.empty:SetPoint("TOPLEFT", 14, -46)
    f.empty:SetWidth(360)

    f.status = W.Text(f, "", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", 10, -148)
    f.status:SetWidth(380)
    f.status:SetJustifyV("TOP")
    f.status:SetWordWrap(true)

    f.go = W.Button(f, "Fill in the mail", 140, 24, function()
        if not chosen then return end
        local line, why = Mail.Prepare(chosen)
        refresh(line or why)
    end, "accent")
    f.go:SetPoint("BOTTOMLEFT", 10, 10)
    local hint = W.Text(f, "You press Send. The game takes the postage.", "GameFontDisableSmall")
    hint:SetPoint("LEFT", f.go, "RIGHT", 10, 0)
    f:Hide()
    return f
end

-- Show the panel. quiet = only when there is something to mail.
function Mail.Show(quiet)
    if not Mail.open then
        if not quiet then ns.Print("Open a mailbox first. Speakeasy then lists the orders you can mail.") end
        return false
    end
    local rows = Mail.Rows()
    if quiet then
        local any = false
        for _, r in ipairs(rows) do if r.left > 0 then any = true end end
        if not any then return false end
    end
    panel = panel or build()
    if not chosen then
        for _, r in ipairs(rows) do
            if not r.why then chosen = r.id; break end
        end
    end
    panel:Show()
    refresh()
    return true
end

ns.On("MAIL_SHOW", function()
    Mail.open = true
    Mail.Show(true)
end)
ns.On("MAIL_CLOSED", function()
    Mail.open = false
    pending = nil
    if panel then panel:Hide() end
end)
ns.On("MAIL_SEND_SUCCESS", function()
    onSent()
    refresh()
end)
ns.On("MAIL_FAILED", function()
    if pending then pending.sent = nil end
end)
ns.On("MAIL_SEND_INFO_UPDATE", function() if pending then refresh() end end)
ns.On("BAG_UPDATE_DELAYED", function() if not pending then refresh() end end)
ns.Listen("LOG_CHANGED", function() if not pending then refresh() end end)
