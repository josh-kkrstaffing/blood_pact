-- Blood Pact: BiS check. Compares your gear with Blood Pact's ranked pre-raid
-- list (Modules/BiSData.lua) and ranks your biggest upgrades.
-- Reads only your own equipped items, bags and bank. Nothing is sent anywhere.
-- Items match by name, so this works on English clients only for now.
local _, ns = ...
local BiS = {}
ns.BiS = BiS

-- Item name from an item link: |cff...|Hitem:...|h[Name]|h|r
function BiS.NameFromLink(link)
    if type(link) ~= "string" then return nil end
    return link:match("|h%[(.-)%]|h")
end

-- Pure scoring, no game API. owned = { [name] = "equipped" | "bags" | "bank" }.
-- Ring and trinket slots share items, so one item never fills two slots.
function BiS.Evaluate(list, owned)
    local rows, used, usedWorn = {}, {}, {}
    local total, wornTotal = 0, 0
    local function best(items, taken, wornOnly)
        for _, it in ipairs(items) do
            local where = owned[it.name]
            if where and not taken[it.name] and (not wornOnly or where == "equipped") then
                taken[it.name] = true
                return it, where
            end
        end
    end
    for order, s in ipairs(list.slots) do
        local pick, where = best(s.items, used, false)
        local worn = best(s.items, usedWorn, true)
        local have = pick and pick.score or 0
        local step
        for i = #s.items, 2, -1 do
            if s.items[i].score > have then step = s.items[i]; break end
        end
        total = total + have
        wornTotal = wornTotal + (worn and worn.score or 0)
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

function BiS.CurrentSpec()
    local lists = BiS.Lists()
    if not lists then return nil end
    local c = charStore()
    local key = c and c.bisSpec
    if key and lists[key] then return key, lists[key] end
    local k = next(lists)
    if k then return k, lists[k] end
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
ns.On("PLAYER_EQUIPMENT_CHANGED", function() if ns.UI then ns.UI.Refresh() end end)

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
    p.summary:SetWidth(480)
    p.specButtons = {}

    local header = { { "Slot", 4 }, { "You have", 84 }, { "Score", 262 }, { "Blood Pact BiS", 312 }, { "How to get it", 480 } }
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
    p.list:Stretch(0, -82, 0, 20)
    p.note = W.Text(p, "Hover a row for every option and a step-up item. Open your bank once so banked items count.", "GameFontDisableSmall")
    p.note:SetPoint("BOTTOMLEFT", 0, 0)
end, function(p)
    local lists, class = BiS.Lists()
    for _, b in ipairs(p.specButtons) do b:Hide() end
    if not lists then
        p.title:SetText("BiS Check")
        p.summary:SetText("Blood Pact doesn't have a ranked list for " .. U.Safe(class or "your class", 20) .. " yet.")
        p.list:SetItems({})
        return
    end
    local key, list = BiS.CurrentSpec()
    local i = 0
    for k, l in pairs(lists) do
        i = i + 1
        local b = p.specButtons[i]
        if not b then
            b = W.Button(p, "", 150, 20)
            p.specButtons[i] = b
        end
        b:SetText(l.label)
        b:SetPoint("TOPRIGHT", 0, -(i - 1) * 22)
        b:SetEnabled(k ~= key)
        b:SetScript("OnClick", function() BiS.SetSpec(k); ns.UI.Refresh() end)
        b:Show()
    end
    local rows, owned, worn = BiS.Evaluate(list, BiS.Owned())
    p.title:SetText("Pre-raid BiS: " .. list.label .. "  (list updated " .. list.updated .. ")")
    local s = "Wearing " .. pct(worn) .. " of Blood Pact BiS. With what's in your bags and bank: " .. pct(owned) .. "."
    if BiS.QuestieReady() then s = s .. " Questie is on, so quest givers show on your map." end
    p.summary:SetText(s)
    p.list:SetItems(rows)
end)
