-- Blood Pact smoke test: runs the whole addon, as the game would load it,
-- inside a stand-in for the WoW client. Three "players" in one guild load
-- the addon, sync with each other over a simulated addon channel, open every
-- tab and press every button. Any Lua error, any call to a widget method the
-- stand-in doesn't have, and any unknown global fails the run.
-- Run from the repo root:  lua tests/smoke.lua   (Lua 5.1+)
local report = print   -- the addon's print is captured per player below
local unpack = unpack or rawget(table, "unpack")
math.randomseed(tonumber(os.getenv("SEED")) or 1)

---------------------------------------------------------------------------
-- World: virtual clock, timers, error collection
---------------------------------------------------------------------------
local clock, BASE = 0, 1797019200
local timers, errors, ctx = {}, {}, nil
local clients = {}

local function fail(where, err) errors[#errors + 1] = where .. ": " .. tostring(err) end

local function inCtx(c, where, fn, ...)
    local prev = ctx
    ctx = c
    local args, n = { ... }, select("#", ...)
    -- Lua 5.1's xpcall passes no arguments, so wrap the call.
    local ok, err = xpcall(function() return fn(unpack(args, 1, n)) end,
        function(e) return debug.traceback(tostring(e), 2) end)
    ctx = prev
    if not ok then fail(where, err) end
end

local function addTimer(delay, fn, every)
    timers[#timers + 1] = { at = clock + delay, fn = fn, every = every, ctx = ctx }
end

local function advance(seconds)
    local stop = clock + seconds
    while true do
        local best, bi
        for i, t in ipairs(timers) do
            if t.at <= stop and (not best or t.at < best.at) then best, bi = t, i end
        end
        if not best then break end
        clock = best.at
        if best.every then best.at = best.at + best.every else table.remove(timers, bi) end
        if best.ctx.online then inCtx(best.ctx, "timer", best.fn) end
    end
    clock = stop
end

---------------------------------------------------------------------------
-- Widgets: every method the addon may call. Calling any other is an error.
---------------------------------------------------------------------------
local M = {}
-- Unknown names read as nil, so calling a method that doesn't exist fails
-- with "attempt to call a nil value", as it would in the game.
local frameMT = { __index = M }

local function widget(kind, parent)
    local w = setmetatable({}, frameMT)
    rawset(w, "_", { kind = kind, parent = parent, scripts = {}, shown = true, enabled = true, text = "",
        w = 100, h = 20, scroll = 0, checked = false, events = {}, ctx = ctx })
    if ctx then ctx.widgets[#ctx.widgets + 1] = w end
    return w
end

local function noop() end
for _, name in ipairs({ "SetPoint", "ClearAllPoints", "SetAllPoints", "SetColorTexture", "SetFontObject", "SetJustifyH",
    "SetJustifyV", "SetWordWrap", "SetTextColor", "SetShadowColor", "SetShadowOffset", "SetFont", "CopyFontObject",
    "SetNormalFontObject", "SetHighlightFontObject", "SetDisabledFontObject", "SetAutoFocus", "SetMaxLetters",
    "SetTextInsets", "ClearFocus", "SetFocus", "HighlightText", "SetMultiLine", "SetCheckedTexture", "RegisterForClicks",
    "RegisterForDrag", "SetScrollChild", "SetFrameStrata", "SetClampedToScreen", "SetMovable", "EnableMouse",
    "SetResizable", "SetResizeBounds", "StartMoving", "StartSizing", "StopMovingOrSizing", "SetDrawLayer",
    "SetSnapToPixelGrid", "SetTexelSnappingBias", "SetOwner", "AddLine", "AddDoubleLine", "EnableMouseWheel",
    "SetOrientation", "SetThumbTexture", "SetToplevel", "Raise", "SetStartPoint", "SetEndPoint", "SetThickness", "SetValueStep", "SetTexture", "SetTexCoord", "SetSpellByID", "SetHyperlink", "SetItemByID", "SetFrameLevel" }) do
    M[name] = noop
end
-- Secure buttons and the frames that hold them are locked while their owner
-- is in combat: changing them then is an error here, as it is blocked in game.
local COMBAT = {}
local function locked(w, what)
    if w._.protected and w._.ctx and COMBAT[w._.ctx.guid] then
        error("a protected frame was changed in combat (" .. what .. ")", 3)
    end
end
function M:SetPoint() locked(self, "SetPoint") end
function M:ClearAllPoints() locked(self, "ClearAllPoints") end
function M:SetAttribute(name, value)
    locked(self, "SetAttribute")
    self._.attrs = self._.attrs or {}
    self._.attrs[name] = value
end
function M:GetAttribute(name) return self._.attrs and self._.attrs[name] end
function M:SetSize(w, h) locked(self, "SetSize"); self._.w, self._.h = w, h end
function M:SetWidth(w) self._.w = w end
function M:SetHeight(h) self._.h = h end
function M:GetWidth() return self._.w end
function M:GetHeight() return self._.h end
function M:SetText(t)
    if type(t) ~= "string" and type(t) ~= "number" then error("SetText needs text, got " .. type(t), 2) end
    self._.text = tostring(t)
end
function M:GetText() return self._.text end
function M:GetStringWidth() return 7 * #self._.text end
function M:GetFontString() self._.fs = self._.fs or widget("FontString", self); self._.fs._.text = self._.text; return self._.fs end
function M:SetScript(name, fn) self._.scripts[name] = fn end
function M:GetScript(name) return self._.scripts[name] end
function M:HookScript(name, fn)
    local old = self._.scripts[name]
    self._.scripts[name] = old and function(...) old(...); fn(...) end or fn
end
function M:Show() locked(self, "Show"); self._.shown = true end
function M:Hide() locked(self, "Hide"); self._.shown = false end
function M:SetShown(v) locked(self, "SetShown"); self._.shown = v and true or false end
function M:IsShown() return self._.shown end
function M:IsVisible()
    local w = self
    while w do
        if not w._.shown then return false end
        w = w._.parent
    end
    return true
end
function M:SetEnabled(v)
    local was = self._.enabled
    self._.enabled = v and true or false
    local s = self._.scripts[self._.enabled and "OnEnable" or "OnDisable"]
    if s and was ~= self._.enabled then s(self) end
end
function M:IsEnabled() return self._.enabled end
function M:SetParent(parent) locked(self, "SetParent"); self._.parent = parent end
function M:CreateTexture() return widget("Texture", self) end
function M:CreateLine() return widget("Line", self) end
function M:CreateFontString() return widget("FontString", self) end
function M:HasFocus() return false end
function M:SetChecked(v) self._.checked = v and true or false end
function M:GetChecked() return self._.checked end
function M:SetMinMaxValues(lo, hi) self._.lo, self._.hi = lo, hi end
function M:GetValue() return self._.value or 0 end
function M:SetValue(v)
    self._.value = v
    if self._.scripts.OnValueChanged then self._.scripts.OnValueChanged(self, v) end
end
function M:GetVerticalScroll() return self._.scroll end
function M:SetVerticalScroll(v) self._.scroll = v end
function M:GetFrameLevel() return 1 end
function M:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function M:RegisterEvent(e) self._.events[e] = true end

---------------------------------------------------------------------------
-- The guild and the addon channel
---------------------------------------------------------------------------
local GUILD = {
    -- name, rank index, rank name, class, level, zone, guid
    { "Binky Bee", 0, "Guild Master", "WARLOCK", 60, "Orgrimmar", "Player-1-GM" },
    { "Grim Tusk", 1, "Officer", "WARRIOR", 60, "Orgrimmar", "Player-1-OFFICER" },
    { "Pip", 4, "Member", "ROGUE", 44, "Tanaris", "Player-1-MEMBER" },
    { "Vela", 3, "Veteran", "MAGE", 60, "Orgrimmar", "Player-1-VET" },
}
local REALM = "-Normal"
local whisperNeedsShortName = false
local sentAddon, invites, guildChat = 0, {}, {}
local CHATLOCK, chatRefused = {}, 0

local function fire(c, event, ...)
    if not c.online then return end
    for _, w in ipairs(c.widgets) do
        if w._.events[event] and w._.scripts.OnEvent then inCtx(c, event, w._.scripts.OnEvent, w, event, ...) end
    end
end

local function clientByName(name)
    for _, c in pairs(clients) do
        if c.name == name or c.name .. REALM == name then return c end
    end
end

---------------------------------------------------------------------------
-- Globals the addon uses. Reading any other global is recorded.
---------------------------------------------------------------------------
local OPTIONAL = {}   -- globals the addon only probes for; fine to be missing
for _, n in ipairs({ "ChatEdit_InsertLink", "ChatFrame_SendTell", "GetContainerNumSlots", "GetContainerItemLink",
    "BANK_CONTAINER", "NUM_BAG_SLOTS", "NUM_BANKBAGSLOTS", "Questie", "ERR_GUILD_JOIN_S", "ERR_GUILD_LEAVE_S",
    "ERR_GUILD_REMOVE_SS", "ERR_GUILD_PROMOTE_SSS", "ERR_GUILD_DEMOTE_SSS", "ERR_CHAT_PLAYER_NOT_FOUND_S",
    "ChatFrame_AddMessageEventFilter", "InviteUnit", "SendChatMessage", "BloodPactDB", "RaidNotice_AddMessage",
    "RaidWarningFrame", "ChatTypeInfo", "SOUNDKIT", "PlaySound", "PixelUtil", "GameFontNormalLarge", "GameFontNormal",
    "GameFontNormalSmall", "GameFontHighlight", "GameFontHighlightSmall", "GameFontDisableSmall", "GameFontDisable",
    "BloodPactFontTitle", "BloodPactFontHeader", "BloodPactFontHeaderSmall", "BloodPactFontBody",
    "BloodPactFontBodySmall", "BloodPactFontMuted", "BloodPactFontDisabled", "os", "C_Item", "GetSpellInfo",
    "ChatEdit_GetActiveWindow", "ChatFrame_OpenChat", "CreateColor", "IsMetaKeyDown",
    "CharacterFrame", "PVPFrame", "PVPUIFrame", "IsInInstance", "UnitBuff", "issecretvalue",
    "PawnGetItemData", "PawnIsItemAnUpgrade", "PawnIsReady", "PawnCanItemHaveStats", "PawnBigUpgradeThreshold" }) do
    OPTIONAL[n] = true
end
local unknownGlobals = {}
setmetatable(_G, { __index = function(_, k)
    if not OPTIONAL[k] then unknownGlobals[k] = true end
    return nil
end })

local G = _G
G.date, G.time = os.date, os.time
G.tinsert, G.wipe = table.insert, function(t) for k in pairs(t) do t[k] = nil end return t end
-- Hooks on game functions, kept per player so one player's hook never sees another's call.
local hooks = {}
G.hooksecurefunc = function(name, fn)
    if type(name) ~= "string" then return end
    hooks[name] = hooks[name] or {}
    table.insert(hooks[name], { ctx = ctx, fn = fn })
end
G.geterrorhandler = function() return function(err) fail("handler", err) end end
G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    if ctx then ctx.out[#ctx.out + 1] = table.concat(parts, " ") end
end
G.GetTime = function() return clock end
G.GetServerTime = function() return BASE + math.floor(clock) end
G.CreateFrame = function(kind, name, parent, template)
    local w = widget(kind, parent)
    if type(template) == "string" and template:find("Secure", 1, true) then
        local up = w
        while up do up._.protected = true; up = up._.parent end
    end
    if name then rawset(G, name, w) end
    return w
end
G.CreateFont = function() return widget("Font") end
G.UIParent = widget("Frame")
G.UISpecialFrames = {}
G.GameTooltip = widget("GameTooltip")
G.GameTooltip_Hide = function() end
G.SlashCmdList = {}
G.Enum = { CalendarEventType = { Raid = 1 }, AuctionHouseSortOrder = { Price = 0 },
    AuctionHouseFilter = { UsableOnly = 2, UncommonQuality = 8, RareQuality = 9, EpicQuality = 10 } }
G.C_Timer = {
    After = function(d, fn) addTimer(d, fn) end,
    NewTicker = function(d, fn) addTimer(d, fn, d) end,
}
-- Groups: GROUPS[guid] = { raid = bool, guid, guid, ... } as that player sees
-- their party ("party1"...) or raid ("raid1"...).
local GROUPS, NEARBY, TARGETS, CHANNELING = {}, {}, {}, {}
local function unitGuid(unit)
    if unit == nil or unit == "player" then return ctx.guid end
    if unit == "target" then return TARGETS[ctx.guid] end
    local kind, i = tostring(unit):match("^(%a+)(%d+)$")
    local g = GROUPS[ctx.guid]
    if g and kind == (g.raid and "raid" or "party") then return g[tonumber(i)] end
    return nil
end
G.UnitGUID = function(unit) return unitGuid(unit) end
G.UnitName = function(unit)
    local guid = unitGuid(unit)
    if guid == ctx.guid then return ctx.name end
    for _, m in ipairs(GUILD) do if m[7] == guid then return m[1] end end
    return nil
end
G.InCombatLockdown = function() return COMBAT[ctx.guid] == true end
G.UnitInRange = function(unit) return NEARBY[unitGuid(unit) or ""] == true, true end
G.UnitChannelInfo = function(unit) return CHANNELING[unitGuid(unit) or ""] end
G.UnitClass = function() return ctx.class, ctx.class end
-- Raid Kit: what each player holds (bags and bank together), their buffs and weapon buff.
local STOCK, AURAS, WEAPON_BUFF = {}, {}, {}
G.GetItemCount = function(name, bank) return bank and (STOCK[ctx.guid] or {})[name] or 0 end
G.C_UnitAuras = { GetAuraDataByIndex = function(unit, i)
    if COMBAT[ctx.guid] then return nil end
    local n = (AURAS[ctx.guid] or {})[i]
    return n and { name = n } or nil
end }
G.GetWeaponEnchantInfo = function() return WEAPON_BUFF[ctx.guid] == true end
-- Text to speech: what each player's computer was asked to say.
local SPOKEN = {}
G.C_VoiceChat = {
    GetTtsVoices = function() return { { voiceID = 0, name = "Default voice" } } end,
    SpeakText = function(voice, text, rate, volume)
        assert(voice == 0 and rate == 0 and volume == 100, "the voice call uses the order that worked in the game")
        SPOKEN[ctx.guid] = SPOKEN[ctx.guid] or {}
        table.insert(SPOKEN[ctx.guid], text)
    end,
}
-- The auction house: materials are bought in bulk in two steps, and arrive by mail.
local AH_PRICE, MONEY, AH_BOUGHT, AH_PENDING = { [10940] = 150, [10938] = 400 }, {}, {}, {}
G.GetMoney = function() return MONEY[ctx.guid] or 0 end
G.C_AuctionHouse = {
    GetItemCommodityStatus = function(item) return item == 10938 and 1 or 2 end,
    StartCommoditiesPurchase = function(item, qty)
        local c = ctx
        AH_PENDING[c.guid] = { item = item, qty = qty }
        addTimer(0.2, function() fire(c, "COMMODITY_PRICE_UPDATED", AH_PRICE[item], AH_PRICE[item] * qty) end)
    end,
    ConfirmCommoditiesPurchase = function(item, qty)
        local c = ctx
        local q = AH_PENDING[c.guid]
        assert(q and q.item == item and q.qty == qty, "a purchase is confirmed only after its own price check")
        AH_PENDING[c.guid] = nil
        MONEY[c.guid] = MONEY[c.guid] - AH_PRICE[item] * qty
        AH_BOUGHT[#AH_BOUGHT + 1] = { who = c.guid, item = item, qty = qty }
        addTimer(0.2, function() fire(c, "COMMODITY_PURCHASE_SUCCEEDED") end)
    end,
    CancelCommoditiesPurchase = function() AH_PENDING[ctx.guid] = nil end,
}
-- Gear at the auction house: a search by name lists item kinds, then each kind lists its auctions.
-- This auction house files a random-enchantment item under its plain name.
local function gearLink(name) return "|cff1eff00|Hitem:1::::::::60:::::|h[" .. name .. "]|h|r" end
local AH_GEAR = {
    { key = { itemID = 2001 }, file = "Master's Mantle", auctions = {
        { id = 501, name = "Master's Mantle of Magic", buyout = 250000 },
        { id = 502, name = "Master's Mantle of the Owl", buyout = 50000 },
        { id = 503, name = "Master's Mantle of Magic", buyout = 0 },
        { id = 504, name = "Master's Mantle of Magic", buyout = 400000 },
        { id = 505, name = "Master's Mantle of Magic", buyout = 10000, mine = true } } },
    { key = { itemID = 2002 }, file = "Argent Shoulders", auctions = { { id = 510, name = "Argent Shoulders", buyout = 1200000 } } },
}
-- Usable gear that is on no list, cheapest first. The auction house hands it over in two pages.
local AH_USABLE = {
    { key = { itemID = 3001 }, file = "Shadoweave Shoulders", loc = "INVTYPE_SHOULDER", price = 30000, auctions = { { id = 601, name = "Shadoweave Shoulders", buyout = 30000 } } },
    { key = { itemID = 3002 }, file = "Raincaller Scepter", loc = "INVTYPE_HOLDABLE", price = 13700, auctions = { { id = 602, name = "Raincaller Scepter of the Elder", buyout = 13700 } } },
    { key = { itemID = 3003 }, file = "Plain Robe", loc = "INVTYPE_ROBE", price = 20000, auctions = { { id = 603, name = "Plain Robe", buyout = 20000 } } },
    { key = { itemID = 3006 }, file = "Slow Ring", loc = "INVTYPE_FINGER", price = 25000, auctions = { { id = 608, name = "Slow Ring", buyout = 25000 } } },
    { key = { itemID = 3005 }, file = "Wanderer's Cloak", loc = "INVTYPE_CLOAK", price = 15000, auctions = {
        { id = 605, name = "Wanderer's Cloak of Magic", buyout = 20000 }, { id = 606, name = "Wanderer's Cloak of Magic", buyout = 15000 } } },
    { key = { itemID = 2002 }, file = "Argent Shoulders", loc = "INVTYPE_SHOULDER", price = 1200000 },
    { key = { itemID = 3004 }, file = "Gold Ring", loc = "INVTYPE_FINGER", price = 90000000, auctions = { { id = 604, name = "Gold Ring", buyout = 90000000 } } },
    { key = { itemID = 3007 }, file = "Never Read", loc = "INVTYPE_HEAD", price = 95000000, auctions = { { id = 609, name = "Never Read", buyout = 95000000 } } },
}
for _, g in ipairs(AH_GEAR) do if g.key.itemID == 2002 then AH_USABLE[6].key, AH_USABLE[6].auctions = g.key, g.auctions end end
local AH_PAGES, AH_SHOWN, AH_MORE = {}, {}, 0
G.GetItemInfoInstant = function(id)
    for _, g in ipairs(AH_USABLE) do if g.key.itemID == id then return id, "Armor", "", g.loc, 1, 4, 1 end end
end
G.AuctionHouseFrameDisplayMode = { Buy = {} }
G.AuctionHouseFrame = { SetDisplayMode = function() end, SearchBar = {
    SearchBox = { SetText = function(_, text) AH_SHOWN[#AH_SHOWN + 1] = text end },
    StartSearch = function() AH_SHOWN.started = (AH_SHOWN.started or 0) + 1 end } }
-- Pawn, as its own code and another WoW Forever addon use it. It knows the stats; the fake knows the answers.
-- "Slow Ring" isn't loaded the first time Pawn is asked.
local PAWN_SAYS = { ["Shadoweave Shoulders"] = 0.214, ["Wanderer's Cloak of Magic"] = 100, ["Slow Ring"] = 0.05, ["Argent Shoulders"] = 0.9 }
local PAWN_ASKED, PAWN_SLOW = {}, {}
local function installPawn()
    G.PawnBigUpgradeThreshold = 100
    G.PawnIsReady = function() return true end
    G.PawnCanItemHaveStats = function(link) return link ~= nil end
    G.PawnGetItemData = function(link)
        local name = link:match("%[(.-)%]")
        PAWN_ASKED[name] = (PAWN_ASKED[name] or 0) + 1
        if name == "Slow Ring" and not PAWN_SLOW[1] then PAWN_SLOW[1] = true; return nil end
        return { Link = link, name = name }
    end
    G.PawnIsItemAnUpgrade = function(item)
        local share = PAWN_SAYS[item.name]
        return share and { { ScaleName = "Warlock: Affliction", PercentUpgrade = share } } or nil
    end
end
local AH_BROWSE, AH_SEARCHES, AH_BIDS = {}, {}, {}
local function gearByKey(key)
    for _, g in ipairs(AH_GEAR) do if g.key == key then return g end end
    for _, g in ipairs(AH_USABLE) do if g.key == key then return g end end
end
G.C_AuctionHouse.IsThrottledMessageSystemReady = function() return true end
G.C_AuctionHouse.SendBrowseQuery = function(q)
    assert(type(q.searchString) == "string" and type(q.sorts) == "table" and #q.filters > 0, "a browse query names its text, sorts and filters")
    local c, out = ctx, {}
    if q.itemClassFilters then
        assert(q.searchString == "" and q.filters[1] == G.Enum.AuctionHouseFilter.UsableOnly and #q.itemClassFilters == 2, "the usable pass asks for usable weapons and armor")
        assert(q.sorts[1] and q.sorts[1].sortOrder == G.Enum.AuctionHouseSortOrder.Price, "cheapest first")
        for i = 1, 4 do out[i] = { itemKey = AH_USABLE[i].key, minPrice = AH_USABLE[i].price } end
        AH_BROWSE[c.guid], AH_PAGES[c.guid] = out, 4
        addTimer(0.2, function() fire(c, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") end)
        return
    end
    for _, g in ipairs(AH_GEAR) do
        if g.file:lower():find(q.searchString:lower(), 1, true) then out[#out + 1] = { itemKey = g.key, minPrice = 1, totalQuantity = #g.auctions } end
    end
    AH_BROWSE[c.guid] = out
    AH_SEARCHES[#AH_SEARCHES + 1] = q.searchString
    addTimer(0.2, function() fire(c, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") end)
end
G.C_AuctionHouse.HasFullBrowseResults = function() return (AH_PAGES[ctx.guid] or #AH_USABLE) >= #AH_USABLE end
G.C_AuctionHouse.RequestMoreBrowseResults = function()
    local c = ctx
    local from = AH_PAGES[c.guid] + 1
    for i = from, math.min(from + 2, #AH_USABLE) do
        table.insert(AH_BROWSE[c.guid], { itemKey = AH_USABLE[i].key, minPrice = AH_USABLE[i].price })
        AH_PAGES[c.guid] = i
    end
    AH_MORE = AH_MORE + 1
    addTimer(0.2, function() fire(c, "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", {}) end)
end
G.C_AuctionHouse.GetItemKeySampleLink = function(key)
    local g = gearByKey(key)
    return g and g.auctions and gearLink(g.auctions[1].name) or nil
end
G.C_AuctionHouse.GetBrowseResults = function() return AH_BROWSE[ctx.guid] or {} end
G.C_AuctionHouse.GetItemKeyInfo = function(key) local g = gearByKey(key); return g and { itemName = g.file } or nil end
G.C_AuctionHouse.SendSearchQuery = function(key, sorts, separate)
    assert(gearByKey(key) and type(sorts) == "table" and separate == false, "an item search uses a key the auction house listed")
    local c = ctx
    addTimer(0.2, function() fire(c, "ITEM_SEARCH_RESULTS_UPDATED", key) end)
end
G.C_AuctionHouse.GetNumItemSearchResults = function(key) return #gearByKey(key).auctions end
G.C_AuctionHouse.GetItemSearchResultInfo = function(key, i)
    local a = gearByKey(key).auctions[i]
    return { auctionID = a.id, buyoutAmount = a.buyout, itemLink = gearLink(a.name), containsOwnerItem = a.mine or false }
end
G.C_AuctionHouse.PlaceBid = function(id, amount)
    local c = ctx
    for _, g in ipairs(AH_GEAR) do
        for _, a in ipairs(g.auctions) do
            if a.id == id then
                assert(amount == a.buyout and a.buyout > 0, "an item is bought at its buyout price, never bid on")
                MONEY[c.guid] = MONEY[c.guid] - amount
                AH_BIDS[#AH_BIDS + 1] = { who = c.guid, id = id, amount = amount }
                addTimer(0.2, function() fire(c, "AUCTION_HOUSE_PURCHASE_COMPLETED", id) end)
                return
            end
        end
    end
    error("bid on an auction that doesn't exist")
end
G.UnitLevel = function() return ctx.level end
-- Skills, served through a different game API for each player so that all
-- three ways of reading them are exercised.
local SKILLS = {
    ["Player-1-GM"] = { api = "modern", list = { { "Tailoring", 300, true }, { "Enchanting", 280, true }, { "Fishing", 40, false, 75 }, { "Cooking", 225 }, { "First Aid", 300 } } },
    ["Player-1-OFFICER"] = { api = "classic", list = { { "Blacksmithing", 300, true }, { "Mining", 290, true }, { "First Aid", 150 }, { "Cooking", 1 } } },
    ["Player-1-MEMBER"] = { api = "ids", list = { { "Skinning", 201, true }, { "Fishing", 75 } } },
}
G.GetProfessions = function()
    local s = SKILLS[ctx.guid]
    if not s or s.api ~= "modern" then return nil end
    return 1, 2, nil, 3, 4, 5
end
G.GetProfessionInfo = function(i)
    local e = SKILLS[ctx.guid].list[i]
    if e then return e[1], nil, e[2], e[4] or 300 end
end
G.GetNumSkillLines = function()
    local s = SKILLS[ctx.guid]
    return (s and s.api == "classic") and #s.list + 3 or 0
end
G.GetSkillLineInfo = function(i)
    local list = SKILLS[ctx.guid].list
    if i == 1 then return "Class Skills", true end
    if i == 2 then return "Professions", true end
    if i <= 4 then return list[i - 2][1], false, false, list[i - 2][2], 0, 0, 300 end
    if i == 5 then return "Secondary Skills", true end
    local e = list[i - 3]
    if e then return e[1], false, false, e[2], 0, 0, e[4] or 225 end
end
G.RAID_CLASS_COLORS = { WARLOCK = { r = 0.53, g = 0.53, b = 0.93 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    ROGUE = { r = 1, g = 0.96, b = 0.41 } }   -- no MAGE: a class without a color must still draw
-- The profession window: which one a player has open, and its recipes.
local RECIPE_NAMES = { [7418] = "Enchant Bracer - Minor Health", [7420] = "Enchant Chest - Minor Health",
    [7421] = "Runed Copper Rod", [13380] = "Enchant Shield - Lesser Spirit", [25124] = "Minor Wizard Oil" }
local TRADE = {}   -- guid -> { prof = "Enchanting", known = { id = true }, linked = bool }
local function tradeWindow() return TRADE[ctx.guid] end
-- Auctionator's public price API: one reagent has an auction price, one none.
G.Auctionator = { API = { v1 = {
    GetAuctionPriceByItemID = function(caller, item)
        assert(caller == "BloodPact", "Auctionator wants the caller's name")
        return (item == 10940 and 150) or (item == 6218 and 12345) or nil
    end,
    GetVendorPriceByItemID = function() return nil end,
} } }
G.C_Spell = { GetSpellName = function(id) return RECIPE_NAMES[id] end }
G.C_TradeSkillUI = {
    IsTradeSkillLinked = function() local w = tradeWindow(); return w and w.linked or false end,
    IsTradeSkillReady = function() return tradeWindow() ~= nil end,
    GetBaseProfessionInfo = function() local w = tradeWindow(); return w and { professionName = w.prof } or {} end,
    GetAllRecipeIDs = function() return tradeWindow() and { 7418, 7420, 7421, 13380, 25124 } or {} end,
    -- 7418 needs one of item 10940 and two of 10938; an optional slot is ignored.
    GetRecipeSchematic = function(id)
        if id == 7421 then return { outputItemID = 6218, reagentSlotSchematics = {} } end   -- makes an item
        if id ~= 7418 then return nil end
        return { reagentSlotSchematics = {
            { reagentType = 1, required = true, quantityRequired = 1, reagents = { { itemID = 10940 } } },
            { reagentType = 1, required = true, quantityRequired = 2, reagents = { { itemID = 10938 } } },
            { reagentType = 2, required = false, quantityRequired = 1, reagents = { { itemID = 99 } } },
        } }
    end,
    GetRecipeInfo = function(id)
        local w = tradeWindow()
        if not w then return nil end          -- names only resolve through the spell lookup here
        return { recipeID = id, name = RECIPE_NAMES[id], learned = w.known[id] or false }
    end,
    GetProfessionInfoBySkillLineID = function(id)
    local s = SKILLS[ctx.guid]
    local names = { [393] = "Skinning", [356] = "Fishing" }
    if s and s.api == "ids" then
        for _, e in ipairs(s.list) do
            if names[id] == e[1] then return { skillLevel = e[2], maxSkillLevel = 225, professionName = e[1] } end
        end
    end
    return { skillLevel = 0 }
end }

-- Talents in the older form: name, icon, points spent.
local TALENTS = { WARLOCK = { { "Affliction", 5 }, { "Demonology", 40 }, { "Destruction", 6 } },
    WARRIOR = { { "Arms", 31 }, { "Fury", 20 }, { "Protection", 0 } }, ROGUE = { { "Assassination", 0 }, { "Combat", 0 }, { "Subtlety", 0 } } }
G.GetNumTalentTabs = function() return 3 end
G.GetTalentTabInfo = function(i)
    local t = (TALENTS[ctx.class] or {})[i]
    if t then return t[1], nil, t[2] end
end
local LEADERS = {}   -- LEADERS[guid] = the guid leading that player's group
G.UnitIsGroupLeader = function(unit)
    local lead = LEADERS[ctx.guid]
    return lead ~= nil and lead == unitGuid(unit)
end
G.UnitIsGroupAssistant = function() return false end
G.IsInGuild = function() return true end
G.IsInRaid = function() local g = GROUPS[ctx.guid]; return g ~= nil and g.raid == true end
G.IsInGroup = function() return GROUPS[ctx.guid] ~= nil end
-- PvP rank, served two ways: the GM through the older call (id 11 = rank 7),
-- the Officer through Forever's rank track, and the Member has no rank.
G.UnitFactionGroup = function() return "Horde" end
G.UnitPVPRank = function() return ctx.guid == "Player-1-GM" and 11 or 0 end
G.C_MajorFactions = { GetMajorFactionData = function(id)
    if id == 2800 and ctx.guid == "Player-1-OFFICER" then return { renownLevel = 3 } end
    return nil
end }
-- Items: the game knows 1001 at once and 1002 only after being asked.
local shiftDown, ctrlDown, linked = false, false, {}
local itemsAsked = {}
G.IsShiftKeyDown = function() return shiftDown end
G.IsControlKeyDown = function() return ctrlDown end
G.ITEM_QUALITY_COLORS = { [4] = { r = 0.64, g = 0.21, b = 0.93 } }
G.GetItemInfo = function(id)
    if id == 1001 then return "Test Blade", "|cffa335ee|Hitem:1001|h[Test Blade]|h|r", 4, 60, 55, "Weapon", "Sword", 1, "INVTYPE_WEAPON", 135274 end
    if id == 1002 and itemsAsked[id] then return "Test Cloak", "|Hitem:1002|h[Test Cloak]|h", 2, 30, 25, "Armor", "Cloth", 1, "INVTYPE_CLOAK", 133762 end
    if id == 6218 then return "Runed Copper Rod", "|Hitem:6218|h[Runed Copper Rod]|h", 1, 5, 1, "Trade Goods", "", 1, "", 135138, 124 end
    itemsAsked[id] = true
    return nil
end
G.GetNumGroupMembers = function()
    local g = GROUPS[ctx.guid]
    return g and (#g + (g.raid and 0 or 1)) or 0
end
G.GetGuildInfo = function() return "Blood Pact" end
G.GetNormalizedRealmName = function() return "Normal" end
local CHANNELS = {}
G.GetChannelList = function() return unpack(CHANNELS[ctx.guid] or {}) end
G.GetZoneText = function() return ctx.zone end
G.GetRealZoneText = function() return ctx.zone end
G.GetNumGuildMembers = function() return #GUILD end
G.GetGuildRosterInfo = function(i)
    local m = GUILD[i]
    if not m then return nil end
    local c = clients[m[7]]
    local online = c ~= nil and c.online
    local label = m[4]:sub(1, 1) .. m[4]:sub(2):lower()            -- the class as the game displays it
    return m[1] .. REALM, m[3], m[2], m[5], label, m[6], "", "", online, 0, m[4], 0, 0, false, false, 0, m[7]
end
G.GetGuildRosterLastOnline = function() return 0, 0, 3, 5 end
G.GetInventoryItemLink = function(_, slot)
    return slot == 5 and "|cffa335ee|Hitem:1::::::::60:::::|h[Robe of the Void]|h|r" or nil
end
-- Bags and the mailbox. Each player has their own bags, cursor and half-written mail.
local BAGS, MAILS = {}, {}
local function mailOf() MAILS[ctx.guid] = MAILS[ctx.guid] or { items = {}, tab = 1 }; return MAILS[ctx.guid] end
local function bagSlot(bag, slot) local b = BAGS[ctx.guid]; return b and b[bag] and b[bag][slot] or nil end
G.C_Container = { GetContainerNumSlots = function() return 2 end, GetContainerItemLink = function() return nil end,
    GetContainerItemInfo = function(bag, slot)
        local it = bagSlot(bag, slot)
        return it and { itemID = it.id, stackCount = it.n, isBound = it.bound or false, isLocked = it.locked or false } or nil
    end,
    PickupContainerItem = function(bag, slot)
        local it = bagSlot(bag, slot)
        if it and not it.locked then mailOf().cursor = it end
    end }
G.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
G.ATTACHMENTS_MAX_SEND = 12
G.ClearCursor = function() mailOf().cursor = nil end
G.ClickSendMailItemButton = function(i)
    local m = mailOf()
    assert(m.tab == 2, "items can only be attached on the Send Mail tab")
    if m.cursor and not m.items[i] then
        assert(not m.cursor.bound, "a bound item can't be mailed")
        m.items[i], m.cursor.locked, m.cursor = m.cursor, true, nil
    end
end
G.GetSendMailItem = function(i)
    local it = mailOf().items[i]
    if it then return "Item " .. it.id, it.id, 134400, it.n, 1 end
end
G.GetSendMailPrice = function()
    local n = 0
    for _ in pairs(mailOf().items) do n = n + 1 end
    return 30 * n
end
G.MailFrame = widget("Frame")
G.MailFrameTab_OnClick = function(_, tab) mailOf().tab = tab end
G.SendMailNameEditBox, G.SendMailSubjectEditBox, G.SendMailBodyEditBox = widget("EditBox"), widget("EditBox"), widget("EditBox")
-- The player presses the game's Send button: the game sends what is in the
-- form, the attached items leave the bags, and the form empties.
local function pressSend(c)
    local prev = ctx
    ctx = c
    local m = mailOf()
    local to, subject, body = G.SendMailNameEditBox:GetText(), G.SendMailSubjectEditBox:GetText(), G.SendMailBodyEditBox:GetText()
    local sent = { to = to, subject = subject, body = body, items = 0 }
    for _, h in ipairs(hooks.SendMail or {}) do
        if h.ctx == c then inCtx(c, "SendMail hook", h.fn, to, subject, body) end
    end
    for _, it in pairs(m.items) do
        sent.items = sent.items + it.n
        for _, bag in pairs(BAGS[c.guid] or {}) do
            for slot, have in pairs(bag) do if have == it then bag[slot] = nil end end
        end
    end
    m.items = {}
    G.SendMailNameEditBox:SetText(""); G.SendMailSubjectEditBox:SetText(""); G.SendMailBodyEditBox:SetText("")
    ctx = prev
    fire(c, "MAIL_SEND_SUCCESS")
    return sent
end
G.C_GuildInfo = { GuildRoster = function()
    local c = ctx
    addTimer(0.1, function() fire(c, "GUILD_ROSTER_UPDATE") end)
end }
-- /who: each search answers a moment later with what the "server" has for it.
local WHO_DATA = {
    ['z-"Durotar" 1-4'] = { total = 60,
        { fullName = "Newbie One-Normal", level = 3, classStr = "Warrior", area = "Durotar", fullGuildName = "" },
        { fullName = "Guilded Gus-Normal", level = 4, classStr = "Mage", area = "Durotar", fullGuildName = "Other Guild" },
        { fullName = "Fresh Troll-Normal", level = 2, classStr = "Hunter", area = "Durotar" } },
    ['z-"Durotar" 5-8'] = {
        { fullName = "Newbie One-Normal", level = 5, classStr = "Warrior", area = "Durotar", fullGuildName = "" },
        { fullName = "Razor Hill Rex-Normal", level = 7, classStr = "Shaman", area = "Durotar", fullGuildName = "" } },
    ['58-60'] = { total = 80, { fullName = "Top Dog-Normal", level = 60, classStr = "Warrior", area = "Orgrimmar", fullGuildName = "" },
        { fullName = "Guilded Sixty-Normal", level = 60, classStr = "Mage", area = "Orgrimmar", fullGuildName = "Other Guild" } },
    ['58-59'] = { { fullName = "Nearly There-Normal", level = 59, classStr = "Priest", area = "Winterspring", fullGuildName = "" } },
    ['60-60'] = { total = 70, { fullName = "Top Dog-Normal", level = 60, classStr = "Warrior", area = "Orgrimmar", fullGuildName = "" } },
    ['c-"Mage" 60-60'] = { { fullName = "Lone Mage-Normal", level = 60, classStr = "Mage", area = "Silithus", fullGuildName = "" } },
    ['z-"Mulgore" 1-4'] = { { fullName = "Moo Two-Normal", level = 1, classStr = "Druid", area = "Mulgore", fullGuildName = "" } },
}
local whoAsked, whoNow = {}, {}
G.C_FriendList = { SetWhoToUi = noop,
    SendWho = function(q)
        local c = ctx
        whoAsked[#whoAsked + 1] = c.name .. ":" .. q
        addTimer(0.5, function() whoNow[c.guid] = WHO_DATA[q] or {}; fire(c, "WHO_LIST_UPDATE") end)
    end,
    GetNumWhoResults = function() local r = whoNow[ctx.guid] or {}; return #r, r.total or #r end,
    GetWhoInfo = function(i) return (whoNow[ctx.guid] or {})[i] end }
local toRaid = 0
G.C_PartyInfo = { InviteUnit = function(name) invites[#invites + 1] = name end,
    ConvertToRaid = function() toRaid = toRaid + 1; local g = GROUPS[ctx.guid]; if g then g.raid = true end end }
G.C_DateAndTime = { GetCurrentCalendarTime = function()
    local t = os.date("!*t", BASE + math.floor(clock))
    return { year = t.year, month = t.month, monthDay = t.day, hour = t.hour, minute = t.min }
end }
local calendarAdds = 0
G.C_Calendar = {
    CanAddEvent = function() return true end, CreateGuildSignUpEvent = noop, EventSetTitle = noop,
    EventSetDescription = noop, EventSetType = noop, EventSetDate = noop, EventSetTime = noop,
    AddEvent = function() calendarAdds = calendarAdds + 1 end,
    SetAbsMonth = noop, GetNumDayEvents = function() return 0 end, GetDayEvent = noop, OpenEvent = noop,
}
-- The chat box: what an addon opened it with, and a box the player is already typing in.
local chatOpened, typingIn = {}, {}
G.ChatFrameUtil = { AddMessageEventFilter = noop, SendTell = noop, InsertLink = function(link) linked[#linked + 1] = link end,
    OpenChat = function(text) chatOpened[#chatOpened + 1] = text end,
    GetActiveWindow = function() return typingIn[ctx.guid] end }
G.C_ChatInfo = {
    RegisterAddonMessagePrefix = noop,
    SendChatMessage = function(msg, kind, _, target)
        -- Inside a battleground the game refuses addon chat: no error, just a blocked-action event.
        if CHATLOCK[ctx.guid] then
            chatRefused = chatRefused + 1
            fire(ctx, "ADDON_ACTION_BLOCKED", "BloodPact", "UNKNOWN()")
            return
        end
        guildChat[#guildChat + 1] = kind .. ":" .. tostring(target) .. ":" .. msg
    end,
    SendAddonMessage = function(prefix, msg, dist, target)
        assert(#msg <= 255, "addon message over 255 bytes")
        sentAddon = sentAddon + 1
        local from = ctx
        if dist == "GUILD" then
            for _, c in pairs(clients) do
                if c ~= from and c.online then addTimer(0.05, function() fire(c, "CHAT_MSG_ADDON", prefix, msg, dist, from.name .. REALM) end) end
            end
        elseif dist == "WHISPER" then
            local c = clientByName(target)
            local found = c and c.online and not (whisperNeedsShortName and target ~= c.name)
            if found then
                addTimer(0.05, function() fire(c, "CHAT_MSG_ADDON", prefix, msg, dist, from.name .. REALM) end)
            else
                addTimer(0.05, function() fire(from, "CHAT_MSG_SYSTEM", ("No player named '%s' is currently playing."):format(target)) end)
            end
        end
        return 0
    end,
}

---------------------------------------------------------------------------
-- Loading the addon the way the game does: the files in the .toc, in order
---------------------------------------------------------------------------
local FILES = {}
for line in io.lines("BloodPact.toc") do
    line = line:gsub("\r", "")
    if line ~= "" and line:sub(1, 1) ~= "#" then FILES[#FILES + 1] = (line:gsub("\\", "/")) end
end

local function newClient(i)
    local m = GUILD[i]
    local c = { name = m[1], guid = m[7], class = m[4], level = m[5], zone = m[6], widgets = {}, out = {}, ns = {},
        online = true }
    clients[c.guid] = c
    ctx = c
    rawset(G, "BloodPactDB", nil)
    for _, f in ipairs(FILES) do
        local chunk, err = loadfile(f)
        if not chunk then error(err) end
        local ok, e = pcall(chunk, "BloodPact", c.ns)
        if not ok then error("loading " .. f .. ": " .. tostring(e)) end
    end
    c.slash = G.SlashCmdList.BLOODPACT
    fire(c, "ADDON_LOADED", "BloodPact")
    fire(c, "PLAYER_LOGIN")
    ctx = nil
    return c
end

local function slash(c, text) inCtx(c, "/bp " .. text, c.slash, text) end
local function open(c)
    if not c.ns.UI.IsOpen() then inCtx(c, "/bp", c.slash, "") end
    inCtx(c, "open", function() assert(c.ns.UI.IsOpen(), "the window did not open") end)
end
local function run(c, where, fn, ...) inCtx(c, where, fn, ...) end
local function said(c, needle)
    for _, line in ipairs(c.out) do if line:find(needle, 1, true) then return true end end
    return false
end

local checks, failed = 0, 0
local function check(cond, what)
    checks = checks + 1
    if not cond then failed = failed + 1; report("FAIL " .. what) end
end

-- Press every button and row the client has made (twice, to hit toggles).
local function pressEverything(c)
    for pass = 1, 2 do
        local n = #c.widgets
        for i = 1, n do
            local w = c.widgets[i]
            local click = w._.scripts.OnClick
            if click and w._.enabled and w:IsVisible() then
                clock = clock + 1       -- past the double-click guard
                inCtx(c, "click #" .. i .. " '" .. w._.text .. "' pass " .. pass, click, w, "LeftButton")
                if not c.ns.UI.IsOpen() then inCtx(c, "reopen", c.slash, "") end   -- that was the close button
            end
            for _, s in ipairs({ "OnEnter", "OnLeave", "OnSizeChanged", "OnShow", "OnTextChanged",
                "OnEditFocusGained", "OnEditFocusLost" }) do
                if w._.scripts[s] then inCtx(c, s .. " #" .. i, w._.scripts[s], w, 100, 100) end
            end
            for _, s in ipairs({ "OnMouseWheel", "OnValueChanged" }) do
                if w._.scripts[s] then
                    inCtx(c, s .. " #" .. i, w._.scripts[s], w, -1)
                    inCtx(c, s .. " #" .. i, w._.scripts[s], w, 1)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- The run
---------------------------------------------------------------------------
-- 1. The Guild Master and an Officer log in.
local gm = newClient(1)
local officer = newClient(2)
advance(5)
check(said(gm, "loaded. Type /bp"), "login message")
check(said(gm, "Made by Kitch, of the Blood Pact guild, US East PvP Horde. Type /bp about to find us."), "the first login says who makes the addon")
check(gm.ns.roster.loaded and gm.ns.roster.complete, "roster loads and is complete")
check(gm.ns.RBAC.RoleOf(gm.guid) == "gm" and officer.ns.RBAC.RoleOf(officer.guid) == "officer", "roles from ranks")

-- 2. Open the window, visit every tab, press everything (real guild, not mock).
open(gm)
check(gm.ns.UI.IsOpen(), "the first /bp opens the window")
slash(gm, "whoami")
slash(gm, "status")
advance(1)
pressEverything(gm)
advance(2)

-- 3. An award by the GM reaches the Officer.
local MEMBER = "Player-1-MEMBER"
run(gm, "award", function() assert(gm.ns.DKP.Award({ MEMBER }, 25, "manual", "smoke")) end)
advance(5)
run(officer, "balance", function() check(officer.ns.Reducer.Balance(MEMBER) == gm.ns.Reducer.Balance(MEMBER)
    and gm.ns.Reducer.Balance(MEMBER) >= 25, "an award syncs GM -> Officer") end)

-- 4. A member logs in later, on a server that only finds short names in
--    whispers. They must still catch up on everything.
whisperNeedsShortName = true
local member = newClient(3)
local caughtUpAfter
for second = 1, 300 do
    advance(1)
    if not caughtUpAfter and member.ns.G() and member.ns.Reducer.Balance(MEMBER) == gm.ns.Reducer.Balance(MEMBER) then
        caughtUpAfter = second
    end
end
check(caughtUpAfter ~= nil and caughtUpAfter <= 120, "a late login catches up within two minutes (took "
    .. tostring(caughtUpAfter) .. " s)")
run(member, "catch-up", function()
    check(member.ns.Reducer.Balance(MEMBER) == gm.ns.Reducer.Balance(MEMBER), "a late login catches up over whispers")
    local _, provisional = member.ns.Log.Count(member.ns.G())
    check(provisional == 0, "caught-up history is confirmed, not provisional")
end)
local bounced = false
for _, c in pairs(clients) do
    for _, line in ipairs(c.out) do if line:find("No player named", 1, true) then bounced = true end end
end
check(not bounced, "whisper bounces stay out of chat output")

-- 5. A member forges an award in the Officer's name: it must not count.
run(member, "forge", function()
    local ns = member.ns
    local g = ns.G()
    local forged = ns.Log.Build(g, officer.guid, "AWARD", { to = { MEMBER }, amt = 5000, r = "manual" }, ns.Now())
    ns.Comm.Send("GUILD", nil, ns.U.Encode({ t = "E", e = ns.Log.Wire(forged) }))
end)
advance(10)
run(gm, "forge check", function() check(gm.ns.Reducer.Balance(MEMBER) < 5000, "a forged award is not counted") end)
-- The Officer's next real award uses the number the fake took. It must win.
local before
run(gm, "before", function() before = gm.ns.Reducer.Balance(MEMBER) end)
run(officer, "real award", function() assert(officer.ns.DKP.Award({ MEMBER }, 7, "manual", "real")) end)
advance(10)
run(gm, "real wins", function()
    check(gm.ns.Reducer.Balance(MEMBER) == before + 7, "a fake can't block an Officer's real award")
    check(gm.ns.Reducer.Balance(MEMBER) < 5000, "and the fake still doesn't count")
end)
run(member, "real wins for the forger too", function()
    check(member.ns.Reducer.Balance(MEMBER) == before + 7, "every client agrees after the fake is replaced")
end)

-- Decay takes the Guild Master, and can be undone.
run(gm, "decay", function()
    local was = gm.ns.Reducer.Balance(MEMBER)
    assert(gm.ns.DKP.Decay())
    check(gm.ns.Reducer.Balance(MEMBER) < was, "decay lowers balances")
    assert(gm.ns.DKP.UndoDecay())
    check(gm.ns.Reducer.Balance(MEMBER) == was, "undoing decay restores them")
end)
advance(5)
run(officer, "decay synced", function()
    check(officer.ns.Reducer.Balance(MEMBER) == gm.ns.Reducer.Balance(MEMBER), "decay and its undo sync")
end)

-- 6. Raids: schedule in Central time, sign up, see it everywhere.
run(gm, "raid", function()
    local e = gm.ns.Raids.Create("Opening night", "Barrow Deeps", "12/20", "8pm", 10, nil, "CT", true)
    assert(e, "raid not created")
    gm.ns.Calendar.Add(gm.ns.Reducer.State().raids[e.id])
end)
advance(5)
run(member, "sign up", function()
    local st = member.ns.Reducer.State()
    local id = next(st.raids)
    check(id ~= nil, "a scheduled raid syncs to members")
    if id then assert(member.ns.Raids.SignUp(id, "yes", "dps")) end
end)
advance(5)
run(gm, "spec from talents", function()
    local key, _, how = gm.ns.BiS.CurrentSpec()
    check(key == "Demonology" and how == "talents", "the BiS list follows the talent build")
    local mine = gm.ns.BiS.MyScore()
    check(mine and mine.pre > 0 and mine.pre < 100, "a readiness score is computed from worn gear")
end)
run(gm, "readiness arrives", function()
    local gear = gm.ns.Reducer.State().gear[MEMBER]
    check(gear ~= nil and gear.spec == "Assassination" and gear.pre == 0, "signing up shares the member's readiness score")
end)
run(gm, "sign-up arrives", function()
    local st = gm.ns.Reducer.State()
    local _, r = next(st.raids)
    check(r and r.signups[MEMBER] and r.signups[MEMBER].role == "dps", "a member's sign-up syncs back")
end)
check(calendarAdds >= 1, "the raid goes on the in-game calendar")
-- Signing up asks for a spot; a Team Captain or above selects who gets one.
local raidId
run(member, "not selected yet", function()
    local ns = member.ns
    local st = ns.Reducer.State()
    raidId = next(st.raids)
    local r = st.raids[raidId]
    local c = ns.Raids.Summary(st, r)
    check(c.yes == 1 and c.picked == 0 and c.waiting == 1 and not ns.Raids.IsPicked(r, MEMBER), "a sign-up alone doesn't hold a raid spot")
    local res, why = ns.Raids.Pick(raidId, MEMBER, true)
    check(res == nil and why == "Only Team Captains and above select the raid.", "a Member can't select themselves")
end)
run(gm, "select", function()
    local ns = gm.ns
    check(select(2, ns.Raids.Pick(raidId, officer.guid, true)) == "They haven't signed up for this raid.", "only someone who signed up can be selected")
    assert(ns.Raids.Pick(raidId, MEMBER, true))
    check(ns.Raids.Pick(raidId, MEMBER, true) == nil, "selecting twice does nothing")
end)
advance(5)
check(said(member, "You're selected for Opening night,") and said(member, ", as DPS."), "the player is told when they are selected")
run(officer, "selection synced", function()
    local st = officer.ns.Reducer.State()
    local c, rows = officer.ns.Raids.Summary(st, st.raids[raidId])
    check(c.picked == 1 and c.waiting == 0 and c.sel.dps == 1 and rows[1].guid == MEMBER and rows[1].picked, "the selection syncs to the whole guild")
    assert(officer.ns.Raids.Pick(raidId, MEMBER, false))          -- any Team Captain or above can take it back
end)
advance(5)
check(said(member, "You're no longer selected for Opening night. You're still signed up."), "and told when the spot is taken back")
run(gm, "select again", function() assert(gm.ns.Raids.Pick(raidId, MEMBER, true)) end)
advance(5)
run(member, "selected", function()
    local st = member.ns.Reducer.State()
    check(member.ns.Raids.IsPicked(st.raids[raidId], MEMBER), "the latest word on a player stands")
end)

-- 7. Summon board: the member asks, the warlock is alerted and invites.
local chatAtAsk = #guildChat
run(member, "ask", function() assert(member.ns.Summon.Request("Blackrock Spire")) end)
check(#guildChat == chatAtAsk, "asking any warlock sends no whisper")
run(member, "ask one", function()
    check(member.ns.Summon.Request("Blackrock Spire", gm.guid) == "whispered", "asking one warlock reports that it whispered them")
end)
check(#guildChat == chatAtAsk + 1 and guildChat[#guildChat]:find("WHISPER:Binky Bee:Could I get a warlock summon to Blackrock Spire?", 1, true) == 1,
    "Ask selected whispers the chosen warlock, so they see it without the addon")
run(member, "ask again", function() assert(member.ns.Summon.Request("Blackrock Spire")) end)
advance(3)
check(said(gm, "asks for a summon"), "the warlock is alerted to a summon request")
run(gm, "start", function()
    local req = gm.ns.Summon.requests[MEMBER]
    check(req ~= nil, "the request is on the warlock's board")
    if req then
        local msg = gm.ns.Summon.Start(req)
        check(type(msg) == "string", "starting a summon reports what happened")
    end
end)
advance(3)
local invitedPip, helpers = false, 0
for _, n in ipairs(invites) do
    if n == "Pip" then invitedPip = true else helpers = helpers + 1 end
end
check(invitedPip, "the asker is invited by short name")
check(helpers == 1, "the guildmate in the warlock's zone is invited to click")
check(said(member, "is inviting you for a summon"), "the asker is told to accept the invite")
run(gm, "call", function() gm.ns.Summon.CallHelpers() end)
advance(3)
local chatBefore = #guildChat
run(member, "guild chat", function() assert(member.ns.Summon.PostToGuildChat("Blackrock Spire")) end)
check(#guildChat == chatBefore + 1 and guildChat[#guildChat]:find("GUILD:", 1, true) == 1
    and guildChat[#guildChat]:find("Blackrock Spire", 1, true) ~= nil, "a summon request can be posted to guild chat")
check(said(officer, "click a summoning portal"), "guildmates in the zone are asked to click")
check(not said(member, "click a summoning portal"), "guildmates elsewhere are not")

-- Professions: each player's own addon reads and shares them (after the
-- login delay), and the Guild Master sees all three.
advance(200)
run(gm, "professions", function()
    local profs = gm.ns.Reducer.State().profs
    local mine, off, mem = profs["Player-1-GM"], profs["Player-1-OFFICER"], profs[MEMBER]
    check(mine and mine.p1 == "Enchanting" and mine.l1 == 280 and mine.p2 == "Tailoring" and mine.l2 == 300
        and mine.fa == 300 and mine.ck == 225 and mine.fi == 40, "professions read the modern way are right")
    check(off and off.p1 == "Blacksmithing" and off.l1 == 300 and off.p2 == "Mining" and off.l2 == 290
        and off.fa == 150 and off.ck == 1 and off.fi == nil, "professions read from the skills list sync to the guild")
    check(mem and mem.p1 == "Skinning" and mem.l1 == 201 and mem.p2 == nil and mem.fi == 75,
        "professions read by skill id sync to the guild")
    check(mine.x1 == 300 and mine.xfi == 75 and off.x2 == 300 and off.xfa == 225 and mem.x1 == 225,
        "skill caps come along from all three ways of reading")
    local P = gm.ns.Professions
    local st = gm.ns.Reducer.State()
    local groups, shared = P.Groups(gm.ns.roster.byGUID, st.profs, {})
    local fishing = P.Crafters(gm.ns.roster.byGUID, st.profs, "Fishing", {})
    check(shared == 3 and #groups == 12 and #fishing == 2 and fishing[1].name == "Pip" and fishing[2].name == "Binky Bee"
        and fishing[2].class == "WARLOCK", "the Professions tab groups the guild by profession, best first")
end)
slash(gm, "prof")
slash(member, "prof")
run(gm, "prof command", function()
    check(said(gm, "Your professions: Enchanting 280/300, Tailoring 300/300, Cooking 225/300, First Aid 300/300, Fishing 40/75"),
        "/bp prof shows what the game reported")
    check(said(gm, "Already shared"), "/bp prof says when nothing changed")
end)

-- Recipes: the GM opens Enchanting; the recipes they know reach the guild.
TRADE[gm.guid] = { prof = "Enchanting", known = { [7418] = true, [7420] = true, [7421] = true } }
fire(gm, "TRADE_SKILL_SHOW")
fire(gm, "TRADE_SKILL_LIST_UPDATE")
advance(30)
check(said(gm, "Shared 3 Enchanting recipes with the guild."), "opening a profession records and shares its recipes")
local eventsBefore
run(gm, "count", function() eventsBefore = gm.ns.Log.Count(gm.ns.G()) end)
fire(gm, "TRADE_SKILL_LIST_UPDATE")           -- nothing changed: nothing is sent
advance(10)
run(gm, "no resend", function() check(gm.ns.Log.Count(gm.ns.G()) == eventsBefore, "an unchanged recipe list isn't sent again") end)
TRADE[gm.guid].known[25124] = true            -- learns one more
fire(gm, "NEW_RECIPE_LEARNED")
advance(30)
check(said(gm, "Shared 1 Enchanting recipes with the guild."), "a newly learned recipe is sent on its own")
-- Looking at someone else's linked profession must not be recorded as mine.
TRADE[officer.guid] = { prof = "Enchanting", known = { [13380] = true }, linked = true }
fire(officer, "TRADE_SKILL_SHOW")
advance(30)
TRADE[gm.guid], TRADE[officer.guid] = nil, nil
run(officer, "recipes arrive", function()
    local ns = officer.ns
    local st = ns.Reducer.State()
    check(ns.Recipes.Count(st, gm.guid, "Enchanting") == 4, "recipes sync to another player")
    check(ns.Recipes.Count(st, officer.guid, "Enchanting") == 0, "a linked profession window isn't recorded as mine")
    local rows = ns.Recipes.List(st.recipes[gm.guid].Enchanting, "", ns.Recipes.Name)
    check(#rows == 4 and rows[1].name == "Enchant Bracer - Minor Health" and rows[4].name == "Runed Copper Rod",
        "recipe names come from the viewer's own game")
    local crafters = ns.Professions.Crafters(ns.roster.byGUID, st.profs, "Enchanting", {})
    check(#crafters == 1 and crafters[1].guid == gm.guid, "the crafter is listed under Enchanting")
end)
slash(gm, "recipes")
check(said(gm, "Open one of your profession windows first."), "/bp recipes explains itself with no window open")

-- PvP rank: read by each player's own addon and shown on everyone's roster.
advance(150)
slash(gm, "pvp")
run(member, "pvp ranks", function()
    local st = member.ns.Reducer.State()
    check(st.pvp[gm.guid] and st.pvp[gm.guid].r == 7, "a PvP rank read the older way syncs to the guild")
    check(st.pvp[officer.guid] and st.pvp[officer.guid].r == 3, "a PvP rank read from Forever's rank track syncs too")
    check(st.pvp[MEMBER] == nil, "a player with no rank shares nothing")
    local row
    for _, r in ipairs(member.ns.Roster.Rows(st)) do if r.guid == gm.guid then row = r end end
    check(row and row.pvp and member.ns.PvP.Icon(row.pvp.r) == "Interface\\PvPRankBadges\\PvPRank07"
        and member.ns.PvP.Title(row.pvp.r, "Horde") == "Blood Guard", "the roster row carries the rank badge and its title")
end)
check(said(gm, "Your PvP rank: 7, Blood Guard."), "/bp pvp shows what the game reported")

-- Crafting orders: a Member orders from the GM (who shared Enchanting recipes).
local orderId, wantedId
local whispersBefore = #guildChat
run(member, "place order", function()
    local O = member.ns.Orders
    local e = assert(O.Create(7418, "Enchanting", 2, "me", "for raid", gm.guid))
    orderId = e.id
    check(select(2, O.Create(7418, "Enchanting", 1, "me", "", "Player-9-STRANGER")) ~= nil and O.Create(7418, "Enchanting", 1, "me", "", "Player-9-STRANGER") == nil,
        "an order can't be sent to someone outside the guild")
    check(O.Create(7418, "Enchanting", 1, "me", "", MEMBER) == nil, "you can't order from yourself")
    check(O.Create(7418, "Enchanting", 0, "me", "", gm.guid) == nil, "an order needs a sensible quantity")
end)
local whisper = guildChat[#guildChat] or ""
check(#guildChat == whispersBefore + 1 and whisper:find("WHISPER:Binky Bee:", 1, true) == 1
    and whisper:find("Blood Pact order", 1, true) ~= nil and whisper:find("x2", 1, true) ~= nil,
    "placing an order whispers the online crafter once, and only them")
advance(10)
check(said(gm, "New crafting order from Pip: Enchant Bracer - Minor Health x2."), "the crafter is told about a new order")
run(gm, "accept", function()
    local ns = gm.ns
    check(#ns.Orders.Rows(ns.Reducer.State(), gm.guid, "craft") == 1 and ns.Orders.Needs(ns.Reducer.State(), gm.guid) == 1,
        "the order shows in the crafter's To craft list")
    check(ns.Orders.Update(orderId, "deliver") == nil, "a crafter can't confirm their own delivery")
    assert(ns.Orders.Update(orderId, "accept", 8, "after raid"))
end)
advance(10)
check(said(member, "Binky Bee accepted your order for Enchant Bracer - Minor Health x2, due in 8h."), "the requester sees the promised turnaround")
run(gm, "ready", function() assert(gm.ns.Orders.Update(orderId, "ready")) end)
advance(10)
check(said(member, "Your order is ready: Enchant Bracer - Minor Health x2 from Binky Bee."), "the requester is told when it's ready")
run(member, "deliver", function() assert(member.ns.Orders.Update(orderId, "deliver")) end)
advance(10)
check(said(gm, "Pip confirmed delivery of Enchant Bracer - Minor Health x2."), "the crafter is told when delivery is confirmed")
run(officer, "order history", function()
    local o = officer.ns.Reducer.State().orders[orderId]
    check(o and o.status == "delivered" and o.crafter == gm.guid and o.note == "after raid", "a finished order is history for the whole guild")
end)
run(member, "browse and price", function()
    local ns = member.ns
    local st = ns.Reducer.State()
    local profs = ns.Recipes.GuildProfs(st, ns.roster.byGUID)
    local rows = ns.Recipes.GuildRecipes(st, ns.roster.byGUID, "Enchanting", "", ns.Recipes.Name)
    check(#profs == 1 and profs[1].name == "Enchanting" and profs[1].count == 4 and #rows == 4 and rows[1].crafters[1] == gm.guid
        and rows[1].online == 1, "New order lists every recipe the guild has shared, with who can make it")
    check(ns.Orders.BuyText(7421) == ns.Orders.Money(12345), "Buy It Now is Auctionator's price for the item the recipe makes")
    do
        local cost, partial, buy, net = ns.Orders.Numbers(7418)
        check(cost == 150 and partial == true and buy == nil and net == nil, "no Net Profit when a material has no price or nothing is made")
        check(ns.Orders.NetText(7418) == nil, "and the Net Profit cell stays blank")
    end
    check(ns.Orders.VendorText(7421) == "1s 24c", "Vendor is what a vendor pays for the finished item")
    check(ns.Orders.VendorText(7418) == nil, "no vendor price when the recipe makes no item")
    check(select(5, ns.Orders.Numbers(7421)) == 124, "the vendor price is there to sort by")
    check(ns.Orders.BuyText(7418) == nil, "an enchant makes no item, so it has no Buy It Now price")
    check(ns.Orders.CostText(7418, 2) == "3s+", "material cost is estimated from Auctionator's prices, flagging what has no price")
    check(ns.Orders.CostText(7418, 2, true) == "Est. materials: 3s from Auctionator's last scan, plus 1 with no price.",
        "the order bar says where the estimate comes from")
    check(ns.Orders.CostText(7420, 1) == nil, "no estimate is shown when the game lists no materials")
end)
-- The Wanted board: only someone who shared the recipe can take it; an Officer can tidy it.
run(member, "post wanted", function() wantedId = assert(member.ns.Orders.Create(7420, "Enchanting", 1, "crafter", "", nil)).id end)
check(#guildChat == whispersBefore + 1, "a Wanted post whispers nobody")
advance(10)
check(said(gm, "New Wanted order you can craft: Enchant Chest - Minor Health for Pip."), "a Wanted order is matched to crafters who shared the recipe")
check(not said(officer, "New Wanted order you can craft"), "and not announced to members who can't make it")
run(gm, "matched", function()
    local ns = gm.ns
    local list = ns.Orders.Rows(ns.Reducer.State(), gm.guid, "craft")
    check(#list == 1 and list[1].id == wantedId, "the matched order shows in the crafter's To craft list")
end)
run(officer, "can't take it", function()
    local res, why = officer.ns.Orders.Update(wantedId, "accept", 2)
    check(res == nil and why:find("shared this recipe", 1, true) ~= nil, "a member without the recipe can't take a Wanted order")
end)
run(gm, "take and hand back", function()
    assert(gm.ns.Orders.Update(wantedId, "accept", 2))
    assert(gm.ns.Orders.Update(wantedId, "release"))
end)
advance(10)
run(member, "back on the board", function()
    local st = member.ns.Reducer.State()
    check(st.orders[wantedId].status == "open" and #member.ns.Orders.Rows(st, MEMBER, "wanted") == 1, "a handed-back order returns to the Wanted board")
    check(member.ns.Orders.Update(wantedId, "accept", 2) == nil, "you can't take your own Wanted order")
end)

-- Mailing an order: the Member orders three Runed Copper Rods from the GM.
local rodId
run(member, "order rods", function() rodId = assert(member.ns.Orders.Create(7421, "Enchanting", 3, "crafter", "", gm.guid)).id end)
advance(10)
slash(gm, "mail")
check(said(gm, "Open a mailbox first."), "/bp mail explains itself away from a mailbox")
run(gm, "accept rods", function() assert(gm.ns.Orders.Update(rodId, "accept", 24)) end)
advance(10)
-- In the GM's bags: stacks of 2 and 1, a stack of 5 (too many), and a bound one.
BAGS[gm.guid] = { [0] = { { id = 6218, n = 2 }, { id = 6218, n = 1 } }, [1] = { { id = 6218, n = 5 }, { id = 6218, n = 1, bound = true } } }
local function mailPanel(c)
    for _, w in ipairs(c.widgets) do
        if w._.kind == "FontString" and w._.text == "Blood Pact: orders to mail" then return w._.parent end
    end
end
run(gm, "not at a mailbox", function()
    check(gm.ns.Mail.Prepare(rodId) == nil, "nothing is filled in away from a mailbox")
    check(mailPanel(gm) == nil, "the mail panel doesn't exist until a mailbox is opened")
end)
fire(gm, "MAIL_SHOW")
run(gm, "mail panel", function()
    local ns = gm.ns
    local f = mailPanel(gm)
    check(f ~= nil and f:IsShown(), "opening a mailbox with an accepted order shows the panel")
    local rows = ns.Mail.Rows()
    local rod, bracer
    for _, r in ipairs(rows) do
        if r.id == rodId then rod = r else bracer = r end
    end
    check(rod and rod.to == "Pip" and rod.left == 3 and rod.have == 8 and rod.why == nil,
        "the order lists what is in the bags, leaving bound items out")
    check(bracer == nil, "finished and handed-back orders aren't offered")
    f.go:GetScript("OnClick")(f.go, "LeftButton")
end)
run(gm, "mail filled in", function()
    local m = MAILS[gm.guid]
    local n, count = 0, 0
    for _, it in pairs(m.items) do n = n + 1; count = count + it.n end
    check(m.tab == 2 and G.SendMailNameEditBox:GetText() == "Pip", "the mail is addressed to the guild member who ordered")
    check(G.SendMailSubjectEditBox:GetText() == "Runed Copper Rod x3", "the item is the subject")
    check(G.SendMailBodyEditBox:GetText():find("here is your Runed Copper Rod x3, made by Binky Bee", 1, true) ~= nil, "the message is written")
    check(n == 2 and count == 3, "exactly what is owed is attached, from whole stacks")
    local status
    for _, w in ipairs(gm.widgets) do
        if w._.text:find("Filled in: 3 Runed Copper Rod for Pip.", 1, true) then status = w._.text end
    end
    check(status and status:find("Postage 60c. Check it, then press Send.", 1, true) ~= nil, "the panel shows the postage and leaves Send to the player")
    check(gm.ns.Reducer.State().orders[rodId].status == "accepted", "filling in the mail changes nothing in the guild's log")
    local again, why = gm.ns.Mail.Prepare(rodId)
    check(again == nil and why:find("already has items attached", 1, true) ~= nil, "a half-written mail isn't filled in twice")
end)
-- The player changes the recipient and sends: that mail isn't counted for the order.
G.SendMailNameEditBox:SetText("Grim Tusk")
local keep = MAILS[gm.guid].items
MAILS[gm.guid].items = {}
pressSend(gm)
advance(10)
run(gm, "other mail", function()
    check(gm.ns.Reducer.State().orders[rodId].status == "accepted" and gm.ns.Mail.Rows()[1].left == 3,
        "a mail sent to someone else doesn't count toward the order")
end)
for _, it in pairs(keep) do it.locked = false end
-- Fill it in again and press Send as written.
run(gm, "fill again", function() assert(gm.ns.Mail.Prepare(rodId)) end)
local sent = pressSend(gm)
advance(10)
check(sent.to == "Pip" and sent.items == 3, "the player's own Send click mails the three rods")
check(said(gm, "Mailed 3 Runed Copper Rod to Pip. The order is now In transit; it's complete when they confirm they have it."), "the crafter is told the order is in transit")
check(said(member, "Binky Bee mailed your order: Runed Copper Rod x3. Collect it at a mailbox, then press \"I received it\""), "the requester is told their order is in the mail")
check(not said(member, "Your order is ready: Runed Copper Rod x3"), "and isn't told twice")
run(gm, "in transit for the crafter", function()
    local ns = gm.ns
    local st = ns.Reducer.State()
    local o = st.orders[rodId]
    check(ns.Orders.InTransit(o) and ns.Orders.StatusText(o, ns.Now(), ns.Orders.NameOf):find("In transit, mailed", 1, true) == 1,
        "after the mail is sent the crafter's order reads In transit")
    check(ns.Orders.Needs({ orders = { [rodId] = o }, recipes = st.recipes }, gm.guid) == 0 and ns.Mail.Rows()[1].left == 0,
        "and it no longer counts as work to do")
end)
run(member, "mailed order", function()
    local ns = member.ns
    local o = ns.Reducer.State().orders[rodId]
    check(o.status == "ready" and o.note == "In your mailbox" and o.mailed == 3 and ns.Orders.InTransit(o),
        "the whole guild sees the order as In transit")
    assert(ns.Orders.Update(rodId, "deliver"))
end)
advance(10)
run(gm, "complete", function()
    local o = gm.ns.Reducer.State().orders[rodId]
    check(o.status == "delivered" and not gm.ns.Orders.InTransit(o), "when the requester confirms, the order is complete")
end)
-- An order mailed with version 0.17.0, which kept the count on the crafter's
-- own character: marked ready by hand, then mailed. It becomes In transit.
local oldId
run(member, "order one more", function() oldId = assert(member.ns.Orders.Create(7421, "Enchanting", 1, "crafter", "", gm.guid)).id end)
advance(10)
run(gm, "old mail", function()
    assert(gm.ns.Orders.Update(oldId, "accept", 2))
    assert(gm.ns.Orders.Update(oldId, "ready"))
    gm.ns.Char().mailed = { [oldId] = 1, gone = 4 }
    gm.ns.Mail.Migrate(true)
    check(gm.ns.Char().mailed == nil, "the old per-character count is moved into the guild's log")
end)
advance(10)
run(member, "old mail seen", function()
    local o = member.ns.Reducer.State().orders[oldId]
    check(o.mailed == 1 and member.ns.Orders.InTransit(o), "an order mailed before this version shows as In transit too")
    assert(member.ns.Orders.Update(oldId, "deliver"))
end)
advance(10)
run(gm, "after delivery", function()
    local f = mailPanel(gm)
    check(#gm.ns.Mail.Rows() == 0 and f.empty:IsShown(), "a delivered order leaves the mail panel")
    local line, why = gm.ns.Mail.Prepare(rodId)
    check(line == nil and why ~= nil, "a delivered order can't be mailed again")
end)
pressEverything(gm)
fire(gm, "MAIL_CLOSED")
run(gm, "mailbox closed", function() check(not mailPanel(gm):IsShown(), "closing the mailbox closes the panel") end)

-- The summon queue. The GM is a warlock, in a party with the Officer and the Member.
GROUPS[gm.guid] = { officer.guid, MEMBER }
GROUPS[officer.guid] = { gm.guid, MEMBER }
LEADERS[gm.guid], LEADERS[officer.guid] = gm.guid, gm.guid
local function chat(c, event, text, from, guid)
    fire(c, event, text, from .. REALM, "", "", from, "", 0, 0, "", 0, 1, guid)
end
local function queuePanel(c)
    for _, w in ipairs(c.widgets) do
        if w._.kind == "FontString" and w._.text:find("^Summon queue") and w._.parent._.protected then return w._.parent end
    end
end
-- What the game would do with a click on a secure button, from its attributes.
local function secureClick(c, b, button)
    local a = b._.attrs or {}
    local n = button == "RightButton" and "2" or "1"
    local kind = a["type" .. n]
    local did = kind and (kind .. ":" .. tostring(a["spell" .. n] or "") .. ":" .. tostring(a.unit)) or "nothing"
    if b._.scripts.PostClick then inCtx(c, "PostClick", b._.scripts.PostClick, b, button, false) end
    return did
end
local function queueNames(c)
    local names = {}
    for i, e in ipairs(c.ns.SummonQueue.list) do names[i] = e.name end
    return table.concat(names, ",")
end
slash(officer, "summon")
check(said(officer, "Only a warlock gets a summon queue."), "/bp summon tells a non-warlock how to ask instead")
chat(gm, "CHAT_MSG_PARTY", "123", "Pip", MEMBER)
chat(officer, "CHAT_MSG_PARTY", "123", "Pip", MEMBER)
chat(gm, "CHAT_MSG_PARTY", "123", "Pip", MEMBER)                       -- asking twice
chat(gm, "CHAT_MSG_PARTY", "1234 gold", "Grim Tusk", officer.guid)     -- not the keyword
chat(gm, "CHAT_MSG_PARTY", "123", "Binky Bee", gm.guid)                -- the warlock's own line
chat(gm, "CHAT_MSG_WHISPER", "123", "Stranger", "Player-9-STRANGER")   -- not in the guild or the group
chat(gm, "CHAT_MSG_GUILD", "123 please", "Vela", "Player-1-VET")       -- a guildmate who isn't in the group
run(gm, "queue", function()
    local f = queuePanel(gm)
    check(f ~= nil and f:IsShown(), "a request in chat opens the warlock's summon queue")
    check(queueNames(gm) == "Pip,Vela", "the keyword puts each asker in the queue once, in order; strangers and other chat are ignored")
    check(#officer.ns.SummonQueue.list == 0 and queuePanel(officer) == nil, "players who aren't warlocks keep no queue")
    local pip, vela = f.rows[1], f.rows[2]
    check(pip:IsShown() and pip.name:GetText() == "Pip" and pip:GetAttribute("unit") == "party2", "a row is tied to that player's place in the group")
    check(secureClick(gm, pip, "RightButton") == "target:nil:party2" or secureClick(gm, pip, "RightButton") == "target::party2",
        "right-click targets the player")
    check(secureClick(gm, pip, "LeftButton") == "spell:Ritual of Summoning:party2", "left-click casts Ritual of Summoning on the player")
    check(pip.info:GetText() == "summoning", "the row shows the summon has started")
    check(vela:IsShown() and vela:GetAttribute("unit") == nil and secureClick(gm, vela, "LeftButton") == "nothing" and vela.inv:IsShown(),
        "a guildmate outside the group can't be summoned yet and gets an Invite button")
    local tells = #guildChat
    vela.inv:GetScript("OnClick")(vela.inv, "LeftButton")
    check(invites[#invites] == "Vela" and #guildChat == tells, "the Invite button invites them, from the warlock's click")
    -- The Officer leads instead: the invite is suggested to them.
    LEADERS[gm.guid] = officer.guid
    vela.inv:GetScript("OnClick")(vela.inv, "LeftButton")
    check(#guildChat == tells + 1 and guildChat[#guildChat] == "WHISPER:Grim Tusk:Could you invite Vela to the group? I'm summoning. (sent with Blood Pact)",
        "when the warlock doesn't lead the group, the leader is asked to invite, with one whisper")
    check(said(gm, "You don't lead this group, so Grim Tusk was asked to invite Vela."), "and the warlock is told so")
    LEADERS[gm.guid] = gm.guid
    check(not f.rows[3]:IsShown(), "unused rows stay hidden")
end)
-- In combat the game locks the list: a new request waits, and nothing breaks.
COMBAT[gm.guid] = true
chat(gm, "CHAT_MSG_PARTY", "123", "Grim Tusk", officer.guid)
advance(4)
run(gm, "queue in combat", function()
    local f = queuePanel(gm)
    check(queueNames(gm) == "Pip,Vela,Grim Tusk" and not f.rows[3]:IsShown(), "a request during combat is kept but the locked list isn't touched")
    check(said(gm, "Grim Tusk asked for a summon. The queue updates when you leave combat."), "the warlock is told in chat")
    f.rows[2].x:GetScript("OnClick")(f.rows[2].x, "LeftButton")           -- remove Vela while locked
end)
COMBAT[gm.guid] = nil
fire(gm, "PLAYER_REGEN_ENABLED")
run(gm, "queue after combat", function()
    local f = queuePanel(gm)
    check(queueNames(gm) == "Pip,Grim Tusk" and f.rows[2].name:GetText() == "Grim Tusk" and f.rows[2]:GetAttribute("unit") == "party1"
        and not f.rows[3]:IsShown(), "after combat the list catches up")
end)
-- Pip arrives next to the warlock: off the list. A Summon-tab request joins it.
NEARBY[MEMBER] = true
run(member, "board request", function() assert(member.ns.Summon.Request("Orgrimmar", nil)) end)
advance(8)
run(gm, "arrivals", function()
    check(queueNames(gm) == "Grim Tusk", "a player who has arrived leaves the queue, and isn't re-added while standing there")
end)
NEARBY[MEMBER] = nil
advance(8)
run(gm, "from the board", function()
    local f = queuePanel(gm)
    check(queueNames(gm) == "Grim Tusk,Pip", "a request made from the Summon tab joins the same queue")
    f.rows[2].x:GetScript("OnClick")(f.rows[2].x, "LeftButton")
end)
advance(8)
run(gm, "dismissed", function()
    local f = queuePanel(gm)
    check(queueNames(gm) == "Grim Tusk", "a name the warlock removed doesn't come straight back from the same request")
    f.key:SetText("Sum")
    f.key:GetScript("OnEditFocusLost")(f.key)
    check(gm.ns.SummonQueue.Key() == "sum" and f.key:GetText() == "sum", "the warlock can change the keyword")
    f.key:SetText("two words")
    f.key:GetScript("OnEditFocusLost")(f.key)
    check(gm.ns.SummonQueue.Key() == "sum", "a keyword that isn't one short word is refused")
end)
chat(gm, "CHAT_MSG_PARTY", "123", "Pip", MEMBER)
chat(gm, "CHAT_MSG_PARTY", "sum", "Pip", MEMBER)
run(gm, "new keyword", function() check(queueNames(gm) == "Grim Tusk,Pip", "only the new keyword is listened for") end)
run(gm, "queue cleared", function()
    for _, w in ipairs(gm.widgets) do
        if w._.text == "Clear list" and w:IsVisible() then w:GetScript("OnClick")(w, "LeftButton") end
    end
    local f = queuePanel(gm)
    check(#gm.ns.SummonQueue.list == 0 and not f.rows[1]:IsShown() and f.empty:IsShown(), "Clear list empties the queue")
    gm.ns.Char().summonKey = nil
end)
chat(gm, "CHAT_MSG_PARTY", "123", "Pip", MEMBER)
pressEverything(gm)
-- "Invite for summon" on the Summon tab, in a group the warlock doesn't lead.
LEADERS[gm.guid] = officer.guid
run(gm, "start without leading", function()
    local tells = #guildChat
    local msg = gm.ns.Summon.Start({ from = "Player-1-VET", zone = "Orgrimmar", at = gm.ns.Now() })
    check(msg and msg:find("You don't lead this group, so Grim Tusk was asked to invite Vela.", 1, true) == 1 and #guildChat == tells + 1,
        "Invite for summon asks the leader too, in one whisper")
end)
run(member, "cancel board request", function() member.ns.Summon.Cancel() end)
GROUPS[gm.guid], GROUPS[officer.guid] = nil, nil
LEADERS[gm.guid], LEADERS[officer.guid] = nil, nil
advance(5)

-- Summon messages: the GM (a warlock, Team Captain or above) summons Vela in a raid.
-- The Officer and the Member stand next to the portal.
local VET = "Player-1-VET"
GROUPS[gm.guid] = { raid = true, gm.guid, officer.guid, MEMBER, VET }
GROUPS[officer.guid] = { raid = true, gm.guid, officer.guid, MEMBER, VET }
NEARBY[officer.guid], NEARBY[MEMBER] = true, true
local function ritual(c, phase)
    local event = phase == "start" and "UNIT_SPELLCAST_START" or phase == "up" and "UNIT_SPELLCAST_CHANNEL_START"
        or phase == "done" and "UNIT_SPELLCAST_SUCCEEDED" or phase == "stop" and "UNIT_SPELLCAST_CHANNEL_STOP" or "UNIT_SPELLCAST_INTERRUPTED"
    fire(c, event, "player", "cast-1", 698)
end
local function chatSince(n)
    local out = {}
    for i = n + 1, #guildChat do out[#out + 1] = guildChat[i] end
    return out
end
run(gm, "empty queue", function()
    for i = #gm.ns.SummonQueue.list, 1, -1 do table.remove(gm.ns.SummonQueue.list, i) end
end)
chat(gm, "CHAT_MSG_RAID", "123", "Vela", VET)
local mark = #guildChat
run(gm, "click the queue", function()
    local f = queuePanel(gm)
    check(f.rows[1].name:GetText() == "Vela" and f.rows[1]:GetAttribute("unit") == "raid4", "in a raid the row is tied to the raid unit")
    check(f.msgs:IsShown(), "a Team Captain or above gets the Messages button")
    secureClick(gm, f.rows[1], "LeftButton")
end)
ritual(gm, "start")
advance(1)
local lines = chatSince(mark)
check(#lines == 2 and lines[1]:find("WHISPER:Vela:Abra-cadabra-fel-o-rama", 1, true) == 1 and lines[1]:sub(-10) == "this room!"
    and lines[2]:find("WHISPER:Vela:Shazam-a-ling-ding", 1, true) == 1 and lines[2]:sub(-17) == "angry elite mobs!",
    "the player being summoned is whispered when the ritual starts, in two whispers that each fit the chat box")
advance(3.5)
check(#chatSince(mark) == 2, "nobody is called out while the ritual is still being cast")
ritual(gm, "done"); ritual(gm, "up")
advance(3)
check(#chatSince(mark) == 2, "nor in the first seconds after the portal appears")
advance(2)
lines = chatSince(mark)
check(#lines == 3 and lines[3] == "RAID:nil:Yo! Click the purple oval! I see you Grim Tusk & Pip doing nothing!",
    "then one line in raid chat names the group members standing there and not clicking")
advance(30)
check(#chatSince(mark) == 3, "the callout is sent once per ritual")
ritual(gm, "stop")
-- The next ritual: one of them clicks, so only the other is named. Vela isn't whispered again so soon.
advance(20)
mark = #guildChat
CHANNELING[officer.guid] = "Ritual of Summoning"
ritual(gm, "start"); advance(5); ritual(gm, "done"); ritual(gm, "up"); advance(6)
lines = chatSince(mark)
check(#lines == 1 and lines[1] == "RAID:nil:Yo! Click the purple oval! I see you Pip doing nothing!", "someone who is clicking isn't called out")
ritual(gm, "stop")
-- Both click: nothing to say.
advance(20)
mark = #guildChat
CHANNELING[MEMBER] = "Ritual of Summoning"
ritual(gm, "start"); advance(5); ritual(gm, "done"); ritual(gm, "up"); advance(6)
check(#chatSince(mark) == 0, "a portal with its two clickers gets no callout")
ritual(gm, "stop")
CHANNELING[officer.guid], CHANNELING[MEMBER] = nil, nil
-- Interrupted before the callout is due.
advance(20)
mark = #guildChat
ritual(gm, "start"); advance(5); ritual(gm, "done"); ritual(gm, "up"); advance(2); ritual(gm, "interrupted"); advance(10)
check(#chatSince(mark) == 0, "a ritual that stops early calls nobody out")
-- The Officer is no warlock: their casts send nothing.
advance(20)
mark = #guildChat
ritual(officer, "start"); advance(5); ritual(officer, "up"); advance(10)
check(#chatSince(mark) == 0, "only a warlock's own ritual sends anything")
-- The warlock's own words, and the off switches.
run(gm, "own messages", function()
    check(gm.ns.SummonCall.ShowSettings(), "the messages can be opened")
    gm.ns.Char().summonCallText = "Portal is up, {names}. Click it."
    gm.ns.Char().summonTell = false
    gm.ns.SummonQueue.lastClick = nil
end)
advance(60)
TARGETS[gm.guid] = VET
mark = #guildChat
ritual(gm, "start"); advance(5); ritual(gm, "done"); ritual(gm, "up"); advance(6)
lines = chatSince(mark)
check(#lines == 1 and lines[1] == "RAID:nil:Portal is up, Grim Tusk & Pip. Click it.", "the callout uses the warlock's own text, and the whisper can be switched off")
ritual(gm, "stop")
run(gm, "callout off", function() gm.ns.Char().summonCall = false end)
advance(20)
mark = #guildChat
ritual(gm, "start"); advance(5); ritual(gm, "done"); ritual(gm, "up"); advance(6)
check(#chatSince(mark) == 0, "with both switched off nothing is sent")
ritual(gm, "stop")
run(officer, "messages gate", function()
    check(officer.ns.SummonCall.ShowSettings() == false and said(officer, "Summon messages are for warlocks of Team Captain rank and above."),
        "the messages are for warlocks of Team Captain rank and above")
end)
pressEverything(gm)
run(gm, "reset messages", function()
    local c = gm.ns.Char()
    c.summonCall, c.summonTell, c.summonCallText, c.summonTellText = nil, nil, nil, nil
    for i = #gm.ns.SummonQueue.list, 1, -1 do table.remove(gm.ns.SummonQueue.list, i) end
end)
GROUPS[gm.guid], GROUPS[officer.guid], TARGETS[gm.guid] = nil, nil, nil
NEARBY[officer.guid], NEARBY[MEMBER] = nil, nil
advance(5)

-- Recruiting: search a starting zone a few levels at a time, then whisper with one click.
local function clickText(c, text, button)
    for _, w in ipairs(c.widgets) do
        if w._.text == text and w._.scripts.OnClick and w._.enabled and w:IsVisible() then
            inCtx(c, "click " .. text, w._.scripts.OnClick, w, button or "LeftButton")
            return true
        end
    end
    return false
end
local function clickRow(c, name, button)
    for _, w in ipairs(c.widgets) do
        if rawget(w, "item") and w.item.name == name and w:IsVisible() then
            inCtx(c, "click row " .. name, w._.scripts.OnClick, w, button or "LeftButton")
            return true
        end
    end
    return false
end
open(gm)
check(clickText(gm, "Recruit"), "the Guild Master has the Recruit tab")
advance(10)
local rp = gm.ns.recruitPanel
run(gm, "starting zones", function()
    local zones = {}
    for i, b in ipairs(rp.zoneButtons) do zones[i] = b:GetText() end
    check(table.concat(zones, ",") == "Durotar,Mulgore,Tirisfal Glades,Zephras Isle", "a Horde recruiter gets the Horde starting zones, by region")
end)
check(clickText(gm, "Durotar"), "a starting zone can be searched")
check(whoAsked[#whoAsked] == 'Binky Bee:z-"Durotar" 1-4', "the search covers the zone's first few levels")
local askedBefore = #whoAsked
clickText(gm, "Mulgore")                                   -- too soon after the last search
check(#whoAsked == askedBefore, "a second search inside a few seconds isn't sent")
advance(6)
run(gm, "first band", function()
    check(#rp.list.items == 2 and rp.list.items[1].name == "Newbie One-Normal" and rp.list.items[2].name == "Fresh Troll-Normal",
        "only unguilded players are listed")
    check(rp.found:GetText() == "2 unguilded in Durotar so far (levels 1-4 searched). The game listed only 3 of 60 players. Click it again for levels 5-8.",
        "the result says what was searched, what the game cut off, and what the next click does")
end)
clickText(gm, "Durotar")
check(whoAsked[#whoAsked] == 'Binky Bee:z-"Durotar" 5-8', "clicking the zone again searches the next levels")
advance(6)
run(gm, "second band", function()
    check(#rp.list.items == 3 and rp.list.items[3].name == "Razor Hill Rex-Normal", "new names are added to the list, each once")
end)
-- One click on a name whispers the picked message to that player.
clickText(gm, "Social")                                    -- an earlier pass left another message picked
local tellsBefore = #guildChat
check(clickRow(gm, "Newbie One-Normal"), "a name in the list can be clicked")
local tell = guildChat[#guildChat] or ""
check(#guildChat == tellsBefore + 1 and tell:find("WHISPER:Newbie One:Hey! Blood Pact is recruiting on WoW Forever.", 1, true) == 1,
    "one click whispers that player the Social message")
clickRow(gm, "Newbie One-Normal")
check(#guildChat == tellsBefore + 1, "a second click on the same name doesn't whisper again")
shiftDown = true
clickRow(gm, "Newbie One-Normal")
shiftDown = false
check(#guildChat == tellsBefore + 2, "Shift-click sends it again on purpose")
clickRow(gm, "Fresh Troll-Normal", "RightButton")
check(#guildChat == tellsBefore + 2, "right-click opens a whisper to type and sends nothing")
check(clickText(gm, "Raiding"), "another message can be picked")
clickRow(gm, "Razor Hill Rex-Normal")
tell = guildChat[#guildChat] or ""
check(#guildChat == tellsBefore + 3 and tell:find("WHISPER:Razor Hill Rex:Blood Pact is building raid teams", 1, true) == 1,
    "the whisper carries whichever message is picked")
run(gm, "edited message", function()
    rp.box:SetText("Custom pitch for you")
    rp.box:GetScript("OnTextChanged")(rp.box, true)
    gm.ns.UI.Refresh()
    check(rp.box:GetText() == "Custom pitch for you", "an edited message stays in the box")
end)
clickRow(gm, "Fresh Troll-Normal")
check((guildChat[#guildChat] or "") == "WHISPER:Fresh Troll:Custom pitch for you", "an edited message is what gets sent")
-- The Recruit tab itself: a Member has none, even if their saved "last tab" says Recruit.
run(member, "no recruit tab", function()
    member.ns.db.ui.tab = "recruit"
    open(member)
    local tab
    for _, w in ipairs(member.widgets) do
        if w._.kind == "Button" and w._.text == "Recruit" and w._.h == 30 then tab = w end
    end
    check(tab ~= nil and not tab:IsVisible(), "a Member's window shows no Recruit tab")
    check(member.ns.db.ui.tab ~= "recruit", "and never opens on it, whatever was saved")
    check(member.ns.recruitPanel == nil or not member.ns.recruitPanel:IsVisible(), "the recruiting screen is not shown to a Member")
end)
run(member, "member can't recruit", function()
    local ok, why = member.ns.Recruit.Whisper("Newbie One-Normal", "hi")
    check(ok == nil and why == "Your guild rank can't recruit.", "a Member can't send recruiting whispers")
end)
-- Someone replies "inv": their name is listed exactly as the game spells it,
-- and a click writes the guild invite for the recruiter to send.
local MOLDY = "Moldy L\195\182cks"                          -- an accented letter nobody wants to type
chat(gm, "CHAT_MSG_WHISPER", "inv", MOLDY, "Player-9-MOLDY")
chat(gm, "CHAT_MSG_WHISPER", "Inv", MOLDY, "Player-9-MOLDY")                  -- asking twice
chat(gm, "CHAT_MSG_WHISPER", "what kind of guild is it?", "Chatty Cat", "Player-9-CAT")
chat(gm, "CHAT_MSG_WHISPER", "inv", "Pip", MEMBER)                            -- already in the guild
chat(member, "CHAT_MSG_WHISPER", "inv", MOLDY, "Player-9-MOLDY")              -- a Member doesn't recruit
advance(2)
run(gm, "replies", function()
    local R = gm.ns.Recruit
    check(#R.replies == 1 and R.replies[1].name == MOLDY .. REALM, "a whispered 'inv' from outside the guild is listed once")
    check(said(gm, MOLDY .. " asked for a guild invite. Type /bp, open Recruit and click their name."), "the recruiter is told in chat")
    check(#member.ns.Recruit.replies == 0, "members who can't recruit get no list")
    check(rp.h3:GetText() == "3. They replied (1). Click a name to copy their guild invite", "step 3 shows who is waiting")
end)
-- A click puts the invite in a copy box. Blood Pact writes nothing into the
-- game's chat box: the game refuses a guild invite an addon wrote or touched.
local openedBefore, typed = #chatOpened, {}
typingIn[gm.guid] = { Insert = function(_, text) typed[#typed + 1] = text end }
check(clickRow(gm, MOLDY .. REALM), "the reply can be clicked")
check(rp.copy:GetText() == "/ginvite " .. MOLDY, "a click puts /ginvite and the name, spelled exactly, in the copy box")
check(#chatOpened == openedBefore and #typed == 0, "nothing is written into the game's chat box")
check(said(gm, "Press Ctrl+C to copy the invite for " .. MOLDY .. ". Then in chat: Enter, Ctrl+V, Enter."), "the recruiter is told the keys to press")
typingIn[gm.guid] = nil
run(gm, "copy box", function()
    rp.copy:SetText("/ginvite Someone Else")                   -- the box is for copying, not editing
    rp.copy:GetScript("OnTextChanged")(rp.copy, true)
    check(rp.copy:GetText() == "/ginvite " .. MOLDY, "typing in the copy box doesn't change the invite")
    rp.copy:GetScript("OnKeyDown")(rp.copy, "C")               -- a plain C does nothing
    ctrlDown = true
    rp.copy:GetScript("OnKeyDown")(rp.copy, "C")
    ctrlDown = false
end)
advance(1)
check(said(gm, "Copied. In chat: press Enter, Ctrl+V, then Enter to send the invite."), "after Ctrl+C the box lets go of the keyboard and says what to do next")
run(gm, "copied", function() check(gm.ns.Recruit.replies[1].copied == true, "the name is marked as copied") end)
-- They join the guild: the name leaves the list.
GUILD[#GUILD + 1] = { MOLDY, 5, "Initiate", "MAGE", 10, "Durotar", "Player-9-MOLDY" }
fire(gm, "GUILD_ROSTER_UPDATE")
advance(2)
run(gm, "joined", function()
    gm.ns.UI.Refresh()
    check(#gm.ns.Recruit.replies == 0, "once they are in the guild the name leaves the list")
end)
GUILD[#GUILD] = nil
fire(gm, "GUILD_ROSTER_UPDATE")
advance(2)
clickText(gm, "Mulgore")
advance(6)
run(gm, "new zone", function()
    check(#rp.list.items == 1 and rp.list.items[1].name == "Moo Two-Normal", "a different zone starts a fresh list")
end)
-- Every zone, for a level range: one search per click, split up when the game cuts a list short.
run(gm, "level range", function()
    rp.lvFrom:SetText("60"); rp.lvTo:SetText("58")
    rp.lvFrom:SetText("61")
end)
local asked = #whoAsked
clickText(gm, "Scan these levels")
check(#whoAsked == asked and said(gm, "Levels run from 1 to 60."), "a level outside 1 to 60 isn't searched")
run(gm, "level range 2", function() rp.lvFrom:SetText("60") end)
advance(6)
clickText(gm, "Scan these levels")
check(whoAsked[#whoAsked] == "Binky Bee:58-60", "the range is searched across every zone, whichever box holds the higher level")
advance(6)
run(gm, "split", function()
    check(#rp.list.items == 1 and rp.found:GetText() == "1 unguilded so far. levels 58-60 searched: too many players for one search, so it is split into smaller ones. Click again for levels 58-59.",
        "a list the game cut short is split into smaller searches")
    check(rp.sweepBtn:GetText() == "Next: levels 58-59 (2 left)", "the button says what the next click searches")
end)
local sweepClicks = 0
while sweepClicks < 20 do
    local before = #whoAsked
    run(gm, "next search", function() rp.sweepBtn:GetScript("OnClick")(rp.sweepBtn, "LeftButton") end)
    if #whoAsked == before then break end
    sweepClicks = sweepClicks + 1
    advance(6)
    if gm.ns.Recruit.Sweep() and #gm.ns.Recruit.Sweep().queue == 0 then break end
end
run(gm, "sweep done", function()
    local names = {}
    for i, c in ipairs(rp.list.items) do names[i] = c.name:gsub("%-Normal", "") end
    check(sweepClicks == 11, "a busy single level is searched class by class: 11 more clicks")
    check(table.concat(names, ",") == "Lone Mage,Top Dog,Nearly There", "everyone unguilded in the range is listed once, highest level first")
    check(rp.found:GetText() == "Done. 3 unguilded found in every zone, levels 58-60.", "the result says when the range is finished")
    check(rp.sweepBtn:GetText() == "Scan these levels", "and the button is ready for a new range")
    rp.lvFrom:SetText("10"); rp.lvTo:SetText("60")
end)
advance(6)
clickText(gm, "Mulgore")
advance(6)
run(gm, "zone scan after sweep", function()
    check(#rp.list.items == 1 and rp.list.items[1].name == "Moo Two-Normal", "a zone scan afterwards starts its own list")
end)

-- In a battleground the game refuses chat from addons. The whisper isn't
-- reported as sent; it is typed into a whisper for the recruiter to send.
CHATLOCK[gm.guid] = true
local lockedTells, typedTell = #guildChat, {}
typingIn[gm.guid] = { Insert = function(_, text) typedTell[#typedTell + 1] = text end }
clickText(gm, "Social")
clickRow(gm, "Moo Two-Normal")
check(#guildChat == lockedTells and chatRefused == 1, "a whisper the game refuses is not sent")
check(said(gm, "The game is blocking chat from addons here, as it does inside battlegrounds and instances. The message is typed in a whisper to Moo Two: press Enter to send it."),
    "the recruiter is told why, and the message is typed into a whisper for them")
check(#typedTell == 1 and typedTell[1]:find("Hey! Blood Pact is recruiting", 1, true) == 1, "the typed whisper carries the picked message")
check(not said(gm, "The game blocked an action for addons (UNKNOWN())"), "the vague blocked-action line isn't shown for it")
check(not said(gm, "Whispered Moo Two the Social message."), "and it isn't reported as whispered")
clickRow(gm, "Moo Two-Normal")
check(chatRefused == 1 and #typedTell == 2, "while the game is refusing, the addon doesn't keep trying; it goes straight to the typed whisper")
run(gm, "other chat while locked", function()
    local ok, why = gm.ns.Summon.PostToGuildChat("Orgrimmar")
    check(ok == nil and why:find("blocking chat from addons", 1, true) ~= nil and why:find("Type it in guild chat.", 1, true) ~= nil,
        "other chat buttons explain the refusal too")
end)
-- Out of the battleground: it works again, and the name was never marked.
CHATLOCK[gm.guid], typingIn[gm.guid] = nil, nil
fire(gm, "PLAYER_ENTERING_WORLD")
clickRow(gm, "Moo Two-Normal")
check(#guildChat == lockedTells + 1 and (guildChat[#guildChat] or ""):find("WHISPER:Moo Two:Hey! Blood Pact is recruiting", 1, true) == 1,
    "after leaving, one click whispers again")
clickText(gm, "Social")
pressEverything(gm)
advance(10)

-- Roster by class: a class column, a pie with a legend to filter by, and a message to one class.
open(gm)
check(clickText(gm, "Roster"), "the Roster tab opens")
advance(2)
clickText(gm, "Members")                                   -- an earlier pass may have left the guild log showing
check(clickText(gm, "Classes"), "the Roster has a Classes view")
run(gm, "class pie", function()
    local ns = gm.ns
    local cp
    for _, w in ipairs(gm.widgets) do if rawget(w, "spokes") and rawget(w, "rows") then cp = w end end
    check(cp ~= nil and cp:IsVisible() and #cp.spokes == ns.Roster.PIE_SPOKES, "the pie is drawn on the Roster screen")
    local shown, legend = 0, {}
    for _, b in ipairs(cp.rows) do
        if b:IsShown() then shown = shown + 1; legend[#legend + 1] = b.name:GetText() .. " " .. b.num:GetText() end
    end
    check(shown == 4 and table.concat(legend, " | ") == "Mage 1  25% | Rogue 1  25% | Warlock 1  25% | Warrior 1  25%",
        "the legend lists each class with its count and share")
    local rows = ns.Roster.Rows(ns.Reducer.State())
    check(#rows == 4 and rows[1].classLabel ~= nil, "every roster row carries its class")
    -- Click Rogue in the legend: only rogues are listed.
    for _, b in ipairs(cp.rows) do
        if b.class == "ROGUE" then b:GetScript("OnClick")(b, "LeftButton") end
    end
    rows = ns.Roster.Rows(ns.Reducer.State())
    check(ns.Roster.ClassFilter() == "ROGUE" and #rows == 1 and rows[1].name == "Pip", "clicking a class lists only its members")
    check(cp.send:IsEnabled() and cp.send:GetText() == "Whisper 1 online Rogue", "the message button says who it will reach")
end)
local classTells = #guildChat
run(gm, "message the class", function()
    local R = gm.ns.Roster
    check(R.MessageClass("") == nil, "an empty message isn't sent")
    check(R.MessageClass("Rogues: I need a lockbox opened, please.") == 1, "one click whispers the online members of that class")
    R.SetClassFilter("MAGE")
    check(select(2, R.MessageClass("Mages: I need water.")) == "Nobody of that class is online.", "nobody online in the class means nothing is sent")
    R.SetClassFilter(nil)
    check(select(2, R.MessageClass("hello")) == "Pick a class first.", "a message needs a class picked, so it can't go to the whole guild")
end)
check(#guildChat == classTells + 1 and guildChat[#guildChat] == "WHISPER:Pip:Rogues: I need a lockbox opened, please.", "the whisper goes to that class only")
run(member, "class message gate", function()
    member.ns.Roster.SetClassFilter("WARLOCK")
    check(select(2, member.ns.Roster.MessageClass("hi")) == "Only Team Captains and above can message a class.", "a Member can't message a class")
    member.ns.Roster.SetClassFilter(nil)
end)
pressEverything(gm)
run(gm, "clear class filter", function() gm.ns.Roster.SetClassFilter(nil) end)
advance(5)

-- The look: glass windows, tabs in the order a guild does things, and sections that fold.
local function fold(c, title)
    for _, w in ipairs(c.widgets) do
        if rawget(w, "body") and rawget(w, "title") and w.title:GetText() == title then return w end
    end
end
run(gm, "tab order", function()
    local ns = gm.ns
    local o = ns.UI.TAB_ORDER
    check(o.recruit < o.roster and o.roster < o.profs and o.profs < o.bis and o.bis < o.raids and o.raids < o.summon
        and o.summon < o.raid and o.raid < o.standings and o.standings < o.settings,
        "tabs run in the order a guild does things: recruit, roster, prepare, sign up, summon, raid and loot, standings, settings")
    local x = {}
    for _, w in ipairs(gm.widgets) do
        if w._.kind == "Button" and (w._.text == "Recruit" or w._.text == "Standings") and w._.h == 30 then x[w._.text] = w end
    end
    check(x.Recruit ~= nil and x.Standings ~= nil, "both ends of the tab strip exist")
end)
clickText(gm, "Raids")
run(gm, "remembered tab", function() check(gm.ns.db.ui.tab == "raids", "the window remembers the tab last used") end)
run(gm, "glass", function()
    local W = gm.ns.W
    local btn
    for _, w in ipairs(gm.widgets) do
        if w._.kind == "Button" and W.GLASS_LABEL[W.glass] == w._.text and w:IsVisible() then btn = w end
    end
    check(btn ~= nil, "the title bar has the glass button")
    local before = W.glass
    local seen = { [before] = true }
    for _ = 1, 2 do
        btn:GetScript("OnClick")(btn, "LeftButton")
        seen[W.glass] = true
        check(gm.ns.db.ui.glass == W.glass and btn:GetText() == W.GLASS_LABEL[W.glass] and W.C.bg[4] == W.GLASS_ALPHA[W.glass],
            "a click changes how see-through the windows are, and it is saved")
    end
    check(seen.frosted and seen.clear and seen.solid, "the button goes through Frosted, Clear and Solid")
    btn:GetScript("OnClick")(btn, "LeftButton")
    check(W.glass == before, "and comes back round")
    check(W.GLASS_ALPHA.clear < W.GLASS_ALPHA.frosted and W.GLASS_ALPHA.frosted < W.GLASS_ALPHA.solid and W.DENSE_ALPHA > W.GLASS_ALPHA.frosted,
        "each setting is more solid than the last, and dialogs over another window stay dense")
end)
run(gm, "folding sections", function()
    local leader = fold(gm, "Schedule a raid and leader tools")
    check(leader ~= nil and leader:IsVisible() and leader.open == false and not leader.body:IsShown(),
        "the leader tools on the Raids tab start folded away")
    leader:GetScript("OnClick")(leader, "LeftButton")
    check(leader.open == true and leader.body:IsShown() and gm.ns.Char().folds.raidsLeader == true and leader:Height() > 22,
        "a click opens the section, and that is remembered")
    leader:GetScript("OnClick")(leader, "LeftButton")
    check(leader.open == false and gm.ns.Char().folds.raidsLeader == false and leader:Height() == 22, "another click folds it again")
    check(fold(gm, "Link or unlink an alt") ~= nil and fold(gm, "Read or edit the message") ~= nil,
        "the Roster's alt tools and the recruiting message fold too")
end)
clickText(gm, "Summon")
run(gm, "summon layout for a warlock", function()
    local askFold = fold(gm, "Need a summon yourself? Ask another warlock")
    local askAny
    for _, w in ipairs(gm.widgets) do if w._.text == "Ask any warlock" then askAny = w end end
    check(askFold ~= nil and askFold:IsVisible() and askFold.open == false and not askAny:IsVisible(),
        "a warlock's Summon tab leads with the requests; asking another warlock is folded away")
    askFold:GetScript("OnClick")(askFold, "LeftButton")
    check(askAny:IsVisible() and askAny._.parent._.parent == askFold.body, "opening it shows the ask buttons inside the section")
    askFold:GetScript("OnClick")(askFold, "LeftButton")
end)
clickText(gm, "Raid & Loot")
clickText(gm, "Award and charge")
run(gm, "raid night order", function()
    local custom = fold(gm, "Custom award or deduction")
    local seen = {}
    for _, w in ipairs(gm.widgets) do
        if w._.kind == "FontString" and w:IsVisible() then seen[w._.text] = true end
    end
    check(seen["1. Start of the raid"] and seen["3. End of the raid"] and seen["2. Loot: charge the winner (fixed price, highest DKP wins ties)"],
        "Raid & Loot is laid out in the order of a raid night")
    check(custom ~= nil and custom:IsVisible() and custom.open == false, "custom awards are folded away until needed")
end)
clickText(gm, "Settings")
run(gm, "settings groups", function()
    local titles = { "1. Earning DKP", "2. Loot prices", "3. Decay", "4. Inactivity and Initiate promotion" }
    local folds, open = {}, 0
    for i, t in ipairs(titles) do
        folds[i] = fold(gm, t)
        if folds[i] and folds[i].open then open = open + 1 end
    end
    check(#folds == 4 and open <= 1, "Settings are grouped in the order the rules apply, with at most one group open")
    if folds[3].open then folds[3]:GetScript("OnClick")(folds[3], "LeftButton") end
    folds[3]:GetScript("OnClick")(folds[3], "LeftButton")
    check(folds[3].open and not folds[1].open and not folds[2].open and not folds[4].open, "opening one group closes the others, so the tab always fits")
    local decay
    for _, w in ipairs(gm.widgets) do if w._.kind == "Button" and w._.text:find("^Run %d+%% decay now") then decay = w end end
    check(decay ~= nil and decay:IsVisible(), "the decay buttons live in the Decay group")
    folds[1]:GetScript("OnClick")(folds[1], "LeftButton")
    check(folds[1].open and not folds[3].open, "the group just opened takes over")
    local n = 0
    for _, w in ipairs(gm.widgets) do
        if w._.kind == "EditBox" and w._.parent == folds[1].body then n = n + 1 end
    end
    check(n == 4 and not decay:IsVisible(), "each group holds its own values")
end)
-- The window may be dragged smaller when a tab's sections are folded, and grows to show one that is opened.
clickText(gm, "Raids")
run(gm, "window fits the tab", function()
    local UI = gm.ns.UI
    local frame
    for _, w in ipairs(gm.widgets) do if rawget(w, "feedback") and rawget(w, "about") then frame = w end end
    local leader = fold(gm, "Schedule a raid and leader tools")
    if leader.open then leader:GetScript("OnClick")(leader, "LeftButton") end
    local w, h = UI.FitWindow()
    check(w == math.max(UI.MIN_W, UI.tabStripW) and h == 160 + 58 + 30 + UI.CHROME_H and h < 500,
        "with the leader tools folded, the Raids tab lets the window go well under its old 500, and never narrower than its tabs")
    frame:SetSize(w, h)                                            -- the player drags it down to the smallest
    leader:GetScript("OnClick")(leader, "LeftButton")              -- then opens the section
    local _, h2 = UI.FitWindow()
    check(h2 == h + leader.bodyHeight + 6 and frame:GetHeight() == h2, "opening a section grows the window just enough to show it")
    leader:GetScript("OnClick")(leader, "LeftButton")
    check(select(2, UI.FitWindow()) == h and frame:GetHeight() == h2, "folding it again lets the window shrink, without moving it by itself")
    check(select(2, UI.MinSize(10)) == UI.MIN_H and select(2, UI.MinSize(nil)) == UI.DEFAULT_NEED + UI.CHROME_H and UI.MinSize(100, 5000) == 1600,
        "the smallest size never goes under the window's own frame or over its largest size")
end)
clickText(gm, "Roster")
run(gm, "roster is the widest tab", function()
    local w = gm.ns.UI.FitWindow()
    check(w == math.max(910, gm.ns.UI.tabStripW), "the Roster keeps the width its columns need")
    local rows = gm.ns.Roster.Rows(gm.ns.Reducer.State())
    local z = {}
    for _, r in ipairs(rows) do z[#z + 1] = r.zone end
    check(#rows > 0 and rows[1].zone ~= nil and table.concat(z, ""):find("Orgrimmar", 1, true) ~= nil, "each roster row carries the member's zone")
    local sorted = gm.ns.Roster.Sort(rows, "zone", false)
    check(sorted[1].zone <= sorted[#sorted].zone or sorted[#sorted].zone == "", "the Zone column sorts")
end)
clickText(gm, "Professions")
run(gm, "tabs without a say keep the old height", function()
    check(select(2, gm.ns.UI.FitWindow()) == 500, "a tab that hasn't been reworked keeps the old smallest height")
end)
run(member, "member sees no leader tools", function()
    open(member)
end)
clickText(member, "Summon")
run(member, "summon layout for everyone else", function()
    local askFold = fold(member, "Need a summon yourself? Ask another warlock")
    local askAny
    for _, w in ipairs(member.widgets) do if w._.text == "Ask any warlock" then askAny = w end end
    check(askFold ~= nil and not askFold:IsVisible() and askAny:IsVisible(), "a player who isn't a warlock gets the ask buttons at the top, with nothing folded")
end)
clickText(member, "Raids")
run(member, "member raids tab", function()
    local leader = fold(member, "Schedule a raid and leader tools")
    check(leader ~= nil and not leader:IsVisible(), "a Member doesn't see the leader tools at all")
end)

-- Tickets: a Member reports a problem; Team Captains and above work it. Tickets
-- travel by whisper to staff only and never touch the guild's shared log.
advance(60)
local ticketId, staffTicketId
run(member, "report", function()
    local T = member.ns.Tickets
    check(select(2, T.Submit(nil, "Vela", "Kept swearing at people in raid chat all night.")) == "Pick what kind of problem it is.", "a ticket needs a kind")
    check(select(2, T.Submit("lang", "Pip", "Kept swearing at people in raid chat all night.")) == "A ticket can't be about yourself.", "a ticket can't be about yourself")
    check(select(2, T.Submit("lang", "Vela", "bad")) == "Say what happened, in a sentence or two.", "a ticket needs a sentence about what happened")
    ticketId = T.Submit("lang", "Vela", "Kept swearing at people in raid chat all night.")
    check(type(ticketId) == "string", "a Member can send a ticket")
    check(select(2, T.Submit("loot", "Vela", "Rolled need on the tank trinket as a mage.")) == "You just sent one. Give it half a minute.", "tickets can't be sent in a burst")
end)
advance(8)
run(gm, "ticket arrives", function()
    local t = gm.ns.Tickets.Store()[ticketId]
    check(t ~= nil and t.by == MEMBER and t.status == "new" and t.about == "Vela" and t.cat == "lang", "a Team Captain or above receives the ticket")
    check(said(gm, "New ticket from Pip: Language or harassment, about Vela. Type /bp and open Tickets."), "and is told a ticket came in")
end)
run(officer, "every staff member has it", function()
    check(officer.ns.Tickets.Store()[ticketId] ~= nil, "the other staff online get it too")
end)
run(member, "sent and private", function()
    local ns = member.ns
    check(ns.Tickets.Mine()[ticketId].sent == true, "the reporter sees it was delivered")
    check(next(ns.Tickets.Store()) == nil, "a Member's game holds no staff copy of any ticket")
    check(not ns.U.Encode(ns.G().log):find("swearing", 1, true), "the ticket is not in the guild's shared log")
    check(select(2, ns.Tickets.Take(ticketId)) == "Only Team Captains and above manage tickets.", "a Member can't manage tickets")
end)
-- Work it: take, note, resolve. The reporter hears the status, never the notes.
run(gm, "take it", function() assert(gm.ns.Tickets.Take(ticketId)) end)
advance(8)
check(said(member, "Your ticket about Vela is now: In progress."), "the reporter is told when someone takes the ticket")
run(officer, "note it", function()
    local t = officer.ns.Tickets.Store()[ticketId]
    check(t.status == "work" and t.owner == gm.guid, "the other staff see who took it")
    assert(officer.ns.Tickets.AddNote(ticketId, "Raid leader confirms, has screenshots."))
end)
advance(8)
run(gm, "resolve it", function()
    local t = gm.ns.Tickets.Store()[ticketId]
    check(#t.notes == 1 and t.notes[1].by == officer.guid, "staff notes reach the other staff")
    check(gm.ns.Tickets.Resolve(ticketId, "nonsense") == nil, "resolving needs an outcome from the list")
    assert(gm.ns.Tickets.Resolve(ticketId, "warn"))
end)
advance(8)
check(said(member, "Your ticket about Vela is now: Resolved (Warning given)."), "the reporter is told the outcome")
check(not said(member, "screenshots"), "the reporter never sees the staff notes")
run(officer, "resolved everywhere", function()
    local t = officer.ns.Tickets.Store()[ticketId]
    check(t.status == "done" and t.outcome == "warn" and #t.notes == 1, "the resolution reaches the other staff with the notes intact")
end)
-- Forgeries: a Member can't change a ticket, and nothing on the guild channel counts.
run(member, "forge", function()
    local ns = member.ns
    local fake = { id = ticketId, by = MEMBER, at = 1, cat = "lang", about = "Vela", text = "x", status = "new", v = 99, ut = 9e9, ub = MEMBER, notes = {} }
    ns.Comm.Send("WHISPER", "Binky Bee", ns.U.Encode({ t = "TU", k = fake }))
    ns.Sync.SendLive({ t = "TN", id = MEMBER .. "/123", at = 1, cat = "cheat", about = "Vela", text = "Sent on the guild channel by mistake." })
end)
advance(8)
run(gm, "forgery ignored", function()
    local st = gm.ns.Tickets.Store()
    check(st[ticketId].status == "done" and st[ticketId].v < 99, "a ticket update from someone who isn't staff is ignored")
    check(st[MEMBER .. "/123"] == nil, "a ticket sent on the guild channel is ignored")
end)
-- A ticket about a staff member never reaches that person, not even when staff sync.
advance(40)
run(member, "report staff", function()
    staffTicketId = assert(member.ns.Tickets.Submit("rules", "grim tusk", "Benched me from the raid for no reason and laughed."))
end)
advance(8)
run(officer, "not shown to its subject", function() officer.ns.Tickets.Sync(true) end)
advance(8)
run(gm, "subject excluded", function()
    check(gm.ns.Tickets.Store()[staffTicketId] ~= nil, "a ticket about an Officer reaches the other staff")
    check(officer.ns.Tickets.Store()[staffTicketId] == nil, "and is never sent to the Officer it is about, even when staff sync")
end)
-- A staff member who missed changes catches up from a colleague.
run(officer, "missed it", function()
    officer.ns.Tickets.Store()[ticketId] = nil
    officer.ns.Tickets.Sync(true)
end)
advance(8)
run(officer, "caught up", function()
    local t = officer.ns.Tickets.Store()[ticketId]
    check(t ~= nil and t.status == "done" and #t.notes == 1, "staff who missed a ticket get it from a colleague")
end)
-- A reporter who missed the news asks where their tickets stand.
run(gm, "work the second", function() assert(gm.ns.Tickets.Take(staffTicketId)) end)
advance(8)
run(member, "missed the news", function()
    member.ns.Tickets.Mine()[staffTicketId].st = "new"
    check(member.ns.Tickets.AskStatus(true), "the reporter can ask where their tickets stand")
end)
advance(8)
run(member, "status caught up", function()
    check(member.ns.Tickets.Mine()[staffTicketId].st == "work", "and gets the current status back")
end)
-- A Team Captain or above reporting: it goes straight into the queue.
run(gm, "staff report", function()
    local id = assert(gm.ns.Tickets.Submit("other", "", "The guild bank tab two is full of junk again."))
    check(gm.ns.Tickets.Store()[id] ~= nil and gm.ns.Tickets.Mine()[id].sent, "a staff member's own ticket goes straight into the queue")
end)
advance(8)
-- The tab: staff land on the queue, everyone else on the report form.
open(gm)
check(clickText(gm, "Tickets"), "the Tickets tab opens")
clickText(gm, "Queue (2)")                                 -- an earlier pass may have left another view showing
run(gm, "queue view", function()
    local seen = {}
    for _, w in ipairs(gm.widgets) do if w._.kind == "Button" and w:IsVisible() then seen[w._.text] = true end end
    check(seen["Queue (2)"] and seen["Open (2)"] and seen["Resolved (1)"] and seen["Report a problem"],
        "staff see the queue with what is open and what is resolved")
end)
open(member)
clickText(member, "Tickets")
clickText(member, "Report a problem")
run(member, "report view", function()
    local seen = {}
    for _, w in ipairs(member.widgets) do if w._.kind == "Button" and w:IsVisible() then seen[w._.text] = true end end
    check(seen["Report a problem"] and seen["My tickets (2)"] and not seen["Queue (2)"] and not seen["Queue"] and seen["Send ticket"],
        "a Member sees the report form and their own tickets, and no queue")
end)
pressEverything(gm)
pressEverything(member)
advance(10)

-- Crafters are told how to share their recipes.
open(member)
clickText(member, "Professions")
clickText(member, "Crafters")
run(member, "recipe how-to", function()
    local btn
    for _, w in ipairs(member.widgets) do if w._.text == "How do I share my recipes?" then btn = w end end
    check(btn ~= nil and btn:IsVisible(), "the Professions tab has a How do I share my recipes? button")
    local P = member.ns.Professions
    check(P.HOWTO[1]:find("Character > Professions", 1, true) and P.HOWTO[2]:find("link bubble", 1, true),
        "its tooltip gives the steps: Character > Professions, then the link bubble")
    btn:GetScript("OnClick")(btn, "LeftButton")
end)
check(said(member, "To share your recipes: open Character > Professions, click the link bubble"), "a click repeats the steps")

-- Members are told how to share their PvP rank.
clickText(member, "Roster")
clickText(member, "Members")
run(member, "pvp how-to", function()
    local btn
    for _, w in ipairs(member.widgets) do if w._.text == "How do I share my PvP rank?" then btn = w end end
    check(btn ~= nil and btn:IsVisible(), "the Roster has a How do I share my PvP rank? button")
    local V = member.ns.PvP
    check(V.HOWTO[1]:find("character sheet", 1, true) and V.HOWTO[2]:find("Player vs. Player", 1, true),
        "its tooltip gives the steps: character sheet, then Player vs. Player")
    btn:GetScript("OnClick")(btn, "LeftButton")
end)
check(said(member, "To share your PvP rank: open Character > Player vs. Player."), "a click repeats the steps")

-- Wiping test data: the Guild Master wipes DKP and crafting orders for everyone.
run(gm, "before wipe", function()
    local st = gm.ns.Reducer.State()
    local orders, pools = 0, 0
    for _ in pairs(st.orders) do orders = orders + 1 end
    for _ in pairs(st.pools) do pools = pools + 1 end
    check(orders > 0 and pools > 0 and next(gm.ns.Tickets.Store()) ~= nil, "there is test DKP, there are test orders and test tickets to wipe")
end)
run(officer, "officer can't wipe", function()
    check(select(2, officer.ns.DKP.Reset("dkp")) == "Only the Guild Master can wipe data.", "an Officer can't wipe data")
end)
open(gm)
clickText(gm, "Settings")
run(gm, "wipe buttons", function()
    local f
    for _, w in ipairs(gm.widgets) do
        if rawget(w, "body") and rawget(w, "title") and w.title:GetText() == "5. Wipe data and start fresh" then f = w end
    end
    check(f ~= nil, "Settings has a Wipe data group")
    if not f.open then f:GetScript("OnClick")(f, "LeftButton") end
    local all
    for _, w in ipairs(gm.widgets) do
        if w._.kind == "Button" and rawget(w, "what") == "all" then all = w end
    end
    check(all ~= nil, "there is a button to wipe everything at once")
    all:GetScript("OnClick")(all, "LeftButton")
    check(all:GetText() == "Click again to wipe", "the first click only asks to confirm")
    gm.wipeAll = all
end)
advance(1.5)                                               -- a real second click, not a double click
run(gm, "confirm wipe", function() gm.wipeAll:GetScript("OnClick")(gm.wipeAll, "LeftButton") end)
advance(10)
for _, c in ipairs({ gm, officer, member }) do
    run(c, "after wipe", function()
        local st = c.ns.Reducer.State()
        check(next(st.orders) == nil and next(st.pools) == nil and #st.history == 0,
            "after the wipe, every guild member's game shows no DKP, loot history or orders")
        check(st.resets.dkp and st.resets.orders and st.resets.tickets, "and knows when it was wiped")
        check(next(c.ns.Tickets.Store()) == nil and next(c.ns.Tickets.Mine()) == nil, "every ticket is gone too, staff copies and reporters' own")
    end)
end
check(said(gm, "Wiped DKP, loot history, attendance, crafting orders, the Wanted board and tickets for the whole guild."), "the Guild Master is told it worked")

-- If the guild's saved records are lost, a player's own professions are shared again.
run(member, "lost records", function()
    local ns = member.ns
    local me = ns.MyGUID()
    ns.Professions.Publish(true)
    check(ns.Reducer.State().profs[me] ~= nil, "the Member's professions are shared")
    local g = ns.G()
    for id, e in pairs(g.log) do if e.a == me and e.k == "PROF" then e.k2, e.ok = true, nil end end   -- as if never confirmed
    ns.Reducer.Invalidate()
    check(ns.Reducer.State().profs[me] == nil and ns.Char().profs ~= nil, "the records are gone but the 'already shared' note remains")
    check(ns.Professions.Publish(true) == true and ns.Reducer.State().profs[me] ~= nil, "the professions are shared again, not skipped as already shared")
end)
advance(5)

slash(member, "status")
check(said(member, "| role member | guild key ") and said(member, "Saved guild data: "), "/bp status prints the troubleshooting lines")

-- Inviting from the Roster: to a party, to a raid when the party is full, or through the leader.
run(gm, "roster invite", function()
    local R = gm.ns.Roster
    local n = #invites
    check(R.Invite(MEMBER) == "Invited Pip." and #invites == n + 1, "a click on the Roster invites the picked member")
    check(select(2, R.Invite(gm.guid)) == "That's you.", "you can't invite yourself")
    check(select(2, R.Invite("Player-1-VET")) == "They're offline.", "an offline member can't be invited")
    GROUPS[gm.guid] = { officer.guid, MEMBER, "Player-1-X1", "Player-1-X2" }      -- a full party the GM leads
    LEADERS[gm.guid] = gm.guid
    local line = R.Invite(MEMBER)
    check(line == "Your party is now a raid. Invited Pip." and toRaid == 1 and #invites == n + 2, "a full party becomes a raid first")
    GROUPS[gm.guid] = { officer.guid }
    LEADERS[gm.guid] = officer.guid
    local tells = #guildChat
    check(R.Invite(MEMBER) == "You don't lead this group, so Grim Tusk was asked to invite Pip." and #invites == n + 2
        and guildChat[#guildChat] == "WHISPER:Grim Tusk:Could you invite Pip to the group? (sent with Blood Pact)" and #guildChat == tells + 1,
        "in a group you don't lead, the leader is asked with one whisper")
    GROUPS[gm.guid], LEADERS[gm.guid] = nil, nil
end)

-- Raid Caller: a captain builds a boss plan, every raider's own addon speaks it.
run(member, "member can't build", function()
    check(select(2, member.ns.Caller.Add("Onyxia", { when = "time", v = "10", what = "spread", who = "all" }))
        == "Only Team Captains and above can change call-outs.", "a Member can't change call-outs")
end)
run(officer, "build a plan", function()
    local C = officer.ns.Caller
    check(select(2, C.Add("Onyxia", { when = "hp", v = "150", what = "p2", who = "all" })) == "Boss health must be 1 to 99 percent.", "health must be a percent")
    check(select(2, C.Add("", { when = "call", what = "burn", who = "all" })) ~= nil, "a call-out needs a boss")
    assert(C.Add("Onyxia", { when = "time", v = "5", what = "spread", who = "all" }))
    assert(C.Add("Onyxia", { when = "time", v = "12", what = "swap", who = "tanks" }))
    assert(C.Add("Onyxia", { when = "hp", v = "65", what = "p2", who = "all" }))
    assert(C.Add("Onyxia", { when = "hp", v = "40", what = "move", who = "all", mark = "green" }))
    assert(C.Add("Onyxia", { when = "stack", v = "5", text = "Bob taunts", who = "tanks" }))
end)
advance(8)
run(member, "the plan runs on my own addon", function()
    local C = member.ns.Caller
    local st = member.ns.Reducer.State()
    local rows = C.Rows(st.calls.Onyxia)
    check(#rows == 5 and C.When(rows[1]) == "0:05" and C.When(rows[3]) == "At 65%" and C.Speech(rows[4]) == "Move to green"
        and C.Speech(rows[5]) == "Tanks. Bob taunts", "the plan reaches the member in fight order")
    member.ns.Kit.SetRole("caster")
    SPOKEN[member.guid] = {}
    GROUPS[member.guid] = { gm.guid }
    fire(member, "ENCOUNTER_START", 1084, "onyxia", 9, 40)
    check(C.run.boss == "Onyxia" and C.run.fighting, "the fight's name arms and starts the matching plan")
end)
advance(6)
run(member, "timed call-outs", function()
    local C = member.ns.Caller
    check(#SPOKEN[member.guid] == 1 and SPOKEN[member.guid][1] == "Spread out", "a timed call-out is spoken at its second")
    advance(8)
    check(#SPOKEN[member.guid] == 1, "a tanks-only call-out isn't spoken to a caster")
    local cue = C.Next()
    check(cue and cue.v == 65 and SPOKEN[member.guid][2] == "Phase two", "a click says the next checklist call-out: health marks can't fire by themselves")
    C.Next()
    check(SPOKEN[member.guid][3] == "Move to green" and C.run.at == 3, "and moves down the checklist")
    member.ns.Char().callerVoice = false
    C.Next()
    check(#SPOKEN[member.guid] == 3, "the voice box off means silence")
    member.ns.Char().callerVoice = true
    fire(member, "ENCOUNTER_END", 1084, "onyxia", 9, 40, 1)
    check(not C.run.fighting and C.run.at == 1, "the end of the fight resets the plan")
    C.Arm(nil)
    GROUPS[member.guid] = nil
end)
run(officer, "remove a call-out", function()
    local C = officer.ns.Caller
    local rows = C.Rows(officer.ns.Reducer.State().calls.Onyxia)
    assert(C.Remove("Onyxia", rows[1].id))
end)
advance(8)
run(gm, "removed for everyone", function()
    check(#gm.ns.Caller.Rows(gm.ns.Reducer.State().calls.Onyxia) == 4, "a removed call-out is gone for the guild")
end)
check(clickText(gm, "Call-outs"), "the Call-outs tab opens")

-- Buying a recipe's materials: one material per pair of clicks, never more.
run(gm, "materials window", function()
    local S = gm.ns.Shop
    MONEY[gm.guid] = 10000
    STOCK[gm.guid] = { [10940] = 1 }
    S.Open(7418)
    check(S.SetCrafts("21") == nil and S.SetCrafts("0") == nil and S.SetCrafts("2.5") == nil and S.SetCrafts("5") == 5, "crafts: whole numbers 1 to 20")
    local rows = S.Rows()
    check(#rows == 2 and rows[1].need == 5 and rows[1].have == 1 and rows[1].buy == 4 and rows[2].need == 10 and rows[2].buy == 10,
        "need = per craft x crafts; to buy = need minus bags and bank")
    check(select(2, S.Quote(rows[1])) == "Open the auction house first.", "nothing happens away from the auction house")
    fire(gm, "AUCTION_HOUSE_SHOW")
    check(select(2, S.Confirm(rows[1])) == "Press Get price first.", "paying needs a price check first")
    assert(S.Quote(rows[1]))
    check(select(2, S.Quote(rows[2])) == "Still waiting for the auction house. One material at a time.", "one material at a time")
end)
advance(1)
run(gm, "pay the quoted price", function()
    local S = gm.ns.Shop
    local rows, st = S.Rows(), S.State()
    check(st.quote and st.quote.item == 10940 and st.quote.qty == 4 and st.quote.total == 600 and #AH_BOUGHT == 0, "the first click only asks the price")
    local kind, text = S.ButtonFor(rows[1], st.quote, st.busy, true, true, 10000)
    check(kind == "pay" and text == "Buy 6s", "the button then shows the real total")
    check(S.ButtonFor(rows[1], st.quote, st.busy, true, true, 100) == "poor", "and won't pay with too little gold")
    assert(S.Confirm(rows[1]))
end)
advance(1)
run(gm, "bought once", function()
    local S = gm.ns.Shop
    local rows = S.Rows()
    check(#AH_BOUGHT == 1 and AH_BOUGHT[1].item == 10940 and AH_BOUGHT[1].qty == 4 and MONEY[gm.guid] == 9400, "the second click buys that one material, once")
    check(rows[1].buy == 0 and rows[1].have == 5, "what is in the mail counts as held, so it isn't bought twice")
    STOCK[gm.guid][10940] = 5                                   -- collected from the mailbox
    check(S.Rows()[1].have == 5, "and it isn't counted double once collected")
    check(S.ButtonFor(rows[2], nil, nil, true, false, 9400) == "none", "an item the auction house doesn't sell in bulk gets no button")
    S.SetCrafts("6")
    check(S.Rows()[1].buy == 1 and S.State().quote == nil, "changing the number re-plans and drops any price check")
    fire(gm, "AUCTION_HOUSE_CLOSED")
    S.frame:Hide()
end)

-- The Party button: a raid warning from the leader, spoken for raiders with the addon.
local partyGroups = { GROUPS[gm.guid], GROUPS[officer.guid], GROUPS[member.guid], LEADERS[gm.guid], LEADERS[officer.guid], LEADERS[member.guid] }
GROUPS[gm.guid] = { raid = true, gm.guid, officer.guid }
GROUPS[officer.guid] = { raid = true, gm.guid, officer.guid }
GROUPS[member.guid] = nil
LEADERS[gm.guid], LEADERS[officer.guid], LEADERS[member.guid] = gm.guid, gm.guid, nil
SPOKEN[gm.guid], SPOKEN[officer.guid], SPOKEN[member.guid] = {}, {}, {}
local partyChatBefore = #guildChat
run(officer, "party needs a leader", function()
    check(select(2, officer.ns.Party.Play("Take a drink!")) == "Only the raid leader and assists can press Party, the same as /rw. In a party, the party leader.", "a raider who isn't leader or assist can't press Party")
end)
run(member, "party needs a group", function()
    check(select(2, member.ns.Party.Next()) == "Join a raid or party first.", "nor can someone outside a group")
    check(select(2, member.ns.Party.SetLine("Hello", true)) == "Only Team Captains and above can change the sound board.", "members can't change the sound board")
end)
run(gm, "party pressed", function()
    local P = gm.ns.Party
    assert(P.Next())
    check(guildChat[#guildChat] == "RAID_WARNING:nil:Take a drink!" and #guildChat == partyChatBefore + 1, "the leader's press sends one raid warning")
    check(SPOKEN[gm.guid][1] == "Take a drink!", "and speaks the line")
    check(select(2, P.Next()):find("^Give it %d+ more seconds"), "a cooldown stops it being spammed")
    assert(P.SetLine("  For the   Horde! ", true))
end)
advance(11)
run(officer, "party heard", function()
    check(#SPOKEN[officer.guid] == 1 and SPOKEN[officer.guid][1] == "Take a drink!", "a raider in the leader's group hears the line")
    check(#SPOKEN[member.guid] == 0, "a guildmate outside the raid hears nothing")
    local lines = officer.ns.Party.Lines(officer.ns.Reducer.State())
    check(lines[#lines] == "For the Horde!" and #lines == #officer.ns.Party.DEFAULT + 1, "a Team Captain's new line reaches the guild's sound board")
    officer.ns.Party.SetMuted(true)
end)
run(gm, "party rotates", function()
    local P = gm.ns.Party
    assert(P.Next())
    check(guildChat[#guildChat] == "RAID_WARNING:nil:Take a shot!", "Next plays the lines in order")
end)
advance(11)
run(gm, "party word and lockdown", function()
    local P = gm.ns.Party
    check(#SPOKEN[officer.guid] == 1, "a muted raider hears nothing more")
    assert(P.Word("murloc"))
    check(guildChat[#guildChat] == "RAID_WARNING:nil:The word of the night is: murloc", "the word of the night is announced")
end)
advance(11)
-- From here the leader's client listens: the word typed in raid chat sets off the next line.
run(gm, "the word is said", function()
    local before = #guildChat
    fire(gm, "CHAT_MSG_RAID_WARNING", "The word of the night is: murloc", gm.name .. REALM, "", "", gm.name, "", 0, 0, "", 0, 1, gm.guid)
    fire(gm, "CHAT_MSG_RAID", "murlocs everywhere", officer.name .. REALM, "", "", officer.name, "", 0, 0, "", 0, 1, officer.guid)
    check(#guildChat == before, "the announcement and near-misses set nothing off")
    fire(gm, "CHAT_MSG_RAID", "ugh, a MURLOC!", officer.name .. REALM, "", "", officer.name, "", 0, 0, "", 0, 1, officer.guid)
    check(#guildChat == before + 1 and guildChat[#guildChat] == "RAID_WARNING:nil:" .. officer.name .. " said murloc. Take a puff!",
        "typing the word in raid chat sends the next line, with who said it")
    fire(gm, "CHAT_MSG_RAID", "murloc murloc", officer.name .. REALM, "", "", officer.name, "", 0, 0, "", 0, 1, officer.guid)
    check(#guildChat == before + 1, "the cooldown stops a pile-up")
end)
run(officer, "only the announcer listens", function()
    local before = #guildChat
    fire(officer, "CHAT_MSG_RAID", "murloc", gm.name .. REALM, "", "", gm.name, "", 0, 0, "", 0, 1, gm.guid)
    check(#guildChat == before and officer.ns.Party.Listening() == nil, "a raider who didn't announce the word sends nothing")
end)
advance(11)
run(gm, "stop listening", function()
    local before = #guildChat
    assert(gm.ns.Party.Word("  "))
    fire(gm, "CHAT_MSG_RAID", "murloc", officer.name .. REALM, "", "", officer.name, "", 0, 0, "", 0, 1, officer.guid)
    check(#guildChat == before and gm.ns.Party.Listening() == nil, "an empty word stops the listening")
end)
advance(11)
local boxed
G.ChatFrame_OpenChat = function(text) boxed = text end
CHATLOCK[gm.guid] = true
run(gm, "party in an instance", function()
    local before = #guildChat
    assert(gm.ns.Party.Play("Bottoms up!"))
    check(#guildChat == before and boxed == "/rw Bottoms up!", "where the game blocks addon chat, the line is put in the chat box for the player to send")
end)
CHATLOCK[gm.guid] = nil
G.ChatFrame_OpenChat = nil
advance(130)
-- A five-player party: party chat, since the game only shows raid warnings to raids.
GROUPS[gm.guid], GROUPS[officer.guid] = { officer.guid }, { gm.guid }
run(officer, "unmute", function() officer.ns.Party.SetMuted(false) end)
run(gm, "party of five", function()
    assert(gm.ns.Party.Play("Take a puff!"))
    check(guildChat[#guildChat] == "PARTY:nil:Take a puff!", "in a party the leader's line goes to party chat")
end)
advance(11)
run(officer, "party of five heard", function()
    check(SPOKEN[officer.guid][#SPOKEN[officer.guid]] == "Take a puff!", "and a party member with the addon hears it")
end)
-- Drink of the Night: set on a raid by a Team Captain or above, shown on its sign-up screen.
local drinkRaid
run(gm, "drink of the night", function()
    local D, R = gm.ns.Drinks, gm.ns.Raids
    local st = gm.ns.Reducer.State()
    for _, r in ipairs(R.List(st, gm.ns.Now())) do
        if r.at >= gm.ns.Now() - 6 * 3600 then drinkRaid = drinkRaid or r.id end
    end
    assert(drinkRaid, "a raid is coming up")
    check(select(2, gm.ns.Party.Drink()):find("no drink of the night yet", 1, true), "nothing to announce before a drink is set")
    local mule = D.Find("Tennessee Mule")
    assert(D.Set(drinkRaid, mule.name, mule.recipe))
    check(D.For(gm.ns.Reducer.State(), drinkRaid).name == "Tennessee Mule", "a leader sets the raid's drink")
    D.Open(drinkRaid)
    check(D.frame:IsShown(), "the recipe window opens on the raid's drink")
    D.frame:Hide()
    assert(gm.ns.Party.Drink())
    check(guildChat[#guildChat] == "PARTY:nil:Drink of the night: Tennessee Mule!", "the Party window announces tonight's drink")
end)
advance(11)
run(member, "drink seen by a raider", function()
    local D = member.ns.Drinks
    local d = D.For(member.ns.Reducer.State(), drinkRaid)
    check(d and d.name == "Tennessee Mule" and d.recipe:find("ginger beer", 1, true) and d.from == "A Nashville favorite", "raiders see the drink and its recipe on the sign-up")
    check(select(2, D.Set(drinkRaid, "Water", "Tap.")) == "Only Team Captains and above can set the drink of the night.", "members can't change it")
end)
run(gm, "own drink, then none", function()
    local D = gm.ns.Drinks
    assert(D.Set(drinkRaid, " Guild   Grog ", "Rum, lime and regret."))
    local d = D.For(gm.ns.Reducer.State(), drinkRaid)
    check(d.name == "Guild Grog" and d.from == "The guild's own", "a guild can set a drink of its own")
    assert(D.Clear(drinkRaid))
    check(D.For(gm.ns.Reducer.State(), drinkRaid) == nil, "and clear it")
end)
check(clickText(gm, "Raids") and clickText(gm, "Pick a drink") and gm.ns.Drinks.frame:IsShown(), "the Raids tab's header opens the drink menu")
run(gm, "close drink", function() gm.ns.Drinks.frame:Hide() end)
check(clickText(gm, "Party") and gm.ns.Party.frame:IsShown(), "the Party button sits in the title bar")
run(gm, "close party", function() gm.ns.Party.frame:Hide() end)
GROUPS[gm.guid], GROUPS[officer.guid], GROUPS[member.guid], LEADERS[gm.guid], LEADERS[officer.guid], LEADERS[member.guid] =
    partyGroups[1], partyGroups[2], partyGroups[3], partyGroups[4], partyGroups[5], partyGroups[6]

-- Upgrades for sale: the spec's list is looked up at the auction house; one click buys one item.
run(gm, "upgrade scan", function()
    local M = gm.ns.Market
    MONEY[gm.guid] = 3000000
    M.Open()
    check(select(2, M.Scan()) == "Open the auction house first.", "no scan away from the auction house")
    fire(gm, "AUCTION_HOUSE_SHOW")
    check(M.SetRange("50", "5") == nil and M.SetRange("", "50") == 0, "the gold range is checked as it is typed")
    assert(M.Scan())
    check(M.State().scanning and select(2, M.Scan()) == "Already scanning.", "one scan at a time")
end)
advance(120)
run(gm, "upgrades found", function()
    local M = gm.ns.Market
    local st, rows = M.State(), M.Rows()
    check(not st.scanning and st.done and st.done.spec == "Demonology" and st.done.checked > 10, "the scan covers the spec's whole list and finishes")
    local asked = {}
    for _, text in ipairs(AH_SEARCHES) do asked[text] = (asked[text] or 0) + 1 end
    check(asked["Master's Mantle of Magic"] == 1 and (asked["Master's Mantle"] or 0) >= 1, "an enchanted item not found by its full name is looked up by its plain name")
    check(not asked["Robe of the Void"], "what you already wear is not looked up")
    check(#rows == 1 and rows[1].name == "Master's Mantle of Magic" and rows[1].id == 501 and rows[1].buyout == 250000,
        "the cheapest buyout in range wins: not another enchantment, a bid-only auction, or your own")
    M.SetRange("", "")
    rows = M.Rows()
    check(#rows == 2, "widening the range shows more without a new scan")
    M.SetRange("", "50")
    check(#AH_BIDS == 0, "scanning buys nothing")
    assert(M.Buy(M.Rows()[1]))
    check(select(2, M.Buy(M.Rows()[1])) == "Still buying the last one. One item at a time.", "one purchase at a time")
end)
advance(1)
run(gm, "upgrade bought once", function()
    local M = gm.ns.Market
    check(#AH_BIDS == 1 and AH_BIDS[1].id == 501 and AH_BIDS[1].amount == 250000 and MONEY[gm.guid] == 2750000, "one click buys that one item at the price shown")
    local row = M.Rows()[1]
    check(row.bought and select(2, M.Buy(row)) == "You already bought that one.", "a bought item can't be bought twice")
    MONEY[gm.guid] = 100
    M.SetRange("", "")
    local other
    for _, r in ipairs(M.Rows()) do if r.id == 510 then other = r end end
    check(other and select(2, M.Buy(other)) == "You don't have 120g." and #AH_BIDS == 1, "no purchase without the gold")
    fire(gm, "AUCTION_HOUSE_CLOSED")
    M.frame:Hide()
end)
-- The "Usable gear" box: gear on no list, judged by the Pawn addon and nothing else.
run(gm, "usable needs Pawn", function()
    local M = gm.ns.Market
    MONEY[gm.guid] = 3000000
    fire(gm, "AUCTION_HOUSE_SHOW")
    M.SetRange("", "50")
    M.SetUsable(true)
    M.SetIdeal(false)
    check(not M.PawnInstalled() and select(2, M.Scan()) == "Usable gear needs the Pawn addon. Install Pawn, then type /reload.", "without Pawn the usable scan says so and guesses nothing")
    M.SetIdeal(true)
    assert(M.Scan())
end)
advance(120)
run(gm, "list only without Pawn", function()
    local M = gm.ns.Market
    local st = M.State()
    check(not st.scanning and st.done.usable == 0 and st.note == "BiS list scanned. Usable gear was skipped: it needs the Pawn addon." and #M.Rows() == 1,
        "with both boxes ticked and no Pawn, the list is still scanned")
    installPawn()
    assert(M.Scan())
end)
advance(180)
run(gm, "usable found", function()
    local M = gm.ns.Market
    local st, rows, by = M.State(), M.Rows(), {}
    for _, r in ipairs(rows) do by[r.name] = r end
    check(not st.scanning and st.done.usable == 7 and AH_MORE == 1 and not PAWN_ASKED["Never Read"], "cheapest first: reading stops once prices pass the most you'll pay")
    check(by["Shadoweave Shoulders"] and by["Shadoweave Shoulders"].up.text == "+21% Pawn" and by["Shadoweave Shoulders"].slot == "Shoulder", "what Pawn calls an upgrade is listed with Pawn's percentage")
    check(by["Wanderer's Cloak of Magic"] and by["Wanderer's Cloak of Magic"].id == 606 and by["Wanderer's Cloak of Magic"].up.text == "Pawn: big upgrade",
        "the cheapest buyout is offered; an upgrade too big for a number says so")
    check(not by["Raincaller Scepter of the Elder"] and not by["Plain Robe"], "what Pawn doesn't call an upgrade is left out, whatever its item level or slot")
    check(by["Slow Ring"] and PAWN_ASKED["Slow Ring"] == 2, "an item the game hadn't loaded is asked about again")
    check(not by["Gold Ring"] and not PAWN_ASKED["Gold Ring"], "gear over the most you'll pay isn't even checked")
    check(#rows == 4 and rows[1].name == "Master's Mantle of Magic" and rows[1].up.kind == "list" and rows[2].name == "Wanderer's Cloak of Magic",
        "list items lead, then Pawn's biggest; gear already on the list isn't repeated")
    M.SortBy("cost")
    check(M.Rows()[1].buyout == 15000 and select(2, M.SortState()) == false, "a heading sorts by its column, cheapest first")
    M.SortBy("cost")
    check(M.Rows()[1].buyout == 250000, "a second click reverses it")
    assert(M.Show(by["Wanderer's Cloak of Magic"]))
    check(AH_SHOWN[#AH_SHOWN] == "Wanderer's Cloak of Magic" and AH_SHOWN.started == 1, "clicking a row searches for that item in the auction window")
    assert(M.Show(M.Rows()[1]))
    check(AH_SHOWN[#AH_SHOWN] == "Master's Mantle", "a list item is shown by the search text that found it")
    check(#AH_BIDS == 1, "showing an item buys nothing")
    -- The two boxes: BiS list, Usable gear, or both.
    M.SetIdeal(false)
    M.SetUsable(false)
    check(select(2, M.Scan()) == "Tick BiS list, Usable gear, or both.", "a scan needs at least one box ticked")
    M.SetUsable(true)
    AH_SEARCHES = {}
    assert(M.Scan())
end)
advance(60)
run(gm, "usable only", function()
    local M = gm.ns.Market
    local st, rows = M.State(), M.Rows()
    check(not st.scanning and st.done.checked == 0 and st.done.usable == 7 and #AH_SEARCHES == 0, "with only Usable gear ticked the list items are not looked up")
    check(#rows == 3 and rows[1].up.kind == "pawn" and M.LookedText(0, 3) == "3 kinds of usable gear", "and only usable gear is shown")
    M.SetIdeal(true)
    M.SetUsable(false)
    check(M.Ideal() and not M.Usable(), "the boxes are remembered")
    for _, n in ipairs({ "PawnIsReady", "PawnCanItemHaveStats", "PawnGetItemData", "PawnIsItemAnUpgrade", "PawnBigUpgradeThreshold" }) do G[n] = nil end
    fire(gm, "AUCTION_HOUSE_CLOSED")
end)
check(clickText(gm, "BiS Check") and clickText(gm, "Find upgrades for sale"), "the BiS Check tab opens the upgrade window")
run(gm, "close upgrade window", function() gm.ns.Market.frame:Hide() end)

-- Raid Kit: the guild's rules, a raider's own count, the ready check and the charge.
run(member, "member kit", function()
    local K = member.ns.Kit
    K.SetRole("caster")
    STOCK[member.guid] = { ["Flask of Supreme Power"] = 2, ["Lobster Stew"] = 12, ["Elixir of the Owl"] = 5, ["Major Mana Potion"] = 4 }
    local rows, have, need = K.Mine()
    check(#rows == 9 and have == 2 and need == 6, "a caster's kit: 6 timed items for a 3-hour raid, 2 fully stocked from bags and bank")
    check(rows[3].need == 6 and rows[3].have == 5 and rows[3].short == 1, "30-minute elixirs: 6 for 3 hours, 1 short")
    check(rows[8].need == nil, "potions have no number until a Team Captain sets one")
    check(select(2, K.SaveRules(4, 30)) == "Only Team Captains and above can change the kit rules.", "a Member can't change the rules")
    check(select(2, K.SetItem("caster", "Major Mana Potion", true, nil, 5)) == "Only Team Captains and above can change the kit list.",
        "a Member can't change the list")
end)
run(officer, "kit rules", function()
    local K = officer.ns.Kit
    check(select(2, K.SetItem("caster", "Major Mana Potion", true, 30, 5)) == "Give minutes or a count, not both.", "minutes or a count")
    assert(K.SetItem("caster", "Major Mana Potion", true, nil, 5))
    assert(K.SetItem("caster", "Lobster Stew", false))
    assert(K.SaveRules(4, 30))
end)
advance(8)
run(member, "kit follows the rules", function()
    local K = member.ns.Kit
    local rows, have, need, raid = K.Mine()
    local potions = (raid and raid.prog) and 10 or 5         -- doubled when the member's next raid is a progression night
    check(#rows == 8 and need == 6 and have == 1, "the list and the 4-hour raid reach the member: stew gone, potions now counted")
    check(rows[2].need == 4 and rows[7].item == "Major Mana Potion" and rows[7].need == potions and rows[7].short == potions - 4, "Bring follows the new hours and count")
    K.Publish(true)
    GROUPS[member.guid] = { gm.guid }
    AURAS[member.guid] = { "Arcane Intellect", "Flask of Supreme Power", "Greater Arcane Elixir" }
    COMBAT[member.guid] = true
    fire(member, "READY_CHECK")
end)
advance(8)
run(gm, "leader sees nothing from a player in combat", function()
    local st = gm.ns.Reducer.State()
    local day = gm.ns.Time.RaidDay(gm.ns.Now())
    check(st.kit[MEMBER] and st.kit[MEMBER].have == 1 and st.kit[MEMBER].need == 6 and gm.ns.Kit.ScoreText(st.kit[MEMBER]):find("kit 1/6", 1, true),
        "the member's kit count reaches the leaders")
    check(not (st.kitChecks[day] and st.kitChecks[day][MEMBER]), "in combat the game hides buffs, so nothing is reported")
end)
run(member, "ready check", function()
    COMBAT[member.guid] = nil
    fire(member, "READY_CHECK")
    fire(member, "READY_CHECK")
end)
advance(8)
run(officer, "the ready check and the charge", function()
    local K, st = officer.ns.Kit, officer.ns.Reducer.State()
    local day = officer.ns.Time.RaidDay(officer.ns.Now())
    local c = st.kitChecks[day] and st.kitChecks[day][MEMBER]
    check(c and c.f == true and c.fd == false and c.w == false and c.e == 1, "a ready check reports the player's own flask, food, weapon buff and elixirs")
    local rows = K.CheckRows(st, day, { officer.guid, MEMBER }, officer.ns.NameForGUID)
    check(rows[1].guid == MEMBER and rows[1].missing == "food" and rows[2].check == nil, "missing food sorts first; no report is shown as such")
    local before = officer.ns.Reducer.Balance(MEMBER)
    assert(K.Charge(MEMBER))
    K.Charge(MEMBER)
    officer.kitBefore = before
end)
advance(8)
run(gm, "one charge a night", function()
    check(gm.ns.Reducer.Balance(MEMBER) == officer.kitBefore - 30, "the 30 DKP kit charge lands once per player per night")
    GROUPS[member.guid], AURAS[member.guid] = nil, nil
end)
run(member, "member can't charge", function()
    check(select(2, member.ns.Kit.Charge(gm.guid)) == "Only Officers and above can award DKP.", "only Officers and above can charge DKP")
end)
check(clickText(gm, "Raid Kit"), "the Raid Kit tab opens")

-- Statics: a team is edited by its captain or an Officer, and everyone sees it.
run(member, "member can't build a team", function()
    check(select(2, member.ns.Statics.Add(MEMBER, "Vela", "dps")) == "Only the team's captain, or an Officer and above, can change a team.",
        "a Member can't make or change a team")
end)
run(gm, "build a team", function()
    local S = gm.ns.Statics
    check(select(2, S.Add(gm.guid, "nobody here", "dps")) == "Nobody in the guild has that name.", "only guild members can be added")
    assert(S.Add(gm.guid, "pip", "healer"))                      -- names aren't case sensitive
    check(select(2, S.Add(gm.guid, "Pip", "dps")) == "They are already on this team.", "a member is added once")
    assert(S.Rename("Night Shift"))
end)
advance(8)
run(officer, "officer edits it", function()
    local S = officer.ns.Statics
    check(select(2, S.Add(officer.guid, "Pip", "dps")):find("They are on Binky Bee's team.", 1, true) == 1, "a member is on one team at a time")
    assert(S.SetRole(gm.guid, MEMBER, "tank"))
end)
advance(8)
open(member)
clickText(member, "Roster")
check(clickText(member, "Statics"), "the Roster has a Statics view next to Members")
run(member, "team synced", function()
    local ns = member.ns
    local teams = ns.Statics.Teams(ns.Reducer.State().statics, ns.roster.byGUID)
    check(#teams == 1 and teams[1].name == "Night Shift" and teams[1].n == 2 and teams[1].tank == 1
        and teams[1].rows[1].isCap and teams[1].rows[2].name == "Pip" and teams[1].rows[2].role == "tank",
        "every guild member sees the team, its name, and each member's role")
    local seen = {}
    for _, w in ipairs(member.widgets) do if w._.kind == "FontString" and w:IsVisible() then seen[w._.text] = true end end
    check(seen["Night Shift"] == true,
        "the view shows the picked team")
    local add
    for _, w in ipairs(member.widgets) do if w._.text == "Add to team" then add = w end end
    check(add ~= nil and not add:IsVisible(), "a Member gets no editing controls")
end)
run(gm, "remove", function() assert(gm.ns.Statics.Remove(gm.guid, MEMBER)) end)
advance(8)
run(member, "removed", function()
    check(member.ns.Statics.TeamOf(member.ns.Reducer.State().statics, MEMBER) == nil, "a removed member is off the team for everyone")
end)
pressEverything(gm)
clickText(member, "Members")

-- Advertising in Trade chat from your own recipe list.
run(gm, "advert", function()
    local ns = gm.ns
    local A = ns.Advert
    local skill = { level = 225, max = 300 }
    ns.Char().adExtra = nil                                    -- the standard words
    assert(A.ToggleLink("Enchanting", 7418)); assert(A.ToggleLink("Enchanting", 7421))
    check(A.IsLinked("Enchanting", 7418) and #A.Links("Enchanting") == 2, "recipes can be ticked for the advert")
    check(select(2, A.Post("Enchanting", skill)) == "You're not in the Trade channel. It is only there in a city.", "outside a city there is no Trade channel to post in")
    CHANNELS[gm.guid] = { 1, "General - Orgrimmar", false, 2, "Trade - City", false }
    local n = #guildChat
    check(A.Post("Enchanting", skill) == "Posted in Trade chat.", "one click posts the advert")
    local line = guildChat[#guildChat] or ""
    check(#guildChat == n + 1 and line:find("CHANNEL:2:[Enchanting] 225/300 LFW in Orgrimmar. Tips appreciated.", 1, true) == 1
        and line:find("[Enchant Bracer - Minor Health] [Runed Copper Rod]", 1, true) ~= nil, "it goes to the Trade channel with the skill, the city and the ticked recipes as links")
    check(select(2, A.Post("Enchanting", skill)):find("One post a minute.", 1, true) == 1 and #guildChat == n + 1, "a second post inside a minute isn't sent")
    A.ToggleLink("Enchanting", 7418); A.ToggleLink("Enchanting", 7421)
    CHANNELS[gm.guid] = nil
end)

-- Alt linking: an officer types the name without capitals.
run(gm, "link alt", function()
    local ns = gm.ns
    check(ns.GUIDForName("pip") == MEMBER and ns.GUIDForName("PIP-normal") == MEMBER and ns.GUIDForName("Nobody") == nil,
        "member names are found whatever the capitals")
    check(ns.Roster.LinkAlt("  pip ", "Player-1-VET") ~= nil, "linking an alt isn't case sensitive")
    check(ns.Reducer.State().alts[MEMBER] == "Player-1-VET", "the alt link is recorded")
    assert(ns.Roster.Unlink(MEMBER))
end)

-- Loot history: the Officer charges two items; every member can see them.
run(officer, "charge loot", function()
    assert(officer.ns.DKP.Award({ MEMBER }, 100, "manual", "for loot"))
    assert(officer.ns.DKP.Spend(MEMBER, "minor", 1001))
    assert(officer.ns.DKP.Spend(MEMBER, "off", 1002))
end)
advance(15)
run(member, "loot history", function()
    local ns = member.ns
    local st = ns.Reducer.State()
    local all = ns.Loot.Entries(st)
    check(#all == 2 and #ns.Loot.For(st, all, MEMBER) == 2 and #ns.Loot.For(st, all, gm.guid) == 0,
        "loot charges show as history for the member who got them")
    local blade = ns.Loot.Item(1001)
    check(blade.name == "Test Blade" and blade.quality == 4 and blade.icon == 135274 and blade.link ~= nil,
        "item name, icon and link come from the game by id")
    check(ns.Loot.Item(1002).name == nil, "an item the game hasn't loaded yet shows without a name")
    fire(member, "GET_ITEM_INFO_RECEIVED", 1002, true)
    check(ns.Loot.Item(1002).name == "Test Cloak", "and fills in once the game has it")
    local rows = ns.Loot.Nights(all, "blade", ns.Loot.NameOf, ns.Loot.ItemName)
    check(#rows == 2 and rows[1].header and rows[2].item == 1001, "the night-by-night list can be searched by item")
    check(not ns.RBAC.ICan("award"), "a Member has no award rights")
    shiftDown = true
    ns.Loot.Click(all[#all])
    shiftDown = false
    ns.Loot.Click(all[#all])
    check(#linked == 1 and linked[1]:find("item:1001", 1, true), "Shift-click links the item in chat; a plain click doesn't")
end)

-- 8. Every tab again with real data, as each role.
for _, c in ipairs({ gm, officer, member }) do
    open(c)
    advance(1)
    pressEverything(c)
    advance(3)
end

-- A Member sees Raid & Loot (for the history) but none of the officer controls.
run(member, "member view of Raid & Loot", function()
    local function visible(text)
        for _, w in ipairs(member.widgets) do
            if w._.text == text and w:IsVisible() then return true end
        end
        return false
    end
    local tab
    for _, w in ipairs(member.widgets) do
        if w._.text == "Raid & Loot" and w._.scripts.OnClick then tab = w end
    end
    check(tab ~= nil, "a Member has the Raid & Loot tab")
    if tab then tab._.scripts.OnClick(tab, "LeftButton") end
    check(not visible("Charge selected player") and not visible("Award") and not visible("Award and charge"),
        "a Member sees the loot history without the award and charge controls")
end)

-- About: who makes it and where to join.
slash(member, "about")
check(said(member, "Join us on Discord: https://discord.gg/hfCKk6kED"), "/bp about gives the Discord link")
check(said(member, "Made by Kitch, of the Blood Pact guild, US East PvP Horde."), "/bp about says who made it")
run(member, "credit in the window", function()
    open(member)
    local places, visible = 0, 0
    for _, w in ipairs(member.widgets) do
        if w._.kind == "FontString" and w._.text == "Made by Kitch" then
            places = places + 1
            if w:IsVisible() then visible = visible + 1 end
        end
    end
    check(visible >= 1, "the window's corner says who made it")
    check(places == 2, "and so does the About page")
    check(member.ns.VERSION:match("^1%.") ~= nil, "this is a 1.x release")
end)
run(member, "about panel", function()
    local seen = false
    for _, w in ipairs(member.widgets) do
        if w._.text == "https://discord.gg/hfCKk6kED" and w:IsVisible() then seen = true end
    end
    check(seen, "the About panel shows the link to copy")
end)

-- 9. Mock mode end to end on the GM's client.
for _, cmd in ipairs({ "mock on", "mock boss", "mock award", "mock forge", "mock signups", "mock attend", "mock roster",
    "mock summon", "mock nonsense" }) do
    slash(gm, cmd)
    advance(1)
end
run(gm, "mock raid", function() gm.ns.Raids.Create("Mock night", "Hyjal Summit", "12/21", "20:00", 20, nil, "LOCAL", false) end)
slash(gm, "mock signups")
advance(1)
open(gm)
pressEverything(gm)
advance(60)
slash(gm, "mock reset")
slash(gm, "mock off")
advance(5)

-- 10. The member logs out; whispers to them stop instead of piling up.
member.online = false
advance(1200)
run(gm, "idle", function() check(gm.ns.Comm.QueueLength() == 0, "nothing is left queued for an offline player") end)

---------------------------------------------------------------------------
local unknown = {}
for k in pairs(unknownGlobals) do unknown[#unknown + 1] = k end
table.sort(unknown)
if #unknown > 0 then failed = failed + 1; report("FAIL unknown globals read: " .. table.concat(unknown, ", ")) end
for i = 1, math.min(#errors, 15) do report("ERROR " .. errors[i]) end
if #errors > 15 then report(("... and %d more errors"):format(#errors - 15)) end
report(("smoke: %d checks, %d failed, %d errors, %d addon messages sent, late login caught up in %s s"):format(
    checks, failed, #errors, sentAddon, tostring(caughtUpAfter)))
if failed > 0 or #errors > 0 then os.exit(1) end
