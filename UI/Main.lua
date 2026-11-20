-- Blood Pact: main window. Built the first time it opens; nothing is created
-- at login except event handlers. Tabs show only to roles allowed to use them.
local _, ns = ...
local UI = {}
ns.UI = UI

local W, U, RBAC = ns.W, ns.U, ns.RBAC
local tabs, order = {}, {}
local frame, roleText, statusText, activeKey

-- Left to right, in the order a guild does things: bring people in, know
-- who they are, get them ready (professions, gear), sign them up, get them
-- to the raid, run it and hand out loot, then see where everyone stands.
-- Problems between players (Tickets) and the guild's rules come last. A tab
-- the player's rank can't use is skipped.
local TAB_ORDER = { recruit = 1, roster = 2, profs = 3, bis = 4, raids = 5, summon = 6, raid = 7, standings = 8, tickets = 9, settings = 10 }
UI.TAB_ORDER = TAB_ORDER

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

-- The window can be dragged as small as the open tab allows. Each tab says
-- how much room it needs right now (UI.Need); a tab with its sections folded
-- needs less, so the window can go smaller. Opening a section, or switching
-- to a tab that needs more, grows the window just enough to show it.
local MIN_W, MIN_H, MAX_W, MAX_H = 760, 280, 1600, 1100
local CHROME_H = 120            -- title bar, tab strip and the status line under the tab
local DEFAULT_NEED = 380        -- a tab that doesn't say gets the old fixed height
UI.MIN_W, UI.MIN_H, UI.CHROME_H, UI.DEFAULT_NEED = MIN_W, MIN_H, CHROME_H, DEFAULT_NEED

-- fn(panel) -> height the tab's content needs, and optionally the window width
function UI.Need(key, fn)
    if tabs[key] then tabs[key].need = fn end
end

-- Smallest window for a tab. Pure: (content height, window width) -> w, h
function UI.MinSize(needH, needW)
    local w = math.min(MAX_W, math.max(MIN_W, math.floor(tonumber(needW) or MIN_W)))
    local h = math.min(MAX_H, math.max(MIN_H, math.floor(tonumber(needH) or DEFAULT_NEED) + CHROME_H))
    return w, h
end

local saveLayout

-- Set the window's smallest size from the open tab, and grow it if it is
-- now too small to show that tab.
function UI.FitWindow()
    if not frame then return end
    local t = activeKey and tabs[activeKey]
    local needH, needW
    if t and t.need and t.panel then
        local ok, h, w = pcall(t.need, t.panel)
        if ok then needH, needW = h, w end
    end
    local minW, minH = UI.MinSize(needH, math.max(tonumber(needW) or 0, UI.tabStripW or 0))
    if frame.SetResizeBounds then
        frame:SetResizeBounds(minW, minH, MAX_W, MAX_H)
    elseif frame.SetMinResize then
        frame:SetMinResize(minW, minH)
    end
    local w, h = frame:GetWidth() or minW, frame:GetHeight() or minH
    if w < minW or h < minH then
        frame:SetSize(math.max(w, minW), math.max(h, minH))
        if saveLayout then saveLayout() end
    end
    return minW, minH
end

local function selectTab(key)
    activeKey = key
    if ns.db and ns.db.ui then ns.db.ui.tab = key end      -- reopen on the tab last used
    for k, t in pairs(tabs) do
        if t.panel then t.panel:SetShown(k == key) end
        if t.button then t.button:SetEnabled(k ~= key) end
    end
    local t = tabs[key]
    if t and t.refresh then t.refresh(t.panel) end
    UI.FitWindow()
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
    UI.tabStripW = x + 10            -- the window never goes narrower than its tabs
    if not activeKey and ns.db and ns.db.ui and tabs[ns.db.ui.tab] then activeKey = ns.db.ui.tab end
    if not activeKey or not allowed(tabs[activeKey]) then activeKey = firstAllowed end
    if activeKey then selectTab(activeKey) end
end

saveLayout = function()
    if not (frame and ns.db) then return end
    local point, _, rel, x, y = frame:GetPoint(1)
    ns.db.ui.frame = { w = math.floor(frame:GetWidth() + 0.5), h = math.floor(frame:GetHeight() + 0.5),
        point = point, rel = rel, x = x, y = y }
end

local function build()
    frame = CreateFrame("Frame", "BloodPactMainFrame", UIParent)
    local saved = ns.db.ui.frame
    -- A new window opens at a comfortable size; a saved one comes back as it was
    -- (the open tab then grows it if it needs more room).
    frame:SetSize(math.max(saved and saved.w or 800, MIN_W), math.max(saved and saved.h or 500, MIN_H))
    if saved and saved.point then
        frame:SetPoint(saved.point, UIParent, saved.rel or saved.point, saved.x or 0, saved.y or 0)
    else
        frame:SetPoint("CENTER")
    end
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    W.Glass(frame)

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
    local close = W.Button(bar, "X", 26, 22, function() frame:Hide() end)
    close:SetPoint("RIGHT", -6, 0)
    local aboutBtn = W.Button(bar, "About", 54, 22, function()
        if frame.about:IsShown() then frame.about:Hide() else frame.about:Show() end
    end)
    aboutBtn:SetPoint("RIGHT", close, "LEFT", -6, 0)
    -- How see-through the windows are: Frosted, Clear or Solid. Kept per account.
    local glassBtn
    glassBtn = W.Button(bar, W.GLASS_LABEL[W.glass] or "Frosted", 62, 22, function()
        local level = W.SetGlass(W.NextGlass())
        ns.db.ui.glass = level
        glassBtn:SetText(W.GLASS_LABEL[level])
    end)
    glassBtn:SetPoint("RIGHT", aboutBtn, "LEFT", -6, 0)
    frame.glassBtn = glassBtn
    statusText = W.Text(bar, "", "GameFontDisableSmall")
    statusText:SetPoint("RIGHT", glassBtn, "LEFT", -12, 0)

    -- About: who makes Blood Pact and where to join. Covers the tabs while open.
    local about = CreateFrame("Frame", nil, frame)
    about:SetPoint("TOPLEFT", 1, -36)
    about:SetPoint("BOTTOMRIGHT", -1, 33)
    if about.SetFrameLevel and frame.GetFrameLevel then about:SetFrameLevel((frame:GetFrameLevel() or 1) + 40) end
    about:EnableMouse(true)
    W.Fill(about, { W.C.bg[1], W.C.bg[2], W.C.bg[3], 0.97 })      -- hides the tab underneath
    local info = ns.ABOUT
    local y = -28
    local function line(text, template, gap)
        local fs = W.Text(about, text, template)
        fs:SetPoint("TOPLEFT", 28, y)
        fs:SetWidth(640)
        y = y - (gap or 22)
        return fs
    end
    line("BLOOD PACT", "GameFontNormalLarge", 28)
    about.version = line("", "GameFontHighlight")
    line("Made by " .. info.author, "GameFontNormal", 22)
    line(("For the %s guild, %s, and any guild that wants it."):format(info.guild, info.home), "GameFontHighlight", 34)
    line("Looking for a guild, or want to follow the addon? Join us on Discord:", "GameFontHighlight", 24)
    local link = W.Edit(about, 300, 80)
    link:SetPoint("TOPLEFT", 28, y)
    link:SetText(info.discord)
    link:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    link:SetScript("OnMouseUp", function(self) self:SetFocus(); self:HighlightText() end)
    -- The link is for copying, not editing: put it back if it's changed.
    link:SetScript("OnTextChanged", function(self)
        if self:GetText() ~= info.discord then self:SetText(info.discord) end
    end)
    about.link = link
    y = y - 30
    line("Click the link, press Ctrl+C, then paste it into your browser.", "GameFontDisableSmall", 40)
    line("Blood Pact is fan-made. It is not affiliated with or endorsed by Blizzard Entertainment.", "GameFontDisableSmall", 30)
    local back = W.Button(about, "Back", 80, 22, function() about:Hide() end)
    back:SetPoint("TOPLEFT", 28, y)
    about:SetScript("OnShow", function() about.version:SetText("Version " .. ns.VERSION .. ". A free guild management addon for WoW Forever.") end)
    about:Hide()
    frame.about = about

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

    -- The maker's credit, quietly, in the corner of every tab.
    frame.credit = W.Text(frame, "Made by " .. ns.ABOUT.author, "GameFontDisableSmall")
    frame.credit:SetPoint("BOTTOMRIGHT", -26, 12)
    frame.feedback = W.Text(frame, "", "GameFontHighlightSmall")
    frame.feedback:SetPoint("BOTTOMLEFT", 16, 12)
    frame.feedback:SetPoint("RIGHT", frame.credit, "LEFT", -12, 0)
    local foot = frame:CreateTexture(nil, "BORDER")
    foot:SetColorTexture(W.C.border[1], W.C.border[2], W.C.border[3], W.C.border[4])
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
        t.button:SetWidth(math.max(54, math.floor(textWidth + 0.5) + 18))
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

-- Open the window on the About panel.
function UI.ShowAbout()
    if not UI.IsOpen() then UI.Toggle() end
    if frame and frame.about then
        frame.about:Show()
        frame.about.version:SetText("Version " .. ns.VERSION .. ". A free guild management addon for WoW Forever.")
    end
end

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

UI.Need("standings", function() return 130 end)

---------------------------------------------------------------------------
-- Raid tab (Officer and above): awards and loot
---------------------------------------------------------------------------
local selectedTier = "major"
local raidView, lootFilter = "work", ""

-- Everyone can open this tab for the loot history; only Officers and above
-- see the award and charge controls (and the actions check the role again).
UI.AddTab("raid", "Raid & Loot", "view", function(p)
    local D = ns.DKP
    p.workBtn = W.Button(p, "Award and charge", 130, 22, function() raidView = "work"; UI.Refresh() end)
    p.workBtn:SetPoint("TOPLEFT", 0, 0)
    p.histBtn = W.Button(p, "Loot history", 110, 22, function() raidView = "history"; UI.Refresh() end)
    p.histBtn:SetPoint("TOPLEFT", 134, 0)

    -- Loot history, night by night.
    local h = CreateFrame("Frame", nil, p)
    h:SetPoint("TOPLEFT", 0, -30)
    h:SetPoint("BOTTOMRIGHT", 0, 0)
    p.hist = h
    W.Text(h, "Search", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 0, -5)
    p.histSearch = W.Edit(h, 150, 30)
    p.histSearch:SetPoint("TOPLEFT", 44, -1)
    p.histSearch:SetScript("OnTextChanged", function(self)
        lootFilter = (self:GetText() or ""):lower()
        UI.Refresh()
    end)
    p.histCount = W.Text(h, "", "GameFontDisableSmall")
    p.histCount:SetPoint("TOPLEFT", 206, -5)
    p.history = W.List(h, 690, 280, 20, function(row, e) ns.Loot.Render(p.history, row, e, true) end,
        function(e) ns.Loot.Click(e) end)
    p.history:Stretch(0, -28, 0, 0)
    p.history.key = "id"
    p.histEmpty = W.Text(h, "", "GameFontHighlightSmall")
    p.histEmpty:SetPoint("TOPLEFT", 4, -36)
    p.histEmpty:SetWidth(600)

    -- Award and charge (Officers and above).
    local a = CreateFrame("Frame", nil, p)
    a:SetPoint("TOPLEFT", 0, -30)
    a:SetPoint("BOTTOMRIGHT", 0, 0)
    p.work = a
    -- Left side, in the order of a raid night: the start, then the end.
    -- Boss kills pay on their own in between, and loot is on the right.
    local h1 = W.Text(a, "1. Start of the raid", "GameFontNormal")
    h1:SetPoint("TOPLEFT", 0, 0)
    p.onTime = W.Button(a, "On-time bonus", 150, 22, function()
        UI.Try("On-time bonus awarded.", D.AwardGroup, "ontime")
    end)
    p.onTime:SetPoint("TOPLEFT", 0, -22)
    p.prog = W.Check(a, "Progression night", function(on)
        ns.db.ui.progression = on
    end)
    p.prog:SetPoint("TOPLEFT", 0, -52)
    p.prog.label:SetWidth(290)
    p.prog.label:SetWordWrap(false)
    p.auto = W.Check(a, "Auto-award raid bosses while I lead or assist", function(on)
        ns.db.ui.autoBossAward = on
    end)
    p.auto:SetPoint("TOPLEFT", 0, -74)

    local hEnd = W.Text(a, "3. End of the raid", "GameFontNormal")
    hEnd:SetPoint("TOPLEFT", 0, -106)
    p.fullRaid = W.Button(a, "Full-raid bonus", 150, 22, function()
        UI.Try("Full-raid bonus awarded.", D.AwardGroup, "fullraid")
    end)
    p.fullRaid:SetPoint("TOPLEFT", 0, -128)
    p.undo = W.Button(a, "Undo my last award or charge", 210, 22, function()
        UI.Try("Your last award or charge was voided.", D.UndoMine)
    end)
    p.undo:SetPoint("TOPLEFT", 0, -158)

    -- A hand-typed award or deduction is the exception, so it folds away.
    p.customFold = W.Accordion(a, "Custom award or deduction", 320, 112, "raidCustom")
    p.customFold:SetPoint("TOPLEFT", 0, -194)
    local cb = p.customFold.body
    local l1 = W.Text(cb, "Names, comma-separated (blank = whole group)", "GameFontHighlightSmall")
    l1:SetPoint("TOPLEFT", 0, 0)
    p.names = W.Edit(cb, 300, 240)
    p.names:SetPoint("TOPLEFT", 6, -14)
    local l2 = W.Text(cb, "DKP (- to deduct)", "GameFontHighlightSmall")
    l2:SetPoint("TOPLEFT", 0, -40)
    p.amount = W.Edit(cb, 60, 6)
    p.amount:SetPoint("TOPLEFT", 6, -54)
    local l3 = W.Text(cb, "Reason", "GameFontHighlightSmall")
    l3:SetPoint("TOPLEFT", 110, -40)
    p.note = W.Edit(cb, 190, 120)
    p.note:SetPoint("TOPLEFT", 116, -54)
    p.award = W.Button(cb, "Award", 100, 22, function()
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
    p.award:SetPoint("TOPLEFT", 0, -84)

    -- Loot (right side)
    local h3 = W.Text(a, "2. Loot: charge the winner (fixed price, highest DKP wins ties)", "GameFontNormal")
    h3:SetPoint("TOPLEFT", 340, 0)
    local l4 = W.Text(a, "Item (shift-click it here, or type its ID)", "GameFontHighlightSmall")
    l4:SetPoint("TOPLEFT", 340, -20)
    p.item = W.Edit(a, 300, 255)
    p.item:SetPoint("TOPLEFT", 346, -34)
    UI.lootEdit = p.item

    p.tierButtons = {}
    local tiers = { { "bis", "BiS" }, { "major", "Major" }, { "minor", "Minor" }, { "off", "Off" } }
    for i, t in ipairs(tiers) do
        local b = W.Button(a, t[2], 72, 22, function()
            selectedTier = t[1]
            tabs.raid.refresh(p)
        end)
        b:SetPoint("TOPLEFT", 340 + (i - 1) * 74, -60)
        b.tier = t[1]
        b.label = t[2]
        p.tierButtons[i] = b
    end

    p.lootList = W.List(a, 280, 210, 18, function(row, item)
        p.lootList.Col(row, 1, 4, 200):SetText(U.Safe(item.name, 40))
        p.lootList.Col(row, 2, 210, 60, "RIGHT"):SetText(item.bal)
    end)
    p.lootList:Stretch(340, -88, nil, 30)       -- fills the height; the charge button sits under it
    p.lootList.key = "guid"
    p.charge = W.Button(a, "Charge selected player", 180, 22, function()
        local who = p.lootList.selected
        if not who then UI.Say("Pick the winner in the list first.") return end
        UI.Try(("Charged %s."):format(U.Safe(who.name, 40)), D.Spend, who.guid, selectedTier, D.ItemIDFrom(p.item:GetText()))
    end, "accent")
    p.charge:SetPoint("BOTTOMLEFT", 340, 0)
end, function(p)
    local st = ns.Reducer.State()
    local can = RBAC.ICan("award")
    if not can then raidView = "history" end
    local history = raidView == "history"
    p.workBtn:SetShown(can)
    p.histBtn:SetShown(can)
    p.workBtn:SetEnabled(history)
    p.histBtn:SetEnabled(not history)
    p.work:SetShown(not history)
    p.hist:SetShown(history)
    if history then
        local all = ns.Loot.Entries(st)
        local rows = ns.Loot.Nights(all, lootFilter, ns.Loot.NameOf, ns.Loot.ItemName)
        local shown = 0
        for _, r in ipairs(rows) do if not r.header then shown = shown + 1 end end
        p.history:SetItems(rows)
        p.histCount:SetText(shown == #all and (#all .. (#all == 1 and " item" or " items")) or (shown .. " of " .. #all .. " items"))
        p.histEmpty:SetShown(#all == 0)
        p.histEmpty:SetText("No loot recorded yet. It shows here when an officer charges DKP for an item.")
        return
    end
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

-- The history is just a list. Awarding needs the left column down to the
-- custom-award section, open or folded.
UI.Need("raid", function(p)
    if raidView == "history" or not RBAC.ICan("award") then return 150 end
    return 30 + 194 + p.customFold:Height() + 6
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
-- Groups in the order the rules apply: earn, spend, decay, then who stays.
local SETTING_GROUPS = {
    { key = "earn", title = "1. Earning DKP", rows = {
        { "onTime", "On-time bonus" }, { "fullRaid", "Full-raid bonus" },
        { "bossFarm", "Boss kill (farm)" }, { "bossProg", "Boss kill (progression)" } } },
    { key = "prices", title = "2. Loot prices", rows = {
        { "priceBis", "Price: best-in-slot" }, { "priceMajor", "Price: major upgrade" },
        { "priceMinor", "Price: minor upgrade" }, { "priceOff", "Price: off spec" } } },
    { key = "decay", title = "3. Decay", rows = { { "decayPct", "Decay %" } }, extra = 58 },
    { key = "people", title = "4. Inactivity and Initiate promotion", rows = {
        { "inactWatch", "Inactive days: Watch" }, { "inactInactive", "Inactive days: Inactive" },
        { "inactCleanup", "Inactive days: Cleanup" }, { "promoDays", "Initiate promo: days (0 = off)" },
        { "promoRaids", "Initiate promo: raids" } } },
}

UI.AddTab("settings", "Settings", "settings", function(p)
    local intro = W.Text(p, "Rules for this guild. DKP defaults follow a published example and inactivity days start at ForeverGuildManager's 30/60/90; set your own here.", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 0, 0)
    intro:SetWidth(700)
    p.edits, p.folds = {}, {}
    -- The groups stack; opening one closes the others, so the tab always fits.
    function p.place()
        local y = -34
        for _, f in ipairs(p.folds) do
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", 0, y)
            y = y - f:Height() - 6
        end
        p.save:ClearAllPoints()
        p.save:SetPoint("TOPLEFT", 0, y - 6)
    end
    for gi, g in ipairs(SETTING_GROUPS) do
        local lines = math.ceil(#g.rows / 2)
        local fold
        fold = W.Accordion(p, g.title, 700, lines * 30 + (g.extra or 0), "settings_" .. g.key, function(open)
            if open then
                for _, other in ipairs(p.folds) do
                    if other ~= fold and other.open then other:SetOpen(false, true) end
                end
            end
            p.place()
        end, gi == 1)
        p.folds[gi] = fold
        p[g.key .. "Fold"] = fold
        for i, r in ipairs(g.rows) do
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            local fs = W.Text(fold.body, r[2], "GameFontHighlight")
            fs:SetPoint("TOPLEFT", col * 350 + 4, -6 - row * 30)
            local e = W.Edit(fold.body, 60, 5)
            e:SetPoint("TOPLEFT", col * 350 + 224, -2 - row * 30)
            p.edits[r[1]] = e
        end
    end
    -- Only one group may start open, whatever was saved.
    local seen = false
    for _, f in ipairs(p.folds) do
        if f.open and seen then f:SetOpen(false, true) end
        seen = seen or f.open
    end
    p.save = W.Button(p, "Save settings", 140, 22, function()
        local values = {}
        for key, e in pairs(p.edits) do values[key] = e:GetText() end
        UI.Try("Settings saved and shared with the guild.", ns.DKP.SaveSettings, values)
    end, "accent")
    -- Decay touches every balance, so it takes two clicks.
    local db = p.decayFold.body
    p.armed = -10
    p.decay = W.Button(db, "Run decay now", 170, 22, function()
        if GetTime() - p.armed > 5 then
            p.armed = GetTime()
            p.decay:SetText("Click again to confirm")
            UI.Say("Decay lowers every positive balance. Click again within 5 seconds to confirm.")
            return
        end
        p.armed = -10
        UI.Try("Decay applied to every balance.", ns.DKP.Decay)
    end)
    p.decay:SetPoint("TOPLEFT", 4, -34)
    p.undoDecay = W.Button(db, "Undo last decay", 140, 22, function()
        UI.Try("The last decay was undone for everyone.", ns.DKP.UndoDecay)
    end)
    p.undoDecay:SetPoint("LEFT", p.decay, "RIGHT", 8, 0)
    p.last = W.Text(db, "", "GameFontDisableSmall")
    p.last:SetPoint("TOPLEFT", 4, -64)
    p.place()
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

-- The groups, whichever is open, and the Save button under them.
UI.Need("settings", function(p)
    local h = 34
    for _, f in ipairs(p.folds) do h = h + f:Height() + 6 end
    return h + 6 + 22 + 8
end)
