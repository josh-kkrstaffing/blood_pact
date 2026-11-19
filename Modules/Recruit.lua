-- Blood Pact: Recruit tab (Team Captain and above).
-- Never sends a whisper or an invite by itself. WoW Forever forbids addon and
-- macro guild invites, and /who needs a click per search, so:
--   1. pick a message (selected for Ctrl+C)   2. Scan my zone (one /who per click)
--   3. click a name to open a whisper, paste, press Enter
--   4. when they reply, right-click their name in chat > Guild Invite
local _, ns = ...
local W, U = ns.W, ns.U

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
local candidates = {}

local function openWhisper(name)
    local sendTell = ChatFrame_SendTell or (ChatFrameUtil and ChatFrameUtil.SendTell)
    if sendTell then sendTell(name) else ns.UI.Say("Type /w " .. name .. " then paste your message.") end
end

ns.UI.AddTab("recruit", "Recruit", "recruit", function(p)
    local h1 = W.Text(p, "1. Pick a message", "GameFontNormal")
    h1:SetPoint("TOPLEFT", 0, 0)
    p.msgButtons = {}
    for i = 1, 3 do
        local b = W.Button(p, LABELS[i], 110, 22, function()
            current = i
            p.box:SetText(messages()[i] or "")
            p.box:SetFocus()
            p.box:HighlightText()
        end)
        b:SetPoint("TOPLEFT", (i - 1) * 116, -20)
        p.msgButtons[i] = b
    end

    local bg = CreateFrame("Frame", nil, p, "BackdropTemplate")
    bg:SetPoint("TOPLEFT", 0, -48)
    bg:SetSize(640, 70)
    bg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    bg:SetBackdropColor(0, 0, 0, 0.6)
    p.box = CreateFrame("EditBox", nil, bg)
    p.box:SetMultiLine(true)
    p.box:SetFontObject(ChatFontNormal)
    p.box:SetPoint("TOPLEFT", 8, -8)
    p.box:SetPoint("BOTTOMRIGHT", -8, 8)
    p.box:SetAutoFocus(false)
    p.box:SetMaxLetters(255)
    p.box:SetScript("OnEscapePressed", p.box.ClearFocus)

    local hint = W.Text(p, "Text is selected: press Ctrl+C to copy.", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 0, -122)
    p.saveMsg = W.Button(p, "Save as guild message", 170, 20, function()
        local msgs = U.Copy(messages())
        msgs[current] = p.box:GetText()
        ns.UI.Try("Recruiting message saved for all recruiters.", function()
            if not ns.RBAC.ICan("recruitEdit") then return nil, "Only Officers and above can edit the messages." end
            return ns.Log.New("RECRUIT_MSGS", { msgs = msgs })
        end)
    end)
    p.saveMsg:SetPoint("TOPRIGHT", 0, -120)

    local h2 = W.Text(p, "2. Scan for unguilded players, then click a name to whisper them", "GameFontNormal")
    h2:SetPoint("TOPLEFT", 0, -150)
    p.scan = W.Button(p, "Scan my zone", 130, 22, function()
        local zone = GetZoneText()
        if not zone or zone == "" then ns.UI.Say("Couldn't read your zone.") return end
        if C_FriendList.SetWhoToUi then C_FriendList.SetWhoToUi(true) end
        C_FriendList.SendWho('z-"' .. zone .. '"')
        p.found:SetText("Searching " .. U.Safe(zone, 40) .. "...")
    end)
    p.scan:SetPoint("TOPLEFT", 0, -170)
    p.found = W.Text(p, "", "GameFontDisableSmall")
    p.found:SetPoint("LEFT", p.scan, "RIGHT", 10, 0)

    p.list = W.List(p, 620, 150, 18, function(row, item)
        p.list.Col(row, 1, 4, 220):SetText(U.Safe(item.name, 40))
        p.list.Col(row, 2, 230, 260):SetText(("|cffaaaaaa%d %s - %s|r"):format(item.level or 0, U.Safe(item.class, 20), U.Safe(item.area, 30)))
    end, function(item)
        openWhisper(item.name)
    end)
    p.list.scroll:SetPoint("TOPLEFT", 0, -198)

    local h3 = W.Text(p, "3. When they reply, right-click their name in chat and choose Guild Invite.", "GameFontHighlightSmall")
    h3:SetPoint("TOPLEFT", 0, -354)
    ns.recruitPanel = p
end, function(p)
    p.saveMsg:SetShown(ns.RBAC.ICan("recruitEdit"))
    if not p.box:HasFocus() then p.box:SetText(messages()[current] or "") end
end)

ns.On("WHO_LIST_UPDATE", function()
    local p = ns.recruitPanel
    if not p or not p:IsVisible() then return end
    wipe(candidates)
    local total = C_FriendList.GetNumWhoResults() or 0
    for i = 1, total do
        local info = C_FriendList.GetWhoInfo(i)
        if info and info.fullName and (not info.fullGuildName or info.fullGuildName == "") then
            candidates[#candidates + 1] = { name = info.fullName, level = info.level, class = info.classStr, area = info.area }
        end
    end
    p.found:SetText(("%d unguilded players found."):format(#candidates))
    p.list:SetItems(candidates)
end)
