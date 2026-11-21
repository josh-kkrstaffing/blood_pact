-- Blood Pact: Recruit tab (Team Captain and above).
-- Never whispers or invites by itself: every search and every whisper is one
-- click by the recruiter, to one player. WoW Forever forbids addon and macro
-- guild invites, and /who needs a click per search, so:
--   1. pick a message (Social, Raiding or Crafting)
--   2. Scan my zone, one of my faction's starting zones, or every zone for a
--      level range (always one /who per click)
--   3. click a name: that player is whispered the picked message, once
--      (right-click opens a whisper to type your own)
--   4. when they reply "inv", their name is listed under step 3 exactly as
--      the game spells it; a click puts "/ginvite <name>" in a copy box, and
--      the recruiter copies it and pastes it into chat themselves (or
--      right-clicks the name in chat > Guild Invite)
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

-- Searching every zone for a level range. The game answers one search with
-- about 50 players at most, guilded ones included, and has no "no guild"
-- filter. So a range is worked through as a queue of searches, one per
-- click, from the top down:
--   1. the range is cut into bands of a few levels;
--   2. a band whose answer was cut short is split in half, down to one level;
--   3. a single level that is still cut short is searched class by class.
-- A band that came back whole is finished and never searched again.
R.MAX_LEVEL = 60
R.SWEEP_BAND = 5
R.CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }

-- The level boxes as typed -> from, to (1..60, in order), or nil and what to fix.
function R.LevelRange(from, to)
    from, to = tonumber(from), tonumber(to)
    if not from or not to then return nil, "Type a level in both boxes, from 1 to " .. R.MAX_LEVEL .. "." end
    from, to = math.floor(from), math.floor(to)
    if from > to then from, to = to, from end
    if from < 1 or to > R.MAX_LEVEL then return nil, "Levels run from 1 to " .. R.MAX_LEVEL .. "." end
    return from, to
end

-- The first queue for a range: bands of R.SWEEP_BAND levels.
function R.SweepPlan(from, to)
    local queue = {}
    local lo = from
    while lo <= to do
        local hi = math.min(to, lo + R.SWEEP_BAND - 1)
        queue[#queue + 1] = { lo = lo, hi = hi }
        lo = hi + 1
    end
    return queue
end

-- A search whose answer was cut short, as smaller searches; nil when it
-- can't be made any smaller (one level of one class).
function R.SweepSplit(step)
    if step.class then return nil end
    if step.lo < step.hi then
        local mid = math.floor((step.lo + step.hi) / 2)
        return { { lo = step.lo, hi = mid }, { lo = mid + 1, hi = step.hi } }
    end
    local out = {}
    for i, class in ipairs(R.CLASSES) do out[i] = { lo = step.lo, hi = step.hi, class = class } end
    return out
end

-- The /who text for one search of every zone.
function R.SweepQuery(step)
    return (step.class and ('c-"' .. step.class .. '" ') or "") .. step.lo .. "-" .. step.hi
end

function R.SweepLabel(step)
    local levels = step.lo == step.hi and ("level " .. step.lo) or ("levels " .. step.lo .. "-" .. step.hi)
    return step.class and (levels .. " " .. step.class .. "s") or levels
end

-- Take in the answer to the search at the head of the queue.
--   sweep = { from, to, queue, done }   cut = the game listed fewer than it found
-- -> "split" (it will be searched in smaller pieces), "short" (cut short and
--    can't be made smaller) or "ok"
function R.SweepAdvance(sweep, cut)
    local step = table.remove(sweep.queue, 1)
    sweep.done = sweep.done + 1
    if not cut or not step then return "ok" end
    local parts = R.SweepSplit(step)
    if not parts then return "short" end
    for i = #parts, 1, -1 do table.insert(sweep.queue, 1, parts[i]) end
    return "split"
end

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
local scan = {}            -- the search in flight: { zone =, band = } (band nil = my own zone), or { sweep = true }
local sweep                -- the all-zones search in progress: { from, to, queue, done }
R.Sweep = function() return sweep end
local lastScan = -100

-- Open a whisper to a player. With text, the message is typed into it so the
-- recruiter only has to press Enter.
local function openWhisper(name, text)
    local sendTell = ChatFrame_SendTell or (ChatFrameUtil and ChatFrameUtil.SendTell)
    if not sendTell then ns.UI.Say("Type /w " .. name .. " then paste your message.") return false end
    sendTell(name)
    if not text then return false end
    local getActive = ChatEdit_GetActiveWindow or (ChatFrameUtil and ChatFrameUtil.GetActiveWindow)
    if getActive then
        local ok, box = pcall(getActive)
        if ok and type(box) == "table" and type(box.Insert) == "function" and pcall(box.Insert, box, text) then return true end
    end
    return false
end

-- Is this whisper someone asking for a guild invite? "inv", "invite",
-- "inv please", "Invite me!". Long messages and other words are not.
function R.IsInviteReply(text)
    if type(text) ~= "string" then return false end
    local t = text:lower():match("^%s*(.-)%s*$")
    if #t > 30 then return false end
    local first = t:match("^(%a+)")
    return first == "inv" or first == "invite"
end

-- Players who asked for an invite since login, newest first. Not saved.
R.replies = {}
R.MAX_REPLIES = 50

-- -> the entry, and whether it is new
function R.AddReply(list, name, text, now)
    for _, r in ipairs(list) do
        if r.name == name then return r, false end
    end
    local r = { name = name, text = text, at = now }
    table.insert(list, 1, r)
    while #list > R.MAX_REPLIES do table.remove(list) end
    return r, true
end

-- The guild invite as the player would type it, with the name spelled
-- exactly as the game sent it. Blood Pact only offers it for copying: the
-- game refuses a guild invite whose chat line an addon wrote or touched
-- ("blocked from an action only available to the Blizzard UI"), so the
-- player copies it here and pastes it into chat themselves.
function R.InviteCommand(name)
    return "/ginvite " .. U.ShortName(name)
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
    local ok, why = ns.Chat(text, "WHISPER", U.ShortName(name))
    if not ok then return nil, why == "locked" and ns.CHAT_LOCKED or "The game didn't send it." end
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

    -- The message itself is read once and rarely edited, so it folds away
    -- and the scan and reply lists get the room. Steps 2 and 3 move with it.
    function p.place()
        local top = -48 - p.msgFold:Height() - 10
        p.step2:ClearAllPoints()
        p.step2:SetPoint("TOPLEFT", 0, top)
        p.list:Stretch(0, top - 104, 0, 122)
    end
    p.msgFold = W.Accordion(p, "Read or edit the message", 640, 98, "recruitMsg", function() p.place() end)
    p.msgFold:SetPoint("TOPLEFT", 0, -48)
    local mb = p.msgFold.body
    local bg = CreateFrame("Frame", nil, mb)
    bg:SetPoint("TOPLEFT", 0, 0)
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

    local hint = W.Text(mb, "This is what a click on a name sends. You can edit it first.", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 0, -78)
    p.saveMsg = W.Button(mb, "Save as guild message", 170, 20, function()
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
    p.saveMsg:SetPoint("TOPRIGHT", 0, -76)

    -- Step 2: its heading, the scan button and the starting zones move as one block.
    local s2 = CreateFrame("Frame", nil, p)
    s2:SetSize(700, 100)
    p.step2 = s2
    local h2 = W.Text(s2, "2. Scan for unguilded players, then click a name to whisper them the picked message", "GameFontNormal")
    h2:SetPoint("TOPLEFT", 0, 0)
    -- One /who per click. zone = nil searches where I am standing.
    local function search(zone)
        -- The tab is hidden below Team Captain; this holds even if it is somehow open.
        if not ns.RBAC.ICan("recruit") then ns.UI.Say("Your guild rank can't recruit.") return end
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
        if p.sweepLabel then p.sweepLabel() end
        if C_FriendList.SetWhoToUi then C_FriendList.SetWhoToUi(true) end
        C_FriendList.SendWho(R.Query(zone, band and R.BANDS[band]))
        p.found:SetText(band and ("Searching %s, levels %d-%d..."):format(U.Safe(zone, 40), R.BANDS[band][1], R.BANDS[band][2])
            or ("Searching " .. U.Safe(zone, 40) .. "..."))
        p.list:SetItems(candidates)
    end
    p.scan = W.Button(s2, "Scan my zone", 130, 22, function() search(nil) end)
    p.scan:SetPoint("TOPLEFT", 0, -20)
    p.found = W.Text(s2, "", "GameFontDisableSmall")
    p.found:SetPoint("LEFT", p.scan, "RIGHT", 10, 0)

    -- My faction's starting zones, grouped by region.
    local faction = "Horde"
    if UnitFactionGroup then
        local ok, f = pcall(UnitFactionGroup, "player")
        if ok and R.STARTER[f] then faction = f end
    end
    local x = 0
    local lead = W.Text(s2, "Starter zones", "GameFontHighlightSmall")
    lead:SetPoint("TOPLEFT", x, -52)
    x = x + 78
    p.zoneButtons = {}
    for _, group in ipairs(R.Regions(faction)) do
        local label = W.Text(s2, group.region .. ":", "GameFontDisableSmall")
        label:SetPoint("TOPLEFT", x, -52)
        x = x + 6 * #group.region + 12
        for _, zone in ipairs(group.zones) do
            local width = 6 * #zone + 20
            local b = W.Button(s2, zone, width, 20, function() search(zone) end)
            b:SetPoint("TOPLEFT", x, -48)
            p.zoneButtons[#p.zoneButtons + 1] = b
            x = x + width + 4
        end
        x = x + 8
    end

    -- Every zone, for a level range. Each click runs the next search in the queue.
    local function sweepNext()
        if not ns.RBAC.ICan("recruit") then ns.UI.Say("Your guild rank can't recruit.") return end
        local from, to = R.LevelRange(p.lvFrom:GetText(), p.lvTo:GetText())
        if not from then ns.UI.Say(to) return end
        if GetTime() - lastScan < R.WAIT then
            ns.UI.Say("The game allows one search every few seconds. Try again in a moment.")
            return
        end
        -- A new range, or a finished one, starts a fresh list.
        if not sweep or sweep.from ~= from or sweep.to ~= to or #sweep.queue == 0 or not scan.sweep then
            sweep = { from = from, to = to, queue = R.SweepPlan(from, to), done = 0 }
            wipe(candidates)
        end
        local step = sweep.queue[1]
        lastScan = GetTime()
        scan = { sweep = true }
        if C_FriendList.SetWhoToUi then C_FriendList.SetWhoToUi(true) end
        C_FriendList.SendWho(R.SweepQuery(step))
        p.found:SetText("Searching every zone, " .. R.SweepLabel(step) .. "...")
        p.list:SetItems(candidates)
    end
    local allLead = W.Text(s2, "All zones", "GameFontHighlightSmall")
    allLead:SetPoint("TOPLEFT", 0, -80)
    local lvLabel = W.Text(s2, "Levels", "GameFontDisableSmall")
    lvLabel:SetPoint("TOPLEFT", 78, -80)
    p.lvFrom = W.Edit(s2, 34, 2)
    p.lvFrom:SetPoint("TOPLEFT", 122, -76)
    p.lvFrom:SetText("10")
    local lvTo = W.Text(s2, "to", "GameFontDisableSmall")
    lvTo:SetPoint("TOPLEFT", 164, -80)
    p.lvTo = W.Edit(s2, 34, 2)
    p.lvTo:SetPoint("TOPLEFT", 182, -76)
    p.lvTo:SetText(tostring(R.MAX_LEVEL))
    p.sweepBtn = W.Button(s2, "Scan these levels", 210, 20, sweepNext)
    p.sweepBtn:SetPoint("TOPLEFT", 226, -76)
    p.sweepNote = W.Text(s2, "One search per click. Busy levels are split up automatically.", "GameFontDisableSmall")
    p.sweepNote:SetPoint("LEFT", p.sweepBtn, "RIGHT", 10, 0)
    -- What the next click will search.
    function p.sweepLabel()
        local from, to = R.LevelRange(p.lvFrom:GetText(), p.lvTo:GetText())
        if sweep and scan.sweep and #sweep.queue > 0 and sweep.from == from and sweep.to == to then
            p.sweepBtn:SetText(("Next: %s (%d left)"):format(R.SweepLabel(sweep.queue[1]), #sweep.queue))
        else
            p.sweepBtn:SetText("Scan these levels")
        end
    end
    p.lvFrom:HookScript("OnTextChanged", function() p.sweepLabel() end)
    p.lvTo:HookScript("OnTextChanged", function() p.sweepLabel() end)

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
            -- Not sent: open a whisper to them with the message typed in, for the recruiter to send.
            local typed = openWhisper(item.name, p.box:GetText())
            ns.UI.Say((why or "That didn't work.") .. (typed and " The message is typed in a whisper to " .. who .. ": press Enter to send it."
                or " A whisper to " .. who .. " is open: paste the message and press Enter."))
        end
        p.list.Update()
    end)
    p.place()

    -- Step 3: who replied "inv". A click puts the invite in a copy box with
    -- the name spelled exactly; the recruiter copies it and pastes it in chat.
    p.h3 = W.Text(p, "", "GameFontNormal")
    p.h3:SetPoint("BOTTOMLEFT", 0, 100)
    local copying          -- the reply whose invite is in the copy box
    p.replies = W.List(p, 620, 72, 18, function(row, r)
        p.replies.Col(row, 1, 4, 220):SetText(U.Safe(r.name, 40))
        p.replies.Col(row, 2, 230, 200):SetText("|cffaaaaaareplied: " .. U.Safe(r.text, 30) .. "|r")
        p.replies.Col(row, 3, 436, 180):SetText(r.copied and "|cff40ff40copied: paste it in chat|r"
            or (r == copying and "|cff40c0ffpress Ctrl+C|r" or "|cffffd100click to copy the invite|r"))
    end, function(r, button)
        if not r then return end
        if button == "RightButton" then
            for i, x in ipairs(R.replies) do
                if x == r then table.remove(R.replies, i); break end
            end
            if copying == r then copying = nil; p.copy:SetText("") end
            ns.UI.Refresh()
            return
        end
        copying = r
        p.copy:SetText(R.InviteCommand(r.name))
        p.copy:SetFocus()
        p.copy:HighlightText()
        ns.UI.Say("Press Ctrl+C to copy the invite for " .. U.Safe(U.ShortName(r.name), 40) .. ". Then in chat: Enter, Ctrl+V, Enter.")
        p.replies.Update()
    end)
    p.replies.scroll:SetPoint("BOTTOMLEFT", 0, 26)
    -- The copy box. Its text can't be edited, only selected and copied.
    p.copy = W.Edit(p, 300, 80)
    p.copy:SetPoint("BOTTOMLEFT", 0, 0)
    p.copy:SetScript("OnTextChanged", function(self, byUser)
        local want = copying and R.InviteCommand(copying.name) or ""
        if byUser and self:GetText() ~= want then
            self:SetText(want)
            self:HighlightText()
        end
    end)
    p.copy:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    p.copy:SetScript("OnMouseUp", function(self) self:SetFocus(); self:HighlightText() end)
    -- Ctrl+C (Cmd+C on a Mac): the game has copied it; let go of the keyboard
    -- so the next Enter opens chat.
    p.copy:SetScript("OnKeyDown", function(self, key)
        if key ~= "C" or not copying then return end
        if not ((IsControlKeyDown and IsControlKeyDown()) or (IsMetaKeyDown and IsMetaKeyDown())) then return end
        local r = copying
        C_Timer.After(0.15, function()
            r.copied = true
            self:ClearFocus()
            ns.UI.Say("Copied. In chat: press Enter, Ctrl+V, then Enter to send the invite.")
            p.replies.Update()
        end)
    end)
    local h4 = W.Text(p, "Click a name, press Ctrl+C, then in chat: Enter, Ctrl+V, Enter. Right-click a name to remove it.", "GameFontDisableSmall")
    h4:SetPoint("LEFT", p.copy, "RIGHT", 10, 0)
    ns.recruitPanel = p
end, function(p)
    p.saveMsg:SetShown(ns.RBAC.ICan("recruitEdit"))
    for i, b in ipairs(p.msgButtons) do b:SetEnabled(i ~= current) end      -- the picked one is marked
    p.msgFold.note:SetText(LABELS[current] .. " message picked")
    -- Anyone who has joined since is done.
    for i = #R.replies, 1, -1 do
        if ns.GUIDForName(U.ShortName(R.replies[i].name)) then table.remove(R.replies, i) end
    end
    p.h3:SetText(#R.replies > 0 and ("3. They replied (%d). Click a name to copy their guild invite"):format(#R.replies)
        or "3. When someone replies 'inv', their name shows here ready to invite")
    p.replies:SetItems(R.replies)
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
    if scan.sweep and sweep then
        -- One search of the all-zones queue came back.
        local step = sweep.queue[1]
        local isCut = type(total) == "number" and total > shown
        R.Merge(candidates, results)
        table.sort(candidates, function(a, b)
            if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
            return a.name < b.name
        end)
        local how = R.SweepAdvance(sweep, isCut)
        local text = ("%d unguilded so far. %s searched%s"):format(#candidates, step and R.SweepLabel(step) or "that",
            how == "split" and ": too many players for one search, so it is split into smaller ones." or
            (how == "short" and (": the game listed only %d of %d."):format(shown, total) or "."))
        if #sweep.queue > 0 then
            text = text .. (" Click again for %s."):format(R.SweepLabel(sweep.queue[1]))
        else
            text = ("Done. %d unguilded found in every zone, levels %d-%d."):format(#candidates, sweep.from, sweep.to)
        end
        p.found:SetText(text)
        p.sweepLabel()
        p.list:SetItems(candidates)
        return
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

-- A whisper asking for an invite, from someone who isn't in the guild, goes on
-- the list under step 3 with the name exactly as the game sent it.
ns.On("CHAT_MSG_WHISPER", function(text, sender, _, _, _, _, _, _, _, _, _, guid)
    if not ns.RBAC.ICan("recruit") or not R.IsInviteReply(text) then return end
    if type(sender) ~= "string" or sender == "" then return end
    if (guid and ns.roster.byGUID[guid]) or ns.GUIDForName(U.ShortName(sender)) then return end
    local _, new = R.AddReply(R.replies, sender, text:match("^%s*(.-)%s*$"), ns.Now())
    if not new then return end
    ns.Print(("%s asked for a guild invite. Type /bp, open Recruit and click their name."):format(U.Safe(U.ShortName(sender), 40)))
    if ns.UI and ns.UI.IsOpen and ns.UI.IsOpen() then ns.UI.RefreshSoon() end
end)

-- Room the tab needs: the message buttons, the message (open or folded),
-- the scan row, a few names, and the replies at the bottom.
ns.UI.Need("recruit", function(p)
    return 48 + p.msgFold:Height() + 10 + 104 + 58 + 122
end)
