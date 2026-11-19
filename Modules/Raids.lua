-- Blood Pact: raid sign-ups and attendance.
-- Team Captains and above schedule raids and take attendance; everyone signs up.
-- Everything is a log event, so it syncs like DKP and no website is needed.
-- Raid nights are grouped by a shared "raid day" so officers in different
-- time zones agree (see Time.RaidDay).
local _, ns = ...
local R = {}
ns.Raids = R

local Log, Red, RBAC = ns.Log, ns.Reducer, ns.RBAC
local date, time = date or os.date, time or os.time   -- WoW globals; os.* for tests

R.PRESETS = {
    { label = "Barrow Deeps", raid = "Barrow Deeps", size = 10 },
    { label = "Hyjal Summit", raid = "Hyjal Summit", size = 20 },
}
R.ROLE_LABEL = { tank = "Tank", healer = "Healer", dps = "DPS" }
R.STATUS_LABEL = { yes = "Coming", maybe = "Maybe", no = "Can't" }

R.RaidDay = ns.Time.RaidDay

-- "8pm", "8:30 PM" or "20:00" -> hour, minute.
function R.ParseClock(text)
    local s = tostring(text or ""):lower():gsub("%s+", ""):gsub("%.", "")
    local h, mi, ap = s:match("^(%d%d?):(%d%d)([ap]?)m?$")
    if not h then
        h, ap = s:match("^(%d%d?)([ap])m?$")
        mi = "0"
    end
    if not h then return nil end
    h, mi = tonumber(h), tonumber(mi)
    if ap ~= "" then
        if h < 1 or h > 12 then return nil end
        if ap == "p" and h < 12 then h = h + 12 elseif ap == "a" and h == 12 then h = 0 end
    end
    if h > 23 or mi > 59 then return nil end
    return h, mi
end

-- "2026-12-09", "12/9" or "12/9/2026" -> year, month, day. A date without a
-- year means the next time that date comes around.
function R.ParseDay(text, now)
    local s = tostring(text or ""):gsub("%s+", "")
    local y, mo, d = s:match("^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$")
    if not y then
        mo, d, y = s:match("^(%d%d?)/(%d%d?)/(%d%d%d?%d?)$")
    end
    if not y then
        mo, d = s:match("^(%d%d?)/(%d%d?)$")
    end
    if not mo then return nil end
    mo, d = tonumber(mo), tonumber(d)
    if y then
        y = tonumber(y)
        if y < 100 then y = y + 2000 end
    else
        y = tonumber(date("!%Y", now))
        if ns.Time.Civil(y, mo, d, 23, 59) < now - 2 * 86400 then y = y + 1 end
    end
    if mo < 1 or mo > 12 or d < 1 then return nil end
    local nextMonthY, nextMonth = y, mo + 1
    if nextMonth == 13 then nextMonthY, nextMonth = y + 1, 1 end
    local daysInMonth = ns.Time.DaysFromCivil(nextMonthY, nextMonth, 1) - ns.Time.DaysFromCivil(y, mo, 1)
    if d > daysInMonth then return nil end
    return y, mo, d
end

-- A typed date and time in a zone (ET/CT/MT/AZ/PT, or "LOCAL" for your PC
-- clock) -> server unix time.
function R.ParseWhen(day, clock, zone)
    local now = ns.Now()
    local y, mo, d = R.ParseDay(day, now)
    local h, mi = R.ParseClock(clock)
    if not y or not h then return nil end
    if zone and zone ~= "LOCAL" then return ns.Time.FromZone(zone, y, mo, d, h, mi) end
    local t = time({ year = y, month = mo, day = d, hour = h, min = mi, sec = 0 })
    -- Local clock -> server clock, in case the PC clock is off.
    return t and (t + (now - time())) or nil
end

function R.Create(title, raid, day, clock, size, note, zone, prog)
    if not RBAC.ICan("schedule") then return nil, "Only Team Captains and above can schedule raids." end
    title = tostring(title or ""):match("^%s*(.-)%s*$")
    if title == "" then title = raid end
    if not raid or raid == "" then return nil, "Pick Barrow Deeps or Hyjal Summit first." end
    local at = R.ParseWhen(day, clock, zone)
    if not at then return nil, "Date like 12/9 or 2026-12-09, and time like 8pm, 8:30pm or 20:00." end
    if at < ns.Now() - 3600 then return nil, "That time has already passed." end
    size = tonumber(size)
    if not size or size < 5 or size > 40 or size ~= math.floor(size) then return nil, "Raid size 5 to 40." end
    return Log.New("RAID", { title = title:sub(1, 40), raid = raid:sub(1, 30), at = at, size = size,
        n = note and note ~= "" and note:sub(1, Log.MAX_NOTE) or nil,
        tz = zone ~= "LOCAL" and zone or nil, prog = prog and true or false })
end

function R.Cancel(id)
    if not RBAC.ICan("schedule") then return nil, "Only Team Captains and above can cancel raids." end
    return Log.New("RAID_CANCEL", { ev = id })
end

function R.SignUp(id, status, role)
    if not RBAC.ICan("signup") then return nil, "You need to be in the guild to sign up." end
    local st = Red.State()
    local r = st and st.raids[id]
    if r and (r.cancelled or r.at < ns.Now() - 6 * 3600) then return nil, "That raid is over." end
    local mine = r and r.signups[ns.MyGUID()]
    if mine and mine.st == status and mine.role == role then return nil, "That's already your answer." end
    return Log.New("SIGNUP", { ev = id, st = status, role = role })
end

function R.TakeAttendance(reason)
    if not RBAC.ICan("schedule") then return nil, "Only Team Captains and above take attendance." end
    local who = ns.DKP.GroupGUIDs()
    if #who < 2 and not ns.mock then return nil, "Get the raid together first." end
    local now = ns.Now()
    -- A boss kill is one record per raid night however many leaders log it;
    -- a manual check is one per minute.
    local idem = (reason or "manual") .. ":" .. (reason == "manual" and date("!%Y-%m-%d %H:%M", now) or R.RaidDay(now))
    local last
    for i = 1, #who, 60 do
        local slice = {}
        for j = i, math.min(i + 59, #who) do slice[#slice + 1] = who[j] end
        local e, why = Log.New("ATTEND", { who = slice, day = R.RaidDay(now), idem = idem .. ":" .. i })
        if not e then return nil, why end
        last = e
    end
    return last, #who
end

-- Boss kills while you lead the raid record attendance too.
ns.On("ENCOUNTER_END", function(encounterID, _, _, _, success)
    if not (success == 1 or success == true) then return end
    if not RBAC.ICan("schedule") then return end
    -- Raids only (dungeon bosses fire this too), from the leader or an assistant.
    if not ns.mock then
        if not IsInRaid() then return end
        if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then return end
    end
    R.TakeAttendance("boss" .. tostring(encounterID))
end)

-- Raids from a week ago onward, soonest first. Pure: takes the state and now.
function R.List(st, now)
    local out = {}
    for _, r in pairs(st and st.raids or {}) do
        if not r.cancelled and r.at >= now - 7 * 86400 then out[#out + 1] = r end
    end
    table.sort(out, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.id < b.id
    end)
    return out
end

-- Head counts and rows for one raid. present = attendance for that raid night.
function R.Summary(st, r)
    local c = { yes = 0, maybe = 0, no = 0, tank = 0, healer = 0, dps = 0 }
    local rows = {}
    local present = st.attendDays[R.RaidDay(r.at)]
    for guid, s in pairs(r.signups) do
        c[s.st] = c[s.st] + 1
        if s.st == "yes" and s.role then c[s.role] = c[s.role] + 1 end
        rows[#rows + 1] = { guid = guid, st = s.st, role = s.role,
            showed = present and present[guid] or nil, name = ns.NameForGUID and ns.NameForGUID(guid) or guid }
    end
    local order = { yes = 1, maybe = 2, no = 3 }
    table.sort(rows, function(a, b)
        if a.st ~= b.st then return order[a.st] < order[b.st] end
        return tostring(a.name) < tostring(b.name)
    end)
    return c, rows
end

-- The raid happening now: started up to 6 hours ago, or starting within the hour.
function R.Current(st, now)
    local best
    for _, r in pairs(st and st.raids or {}) do
        if not r.cancelled and r.at - 3600 <= now and now <= r.at + 6 * 3600 then
            if not best or math.abs(r.at - now) < math.abs(best.at - now) then best = r end
        end
    end
    return best
end

-- Reminders that are due for you: 30 and 15 minutes before raids you said
-- yes or maybe to. Pure: done = { [raidId..":30"] = true, ... }.
function R.DueReminders(st, me, now, done)
    local out = {}
    for _, r in pairs(st and st.raids or {}) do
        local s = r.signups[me]
        if not r.cancelled and s and s.st ~= "no" then
            local left = r.at - now
            for _, mark in ipairs({ 30, 15 }) do
                local key = r.id .. ":" .. mark
                if left <= mark * 60 and left > (mark - 15) * 60 and not done[key] then
                    out[#out + 1] = { raid = r, mark = mark, key = key }
                    break
                end
            end
        end
    end
    return out
end

-- Text for a raid time: your PC time, plus the time zone it was scheduled in.
function R.When(r, fmt)
    local mine = date(fmt or "%a %b %d  %I:%M %p", r.at)
    if r.tz then
        local theirs = ns.Time.Format(r.tz, r.at)
        if theirs then mine = mine .. "  (" .. theirs .. ")" end
    end
    return mine
end

---------------------------------------------------------------------------
-- Raids tab (everyone; scheduling for Team Captain and above)
---------------------------------------------------------------------------
local W, U = ns.W, ns.U
local selected

local function charStore()
    local guid = ns.MyGUID()
    if not guid or not ns.db then return {} end
    ns.db.chars = ns.db.chars or {}
    ns.db.chars[guid] = ns.db.chars[guid] or {}
    return ns.db.chars[guid]
end


ns.UI.AddTab("raids", "Raids", "view", function(p)
    local h = W.Text(p, "Raids (shown in your PC's time)", "GameFontNormal")
    h:SetPoint("TOPLEFT", 0, 0)
    p.list = W.List(p, 300, 180, 18, function(row, r)
        local past = r.at < ns.Now() - 6 * 3600
        local c = R.Summary(Red.State(), r)
        p.list.Col(row, 1, 4, 130):SetText((past and "|cff808080" or "") .. date("%a %b %d  %I:%M %p", r.at))
        p.list.Col(row, 2, 136, 110):SetText(U.Safe(r.title, 30))
        p.list.Col(row, 3, 248, 50):SetText(c.yes .. "/" .. r.size)
    end, function(r) selected = r.id; ns.UI.Refresh() end)
    p.list.scroll:SetPoint("TOPLEFT", 0, -18)
    p.list.key = "id"

    -- Right side: selected raid
    p.title = W.Text(p, "", "GameFontNormal")
    p.title:SetPoint("TOPLEFT", 330, 0)
    p.title:SetWidth(320)
    p.info = W.Text(p, "", "GameFontHighlightSmall")
    p.info:SetPoint("TOPLEFT", 330, -18)
    p.info:SetWidth(320)
    p.info:SetWordWrap(false)
    p.when = W.Text(p, "", "GameFontHighlightSmall")
    p.when:SetPoint("TOPLEFT", 330, -34)
    p.when:SetWidth(360)
    p.when:SetWordWrap(false)
    p.counts = W.Text(p, "", "GameFontHighlightSmall")
    p.counts:SetPoint("TOPLEFT", 330, -50)
    p.counts:SetWidth(360)
    p.mine = W.Text(p, "", "GameFontNormalSmall")
    p.mine:SetPoint("TOPLEFT", 330, -68)
    p.mine:SetWidth(360)
    local btns = {
        { "Tank", "yes", "tank" }, { "Healer", "yes", "healer" }, { "DPS", "yes", "dps" },
        { "Maybe", "maybe" }, { "Can't", "no" },
    }
    p.signButtons = {}
    for i, b in ipairs(btns) do
        local btn = W.Button(p, b[1], 62, 22, function()
            if not selected then return end
            if b[3] then charStore().role = b[3] end
            local role = b[3] or charStore().role
            local ok = ns.UI.Try("Signed up: " .. R.STATUS_LABEL[b[2]] .. (b[2] == "yes" and (" as " .. R.ROLE_LABEL[role]) or "") .. ".",
                R.SignUp, selected, b[2], role)
            local r = ok and Red.State().raids[selected]
            if r and ns.Calendar then ns.Calendar.Respond(r, b[2]) end
        end)
        btn:SetPoint("TOPLEFT", 330 + (i - 1) * 64, -88)
        p.signButtons[i] = btn
    end
    p.people = W.List(p, 320, 92, 16, function(row, s)
        p.people.Col(row, 1, 4, 140):SetText(U.Safe(s.name or "?", 40))
        p.people.Col(row, 2, 146, 80):SetText(R.STATUS_LABEL[s.st] .. (s.role and (" " .. R.ROLE_LABEL[s.role]) or ""))
        p.people.Col(row, 3, 230, 86):SetText(s.showed and "|cff40ff40was there|r" or "")
    end)
    p.people.scroll:SetPoint("TOPLEFT", 330, -116)

    -- Scheduling (Team Captain and above)
    local s = CreateFrame("Frame", nil, p)
    s:SetPoint("TOPLEFT", 0, -214)
    s:SetSize(660, 140)
    p.sched = s
    W.Text(s, "Schedule a raid", "GameFontNormal"):SetPoint("TOPLEFT", 0, 0)
    W.Text(s, "Title", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 0, -24)
    s.titleBox = W.Edit(s, 150, 40)
    s.titleBox:SetPoint("TOPLEFT", 40, -20)
    s.raid, s.size = nil, nil
    s.presetButtons = {}
    for i, pr in ipairs(R.PRESETS) do
        local b = W.Button(s, pr.label .. " (" .. pr.size .. ")", 130, 22, function()
            s.raid = pr.raid
            s.sizeBox:SetText(tostring(pr.size))
            for j, other in ipairs(s.presetButtons) do other:SetEnabled(j ~= i) end
        end)
        b:SetPoint("TOPLEFT", 200 + (i - 1) * 134, -20)
        s.presetButtons[i] = b
    end
    W.Text(s, "Date", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 0, -52)
    s.dayBox = W.Edit(s, 90, 10)
    s.dayBox:SetPoint("TOPLEFT", 40, -48)
    s.dayBox:SetText(date("%m/%d"))
    W.Text(s, "Time", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 140, -52)
    s.timeBox = W.Edit(s, 50, 5)
    s.timeBox:SetPoint("TOPLEFT", 172, -48)
    W.Text(s, "Size", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 232, -52)
    s.sizeBox = W.Edit(s, 30, 2)
    s.sizeBox:SetPoint("TOPLEFT", 262, -48)
    s.create = W.Button(s, "Create raid", 100, 22, function()
        local e = ns.UI.Try("Raid scheduled.", R.Create, s.titleBox:GetText(), s.raid,
            s.dayBox:GetText(), s.timeBox:GetText(), s.sizeBox:GetText(), nil,
            charStore().tz or "LOCAL", s.prog:GetChecked())
        if e then
            selected = e.id
            s.titleBox:SetText("")
            s.prog:SetChecked(false)
            ns.UI.Refresh()
            if ns.Calendar then ns.Calendar.Add(Red.State().raids[e.id] or { title = e.d.title, raid = e.d.raid, at = e.d.at, prog = e.d.prog }) end
        end
    end, "accent")
    s.create:SetPoint("TOPLEFT", 310, -48)
    local zones = { { key = "LOCAL", label = "My PC time" } }
    for _, z in ipairs(ns.Time.ZONES) do zones[#zones + 1] = z end
    local function zoneIndex()
        local saved = charStore().tz or "LOCAL"
        for i, z in ipairs(zones) do if z.key == saved then return i end end
        return 1
    end
    s.zone = W.Button(s, "", 110, 22, function()
        local i = zoneIndex() % #zones + 1
        charStore().tz = zones[i].key
        s.zone:SetText(zones[i].label)
    end)
    s.zone:SetPoint("TOPLEFT", 416, -48)
    s.zone:SetScript("OnShow", function() s.zone:SetText(zones[zoneIndex()].label) end)
    s.zone:SetText(zones[zoneIndex()].label)
    s.prog = W.Check(s, "Progression (boss kills pay progression DKP)")
    s.prog:SetPoint("TOPLEFT", 0, -72)
    W.Text(s, "Date like 12/9. Time like 8pm or 20:00. Click the zone button to change it.", "GameFontDisableSmall"):SetPoint("TOPLEFT", 300, -76)
    s.attend = W.Button(s, "Take attendance now", 160, 22, function()
        local e, n = R.TakeAttendance("manual")
        if e then ns.UI.Say(("Attendance taken: %d guild members."):format(n)) else ns.UI.Say(n or "That didn't work.") end
    end)
    s.attend:SetPoint("TOPLEFT", 0, -100)
    s.cancel = W.Button(s, "Cancel selected raid", 160, 22)
    s.cancel:SetScript("OnClick", ns.UI.Confirm(s.cancel, function()
        if not selected then return end
        if ns.UI.Try("Raid cancelled.", R.Cancel, selected) then selected = nil end
    end))
    s.cancel:SetPoint("TOPLEFT", 166, -100)
    s.whisper = W.Button(s, "Whisper sign-ups", 140, 22, function()
        local r = Red.State() and Red.State().raids[selected]
        if not r then return end
        local n, why = R.WhisperSignups(r)
        ns.UI.Say(n and ("Whispered %d raiders."):format(n) or why)
    end)
    s.whisper:SetPoint("TOPLEFT", 332, -100)
    W.Text(s, "Boss kills take attendance on their own while you lead.", "GameFontDisableSmall"):SetPoint("TOPLEFT", 0, -126)
end, function(p)
    local st = Red.State()
    local list = R.List(st, ns.Now())
    local found
    for _, r in ipairs(list) do if r.id == selected then found = r end end
    if not found then
        for _, r in ipairs(list) do
            if r.at >= ns.Now() - 6 * 3600 then found = r; break end
        end
        found = found or list[1]
    end
    selected = found and found.id or nil
    p.list.selected = found
    p.list:SetItems(list)
    p.sched:SetShown(RBAC.ICan("schedule"))
    local open = found ~= nil and found.at >= ns.Now() - 6 * 3600
    for _, b in ipairs(p.signButtons) do b:SetEnabled(open) end
    if not found then
        p.title:SetText("No raids scheduled yet.")
        p.info:SetText(RBAC.ICan("schedule") and "Schedule one below." or "A Team Captain or Officer schedules raids.")
        p.when:SetText("")
        p.counts:SetText("")
        p.mine:SetText("")
        p.people:SetItems({})
        return
    end
    local c, rows = R.Summary(st, found)
    p.title:SetText(U.Safe(found.title, 40))
    p.info:SetText(U.Safe(found.raid, 30) .. " (" .. found.size .. ")  -  " .. (found.prog and "|cffff8040Progression|r" or "Farm")
        .. (found.n and ("  -  " .. U.Safe(found.n, 60)) or ""))
    p.when:SetText(R.When(found))
    p.counts:SetText(("Coming %d/%d   Tanks %d  Healers %d  DPS %d   Maybe %d   Can't %d"):format(
        c.yes, found.size, c.tank, c.healer, c.dps, c.maybe, c.no))
    local mine = found.signups[ns.MyGUID()]
    if not open then
        p.mine:SetText("This raid is over.")
    elseif not mine then
        p.mine:SetText("You haven't answered yet. Pick one:")
    else
        p.mine:SetText("Your answer: " .. R.STATUS_LABEL[mine.st]
            .. (mine.st == "yes" and mine.role and (" as " .. R.ROLE_LABEL[mine.role]) or "") .. ". Click another to change it.")
    end
    p.people:SetItems(rows)
end)

---------------------------------------------------------------------------
-- Reminders on your own screen, and the leader's whisper button
---------------------------------------------------------------------------
local function remindersDone()
    local c = charStore()
    c.reminded = c.reminded or {}
    return c.reminded
end

local function alert(msg)
    ns.Print(msg)
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.3, b = 0.1 })
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
end

function R.CheckReminders()
    local st = Red.State()
    if not st then return end
    local done = remindersDone()
    -- Forget reminders for raids that are gone.
    for key in pairs(done) do
        local r = st.raids[(key:gsub(":%d+$", ""))]
        if not r or r.at < ns.Now() - 86400 then done[key] = nil end
    end
    for _, due in ipairs(R.DueReminders(st, ns.MyGUID(), ns.Now(), done)) do
        done[due.key] = true
        local r = due.raid
        if due.mark == 30 then
            alert(("%s starts in 30 minutes (%s). Get ready and be there by %s."):format(
                U.Safe(r.title, 40), date("%I:%M %p", r.at), date("%I:%M %p", r.at - 900)))
        else
            alert(("%s starts in 15 minutes. Head to the raid now."):format(U.Safe(r.title, 40)))
        end
    end
end

ns.On("PLAYER_LOGIN", function()
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(30, R.CheckReminders) end
end)

-- One click by a Team Captain or above: whisper everyone who said yes or maybe
-- and is online. Only ever sent from that click, never on a timer.
function R.WhisperSignups(r)
    if not RBAC.ICan("schedule") then return nil, "Only Team Captains and above can do this." end
    local mins = math.floor((r.at - ns.Now()) / 60 + 0.5)
    local msg = mins > 0
        and ("Blood Pact: %s starts in %d minutes. Get ready, and please be there 15 minutes early."):format(r.title, mins)
        or ("Blood Pact: %s is starting. Please head to the raid now."):format(r.title)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local names = {}
    for guid, s in pairs(r.signups) do
        local m = ns.roster.byGUID[guid]
        if s.st ~= "no" and guid ~= ns.MyGUID() and m and m.online and #names < 40 then
            names[#names + 1] = ns.U.ShortName(m.name)
        end
    end
    if #names == 0 then return nil, "Nobody who signed up is online." end
    if ns.mock then return #names end   -- test mode never whispers anyone
    -- Spaced out so the chat server doesn't drop them.
    for i, name in ipairs(names) do
        C_Timer.After((i - 1) * 0.3, function() pcall(send, msg, "WHISPER", nil, name) end)
    end
    return #names
end
