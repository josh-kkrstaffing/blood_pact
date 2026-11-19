-- Blood Pact: main window. Built the first time it opens; nothing is created
-- at login except event handlers. Tabs show only to roles allowed to use them.
local _, ns = ...
local UI = {}
ns.UI = UI

local W, U, RBAC = ns.W, ns.U, ns.RBAC
local tabs, order = {}, {}
local frame, roleText, statusText, activeKey

function UI.AddTab(key, label, action, build, refresh)
    order[#order + 1] = key
    tabs[key] = { label = label, action = action, build = build, refresh = refresh }
end

local function allowed(tab) return RBAC.ICan(tab.action) end

function UI.Say(msg)
    ns.Print(msg)
    if frame and frame.feedback then frame.feedback:SetText(U.Safe(msg, 200)) end
end

-- Run an action that returns (result) or (nil, error message).
function UI.Try(okMsg, fn, ...)
    local res, why = fn(...)
    if res then UI.Say(okMsg) else UI.Say(why or "That didn't work.") end
    return res
end

local function selectTab(key)
    activeKey = key
    for k, t in pairs(tabs) do
        if t.panel then t.panel:SetShown(k == key) end
        if t.button then t.button:SetEnabled(k ~= key) end
    end
    local t = tabs[key]
    if t and t.refresh then t.refresh(t.panel) end
end

function UI.Refresh()
    if not frame or not frame:IsShown() then return end
    local role = RBAC.RoleOf(ns.MyGUID())
    roleText:SetText("Your role: " .. (role and RBAC.LABEL[role] or "not in a guild"))
    local g = ns.G()
    local status = ns.Sync.Status()
    if g then
        local _, provisional = ns.Log.Count(g)
        if provisional > 0 then status = status .. "  |  " .. provisional .. " provisional" end
    end
    statusText:SetText(status)
    local x, firstAllowed = 20, nil
    for _, key in ipairs(order) do
        local t = tabs[key]
        if allowed(t) then
            t.button:ClearAllPoints()
            t.button:SetPoint("TOPLEFT", x, -44)
            t.button:Show()
            x = x + t.button:GetWidth() + 4
            firstAllowed = firstAllowed or key
        else
            t.button:Hide()
            if t.panel then t.panel:Hide() end
        end
    end
    if not activeKey or not allowed(tabs[activeKey]) then activeKey = firstAllowed end
    if activeKey then selectTab(activeKey) end
end

local function build()
    frame = CreateFrame("Frame", "BloodPactMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(700, 500)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tinsert(UISpecialFrames, "BloodPactMainFrame")

    local title = W.Text(frame, "Blood Pact", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 22, -18)
    roleText = W.Text(frame, "", "GameFontHighlightSmall")
    roleText:SetPoint("LEFT", title, "RIGHT", 16, 0)
    statusText = W.Text(frame, "", "GameFontDisableSmall")
    statusText:SetPoint("TOPRIGHT", -40, -22)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    frame.feedback = W.Text(frame, "", "GameFontNormalSmall")
    frame.feedback:SetPoint("BOTTOMLEFT", 22, 18)
    frame.feedback:SetWidth(650)

    for _, key in ipairs(order) do
        local t = tabs[key]
        t.button = W.Button(frame, t.label, 110, 22, function() selectTab(key) end)
        t.panel = CreateFrame("Frame", nil, frame)
        t.panel:SetPoint("TOPLEFT", 20, -76)
        t.panel:SetPoint("BOTTOMRIGHT", -20, 36)
        t.panel:Hide()
        t.build(t.panel)
    end
    frame:SetScript("OnShow", UI.Refresh)
end

function UI.Toggle()
    if not ns.db then return end
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end

ns.Listen("LOG_CHANGED", UI.Refresh)
ns.Listen("ROSTER_CHANGED", UI.Refresh)

---------------------------------------------------------------------------
-- Standings tab (everyone)
---------------------------------------------------------------------------
UI.AddTab("standings", "Standings", "view", function(p)
    local header = { { "#", 4, 24 }, { "Name", 34, 240 }, { "DKP", 290, 70 }, { "Earned", 380, 70 }, { "Spent", 470, 70 } }
    for _, h in ipairs(header) do
        local fs = W.Text(p, h[1], "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", h[2], 0)
    end
    p.list = W.List(p, 630, 330, 18, function(row, item)
        p.list.Col(row, 1, 4, 24):SetText(item.rank)
        p.list.Col(row, 2, 34, 240):SetText(U.Safe(item.name, 48))
        p.list.Col(row, 3, 290, 70):SetText(item.bal)
        p.list.Col(row, 4, 380, 70):SetText(item.earned)
        p.list.Col(row, 5, 470, 70):SetText(item.spent)
    end)
    p.list.scroll:SetPoint("TOPLEFT", 0, -18)
end, function(p)
    local rows = ns.DKP.Standings()
    for i, r in ipairs(rows) do r.rank = i end
    p.list:SetItems(rows)
end)

---------------------------------------------------------------------------
-- Raid tab (Officer and above): awards and loot
---------------------------------------------------------------------------
local selectedTier = "major"

UI.AddTab("raid", "Raid & Loot", "award", function(p)
    local D = ns.DKP
    local h1 = W.Text(p, "Award everyone in your group", "GameFontNormal")
    h1:SetPoint("TOPLEFT", 0, 0)

    p.onTime = W.Button(p, "On-time bonus", 150, 22, function()
        UI.Try("On-time bonus awarded.", D.AwardGroup, "ontime")
    end)
    p.onTime:SetPoint("TOPLEFT", 0, -22)
    p.fullRaid = W.Button(p, "Full-raid bonus", 150, 22, function()
        UI.Try("Full-raid bonus awarded.", D.AwardGroup, "fullraid")
    end)
    p.fullRaid:SetPoint("LEFT", p.onTime, "RIGHT", 8, 0)

    p.prog = W.Check(p, "Progression night: boss kills pay the progression amount", function(on)
        ns.db.ui.progression = on
    end)
    p.prog:SetPoint("TOPLEFT", 0, -50)
    p.auto = W.Check(p, "Auto-award boss kills while I lead the raid", function(on)
        ns.db.ui.autoBossAward = on
    end)
    p.auto:SetPoint("TOPLEFT", 0, -74)

    local h2 = W.Text(p, "Custom award", "GameFontNormal")
    h2:SetPoint("TOPLEFT", 0, -108)
    local l1 = W.Text(p, "Names, comma-separated (blank = whole group)", "GameFontHighlightSmall")
    l1:SetPoint("TOPLEFT", 0, -128)
    p.names = W.Edit(p, 300, 240)
    p.names:SetPoint("TOPLEFT", 6, -142)
    local l2 = W.Text(p, "DKP (- to deduct)", "GameFontHighlightSmall")
    l2:SetPoint("TOPLEFT", 0, -168)
    p.amount = W.Edit(p, 60, 6)
    p.amount:SetPoint("TOPLEFT", 6, -182)
    local l3 = W.Text(p, "Reason", "GameFontHighlightSmall")
    l3:SetPoint("TOPLEFT", 110, -168)
    p.note = W.Edit(p, 190, 120)
    p.note:SetPoint("TOPLEFT", 116, -182)
    p.award = W.Button(p, "Award", 100, 22, function()
        local guids, missing = {}, {}
        local text = p.names:GetText() or ""
        if text:match("^%s*$") then
            guids = D.GroupGUIDs()
        else
            for name in text:gmatch("[^,]+") do
                name = name:match("^%s*(.-)%s*$")
                local guid = ns.GUIDForName(name)
                if guid then guids[#guids + 1] = guid else missing[#missing + 1] = name end
            end
        end
        if #missing > 0 then
            UI.Say("Not in the guild roster: " .. table.concat(missing, ", "))
            return
        end
        UI.Try("Custom award sent.", D.Award, guids, tonumber(p.amount:GetText()), "manual", p.note:GetText())
    end)
    p.award:SetPoint("TOPLEFT", 0, -210)
    p.undo = W.Button(p, "Undo my last award or charge", 210, 22, function()
        UI.Try("Your last award or charge was voided.", D.UndoMine)
    end)
    p.undo:SetPoint("LEFT", p.award, "RIGHT", 8, 0)

    -- Loot (right side)
    local h3 = W.Text(p, "Charge loot: fixed price, highest DKP wins ties", "GameFontNormal")
    h3:SetPoint("TOPLEFT", 340, 0)
    local l4 = W.Text(p, "Item (shift-click it here, or type its ID)", "GameFontHighlightSmall")
    l4:SetPoint("TOPLEFT", 340, -20)
    p.item = W.Edit(p, 300, 255)
    p.item:SetPoint("TOPLEFT", 346, -34)
    UI.lootEdit = p.item

    p.tierButtons = {}
    local tiers = { { "bis", "BiS" }, { "major", "Major" }, { "minor", "Minor" }, { "off", "Off" } }
    for i, t in ipairs(tiers) do
        local b = W.Button(p, t[2], 72, 22, function()
            selectedTier = t[1]
            tabs.raid.refresh(p)
        end)
        b:SetPoint("TOPLEFT", 340 + (i - 1) * 74, -60)
        b.tier = t[1]
        b.label = t[2]
        p.tierButtons[i] = b
    end

    p.lootList = W.List(p, 280, 210, 18, function(row, item)
        p.lootList.Col(row, 1, 4, 200):SetText(U.Safe(item.name, 40))
        p.lootList.Col(row, 2, 210, 60, "RIGHT"):SetText(item.bal)
    end)
    p.lootList.scroll:SetPoint("TOPLEFT", 340, -88)
    p.charge = W.Button(p, "Charge selected player", 180, 22, function()
        local who = p.lootList.selected
        if not who then UI.Say("Pick the winner in the list first.") return end
        UI.Try(("Charged %s."):format(U.Safe(who.name, 40)), D.Spend, who.guid, selectedTier, D.ItemIDFrom(p.item:GetText()))
    end)
    p.charge:SetPoint("TOPLEFT", 340, -304)
end, function(p)
    local st = ns.Reducer.State()
    if not st then return end
    local s = st.settings
    p.onTime:SetText(("On-time bonus (+%d)"):format(s.onTime))
    p.fullRaid:SetText(("Full-raid bonus (+%d)"):format(s.fullRaid))
    p.prog:SetChecked(ns.db.ui.progression)
    p.prog.label:SetText(("Progression night: boss kills pay %d instead of %d"):format(s.bossProg, s.bossFarm))
    p.auto:SetChecked(ns.db.ui.autoBossAward)
    for _, b in ipairs(p.tierButtons) do
        b:SetText(("%s %d"):format(b.label, ns.Reducer.Price(b.tier) or 0))
        b:SetEnabled(b.tier ~= selectedTier)
    end
    local items = {}
    for _, guid in ipairs(ns.DKP.GroupGUIDs()) do
        items[#items + 1] = { guid = guid, name = ns.NameForGUID(guid) or "?", bal = ns.Reducer.Balance(guid) }
    end
    table.sort(items, function(a, b)
        if a.bal ~= b.bal then return a.bal > b.bal end
        return a.name < b.name
    end)
    p.lootList:SetItems(items)
end)

-- Shift-click an item while the loot box has focus puts its link there.
local function insertLink(link)
    if UI.lootEdit and UI.lootEdit:HasFocus() and type(link) == "string" then
        UI.lootEdit:SetText(link)
    end
end
if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", insertLink) end
if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", insertLink) end

---------------------------------------------------------------------------
-- Settings tab (Guild Master and ADMIN)
---------------------------------------------------------------------------
local SETTING_ROWS = {
    { "onTime", "On-time bonus" }, { "fullRaid", "Full-raid bonus" },
    { "bossFarm", "Boss kill (farm)" }, { "bossProg", "Boss kill (progression)" },
    { "decayPct", "Decay %" },
    { "priceBis", "Price: best-in-slot" }, { "priceMajor", "Price: major upgrade" },
    { "priceMinor", "Price: minor upgrade" }, { "priceOff", "Price: off spec" },
}

UI.AddTab("settings", "Settings", "settings", function(p)
    local intro = W.Text(p, "DKP values for this guild. Defaults follow a published example; set your guild's own rules here.", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 0, 0)
    intro:SetWidth(640)
    p.edits = {}
    for i, r in ipairs(SETTING_ROWS) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local fs = W.Text(p, r[2], "GameFontHighlight")
        fs:SetPoint("TOPLEFT", col * 320, -30 - row * 30)
        local e = W.Edit(p, 60, 5)
        e:SetPoint("TOPLEFT", col * 320 + 190, -26 - row * 30)
        p.edits[r[1]] = e
    end
    p.save = W.Button(p, "Save settings", 140, 22, function()
        local values = {}
        for key, e in pairs(p.edits) do values[key] = e:GetText() end
        UI.Try("Settings saved and shared with the guild.", ns.DKP.SaveSettings, values)
    end)
    p.save:SetPoint("TOPLEFT", 0, -190)
    p.decay = W.Button(p, "Run decay now", 140, 22, function()
        UI.Try("Decay applied to every balance.", ns.DKP.Decay)
    end)
    p.decay:SetPoint("LEFT", p.save, "RIGHT", 8, 0)
    p.last = W.Text(p, "", "GameFontDisableSmall")
    p.last:SetPoint("TOPLEFT", 0, -222)
end, function(p)
    local st = ns.Reducer.State()
    if not st then return end
    for key, e in pairs(p.edits) do
        if not e:HasFocus() then e:SetText(tostring(st.settings[key])) end
    end
    p.decay:SetText(("Run %d%% decay now"):format(st.settings.decayPct))
    p.last:SetText(st.lastDecay and ("Last decay: " .. date("%b %d, %Y", st.lastDecay.t)) or "Decay has not been run yet.")
end)
