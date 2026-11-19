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
    "SetOrientation", "SetThumbTexture", "SetValueStep" }) do
    M[name] = noop
end
function M:SetSize(w, h) self._.w, self._.h = w, h end
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
function M:Show() self._.shown = true end
function M:Hide() self._.shown = false end
function M:SetShown(v) self._.shown = v and true or false end
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
function M:CreateTexture() return widget("Texture", self) end
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
    "BloodPactFontBodySmall", "BloodPactFontMuted", "BloodPactFontDisabled", "os" }) do
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
G.hooksecurefunc = function() end
G.geterrorhandler = function() return function(err) fail("handler", err) end end
G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    if ctx then ctx.out[#ctx.out + 1] = table.concat(parts, " ") end
end
G.GetTime = function() return clock end
G.GetServerTime = function() return BASE + math.floor(clock) end
G.CreateFrame = function(kind, name, parent)
    local w = widget(kind, parent)
    if name then rawset(G, name, w) end
    return w
end
G.CreateFont = function() return widget("Font") end
G.UIParent = widget("Frame")
G.UISpecialFrames = {}
G.GameTooltip = widget("GameTooltip")
G.GameTooltip_Hide = function() end
G.SlashCmdList = {}
G.Enum = { CalendarEventType = { Raid = 1 } }
G.C_Timer = {
    After = function(d, fn) addTimer(d, fn) end,
    NewTicker = function(d, fn) addTimer(d, fn, d) end,
}
G.UnitGUID = function() return ctx.guid end
G.UnitName = function() return ctx.name end
G.UnitClass = function() return ctx.class, ctx.class end
G.UnitLevel = function() return ctx.level end
-- Talents in the older form: name, icon, points spent.
local TALENTS = { WARLOCK = { { "Affliction", 5 }, { "Demonology", 40 }, { "Destruction", 6 } },
    WARRIOR = { { "Arms", 31 }, { "Fury", 20 }, { "Protection", 0 } }, ROGUE = { { "Assassination", 0 }, { "Combat", 0 }, { "Subtlety", 0 } } }
G.GetNumTalentTabs = function() return 3 end
G.GetTalentTabInfo = function(i)
    local t = (TALENTS[ctx.class] or {})[i]
    if t then return t[1], nil, t[2] end
end
G.UnitIsGroupLeader = function() return false end
G.UnitIsGroupAssistant = function() return false end
G.IsInGuild = function() return true end
G.IsInRaid = function() return false end
G.IsInGroup = function() return false end
G.GetNumGroupMembers = function() return 0 end
G.GetGuildInfo = function() return "Blood Pact" end
G.GetNormalizedRealmName = function() return "Normal" end
G.GetZoneText = function() return ctx.zone end
G.GetRealZoneText = function() return ctx.zone end
G.GetNumGuildMembers = function() return #GUILD end
G.GetGuildRosterInfo = function(i)
    local m = GUILD[i]
    if not m then return nil end
    local c = clients[m[7]]
    local online = c ~= nil and c.online
    return m[1] .. REALM, m[3], m[2], m[5], m[4], m[6], "", "", online, 0, m[4], 0, 0, false, false, 0, m[7]
end
G.GetGuildRosterLastOnline = function() return 0, 0, 3, 5 end
G.GetInventoryItemLink = function(_, slot)
    return slot == 5 and "|cffa335ee|Hitem:1::::::::60:::::|h[Robe of the Void]|h|r" or nil
end
G.C_Container = { GetContainerNumSlots = function() return 2 end, GetContainerItemLink = function() return nil end }
G.C_GuildInfo = { GuildRoster = function()
    local c = ctx
    addTimer(0.1, function() fire(c, "GUILD_ROSTER_UPDATE") end)
end }
G.C_FriendList = { SendWho = noop, SetWhoToUi = noop, GetNumWhoResults = function() return 0 end, GetWhoInfo = noop }
G.C_PartyInfo = { InviteUnit = function(name) invites[#invites + 1] = name end }
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
G.ChatFrameUtil = { AddMessageEventFilter = noop, SendTell = noop, InsertLink = noop }
G.C_ChatInfo = {
    RegisterAddonMessagePrefix = noop,
    SendChatMessage = function(msg, kind, _, target)
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

-- 7. Summon board: the member asks, the warlock is alerted and invites.
run(member, "ask", function() assert(member.ns.Summon.Request("Blackrock Spire")) end)
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

-- 8. Every tab again with real data, as each role.
for _, c in ipairs({ gm, officer, member }) do
    open(c)
    advance(1)
    pressEverything(c)
    advance(3)
end

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
