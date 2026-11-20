-- Blood Pact: guild summon board.
-- WoW Forever has no summoning stones, so a warlock's Ritual of Summoning
-- (level 20, needs the warlock and 2 more group members) is the only summon.
-- Anyone asks for a summon; every warlock in the guild sees it, along with
-- how many guildmates are in their zone to click the portal. The warlock
-- invites the asker and two helpers with one click, then casts the ritual.
-- Nothing here is automatic: every invite and message is a button click, and
-- requests live only for this session (they are not written to the log).
local _, ns = ...
local S = {}
ns.Summon = S

local U = ns.U

S.MIN_LEVEL = 20        -- Ritual of Summoning
S.HELPERS = 2           -- group members besides the warlock
S.TTL = 600             -- a request lasts 10 minutes
S.requests = {}         -- [asker guid] = { from, zone, note, to, at, by }
S.offers = {}           -- [warlock guid] = { [helper guid] = time }
S.calls = {}            -- [warlock guid] = { zone, at } "I need clickers"

---------------------------------------------------------------------------
-- Pure logic (tested without the game)
---------------------------------------------------------------------------
local function cleanZone(z) return type(z) == "string" and z ~= "" and z or nil end

-- Online warlocks who can summon, each with the online guildmates in their
-- zone. ready = enough of them are there to click the portal.
function S.Warlocks(roster)
    local byZone = {}
    for guid, m in pairs(roster) do
        local z = m.online and cleanZone(m.zone)
        if z then
            byZone[z] = byZone[z] or {}
            byZone[z][#byZone[z] + 1] = guid
        end
    end
    local out = {}
    for guid, m in pairs(roster) do
        if m.online and m.class == "WARLOCK" and (m.level or 0) >= S.MIN_LEVEL then
            local near = {}
            for _, g in ipairs(byZone[cleanZone(m.zone) or ""] or {}) do
                if g ~= guid then near[#near + 1] = g end
            end
            out[#out + 1] = { guid = guid, name = m.name or "?", level = m.level or 0, zone = cleanZone(m.zone) or "?",
                near = near, ready = #near >= S.HELPERS }
        end
    end
    table.sort(out, function(a, b)
        if a.ready ~= b.ready then return a.ready end
        if #a.near ~= #b.near then return #a.near > #b.near end
        return a.name < b.name
    end)
    return out
end

-- Up to `need` guildmates to invite as clickers: in the warlock's zone, online,
-- not the warlock, not the asker, not already grouped. People who offered first.
function S.PickHelpers(roster, warlock, asker, grouped, offers, need)
    local zone = roster[warlock] and cleanZone(roster[warlock].zone)
    local picks = {}
    if not zone or need <= 0 then return picks end
    local function try(guid)
        local m = roster[guid]
        if #picks < need and m and m.online and m.zone == zone and guid ~= warlock and guid ~= asker
            and not grouped[guid] then
            for _, p in ipairs(picks) do if p == guid then return end end
            picks[#picks + 1] = guid
        end
    end
    local offered = {}
    for guid in pairs(offers or {}) do offered[#offered + 1] = guid end
    table.sort(offered)
    for _, guid in ipairs(offered) do try(guid) end
    local rest = {}
    for guid in pairs(roster) do rest[#rest + 1] = guid end
    table.sort(rest)
    for _, guid in ipairs(rest) do try(guid) end
    return picks
end

local function text(s, max) return type(s) == "string" and #s <= max end

-- Apply one board message from `sender` (a guild member's GUID). Returns what
-- to tell the local player, if anything: "request", "claimed", "call", "offer".
function S.Apply(msg, sender, roster, me, now)
    local t = msg.t
    if t == "SR" then
        if not text(msg.z, 48) or (msg.n ~= nil and not text(msg.n, 60)) then return end
        if msg.to ~= nil and not text(msg.to, 64) then return end
        S.requests[sender] = { from = sender, zone = msg.z, note = msg.n, to = msg.to, at = now }
        return "request", S.requests[sender]
    elseif t == "SX" then
        if not text(msg.who, 64) then return end
        -- The asker, the warlock handling it, or any warlock may close it.
        local r = S.requests[msg.who]
        local m = roster[sender]
        if r and (sender == r.from or sender == r.by or (m and m.class == "WARLOCK")) then
            S.requests[msg.who] = nil
        end
    elseif t == "SA" then
        if not text(msg.who, 64) then return end
        local r = S.requests[msg.who]
        local m = roster[sender]
        if r and m and m.class == "WARLOCK" then
            r.by = sender
            if msg.who == me then return "claimed", r end
        end
    elseif t == "SH" then
        if not text(msg.z, 48) then return end
        local m = roster[sender]
        if m and m.class == "WARLOCK" then
            S.calls[sender] = { zone = msg.z, at = now }
            return "call", S.calls[sender]
        end
    elseif t == "SI" then
        if not text(msg.to, 64) then return end
        S.offers[msg.to] = S.offers[msg.to] or {}
        S.offers[msg.to][sender] = now
        if msg.to == me then return "offer" end
    end
end

-- Open requests, oldest first; expired ones are dropped.
function S.Open(now)
    local out = {}
    for guid, r in pairs(S.requests) do
        if now - r.at > S.TTL then S.requests[guid] = nil else out[#out + 1] = r end
    end
    for guid, c in pairs(S.calls) do
        if now - c.at > S.TTL then S.calls[guid] = nil; S.offers[guid] = nil end
    end
    table.sort(out, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.from < b.from
    end)
    return out
end

---------------------------------------------------------------------------
-- Game side
---------------------------------------------------------------------------
local function myZone()
    return cleanZone(GetRealZoneText and GetRealZoneText()) or cleanZone(GetZoneText and GetZoneText()) or "?"
end

local function iAmWarlock()
    local _, class = UnitClass("player")
    return class == "WARLOCK" and (UnitLevel("player") or 0) >= S.MIN_LEVEL
end
S.IAmWarlock = iAmWarlock

local function nameOf(guid) return U.ShortName(ns.NameForGUID(guid) or "someone") end

local function alert(msg)
    ns.Print(msg)
    if ns.Char().summonAlerts == false then return end
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.3, b = 0.1 })
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
end

-- Send a board message to the guild and apply it here too (we don't hear
-- our own messages). In mock mode it only applies here.
local function post(msg)
    local me = ns.MyGUID()
    S.Apply(msg, me, ns.roster.byGUID, me, ns.Now())
    if ns.UI then ns.UI.RefreshSoon() end
    if ns.mock then return true end
    return ns.Sync.SendLive(msg)
end

local lastAlert = {}
local function onMessage(msg, _, sguid)
    local me = ns.MyGUID()
    local what, data = S.Apply(msg, sguid, ns.roster.byGUID, me, ns.Now())
    if ns.UI then ns.UI.RefreshSoon() end
    if not what then return end
    local key = what .. ":" .. sguid
    if GetTime() - (lastAlert[key] or -100) < 60 then return end
    lastAlert[key] = GetTime()
    local who = U.Safe(nameOf(sguid), 40)
    if what == "request" and iAmWarlock() and (data.to == nil or data.to == me) then
        local near = 0
        for _, w in ipairs(S.Warlocks(ns.roster.byGUID)) do
            if w.guid == me then near = #w.near end
        end
        alert(("%s asks for a summon%s. %d guildmate%s in your zone. Type /bp and open Summon."):format(
            who, data.note and (" (" .. U.Safe(data.note, 60) .. ")") or "", near, near == 1 and "" or "s"))
    elseif what == "claimed" then
        alert(who .. " is inviting you for a summon. Accept the group invite.")
    elseif what == "call" and data.zone == myZone() then
        alert(("%s needs %d people to click a summoning portal in %s. Type /bp and open Summon."):format(
            who, S.HELPERS, U.Safe(data.zone, 48)))
    elseif what == "offer" then
        alert(who .. " will help click your summoning portal.")
    end
end

for _, kind in ipairs({ "SR", "SX", "SA", "SH", "SI" }) do ns.Sync.Handle(kind, onMessage) end

function S.Request(note, toGUID)
    if not ns.RBAC.ICan("view") then return nil, "You need to be in the guild." end
    note = tostring(note or ""):match("^%s*(.-)%s*$")
    local ok = post({ t = "SR", z = myZone():sub(1, 48), n = note ~= "" and note:sub(1, 60) or nil, to = toGUID })
    if not ok then
        S.requests[ns.MyGUID()] = nil
        return nil, "Not connected to the guild yet. Try again in a moment."
    end
    -- Asking one warlock: also whisper them, from this click, so they see it
    -- even without Blood Pact. Guild members only; never in test mode.
    local m = toGUID and ns.roster.byGUID[toGUID]
    if m and m.online and toGUID ~= ns.MyGUID() and not ns.mock then
        local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
        local msg = "Could I get a warlock summon" .. (note ~= "" and (" to " .. note:sub(1, 60)) or "") .. "? I'm in " .. myZone() .. ". (sent with Blood Pact)"
        if send and pcall(send, msg, "WHISPER", nil, ns.U.ShortName(m.name)) then return "whispered" end
    end
    return true
end

function S.Cancel(who)
    return post({ t = "SX", who = who or ns.MyGUID() }) or nil
end

-- One line in guild chat, for guildmates who don't have Blood Pact.
function S.PostToGuildChat(note)
    note = tostring(note or ""):match("^%s*(.-)%s*$")
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local msg = "Looking for a warlock summon" .. (note ~= "" and (" to " .. note:sub(1, 60)) or "") .. ". I'm in " .. myZone() .. "."
    if ns.mock then return true end
    local ok = pcall(send, msg, "GUILD")
    if not ok then return nil, "The game didn't send it. Type it in guild chat." end
    return true
end

local invitedByHand = {}
function S.Invite(guid)
    local name = nameOf(guid)
    invitedByHand[#invitedByHand + 1] = name
    if ns.mock then return true end
    local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if not fn or not pcall(fn, name) then return nil, "Type /invite " .. name end
    return true
end

-- If the game refuses addon invites, show the commands to type instead.
ns.Listen("ACTION_BLOCKED", function(func)
    if #invitedByHand == 0 or not tostring(func):find("Invite") then return end
    local parts = {}
    for i, name in ipairs(invitedByHand) do parts[i] = "/invite " .. name end
    invitedByHand = {}
    ns.Print("Invite by hand: " .. table.concat(parts, "   "))
end)

-- Warlock, one click: invite the asker and, if needed, two helpers from your
-- zone, and tell the asker you're on it.
function S.Start(request)
    if not iAmWarlock() and not ns.mock then return nil, "Only a warlock of level 20 or higher can summon." end
    if not ns.mock and IsInGroup() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        return nil, "Only your group's leader can invite. Ask them, or leave the group first."
    end
    local me = ns.MyGUID()
    invitedByHand = {}
    local grouped, others = {}, 0
    for _, guid in ipairs(ns.mock and { me } or ns.DKP.GroupGUIDs()) do
        grouped[guid] = true
        if guid ~= me then others = others + 1 end
    end
    local helpers = S.PickHelpers(ns.roster.byGUID, me, request.from, grouped, S.offers[me], S.HELPERS - others)
    local invited = {}
    if not grouped[request.from] then
        S.Invite(request.from)
        invited[#invited + 1] = nameOf(request.from)
    end
    for _, guid in ipairs(helpers) do
        S.Invite(guid)
        invited[#invited + 1] = nameOf(guid)
    end
    post({ t = "SA", who = request.from })
    local short = S.HELPERS - others - #helpers
    local msg = #invited > 0 and ("Invited " .. table.concat(invited, ", ") .. ".") or "Everyone is already in your group."
    if short > 0 then
        msg = msg .. (" You still need %d more to click: press Ask for clickers."):format(short)
    else
        msg = msg .. " Target " .. nameOf(request.from) .. " and cast Ritual of Summoning."
    end
    return msg
end

local lastCall = -100
function S.CallHelpers()
    if not iAmWarlock() and not ns.mock then return nil, "Only a warlock can ask for clickers." end
    if GetTime() - lastCall < 30 then return nil, "You just asked. Give it half a minute." end
    lastCall = GetTime()
    return post({ t = "SH", z = myZone():sub(1, 48) }) or nil
end

function S.Offer(warlock)
    return post({ t = "SI", to = warlock }) or nil
end

---------------------------------------------------------------------------
-- Summon tab (everyone)
---------------------------------------------------------------------------
local W = ns.W
local lastRosterAsk = -100

local function ago(seconds)
    if seconds < 60 then return "just now" end
    return math.floor(seconds / 60) .. " min ago"
end

ns.UI.AddTab("summon", "Summon", "view", function(p)
    W.Text(p, "Warlocks online", "GameFontNormal"):SetPoint("TOPLEFT", 0, 0)
    p.locks = W.List(p, 390, 130, 18, function(row, w)
        p.locks.Col(row, 1, 4, 130):SetText(U.Safe(U.ShortName(w.name), 30) .. " |cff808080" .. w.level .. "|r")
        p.locks.Col(row, 2, 136, 130):SetText(U.Safe(w.zone, 30))
        p.locks.Col(row, 3, 268, 120):SetText(w.ready and ("|cff40ff40can summon|r (" .. #w.near .. " there)")
            or ("|cff808080" .. #w.near .. " guildmate" .. (#w.near == 1 and "" or "s") .. " there|r"))
    end, function() ns.UI.Refresh() end)
    p.locks.scroll:SetPoint("TOPLEFT", 0, -20)
    p.locks.key = "guid"
    -- Warlocks: the click-to-summon list (Modules/SummonQueue.lua).
    p.queue = W.Button(p, "Open summon queue", 140, 18, function() ns.SummonQueue.Show(false) end)
    p.queue:SetPoint("TOPLEFT", 250, 2)

    -- Asking for a summon
    W.Text(p, "Need a summon?", "GameFontNormal"):SetPoint("TOPLEFT", 430, 0)
    W.Text(p, "Where to (optional)", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 430, -22)
    p.note = W.Edit(p, 270, 60)
    p.note:SetPoint("TOPLEFT", 430, -38)
    p.askAny = W.Button(p, "Ask any warlock", 132, 22, function()
        ns.UI.Try("Asked every warlock in the guild.", S.Request, p.note:GetText(), nil)
    end, "accent")
    p.askAny:SetPoint("TOPLEFT", 430, -66)
    p.askOne = W.Button(p, "Ask selected", 132, 22, function()
        local w = p.locks.selected
        if not w then ns.UI.Say("Pick a warlock in the list first.") return end
        local who = U.Safe(U.ShortName(w.name), 30)
        local res, why = S.Request(p.note:GetText(), w.guid)
        if res == "whispered" then
            ns.UI.Say("Whispered " .. who .. " and put your request on the board.")
        elseif res then
            ns.UI.Say("Your request for " .. who .. " is on the board. The game didn't send the whisper, so whisper them yourself.")
        else
            ns.UI.Say(why or "That didn't work.")
        end
    end)
    p.askOne:SetPoint("TOPLEFT", 568, -66)
    p.cancel = W.Button(p, "Cancel my request", 132, 22, function()
        S.Cancel()
        ns.UI.Say("Your summon request was cancelled.")
    end)
    p.cancel:SetPoint("TOPLEFT", 430, -92)
    p.chat = W.Button(p, "Post in guild chat", 132, 22, function()
        ns.UI.Try("Posted one line in guild chat.", S.PostToGuildChat, p.note:GetText())
    end)
    p.chat:SetPoint("TOPLEFT", 568, -92)
    p.status = W.Text(p, "", "GameFontHighlightSmall")
    p.status:SetPoint("TOPLEFT", 430, -122)
    p.status:SetWidth(280)

    -- The board
    p.boardTitle = W.Text(p, "Summon requests", "GameFontNormal")
    p.boardTitle:SetPoint("TOPLEFT", 0, -162)
    p.board = W.List(p, 690, 110, 18, function(row, r)
        local m = ns.roster.byGUID[r.from]
        p.board.Col(row, 1, 4, 130):SetText(U.Safe(nameOf(r.from), 30))
        p.board.Col(row, 2, 136, 130):SetText("in " .. U.Safe(m and m.zone or r.zone, 30))
        p.board.Col(row, 3, 268, 170):SetText(r.note and ("to " .. U.Safe(r.note, 60)) or "")
        p.board.Col(row, 4, 440, 80):SetText("|cff808080" .. ago(ns.Now() - r.at) .. "|r")
        p.board.Col(row, 5, 522, 160):SetText(r.by and ("|cff40ff40" .. U.Safe(nameOf(r.by), 30) .. " is on it|r")
            or (r.to and ("asked " .. U.Safe(nameOf(r.to), 30)) or "asked everyone"))
    end, function() ns.UI.Refresh() end)
    p.board:Stretch(0, -182, 0, 62)
    p.board.key = "from"

    local foot = CreateFrame("Frame", nil, p)
    foot:SetPoint("BOTTOMLEFT", 0, 0)
    foot:SetPoint("BOTTOMRIGHT", 0, 0)
    foot:SetHeight(56)
    p.start = W.Button(foot, "Invite for summon", 150, 22, function()
        local r = p.board.selected
        if not r then ns.UI.Say("Pick a request in the list first.") return end
        local msg, why = S.Start(r)
        ns.UI.Say(msg or why)
    end, "accent")
    p.start:SetPoint("TOPLEFT", 0, 0)
    p.call = W.Button(foot, "Ask for clickers", 130, 22, function()
        ns.UI.Try("Asked guildmates in your zone to come click.", S.CallHelpers)
    end)
    p.call:SetPoint("TOPLEFT", 156, 0)
    p.done = W.Button(foot, "Done", 70, 22, function()
        local r = p.board.selected
        if r then S.Cancel(r.from) end
    end)
    p.done:SetPoint("TOPLEFT", 292, 0)
    p.help = W.Button(foot, "I'll help click", 130, 22, function()
        if p.helpFor then
            S.Offer(p.helpFor)
            ns.UI.Say("Told " .. U.Safe(nameOf(p.helpFor), 30) .. " you'll help. Watch for the group invite.")
        end
    end)
    p.help:SetPoint("TOPLEFT", 368, 0)
    p.alerts = W.Check(foot, "Pop up summon alerts", function(on) ns.Char().summonAlerts = on end)
    p.alerts:SetPoint("TOPLEFT", 510, -3)
    p.hint = W.Text(foot, "", "GameFontDisableSmall")
    p.hint:SetPoint("TOPLEFT", 0, -30)
    p.hint:SetPoint("RIGHT", 0, 0)
end, function(p)
    -- Zones come from the guild roster; ask for a fresh one now and then.
    if not ns.mock and GetTime() - lastRosterAsk > 15 and C_GuildInfo and C_GuildInfo.GuildRoster then
        lastRosterAsk = GetTime()
        C_GuildInfo.GuildRoster()
    end
    local me, now = ns.MyGUID(), ns.Now()
    local locks = S.Warlocks(ns.roster.byGUID)
    p.locks:SetItems(locks)
    local open = S.Open(now)
    p.board:SetItems(open)
    p.boardTitle:SetText(#open == 0 and "Summon requests: none right now" or ("Summon requests (" .. #open .. ")"))

    local mine = S.requests[me]
    p.cancel:SetEnabled(mine ~= nil)
    if #locks == 0 then
        p.status:SetText("No warlock of level " .. S.MIN_LEVEL .. " or higher is online in the guild.")
    elseif mine and mine.by then
        p.status:SetText("|cff40ff40" .. U.Safe(nameOf(mine.by), 30) .. " is inviting you. Accept the group invite.|r")
    elseif mine then
        p.status:SetText(mine.to and ("Your request is out. " .. U.Safe(nameOf(mine.to), 30) .. " was whispered.")
            or "Your request is out. Warlocks running Blood Pact were alerted; use Post in guild chat to reach the rest.")
    else
        p.status:SetText("Green warlocks have " .. S.HELPERS .. " or more guildmates in their zone to click the portal.")
    end

    local lock = iAmWarlock() or (ns.mock and true)
    local sel = p.board.selected
    p.queue:SetShown(iAmWarlock())
    p.start:SetShown(lock)
    p.call:SetShown(lock)
    p.done:SetShown(lock)
    p.start:SetEnabled(sel ~= nil)
    p.done:SetEnabled(sel ~= nil)
    p.alerts:SetChecked(ns.Char().summonAlerts ~= false)

    -- A warlock in my zone is asking for clickers.
    p.helpFor = nil
    local here = myZone()
    for guid, c in pairs(S.calls) do
        if guid ~= me and c.zone == here and now - c.at <= S.TTL then p.helpFor = guid end
    end
    p.help:SetShown(p.helpFor ~= nil)
    if p.helpFor then
        p.hint:SetText(U.Safe(nameOf(p.helpFor), 30) .. " needs clickers for a summoning portal in your zone.")
    elseif lock then
        local offers = 0
        for _ in pairs(S.offers[me] or {}) do offers = offers + 1 end
        p.hint:SetText("Pick a request, then Invite for summon: it invites them and up to " .. S.HELPERS
            .. " guildmates in your zone. Then click their name in the summon queue."
            .. (offers > 0 and ("  " .. offers .. " offered to help click.") or ""))
    else
        p.hint:SetText("In a group with a warlock? Type 123 in raid or party chat to join their summon queue. The ritual needs the warlock and "
            .. S.HELPERS .. " more group members to click the portal.")
    end
end)
