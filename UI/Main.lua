-- Blood Pact: main window. Built the first time it opens; nothing is created
-- at login except event handlers. Tabs show only to roles allowed to use them.
local _, ns = ...
local UI = {}
ns.UI = UI

local W, U, RBAC = ns.W, ns.U, ns.RBAC
local tabs, order = {}, {}
local frame, roleText, statusText, activeKey

-- Left to right. Everyday tabs first, officer tools after, Settings last.
local TAB_ORDER = { standings = 1, raids = 2, roster = 3, bis = 4, summon = 5, raid = 6, recruit = 7, settings = 8 }

function UI.AddTab(key, label, action, build, refresh)
    order[#order + 1] = key
    tabs[key] = { label = label, action = action, build = build, refresh = refresh }
    table.sort(order, function(a, b) return (TAB_ORDER[a] or 99) < (TAB_ORDER[b] or 99) end)
end

local function allowed(tab) return RBAC.ICan(tab.action) end

function UI.Say(msg)
    ns.Print(msg)
    if frame and frame.feedback then frame.feedback:SetText(U.Safe(msg, 200)) end
end

-- For actions that can't be taken back: the first click arms the button,
-- a second click within 5 seconds runs it.
function UI.Confirm(button, fn)
    local armedAt, label = -10, nil
    return function(...)
        if GetTime() - armedAt > 5 then
            armedAt, label = GetTime(), button:GetText()
            button:SetText("Click again to confirm")
            C_Timer.After(5, function()
                if armedAt > 0 and label then button:SetText(label) end
            end)
            return
        end
        armedAt = -10
        if label then button:SetText(label) end
        return fn(...)
    end
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
    local x, firstAllowed = 12, nil
    for _, key in ipairs(order) do
        local t = tabs[key]
        if allowed(t) then
            t.button:ClearAllPoints()
            t.button:SetPoint("TOPLEFT", x, -38)
            t.button:Show()
            x = x + t.button:GetWidth() + 2
            firstAllowed = firstAllowed or key
        else
            t.button:Hide()
            if t.panel then t.panel:Hide() end
        end
    end
    if not activeKey or not allowed(tabs[activeKey]) then activeKey = firstAllowed end
    if activeKey then selectTab(activeKey) end
end

local MIN_W, MIN_H, MAX_W, MAX_H = 760, 500, 1600, 1100

local function saveLayout()
    if not (frame and ns.db) then return end
    local point, _, rel, x, y = frame:GetPoint(1)
    ns.db.ui.frame = { w = math.floor(frame:GetWidth() + 0.5), h = math.floor(frame:GetHeight() + 0.5),
        point = point, rel = rel, x = x, y = y }
end

local function build()
    frame = CreateFrame("Frame", "BloodPactMainFrame", UIParent)
    local saved = ns.db.ui.frame
    frame:SetSize(saved and saved.w or MIN_W, saved and saved.h or MIN_H)
    if saved and saved.point then
        frame:SetPoint(saved.point, UIParent, saved.rel or saved.point, saved.x or 0, saved.y or 0)
    else
        frame:SetPoint("CENTER")
    end
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    W.Fill(frame, W.C.bg)
    W.Border(frame)

    -- Title bar: drag to move.
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(34)
    W.Fill(bar, W.C.bar)
    local accent = W.Line(frame, -35, W.C.accent, 1, 1)
    accent:SetDrawLayer("ARTWORK")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() frame:StartMoving() end)
    bar:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); saveLayout() end)
    tinsert(UISpecialFrames, "BloodPactMainFrame")

    local title = W.Text(bar, "BLOOD PACT", "GameFontNormalLarge")
    title:SetPoint("LEFT", 14, 0)
    roleText = W.Text(bar, "", "GameFontDisableSmall")
    roleText:SetPoint("LEFT", title, "RIGHT", 14, -1)
    statusText = W.Text(bar, "", "GameFontDisableSmall")
    statusText:SetPoint("RIGHT", -44, 0)
    local close = W.Button(bar, "X", 26, 22, function() frame:Hide() end)
    close:SetPoint("RIGHT", -6, 0)

    -- Resizing from the bottom-right corner.
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    elseif frame.SetMinResize then
        frame:SetMinResize(MIN_W, MIN_H)
        frame:SetMaxResize(MAX_W, MAX_H)
    end
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    for _, xy in ipairs({ { 2, 2 }, { 6, 2 }, { 10, 2 }, { 2, 6 }, { 6, 6 }, { 2, 10 } }) do
        local dot = grip:CreateTexture(nil, "OVERLAY")
        dot:SetColorTexture(W.C.muted[1], W.C.muted[2], W.C.muted[3], 0.9)
        dot:SetSize(2, 2)
        dot:SetPoint("BOTTOMRIGHT", -xy[1], xy[2])
    end
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() frame:StopMovingOrSizing(); saveLayout() end)

    frame.feedback = W.Text(frame, "", "GameFontHighlightSmall")
    frame.feedback:SetPoint("BOTTOMLEFT", 16, 12)
    frame.feedback:SetPoint("BOTTOMRIGHT", -30, 12)
    local foot = frame:CreateTexture(nil, "BORDER")
    foot:SetColorTexture(W.C.border[1], W.C.border[2], W.C.border[3], 1)
    foot:SetPoint("BOTTOMLEFT", 1, 32)
    foot:SetPoint("BOTTOMRIGHT", -1, 32)
    foot:SetHeight(1)

    -- Tab strip
    W.Line(frame, -68, W.C.border, 1, 1)
    for _, key in ipairs(order) do
        local t = tabs[key]
        t.button = W.Button(frame, t.label, 96, 30, function() selectTab(key) end, "tab")
        local fs = t.button:GetFontString()
        local textWidth = fs and fs:GetStringWidth() or 0
        t.button:SetWidth(math.max(60, math.floor(textWidth + 0.5) + 26))
        t.panel = CreateFrame("Frame", nil, frame)
        t.panel:SetPoint("TOPLEFT", 20, -80)
        t.panel:SetPoint("BOTTOMRIGHT", -20, 40)
        t.panel:Hide()
        t.build(t.panel)
    end
    frame:SetScript("OnShow", UI.Refresh)
    -- Keeps "5 min ago", zones and the sync status current while it's open.
    C_Timer.NewTicker(15, function() UI.RefreshSoon() end)
end

-- Many changes can land at once (a sync, a roster burst). Redraw once.
local refreshQueued = false
function UI.RefreshSoon()
    if refreshQueued or not frame or not frame:IsShown() then return end
    refreshQueued = true
    C_Timer.After(0.15, function()
        refreshQueued = false
        UI.Refresh()
    end)
end

function UI.Toggle()
    if not ns.db then
        ns.Print("Blood Pact is still loading. Try again in a moment.")
        return
    end
    if not frame then
        local ok, err = pcall(build)
        if not ok then
            frame = nil
            ns.Print("The window couldn't open: " .. tostring(err))
            return
        end
        -- A new frame starts out shown, so the first /bp opens it.
        frame:Show()
        UI.Refresh()
        return
    end
    frame:SetShown(not frame:IsShown())
end

function UI.IsOpen() return frame ~= nil and frame:IsShown() end

ns.Listen("LOG_CHANGED", UI.RefreshSoon)
ns.Listen("ROSTER_CHANGED", UI.RefreshSoon)

---------------------------------------------------------------------------
-- Standings tab (everyone)
---------------------------------------------------------------------------
UI.AddTab("standings", "Standings", "view", function(p)
    local header = { { "#", 4, 24 }, { "Name", 34, 240 }, { "DKP", 290, 70 }, { "Earned", 380, 70 }, { "Spent", 470, 70 }, { "Attend.", 560, 70 } }
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
        local here, held = ns.Reducer.Attendance(item.guid)
        p.list.Col(row, 6, 560, 70):SetText(held > 0 and (here .. "/" .. held) or "-")
    end)
    p.list:Stretch(0, -20, 0, 0)
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

    p.prog = W.Check(p, "Progression night", function(on)
        ns.db.ui.progression = on
    end)
    p.prog:SetPoint("TOPLEFT", 0, -50)
    p.prog.label:SetWidth(290)
    p.prog.label:SetWordWrap(false)
    p.auto = W.Check(p, "Auto-award raid bosses while I lead or assist", function(on)
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
            if not ns.mock and not IsInGroup() then
                UI.Say("Type one or more names, or join the raid to award your whole group.")
                return
            end
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
    end, "accent")
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
    p.lootList.key = "guid"
    p.charge = W.Button(p, "Charge selected player", 180, 22, function()
        local who = p.lootList.selected
        if not who then UI.Say("Pick the winner in the list first.") return end
        UI.Try(("Charged %s."):format(U.Safe(who.name, 40)), D.Spend, who.guid, selectedTier, D.ItemIDFrom(p.item:GetText()))
    end, "accent")
    p.charge:SetPoint("TOPLEFT", 340, -304)
end, function(p)
    local st = ns.Reducer.State()
    if not st then return end
    local s = st.settings
    p.onTime:SetText(("On-time bonus (+%d)"):format(s.onTime))
    p.fullRaid:SetText(("Full-raid bonus (+%d)"):format(s.fullRaid))
    p.prog:SetChecked(ns.db.ui.progression)
    p.prog.label:SetText(("Progression night: bosses pay %d, not %d"):format(s.bossProg, s.bossFarm))
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
    { "inactWatch", "Inactive days: Watch" }, { "inactInactive", "Inactive days: Inactive" },
    { "inactCleanup", "Inactive days: Cleanup" }, { "promoDays", "Initiate promo: days (0 = off)" },
    { "promoRaids", "Initiate promo: raids" },
}

UI.AddTab("settings", "Settings", "settings", function(p)
    local intro = W.Text(p, "Rules for this guild. DKP defaults follow a published example and inactivity days start at ForeverGuildManager's 30/60/90; set your own here.", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 0, 0)
    intro:SetWidth(700)
    p.edits = {}
    for i, r in ipairs(SETTING_ROWS) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local fs = W.Text(p, r[2], "GameFontHighlight")
        fs:SetPoint("TOPLEFT", col * 350, -30 - row * 30)
        local e = W.Edit(p, 60, 5)
        e:SetPoint("TOPLEFT", col * 350 + 220, -26 - row * 30)
        p.edits[r[1]] = e
    end
    p.save = W.Button(p, "Save settings", 140, 22, function()
        local values = {}
        for key, e in pairs(p.edits) do values[key] = e:GetText() end
        UI.Try("Settings saved and shared with the guild.", ns.DKP.SaveSettings, values)
    end, "accent")
    p.save:SetPoint("TOPLEFT", 0, -250)
    -- Decay touches every balance, so it takes two clicks.
    p.armed = -10
    p.decay = W.Button(p, "Run decay now", 170, 22, function()
        if GetTime() - p.armed > 5 then
            p.armed = GetTime()
            p.decay:SetText("Click again to confirm")
            UI.Say("Decay lowers every positive balance. Click again within 5 seconds to confirm.")
            return
        end
        p.armed = -10
        UI.Try("Decay applied to every balance.", ns.DKP.Decay)
    end)
    p.decay:SetPoint("LEFT", p.save, "RIGHT", 8, 0)
    p.undoDecay = W.Button(p, "Undo last decay", 140, 22, function()
        UI.Try("The last decay was undone for everyone.", ns.DKP.UndoDecay)
    end)
    p.undoDecay:SetPoint("LEFT", p.decay, "RIGHT", 8, 0)
    p.last = W.Text(p, "", "GameFontDisableSmall")
    p.last:SetPoint("TOPLEFT", 0, -282)
end, function(p)
    local st = ns.Reducer.State()
    if not st then return end
    for key, e in pairs(p.edits) do
        if not e:HasFocus() then e:SetText(tostring(st.settings[key])) end
    end
    if GetTime() - p.armed > 5 then p.decay:SetText(("Run %d%% decay now"):format(st.settings.decayPct)) end
    p.undoDecay:SetEnabled(st.lastDecay ~= nil)
    p.last:SetText(st.lastDecay and ("Last decay: " .. date("%b %d, %Y", st.lastDecay.t)) or "Decay has not been run yet.")
end)
