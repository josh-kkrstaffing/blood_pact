-- Blood Pact: loot history.
-- Every time an officer charges DKP for an item in Raid & Loot, the guild's
-- log already records who got it, which item, the price and when. This file
-- turns those records into two views: a member's loot (Roster) and the
-- guild's loot night by night (Raid & Loot, visible to every member).
-- Item names, icons and stats are not stored or bundled: they are asked from
-- the game itself by item id, the same data the game shows in its tooltips.
local _, ns = ...
local Loot = {}
ns.Loot = Loot

local U = ns.U
local date = date or os.date   -- WoW global; os.date in tests

Loot.TIER = { bis = "BiS", major = "Major", minor = "Minor", off = "Off spec" }
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

---------------------------------------------------------------------------
-- Pure logic
---------------------------------------------------------------------------
-- Every loot charge that still counts (voided ones are gone), newest first.
function Loot.Entries(st)
    local out = {}
    for _, e in ipairs(st and st.history or {}) do
        if e.k == "SPEND" then
            out[#out + 1] = { id = e.id, to = e.d.from, item = e.d.item, amt = e.d.amt, tier = e.d.tier,
                t = e.t, by = e.a, night = ns.Time.RaidDay(e.t) }
        end
    end
    table.sort(out, function(a, b)
        if a.t ~= b.t then return a.t > b.t end
        return tostring(a.id) > tostring(b.id)
    end)
    return out
end

-- One person's loot: the character's own and their linked alts' or main's.
function Loot.For(st, entries, guid)
    local alts = st and st.alts or {}
    local main = alts[guid] or guid
    local out = {}
    for _, e in ipairs(entries) do
        if (alts[e.to] or e.to) == main then out[#out + 1] = e end
    end
    return out
end

-- "2026-11-17" -> "Nov 17, 2026"
function Loot.NightLabel(night)
    local y, m, d = tostring(night):match("^(%d+)-(%d+)-(%d+)$")
    if not y then return tostring(night) end
    return ("%s %d, %s"):format(MONTHS[tonumber(m)] or "?", tonumber(d), y)
end

-- Rows for the night-by-night list: a header row per raid night, then its
-- loot. filter matches a winner's name or an item's name.
function Loot.Nights(entries, filter, nameOf, itemNameOf)
    local rows, header = {}, nil
    for _, e in ipairs(entries) do
        local keep = not filter or filter == ""
        if not keep then
            local who = (nameOf(e.to) or ""):lower()
            local what = (e.item and itemNameOf(e.item) or ""):lower()
            keep = who:find(filter, 1, true) ~= nil or what:find(filter, 1, true) ~= nil
        end
        if keep then
            if not header or header.night ~= e.night then
                header = { header = true, id = "night:" .. e.night, night = e.night, count = 0, total = 0 }
                rows[#rows + 1] = header
            end
            header.count = header.count + 1
            header.total = header.total + (e.amt or 0)
            rows[#rows + 1] = e
        end
    end
    return rows
end

---------------------------------------------------------------------------
-- Game side: item data straight from the game, by id
---------------------------------------------------------------------------
local cache = {}

-- -> { name, link, quality, icon }; fields are nil until the game has them.
function Loot.Item(id)
    if not id then return nil end
    local c = cache[id]
    if c and c.name then return c end
    c = c or {}
    cache[id] = c
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if type(get) == "function" then
        local ok, name, link, quality, _, _, _, _, _, _, icon = pcall(get, id)
        if ok and type(name) == "string" then c.name, c.link, c.quality, c.icon = name, link, quality, icon end
    end
    if not c.name then
        -- Not loaded yet: take the icon now and ask the game for the rest.
        if not c.icon and C_Item and C_Item.GetItemIconByID then
            local ok, icon = pcall(C_Item.GetItemIconByID, id)
            if ok then c.icon = icon end
        end
        if not c.asked and C_Item and C_Item.RequestLoadItemDataByID then
            c.asked = true
            pcall(C_Item.RequestLoadItemDataByID, id)
        end
    end
    return c
end

function Loot.ItemName(id)
    local c = Loot.Item(id)
    return c and c.name or nil
end

-- The game tells us when an item's data has arrived: redraw.
ns.On("GET_ITEM_INFO_RECEIVED", function()
    if ns.UI and ns.UI.IsOpen and ns.UI.IsOpen() then ns.UI.RefreshSoon() end
end)

local function nameOf(guid)
    local st = ns.Reducer.State()
    return ns.NameForGUID(guid) or (st and st.members[guid] and st.members[guid].name) or "?"
end
Loot.NameOf = nameOf

-- The game's own item tooltip (stats and all), plus who got it and when.
function Loot.Tooltip(owner, e)
    if not e or e.header then return end
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")      -- at the pointer, so it stays on screen
    local item = Loot.Item(e.item)
    local shown = false
    if e.item then
        if item and item.link and GameTooltip.SetHyperlink then
            shown = pcall(GameTooltip.SetHyperlink, GameTooltip, item.link)
        elseif GameTooltip.SetItemByID then
            shown = pcall(GameTooltip.SetItemByID, GameTooltip, e.item)
        end
    end
    if not shown then GameTooltip:AddLine(e.item and ("Item " .. e.item) or "Item not recorded") end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("%s, %s"):format(U.Safe(nameOf(e.to), 40), date("%b %d, %Y", e.t)), 1, 0.82, 0)
    GameTooltip:AddLine(("%d DKP, %s. Charged by %s."):format(e.amt or 0, Loot.TIER[e.tier] or "?", U.Safe(nameOf(e.by), 40)), 0.8, 0.8, 0.8)
    if item and item.link then GameTooltip:AddLine("Shift-click to link it in chat.", 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

-- A click with Shift held puts the item's link in the chat box, as the game does.
function Loot.Click(e)
    if not e or e.header or not e.item then return end
    if not (IsShiftKeyDown and IsShiftKeyDown()) then return end
    local item = Loot.Item(e.item)
    if not (item and item.link) then return end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        ChatFrameUtil.InsertLink(item.link)
    elseif ChatEdit_InsertLink then
        ChatEdit_InsertLink(item.link)
    end
end

-- Draw one row. wide = the night-by-night list; otherwise a member's list.
function Loot.Render(list, row, e, wide)
    if not row.icon then
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", wide and 6 or 2, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row:SetScript("OnEnter", function(self) Loot.Tooltip(self, self.item) end)
        row:SetScript("OnLeave", GameTooltip_Hide)
    end
    local W = ns.W
    local name = list.Col(row, 1, wide and 28 or 22, wide and 230 or 118)
    local c2 = list.Col(row, 2, wide and 264 or 142, wide and 150 or 44)
    local c3 = list.Col(row, 3, wide and 418 or 188, wide and 66 or 32, (not wide) and "RIGHT" or nil)
    local c4 = wide and list.Col(row, 4, 486, 50, "RIGHT")
    local c5 = wide and list.Col(row, 5, 548, 140)
    if e.header then
        row.icon:Hide()
        name:SetText(Loot.NightLabel(e.night))
        name:SetTextColor(W.C.gold[1], W.C.gold[2], W.C.gold[3])
        c2:SetText(e.count .. (e.count == 1 and " item" or " items"))
        c2:SetTextColor(W.C.muted[1], W.C.muted[2], W.C.muted[3])
        c3:SetText("")
        if c4 then c4:SetText(e.total); c4:SetTextColor(W.C.muted[1], W.C.muted[2], W.C.muted[3]) end
        if c5 then c5:SetText("") end
        return
    end
    local item = Loot.Item(e.item)
    row.icon:SetShown(item ~= nil and item.icon ~= nil)
    if item and item.icon then row.icon:SetTexture(item.icon) end
    name:SetText(U.Safe(item and item.name or (e.item and ("Item " .. e.item) or "Item not recorded"), 60))
    local q = item and item.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality]
    if q then name:SetTextColor(q.r, q.g, q.b) else name:SetTextColor(W.C.text[1], W.C.text[2], W.C.text[3]) end
    if wide then
        c2:SetText(U.Safe(nameOf(e.to), 40))
        local m = ns.roster.byGUID[e.to]
        local cc = m and m.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.class]
        if cc then c2:SetTextColor(cc.r, cc.g, cc.b) else c2:SetTextColor(W.C.text[1], W.C.text[2], W.C.text[3]) end
        c3:SetText(Loot.TIER[e.tier] or "")
        c4:SetText(e.amt or 0)
        c4:SetTextColor(W.C.text[1], W.C.text[2], W.C.text[3])
        c5:SetText("by " .. U.Safe(nameOf(e.by), 30))
        c5:SetTextColor(W.C.muted[1], W.C.muted[2], W.C.muted[3])
    else
        c2:SetText(date("%b %d", e.t))
        c2:SetTextColor(W.C.muted[1], W.C.muted[2], W.C.muted[3])
        c3:SetText(e.amt or 0)
    end
end
