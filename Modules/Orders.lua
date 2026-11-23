-- Blood Pact: crafting orders, inside the guild only.
-- A member asks for a recipe to be crafted, either from one named guild
-- crafter or on the Wanted board for any guild crafter who knows it. The
-- crafter accepts with a promised turnaround (2, 8, 24 or 48 hours), marks it
-- ready, and the member who asked confirms delivery.
-- Orders travel only on the guild's addon channel. The one whisper (to an
-- online crafter, when an order is placed for them) goes only to a guild
-- member and only from the player's own click. Handing the item over is done
-- by the players themselves: by trade, or by mail with Modules/Mail.lua
-- filling in the form and the player pressing Send.
local _, ns = ...
local O = {}
ns.Orders = O

local U = ns.U
local date = date or os.date   -- WoW global; os.date in tests

O.HOURS = { 2, 8, 24, 48 }
O.MAX_ACTIVE = 20              -- orders one member can have open at a time
O.MATS = { me = "Requester sends mats", crafter = "Crafter's mats", bank = "Guild bank mats" }
O.MATS_ORDER = { "me", "crafter", "bank" }
O.MATS_ASK = { me = "I'll send the mats.", crafter = "Using your mats.", bank = "Mats from the guild bank." }
local ACTIVE = { open = true, accepted = true, ready = true }

---------------------------------------------------------------------------
-- Pure logic
---------------------------------------------------------------------------
function O.IsActive(o) return ACTIVE[o.status] == true end

-- Mailed in full by the crafter and not yet confirmed by the member who asked.
function O.InTransit(o)
    return (o.status == "accepted" or o.status == "ready") and (o.mailed or 0) >= o.q
end

-- Has this member shared the recipe an order asks for?
function O.CanCraft(st, guid, o)
    local mine = st and st.recipes[guid]
    return (mine and mine[o.p] and mine[o.p][o.rid]) and true or false
end

-- A Wanted order this member could take: open, for anyone, not their own, and
-- in their shared recipes.
function O.Matches(st, guid, o)
    return o.status == "open" and o.to == nil and o.by ~= guid and O.CanCraft(st, guid, o)
end

-- Copper as "3g 20s". Copper is dropped once there is gold.
function O.Money(copper)
    copper = math.max(0, math.floor((tonumber(copper) or 0) + 0.5))
    local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
    if g > 0 then return s > 0 and (g .. "g " .. s .. "s") or (g .. "g") end
    if s > 0 then return c > 0 and (s .. "s " .. c .. "c") or (s .. "s") end
    return c .. "c"
end

-- Estimated material cost: reagents = { { item, n } }, priceOf(item) = copper or nil.
-- -> total for the reagents that have a price, how many have none, how many in all.
function O.Estimate(reagents, qty, priceOf)
    local total, missing = 0, 0
    for _, r in ipairs(reagents or {}) do
        local price = priceOf(r.item)
        if price and price > 0 then total = total + price * r.n * qty else missing = missing + 1 end
    end
    return total, missing, #(reagents or {})
end

-- What `me` may do with an order right now. canCraft = I have shared this recipe.
function O.Actions(o, me, isOfficer, canCraft)
    local a = {}
    if not ACTIVE[o.status] then return a end
    if o.status == "open" then
        if o.to == me then
            a.accept, a.decline = true, true
        elseif o.to == nil and o.by ~= me and canCraft then
            a.accept = true
        end
    elseif o.crafter == me then
        a.release = true
        if o.status == "accepted" then a.ready = true end
    end
    if o.by == me then
        a.cancel = true
        if o.status ~= "open" then a.deliver = true end
    elseif isOfficer then
        a.moderate = true                       -- an Officer tidying the board
    end
    return a
end

local function span(seconds)
    seconds = math.max(0, seconds)
    if seconds < 3600 then return math.max(1, math.floor(seconds / 60 + 0.5)) .. "m" end
    if seconds < 48 * 3600 then return math.floor(seconds / 3600 + 0.5) .. "h" end
    return math.floor(seconds / 86400 + 0.5) .. "d"
end
O.Span = span

-- -> text, tone ("late", "good", "transit", "muted" or nil)
function O.StatusText(o, now, nameOf)
    if O.InTransit(o) then
        return "In transit, mailed " .. date("%b %d", o.mailedAt or o.t), "transit"
    elseif o.status == "open" then
        if o.to then return "Waiting for " .. (nameOf(o.to) or "?"), "muted" end
        return "Open: any crafter", nil
    elseif o.status == "accepted" then
        local part = (o.mailed or 0) > 0 and (", %d of %d mailed"):format(o.mailed, o.q) or ""
        if now > o.due then return "Late by " .. span(now - o.due) .. part, "late" end
        return "Due in " .. span(o.due - now) .. part, nil
    elseif o.status == "ready" then
        if (o.mailed or 0) > 0 then return ("Ready, %d of %d mailed"):format(o.mailed, o.q), "good" end
        return "Ready to hand over", "good"
    elseif o.status == "delivered" then
        return "Delivered " .. date("%b %d", o.doneAt or o.t), "good"
    elseif o.status == "declined" then
        return "Declined", "muted"
    end
    return "Cancelled", "muted"
end

function O.IsLate(o, now) return o.status == "accepted" and now > o.due and not O.InTransit(o) end

-- Rows for one of the four lists.
--   craft   = asked of me, accepted by me and not handed over, or on the
--             Wanted board and in my shared recipes
--   mine    = orders I placed that are still going
--   wanted  = open orders any crafter may take
--   history = finished orders, newest first
function O.Rows(st, me, which)
    local rows = {}
    for _, o in pairs(st and st.orders or {}) do
        local keep
        if which == "craft" then
            keep = (o.status == "open" and o.to == me) or ((o.status == "accepted" or o.status == "ready") and o.crafter == me)
                or O.Matches(st, me, o)
        elseif which == "mine" then
            keep = o.by == me and ACTIVE[o.status]
        elseif which == "wanted" then
            keep = o.status == "open" and o.to == nil
        else
            keep = not ACTIVE[o.status]
        end
        if keep then rows[#rows + 1] = o end
    end
    if which == "history" then
        table.sort(rows, function(a, b)
            local x, y = a.doneAt or a.t, b.doneAt or b.t
            if x ~= y then return x > y end
            return a.id > b.id
        end)
    else
        -- Soonest due first, then oldest first.
        table.sort(rows, function(a, b)
            local x, y = a.due or (a.t + 1e9), b.due or (b.t + 1e9)
            if x ~= y then return x < y end
            return a.id < b.id
        end)
    end
    return rows
end

-- How many orders need something from me: to accept or finish, or to collect.
function O.Needs(st, me)
    local n = 0
    for _, o in pairs(st and st.orders or {}) do
        if (o.status == "open" and o.to == me) or (o.status == "accepted" and o.crafter == me and not O.InTransit(o))
            or ((o.status == "ready" or O.InTransit(o)) and o.by == me) or O.Matches(st, me, o) then
            n = n + 1
        end
    end
    return n
end

function O.ActiveCount(st, guid)
    local n = 0
    for _, o in pairs(st and st.orders or {}) do
        if o.by == guid and ACTIVE[o.status] then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------
-- Game side
---------------------------------------------------------------------------
local function nameOf(guid)
    local st = ns.Reducer.State()
    return ns.NameForGUID(guid) or (st and st.members[guid] and st.members[guid].name) or "?"
end
O.NameOf = nameOf

function O.ItemText(o)
    local name = ns.Recipes.Name(o.rid) or ("Recipe " .. o.rid)
    return name .. (o.q > 1 and (" x" .. o.q) or "")
end

-- A clickable link for the recipe when the game gives one, else its name.
local recipeLink
function O.RecipeLink(rid) return recipeLink(rid) end
recipeLink = function(rid)
    local api = C_TradeSkillUI
    if api and api.GetRecipeLink then
        local ok, link = pcall(api.GetRecipeLink, rid)
        if ok and type(link) == "string" and link ~= "" then return link end
    end
    if C_Spell and C_Spell.GetSpellLink then
        local ok, link = pcall(C_Spell.GetSpellLink, rid)
        if ok and type(link) == "string" and link ~= "" then return link end
    end
    return "[" .. (ns.Recipes.Name(rid) or ("Recipe " .. rid)) .. "]"
end

-- Auction prices come from the Auctionator addon when the player has it: its
-- last scan for the item, or the vendor price it has seen. Nothing is scanned
-- or bought by Blood Pact.
function O.HasPrices()
    return Auctionator ~= nil and Auctionator.API ~= nil and Auctionator.API.v1 ~= nil
        and Auctionator.API.v1.GetAuctionPriceByItemID ~= nil
end

function O.PriceOf(item)
    if not O.HasPrices() then return nil end
    local api = Auctionator.API.v1
    local ok, price = pcall(api.GetAuctionPriceByItemID, "BloodPact", item)
    if ok and type(price) == "number" and price > 0 then return price end
    if api.GetVendorPriceByItemID then
        ok, price = pcall(api.GetVendorPriceByItemID, "BloodPact", item)
        if ok and type(price) == "number" and price > 0 then return price end
    end
    return nil
end

-- "3g 20s", "3g 20s+" when some reagents have no price, or nil when there
-- is nothing to go on. long = a full sentence for the order bars.
function O.CostText(rid, qty, long)
    if not O.HasPrices() then
        return long and "Install the Auctionator addon to see an estimated material cost." or nil
    end
    local list = ns.Recipes.Reagents(rid)
    if not list then return long and "The game didn't list this recipe's materials." or nil end
    local total, missing, all = O.Estimate(list, qty or 1, O.PriceOf)
    if missing == all then return long and "No auction prices for these materials yet. Scan the auction house with Auctionator." or nil end
    if not long then return O.Money(total) .. (missing > 0 and "+" or "") end
    return ("Est. materials: %s from Auctionator's last scan%s."):format(O.Money(total),
        missing > 0 and (", plus " .. missing .. " with no price") or "")
end

-- What the finished item sells for: Auctionator's last scanned auction price
-- for the item the recipe makes. nil when the recipe makes no item (an
-- enchant put straight on gear), the game won't say, or nobody has listed it.
function O.BuyPrice(rid)
    if not O.HasPrices() then return nil end
    local item = ns.Recipes.Output(rid)
    if not item then return nil end
    local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, "BloodPact", item)
    if ok and type(price) == "number" and price > 0 then return price end
    return nil
end

function O.BuyText(rid)
    local price = O.BuyPrice(rid)
    return price and O.Money(price) or nil
end

-- One recipe's numbers in copper: cost = materials (nil when nothing has a
-- price), partial = some materials have no price, buy = the finished item's
-- auction price, net = buy - cost. net is only given when both are known and
-- every material has a price; the auction house's cut is not taken off.
function O.Numbers(rid)
    local cost, partial
    local list = O.HasPrices() and ns.Recipes.Reagents(rid)
    if list then
        local total, missing, all = O.Estimate(list, 1, O.PriceOf)
        if missing < all then cost, partial = total, missing > 0 end
    end
    local buy = O.BuyPrice(rid)
    local net = cost and buy and not partial and (buy - cost) or nil
    return cost, partial or false, buy, net
end

-- "+12s 5c" in green or "-3s" in red, or nil.
function O.NetText(rid)
    local _, _, _, net = O.Numbers(rid)
    if not net then return nil end
    if net < 0 then return "|cffff5050-" .. O.Money(-net) .. "|r" end
    return "|cff40d060+" .. O.Money(net) .. "|r"
end

-- Sort recipe rows ({ id, name }) in place. key = "name", "cost", "buy" or
-- "net"; numbers(id) -> cost, partial, buy, net. Rows with no number for the
-- column always go to the bottom; ties go by name.
function O.SortRecipes(list, key, desc, numbers)
    local val = {}
    for _, r in ipairs(list) do
        if key == "name" then
            val[r] = (r.name or ""):lower()
        else
            local cost, _, buy, net = numbers(r.id)
            val[r] = (key == "cost" and cost) or (key == "buy" and buy) or (key == "net" and net) or nil
        end
    end
    table.sort(list, function(a, b)
        local x, y = val[a], val[b]
        if x == nil or y == nil then
            if x ~= nil or y ~= nil then return x ~= nil end
        elseif x ~= y then
            if desc then return x > y end
            return x < y
        end
        local m, n = (a.name or ""):lower(), (b.name or ""):lower()
        if m ~= n then return m < n end
        return (a.id or 0) < (b.id or 0)
    end)
    return list
end

-- Place an order. toGUID = a guild crafter, or nil for the Wanted board.
function O.Create(rid, prof, qty, mats, note, toGUID)
    if not ns.RBAC.ICan("signup") then return nil, "Your guild rank can't place orders." end
    local st = ns.Reducer.State()
    if not st then return nil, "No guild data yet." end
    local me = ns.MyGUID()
    qty = tonumber(qty)
    if not qty or qty ~= math.floor(qty) or qty < 1 or qty > 99 then return nil, "Quantity must be 1 to 99." end
    if not O.MATS[mats] then return nil, "Pick who supplies the materials." end
    if toGUID then
        local m = ns.roster.byGUID[toGUID]
        if not m then return nil, "Orders stay inside the guild: that player isn't in the roster." end
        if toGUID == me then return nil, "You can't order from yourself." end
    end
    if O.ActiveCount(st, me) >= O.MAX_ACTIVE then
        return nil, ("You already have %d orders open. Cancel or finish one first."):format(O.MAX_ACTIVE)
    end
    note = note and note:match("^%s*(.-)%s*$") or ""
    if #note > ns.Log.MAX_NOTE then return nil, "That note is too long." end
    local e, why = ns.Log.New("ORDER", { rid = rid, p = prof, q = qty, mats = mats, to = toGUID, n = note ~= "" and note or nil })
    if not e then return nil, why end
    -- One whisper from this click, to a guild member who is online. Never in test mode.
    local m = toGUID and ns.roster.byGUID[toGUID]
    if m and m.online and not ns.mock then
        local msg = ("Blood Pact order: can you make %s%s for me? %s See /bp > Professions > Orders."):format(
            recipeLink(rid), qty > 1 and (" x" .. qty) or "", O.MATS_ASK[mats])
        ns.Chat(msg:sub(1, 255), "WHISPER", U.ShortName(m.name))      -- the order stands either way
    end
    return e
end

-- accept (with hours), decline, ready, release, deliver, cancel.
function O.Update(id, action, hours, note)
    local st = ns.Reducer.State()
    local o = st and st.orders[id]
    if not o then return nil, "That order is gone." end
    local me = ns.MyGUID()
    local allowed = O.Actions(o, me, ns.RBAC.ICan("void"), O.CanCraft(st, me, o))
    if action == "cancel" and allowed.moderate and not allowed.cancel then
        return ns.Log.New("ORDER_MOD", { id = id, st = "cancel" })
    end
    if not allowed[action] then
        if action == "accept" and o.status == "open" and o.to == nil then
            return nil, "Only crafters who have shared this recipe can take it. Open your profession window once."
        end
        return nil, "That isn't possible for this order now."
    end
    note = note and note:match("^%s*(.-)%s*$") or ""
    if #note > ns.Log.MAX_NOTE then return nil, "That note is too long." end
    return ns.Log.New("ORDER_ST", { id = id, st = action, h = action == "accept" and hours or nil, n = note ~= "" and note or nil })
end

-- The crafter records that n of an order's items were mailed. Called after
-- the player's own Send click at the mailbox (Modules/Mail.lua).
function O.Mailed(id, n)
    local st = ns.Reducer.State()
    local o = st and st.orders[id]
    if not o or o.crafter ~= ns.MyGUID() or not (o.status == "accepted" or o.status == "ready") then
        return nil, "That order isn't yours to mail."
    end
    n = math.min(tonumber(n) or 0, o.q - (o.mailed or 0))
    if n < 1 then return nil, "Everything for that order is already mailed." end
    return ns.Log.New("ORDER_MAIL", { id = id, n = n })
end

---------------------------------------------------------------------------
-- Telling the player what changed (chat lines only, for their own orders)
---------------------------------------------------------------------------
local seen, seenMail, primed = {}, {}, false

function O.Announce()
    local st = ns.Reducer.State()
    if not st then return end
    local me = ns.MyGUID()
    for id, o in pairs(st.orders) do
        local was = seen[id]
        local mailedNow = o.mailed or 0
        if primed and o.by == me and ACTIVE[o.status] and mailedNow > (seenMail[id] or 0) then
            local item, who = O.ItemText(o), U.Safe(nameOf(o.crafter), 40)
            if mailedNow >= o.q then
                ns.Print(("%s mailed your order: %s. Collect it at a mailbox, then press \"I received it\" under /bp > Professions > Orders."):format(who, item))
            else
                ns.Print(("%s mailed %d of your order: %s. The rest will follow."):format(who, mailedNow, item))
            end
        end
        seenMail[id] = mailedNow
        if primed and was ~= o.status and o.lastBy ~= me then
            local item, who = O.ItemText(o), U.Safe(nameOf(o.lastBy), 40)
            if o.status == "open" and o.to == me and was == nil then
                ns.Print(("New crafting order from %s: %s. Type /bp, then Professions > Orders."):format(U.Safe(nameOf(o.by), 40), item))
            elseif was == nil and O.Matches(st, me, o) then
                ns.Print(("New Wanted order you can craft: %s for %s. Type /bp, then Professions > Orders."):format(item, U.Safe(nameOf(o.by), 40)))
            elseif o.by == me and o.status == "accepted" then
                ns.Print(("%s accepted your order for %s, due in %s."):format(who, item, span(o.due - ns.Now())))
            elseif o.by == me and o.status == "ready" then
                -- Mailed in full: the line above already said so.
                if mailedNow < o.q then ns.Print(("Your order is ready: %s from %s."):format(item, who)) end
            elseif o.by == me and o.status == "declined" then
                ns.Print(("%s can't make %s for you right now."):format(who, item))
            elseif o.by == me and o.status == "open" and was ~= nil then
                ns.Print(("%s handed your order for %s back. It's on the Wanted board again."):format(who, item))
            elseif o.by == me and o.status == "cancelled" then
                ns.Print(("An officer cancelled your order for %s."):format(item))
            elseif o.crafter == me and o.status == "delivered" then
                ns.Print(("%s confirmed delivery of %s. Thank you."):format(who, item))
            elseif (o.crafter == me or o.to == me) and o.status == "cancelled" then
                ns.Print(("The order for %s was cancelled."):format(item))
            end
        end
        seen[id] = o.status
    end
    primed = true
end

local queued, greeted = false, false
ns.Listen("LOG_CHANGED", function()
    if queued or not (C_Timer and C_Timer.After) then return end
    queued = true
    C_Timer.After(1, function()
        queued = false
        O.Announce()
    end)
end)
ns.Listen("ROSTER_CHANGED", function()
    if greeted or not ns.roster.loaded or not (C_Timer and C_Timer.After) then return end
    greeted = true
    C_Timer.After(25, function()
        O.Announce()
        local n = O.Needs(ns.Reducer.State(), ns.MyGUID())
        if n > 0 then
            ns.Print(("%d crafting order%s waiting for you. Type /bp, then Professions > Orders."):format(n, n == 1 and "" or "s"))
        end
    end)
end)
