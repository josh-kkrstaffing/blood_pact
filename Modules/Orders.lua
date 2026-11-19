-- Blood Pact: crafting orders, inside the guild only.
-- A member asks for a recipe to be crafted, either from one named guild
-- crafter or on the Wanted board for any guild crafter who knows it. The
-- crafter accepts with a promised turnaround (2, 8, 24 or 48 hours), marks it
-- ready, and the member who asked confirms delivery.
-- Orders travel only on the guild's addon channel. The one whisper (to an
-- online crafter, when an order is placed for them) goes only to a guild
-- member and only from the player's own click. Trading or mailing the item
-- is always done by the players themselves.
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

-- -> text, tone ("late", "good", "muted" or nil)
function O.StatusText(o, now, nameOf)
    if o.status == "open" then
        if o.to then return "Waiting for " .. (nameOf(o.to) or "?"), "muted" end
        return "Open: any crafter", nil
    elseif o.status == "accepted" then
        if now > o.due then return "Late by " .. span(now - o.due), "late" end
        return "Due in " .. span(o.due - now), nil
    elseif o.status == "ready" then
        return "Ready to hand over", "good"
    elseif o.status == "delivered" then
        return "Delivered " .. date("%b %d", o.doneAt or o.t), "good"
    elseif o.status == "declined" then
        return "Declined", "muted"
    end
    return "Cancelled", "muted"
end

function O.IsLate(o, now) return o.status == "accepted" and now > o.due end

-- Rows for one of the four lists.
--   craft   = waiting for me to accept, or accepted by me and not handed over
--   mine    = orders I placed that are still going
--   wanted  = open orders any crafter may take
--   history = finished orders, newest first
function O.Rows(st, me, which)
    local rows = {}
    for _, o in pairs(st and st.orders or {}) do
        local keep
        if which == "craft" then
            keep = (o.status == "open" and o.to == me) or ((o.status == "accepted" or o.status == "ready") and o.crafter == me)
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
        if (o.status == "open" and o.to == me) or (o.status == "accepted" and o.crafter == me)
            or (o.status == "ready" and o.by == me) then
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
local function recipeLink(rid)
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
        local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
        local msg = ("Blood Pact order: can you make %s%s for me? %s See /bp > Professions > Orders."):format(
            recipeLink(rid), qty > 1 and (" x" .. qty) or "", O.MATS_ASK[mats])
        if send then pcall(send, msg:sub(1, 255), "WHISPER", nil, U.ShortName(m.name)) end
    end
    return e
end

-- accept (with hours), decline, ready, release, deliver, cancel.
function O.Update(id, action, hours, note)
    local st = ns.Reducer.State()
    local o = st and st.orders[id]
    if not o then return nil, "That order is gone." end
    local me = ns.MyGUID()
    local canCraft = st.recipes[me] and st.recipes[me][o.p] and st.recipes[me][o.p][o.rid] or false
    local allowed = O.Actions(o, me, ns.RBAC.ICan("void"), canCraft)
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

---------------------------------------------------------------------------
-- Telling the player what changed (chat lines only, for their own orders)
---------------------------------------------------------------------------
local seen, primed = {}, false

function O.Announce()
    local st = ns.Reducer.State()
    if not st then return end
    local me = ns.MyGUID()
    for id, o in pairs(st.orders) do
        local was = seen[id]
        if primed and was ~= o.status and o.lastBy ~= me then
            local item, who = O.ItemText(o), U.Safe(nameOf(o.lastBy), 40)
            if o.status == "open" and o.to == me and was == nil then
                ns.Print(("New crafting order from %s: %s. Type /bp, then Professions > Orders."):format(U.Safe(nameOf(o.by), 40), item))
            elseif o.by == me and o.status == "accepted" then
                ns.Print(("%s accepted your order for %s, due in %s."):format(who, item, span(o.due - ns.Now())))
            elseif o.by == me and o.status == "ready" then
                ns.Print(("Your order is ready: %s from %s."):format(item, who))
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
