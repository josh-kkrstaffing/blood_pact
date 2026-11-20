-- Blood Pact: Recruit tab (Team Captain and above).
-- Never whispers or invites by itself: every search and every whisper is one
-- click by the recruiter, to one player. WoW Forever forbids addon and macro
-- guild invites, and /who needs a click per search, so:
--   1. pick a message (Social, Raiding or Crafting)
--   2. Scan my zone, or one of my faction's starting zones (one /who per click)
--   3. click a name: that player is whispered the picked message, once
--      (right-click opens a whisper to type your own)
--   4. when they reply, right-click their name in chat > Guild Invite
local _, ns = ...
local W, U = ns.W, ns.U
local R = {}
ns.Recruit = R

-- WoW Forever's seven starting zones, by faction and region. Each runs from
-- level 1 to about 12. Both factions' Skyborne start on Zephras Isle.
R.STARTER = {
    Horde = {
        { region = "Kalimdor", zones = { "Durotar", "Mulgore" } },
        { region = "Eastern Kingdoms", zones = { "Tirisfal Glades" } },
        { region = "Skyborne", zones = { "Zephras Isle" } },
    },
    Alliance = {
        { region = "Kalimdor", zones = { "Teldrassil" } },
        { region = "Eastern Kingdoms", zones = { "Elwynn Forest", "Dun Morogh" } },
        { region = "Skyborne", zones = { "Zephras Isle" } },
    },
}
-- The game lists at most about 50 players per search, guilded ones included,
-- so a busy starting zone is searched a few levels at a time.
R.BANDS = { { 1, 4 }, { 5, 8 }, { 9, 12 } }
R.WAIT = 5      -- seconds between searches; the game ignores faster ones

function R.Regions(faction) return R.STARTER[faction] or R.STARTER.Horde end

-- The /who text for a zone, optionally one level band of it.
function R.Query(zone, band)
    local q = 'z-"' .. zone .. '"'
    if band then q = q .. " " .. band[1] .. "-" .. band[2] end
    return q
end

-- Which band to search next: the first for a new zone, else the one after.
function R.NextBand(lastZone, lastBand, zone)
    if lastZone ~= zone or not lastBand then return 1 end
    return lastBand % #R.BANDS + 1
end

-- Add unguilded players from one search to the list, each name once.
--   results = { { name =, guild =, level =, class =, area = }, ... }
-- -> how many were added
function R.Merge(list, results)
    local have, added = {}, 0
    for _, c in ipairs(list) do have[c.name] = true end
    for _, r in ipairs(results) do
        if r.name and not have[r.name] and (r.guild == nil or r.guild == "") then
            have[r.name] = true
            list[#list + 1] = { name = r.name, level = r.level, class = r.class, area = r.area }
            added = added + 1
        end
    end
    return added
end

local DEFAULT_MESSAGES = {
    "Hey! <guild> is recruiting on WoW Forever. We're a friendly, active guild that levels, runs dungeons and helps each other out. Want an invite? Just reply 'inv'.",
    "<guild> is building raid teams for Barrow Deeps and Hyjal Summit, with DKP loot run through our guild addon. All roles welcome. Reply 'inv' to join!",
    "<guild> is recruiting crafters and gatherers! Want your professions to matter? Reply 'inv' if you want in.",
}
local LABELS = { "Social", "Raiding", "Crafting" }

-- Shared messages if an Officer saved some, else defaults with the guild's name.
local function messages()
    local st = ns.Reducer.State()
    if st and st.recruitMsgs then return st.recruitMsgs end
    local guild = GetGuildInfo("player") or "Our guild"
    local out = {}
    for i, m in ipairs(DEFAULT_MESSAGES) do out[i] = (m:gsub("<guild>", function() return guild end)) end
    return out
end

local current = 1
local drafts = {}          -- a message edited in the box but not saved, per slot, until reload
local candidates = {}
local scan = {}            -- the search in flight: { zone =, band = } (band nil = my own zone)
local lastScan = -100

local function openWhisper(name)
    local sendTell = ChatFrame_SendTell or (ChatFrameUtil and ChatFrameUtil.SendTell)
    if sendTell then sendTell(name) else ns.UI.Say("Type /w " .. name .. " then paste your message.") end
end

-- Names whispered since login, so a slip of the finger doesn't send twice.
-- Not saved and not shared.
local whispered = {}

-- One whisper to one player, from the recruiter's own click.
-- -> true, or nil and why not
function R.Whisper(name, text)
    if ns.mock then return nil, "Test mode is on, so nothing is whispered." end
    if not ns.RBAC.ICan("recruit") then return nil, "Your guild rank can't recruit." end
    text = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
    if text == "" then return nil, "Pick a message first." end
    if #text > 255 then return nil, "That message is too long for one whisper (255 letters)." end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send or not pcall(send, text, "WHISPER", nil, U.ShortName(name)) then
        return nil, "The game didn't send it."
    end
    whispered[name] = true
    return true
end

ns.UI.AddTab("recruit", "Recruit", "recruit", function(p)
    local h1 = W.Text(p, "1. Pick a message", "GameFontNormal")
    h1:SetPoint("TOPLEFT", 0, 0)
    p.msgButtons = {}
    for i = 1, 3 do
        local b = W.Button(p, LABELS[i], 110, 22, function()
            current = i
            p.box:SetText(drafts[i] or messages()[i] or "")
            ns.UI.Refresh()
        end)
        b:SetPoint("TOPLEFT", (i - 1) * 116, -20)
        p.msgButtons[i] = b
    end

    local bg = CreateFrame("Frame", nil, p)
    bg:SetPoint("TOPLEFT", 0, -48)
    bg:SetSize(640, 70)
    W.Panel(bg)
    p.box = CreateFrame("EditBox", nil, bg)
    p.box:SetMultiLine(true)
    p.box:SetFontObject(W.F.body)
    p.box:SetPoint("TOPLEFT", 8, -8)
    p.box:SetPoint("BOTTOMRIGHT", -8, 8)
    p.box:SetAutoFocus(false)
    p.box:SetMaxLetters(255)
    p.box:SetScript("OnEscapePressed", p.box.ClearFocus)
    -- Keep what the recruiter typed, so it is still there when they click a name.
    p.box:SetScript("OnTextChanged", function(self, byUser)
        if byUser then drafts[current] = self:GetText() end
    end)

    local hint = W.Text(p, "This is what a click on a name sends. You can edit it first.", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 0, -122)
    p.saveMsg = W.Button(p, "Save as guild message", 170, 20, function()
        local msgs = U.Copy(messages())
        if msgs[current] == p.box:GetText() then ns.UI.Say("That message is already saved.") return end
        msgs[current] = p.box:GetText()
        ns.UI.Try("Recruiting message saved for all recruiters.", function()
            if not ns.RBAC.ICan("recruitEdit") then return nil, "Only Officers and above can edit the messages." end
            local e, why = ns.Log.New("RECRUIT_MSGS", { msgs = msgs })
            if e then drafts[current] = nil end
            return e, why
        end)
    end)
    p.saveMsg:SetPoint("TOPRIGHT", 0, -120)

    local h2 = W.Text(p, "2. Scan for unguilded players, then click a name to whisper them the message above", "GameFontNormal")
    h2:SetPoint("TOPLEFT", 0, -150)
    -- One /who per click. zone = nil searches where I am standing.
    local function search(zone)
        if GetTime() - lastScan < R.WAIT then
            ns.UI.Say("The game allows one search every few seconds. Try again in a moment.")
            return
        end
        local band
        if zone then
            band = R.NextBand(scan.zone, scan.band, zone)
            if scan.zone ~= zone or not scan.band then wipe(candidates) end
        else
            zone = GetZoneText()
            if not zone or zone == "" then ns.UI.Say("Couldn't read your zone.") return end
            wipe(candidates)
        end
        lastScan = GetTime()
        scan = { zone = zone, band = band }
        if C_FriendList.SetWhoToUi then C_FriendList.SetWhoToUi(true) end
        C_FriendList.SendWho(R.Query(zone, band and R.BANDS[band]))
        p.found:SetText(band and ("Searching %s, levels %d-%d..."):format(U.Safe(zone, 40), R.BANDS[band][1], R.BANDS[band][2])
            or ("Searching " .. U.Safe(zone, 40) .. "..."))
        p.list:SetItems(candidates)
    end
    p.scan = W.Button(p, "Scan my zone", 130, 22, function() search(nil) end)
    p.scan:SetPoint("TOPLEFT", 0, -170)
    p.found = W.Text(p, "", "GameFontDisableSmall")
    p.found:SetPoint("LEFT", p.scan, "RIGHT", 10, 0)

    -- My faction's starting zones, grouped by region.
    local faction = "Horde"
    if UnitFactionGroup then
        local ok, f = pcall(UnitFactionGroup, "player")
        if ok and R.STARTER[f] then faction = f end
    end
    local x = 0
    local lead = W.Text(p, "Starter zones", "GameFontHighlightSmall")
    lead:SetPoint("TOPLEFT", x, -202)
    x = x + 78
    p.zoneButtons = {}
    for _, group in ipairs(R.Regions(faction)) do
        local label = W.Text(p, group.region .. ":", "GameFontDisableSmall")
        label:SetPoint("TOPLEFT", x, -202)
        x = x + 6 * #group.region + 12
        for _, zone in ipairs(group.zones) do
            local width = 6 * #zone + 20
            local b = W.Button(p, zone, width, 20, function() search(zone) end)
            b:SetPoint("TOPLEFT", x, -198)
            p.zoneButtons[#p.zoneButtons + 1] = b
            x = x + width + 4
        end
        x = x + 8
    end

    p.list = W.List(p, 620, 150, 18, function(row, item)
        local sent = whispered[item.name]
        local name = p.list.Col(row, 1, 4, 220)
        name:SetText(U.Safe(item.name, 40))
        local c = sent and W.C.muted or W.C.text
        name:SetTextColor(c[1], c[2], c[3])
        p.list.Col(row, 2, 230, 260):SetText(("|cffaaaaaa%d %s - %s|r"):format(item.level or 0, U.Safe(item.class, 20), U.Safe(item.area, 30)))
        p.list.Col(row, 3, 496, 110):SetText(sent and "|cff40ff40whispered|r" or "")
    end, function(item, button)
        if not item then return end
        local who = U.Safe(U.ShortName(item.name), 40)
        if button == "RightButton" then
            openWhisper(item.name)                      -- type your own
            return
        end
        if whispered[item.name] and not (IsShiftKeyDown and IsShiftKeyDown()) then
            ns.UI.Say("You already whispered " .. who .. ". Shift-click to send it again, or right-click to type your own.")
            return
        end
        local ok, why = R.Whisper(item.name, p.box:GetText())
        if ok then
            ns.UI.Say(("Whispered %s the %s message."):format(who, LABELS[current]))
        else
            ns.UI.Say((why or "That didn't work.") .. " Opening a whisper so you can paste it.")
            openWhisper(item.name)
        end
        p.list.Update()
    end)
    p.list:Stretch(0, -226, 0, 22)

    local h3 = W.Text(p, "3. When they reply, right-click their name in chat and choose Guild Invite.", "GameFontHighlightSmall")
    h3:SetPoint("BOTTOMLEFT", 0, 2)
    ns.recruitPanel = p
end, function(p)
    p.saveMsg:SetShown(ns.RBAC.ICan("recruitEdit"))
    for i, b in ipairs(p.msgButtons) do b:SetEnabled(i ~= current) end      -- the picked one is marked
    if not p.box:HasFocus() then p.box:SetText(drafts[current] or messages()[current] or "") end
end)

ns.On("WHO_LIST_UPDATE", function()
    local p = ns.recruitPanel
    if not p or not p:IsVisible() then return end
    local shown, total = C_FriendList.GetNumWhoResults()
    shown = shown or 0
    local results = {}
    for i = 1, shown do
        local info = C_FriendList.GetWhoInfo(i)
        if info and info.fullName then
            results[#results + 1] = { name = info.fullName, guild = info.fullGuildName, level = info.level,
                class = info.classStr, area = info.area }
        end
    end
    if not scan.band then wipe(candidates) end      -- my own zone: a fresh list each time
    R.Merge(candidates, results)
    local cut = (type(total) == "number" and total > shown) and (" The game listed only %d of %d players."):format(shown, total) or ""
    if scan.band then
        local done, nxt = R.BANDS[scan.band], R.BANDS[R.NextBand(scan.zone, scan.band, scan.zone)]
        p.found:SetText(("%d unguilded in %s so far (levels %d-%d searched).%s Click it again for levels %d-%d."):format(
            #candidates, U.Safe(scan.zone, 30), done[1], done[2], cut, nxt[1], nxt[2]))
    else
        p.found:SetText(("%d unguilded players found.%s"):format(#candidates, cut))
    end
    p.list:SetItems(candidates)
end)
