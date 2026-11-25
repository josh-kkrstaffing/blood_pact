-- Blood Pact: raid sign-ups and attendance.
-- Team Captains and above schedule raids and take attendance; everyone signs up.
-- Signing up asks for a spot. A Team Captain or above selects who gets one.
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
    { label = "Onyxia's Lair", raid = "Onyxia's Lair", size = 40 },
}
R.ROLE_LABEL = { tank = "Tank", healer = "Healer", dps = "DPS" }
R.STATUS_LABEL = { yes = "Signed up", maybe = "Maybe", no = "Can't" }

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

-- Does this player hold a spot? Selected by a Team Captain or above, and
-- still signed up (an answer of "Can't" gives the spot back).
function R.IsPicked(r, guid)
    local s = r.signups[guid]
    return (r.picked and r.picked[guid] ~= nil and s ~= nil and s.st ~= "no") or false
end

function R.PickedCount(r)
    local n = 0
    for guid in pairs(r.picked or {}) do
        if R.IsPicked(r, guid) then n = n + 1 end
    end
    return n
end

-- May a spot be given (on = true) or taken back? Pure. -> true, or nil and why
function R.CanPick(r, guid, on, now)
    if not r or r.cancelled then return nil, "That raid is gone." end
    if r.at < now - 6 * 3600 then return nil, "That raid is over." end
    if not on then
        if not (r.picked and r.picked[guid]) then return nil, "They aren't selected." end
        return true
    end
    local s = r.signups[guid]
    if not s or s.st == "no" then return nil, "They haven't signed up for this raid." end
    if R.IsPicked(r, guid) then return nil, "They are already selected." end
    local n = R.PickedCount(r)
    if n >= r.size then
        return nil, ("All %d spots are taken. Unselect someone first."):format(r.size)
    end
    return true
end

-- Team Captain or above: give a signed-up player a spot, or take it back.
function R.Pick(id, guid, on)
    if not RBAC.ICan("schedule") then return nil, "Only Team Captains and above select the raid." end
    local st = Red.State()
    local ok, why = R.CanPick(st and st.raids[id], guid, on, ns.Now())
    if not ok then return nil, why end
    return Log.New("RAID_PICK", { ev = id, who = guid, on = on and true or false })
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
-- c.picked = players holding a spot, c.sel = their roles, c.waiting = signed
-- up and not selected yet. c.yes and the plain role counts are everyone who
-- signed up as coming.
function R.Summary(st, r)
    local c = { yes = 0, maybe = 0, no = 0, tank = 0, healer = 0, dps = 0, picked = 0, waiting = 0,
        sel = { tank = 0, healer = 0, dps = 0 } }
    local rows = {}
    local present = st.attendDays[R.RaidDay(r.at)]
    for guid, s in pairs(r.signups) do
        local picked = R.IsPicked(r, guid)
        c[s.st] = c[s.st] + 1
        if s.st == "yes" and s.role then c[s.role] = c[s.role] + 1 end
        if picked then
            c.picked = c.picked + 1
            if s.role then c.sel[s.role] = c.sel[s.role] + 1 end
        elseif s.st == "yes" then
            c.waiting = c.waiting + 1
        end
        rows[#rows + 1] = { guid = guid, st = s.st, role = s.role, picked = picked, gear = st.gear and st.gear[guid] or nil, kit = st.kit and st.kit[guid] or nil,
            showed = present and present[guid] or nil, name = ns.NameForGUID and ns.NameForGUID(guid) or guid }
    end
    -- Selected first, then signed up; within each the best-prepared first, so
    -- a leader who has to choose sees who put in the work. No score sorts last.
    local order = { yes = 1, maybe = 2, no = 3 }
    table.sort(rows, function(a, b)
        if a.picked ~= b.picked then return a.picked end
        if a.st ~= b.st then return order[a.st] < order[b.st] end
        local ga, gb = a.gear and a.gear.pre or -1, b.gear and b.gear.pre or -1
        if ga ~= gb then return ga > gb end
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
        -- Once the raid has been selected, only the selected are reminded.
        local mine = R.PickedCount(r) == 0 or R.IsPicked(r, me)
        if not r.cancelled and s and s.st ~= "no" and mine then
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
    -- The screen reads in the order you use it: pick a raid on the left, then
    -- on the right the raid, your answer, and the roster. Leader tools fold
    -- away at the bottom.
    local function section(text, x, y)
        local fs = W.Text(p, text, "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", x, y)
        return fs
    end
    local function colHead(text, x, y, w)
        local fs = W.Text(p, text, "GameFontDisableSmall")
        fs:SetPoint("TOPLEFT", x, y)
        fs:SetWidth(w)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        return fs
    end
    local h = W.Text(p, "Raids", "GameFontNormal")
    h:SetPoint("TOPLEFT", 0, 0)
    colHead("When (your PC's time)", 4, -18, 130)
    colHead("Raid", 136, -18, 110)
    colHead("Spots", 248, -18, 50)
    p.list = W.List(p, 300, 180, 18, function(row, r)
        local past = r.at < ns.Now() - 6 * 3600
        local c = R.Summary(Red.State(), r)
        p.list.Col(row, 1, 4, 130):SetText((past and "|cff808080" or "") .. date("%a %b %d  %I:%M %p", r.at))
        p.list.Col(row, 2, 136, 110):SetText(U.Safe(r.title, 30))
        p.list.Col(row, 3, 248, 50):SetText(c.picked .. "/" .. r.size)
    end, function(r) selected = r.id; ns.UI.Refresh() end)
    p.list.scroll:SetPoint("TOPLEFT", 0, -34)
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
    p.counts:SetPoint("TOPLEFT", 380, -116)
    p.counts:SetPoint("RIGHT", -4, 0)
    p.counts:SetJustifyH("LEFT")
    p.counts:SetWordWrap(false)        -- one line, so it can't run into the line below
    p.answerHead = section("Your answer", 330, -54)
    p.rosterHead = section("Roster", 330, -116)
    p.mine = W.Text(p, "", "GameFontHighlightSmall")
    p.mine:SetPoint("TOPLEFT", 330, -68)
    p.mine:SetWidth(360)
    p.mine:SetWordWrap(false)
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
            local ok = ns.UI.Try(b[2] == "yes" and ("Signed up as " .. R.ROLE_LABEL[role] .. ". A Team Captain or above selects who gets a spot.")
                or ("Answered: " .. R.STATUS_LABEL[b[2]] .. "."), R.SignUp, selected, b[2], role)
            local r = ok and Red.State().raids[selected]
            if r and ns.Calendar then ns.Calendar.Respond(r, b[2]) end
            -- Signing up shares your current readiness score with the leaders.
            if ok and b[2] ~= "no" and ns.BiS then ns.BiS.Publish(true) end
            if ok and b[2] ~= "no" and ns.Kit then ns.Kit.Publish(true) end
        end)
        btn:SetPoint("TOPLEFT", 330 + (i - 1) * 64, -84)
        p.signButtons[i] = btn
    end
    p.people = W.List(p, 360, 92, 16, function(row, s)
        p.people.Col(row, 1, 4, 100):SetText(U.Safe(s.name or "?", 40))
        local role = s.role and s.st ~= "no" and (" " .. R.ROLE_LABEL[s.role]) or ""
        p.people.Col(row, 2, 106, 98):SetText(s.picked and ("|cff40ff40Selected|r" .. role) or (R.STATUS_LABEL[s.st] .. role))
        local g = s.gear
        local color = not g and "808080" or (g.pre >= 75 and "40ff40" or (g.pre >= 40 and "ffd100" or "ff6040"))
        p.people.Col(row, 3, 206, 100):SetText("|cff" .. color .. (g and (g.pre .. "%  " .. U.Safe(g.spec, 24)) or "no score yet") .. "|r")
        -- The kit count is for Team Captains and above (and always your own).
        local showKit = ns.Kit and (RBAC.ICan("schedule") or s.guid == ns.MyGUID())
        p.people.Col(row, 4, 308, 60):SetText(showKit and ns.Kit.ScoreText(s.kit) or "")
        p.people.Col(row, 5, 372, 60):SetText(s.showed and "|cff40ff40was there|r" or "")
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(U.Safe(s.name or "?", 40))
            if s.picked then
                GameTooltip:AddLine("Selected for this raid.", 0.25, 1, 0.25)
            elseif s.st ~= "no" then
                GameTooltip:AddLine("Signed up. Not selected yet.", 1, 0.82, 0)
            end
            if RBAC.ICan("schedule") and s.st ~= "no" then
                GameTooltip:AddLine(s.picked and "Click to take the spot back." or "Click to give them a spot.", 0.8, 0.8, 0.8)
            end
            if g then
                GameTooltip:AddLine(("Pre-raid BiS, %s list"):format(U.Safe(g.spec, 24)), 1, 1, 1)
                GameTooltip:AddLine(("Owns %d%% of it (bags and bank count); wearing %d%%"):format(g.pre, g.worn), 0.8, 0.8, 0.8)
                GameTooltip:AddLine("Reported by their own Blood Pact on " .. date("%b %d", g.t), 0.6, 0.6, 0.6)
            else
                GameTooltip:AddLine("No readiness score: they haven't run this Blood Pact version yet.", 0.8, 0.8, 0.8, true)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
    end, function(s)
        -- Team Captain and above: a click gives this player a spot or takes it back.
        if not (s and selected and RBAC.ICan("schedule")) then return end
        if s.st == "no" and not s.picked then ns.UI.Say(U.Safe(s.name or "They", 40) .. " can't make this raid.") return end
        local who = U.Safe(s.name or "?", 40)
        ns.UI.Try(s.picked and (who .. " is no longer selected.") or (who .. " is selected for the raid."),
            R.Pick, selected, s.guid, not s.picked)
    end)
    p.people.key = "guid"
    p.peopleHead = W.Text(p, "Sign-ups (the % is how much of their pre-raid BiS list they own)", "GameFontDisableSmall")
    p.peopleHead:SetPoint("TOPLEFT", 330, -130)
    p.peopleHead:SetWidth(380)
    p.peopleHead:SetWordWrap(false)
    p.peopleCols = { colHead("Name", 334, -146, 100), colHead("Answer", 436, -146, 98), colHead("Pre-raid BiS", 536, -146, 100),
        colHead("Kit", 638, -146, 60), colHead("Attended", 702, -146, 60) }
    p.people.scroll:SetPoint("TOPLEFT", 330, -160)
    p.people.scroll:SetHeight(76)

    -- Scheduling and leader tools (Team Captain and above) are used now and
    -- then, so they fold away at the bottom and the two lists get the room.
    function p.place()
        local can = RBAC.ICan("schedule")
        p.fold:SetShown(can)
        p.fold:ClearAllPoints()
        p.fold:SetPoint("BOTTOMLEFT", 0, can and (p.fold:Height() - 22) or 0)
        local below = can and (p.fold:Height() + 8) or 0
        p.list:Stretch(0, -34, nil, below)
        p.people:Stretch(330, -160, nil, below)
    end
    p.fold = W.Accordion(p, "Schedule a raid and leader tools", 700, 158, "raidsLeader", function() p.place() end)
    local s = CreateFrame("Frame", nil, p.fold.body)
    s:SetPoint("TOPLEFT", 0, 0)
    s:SetSize(700, 158)
    -- Two groups: make a new raid, then the tools for the raid picked above.
    W.Text(s, "New raid", "GameFontNormalSmall"):SetPoint("TOPLEFT", 0, 0)
    s.toolsHead = W.Text(s, "Selected raid", "GameFontNormalSmall")
    s.toolsHead:SetPoint("TOPLEFT", 0, -98)
    p.sched = s
    W.Text(s, "Title", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 0, -22)
    s.titleBox = W.Edit(s, 150, 40)
    s.titleBox:SetPoint("TOPLEFT", 40, -18)
    s.raid, s.size = nil, nil
    s.presetButtons = {}
    for i, pr in ipairs(R.PRESETS) do
        local b = W.Button(s, pr.label .. " (" .. pr.size .. ")", 130, 22, function()
            s.raid = pr.raid
            s.sizeBox:SetText(tostring(pr.size))
            for j, other in ipairs(s.presetButtons) do other:SetEnabled(j ~= i) end
        end)
        b:SetPoint("TOPLEFT", 200 + (i - 1) * 134, -18)
        s.presetButtons[i] = b
    end
    W.Text(s, "Date", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 0, -50)
    s.dayBox = W.Edit(s, 90, 10)
    s.dayBox:SetPoint("TOPLEFT", 40, -46)
    s.dayBox:SetText(date("%m/%d"))
    W.Text(s, "Time", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 140, -50)
    s.timeBox = W.Edit(s, 50, 5)
    s.timeBox:SetPoint("TOPLEFT", 172, -46)
    W.Text(s, "Size", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 232, -50)
    s.sizeBox = W.Edit(s, 30, 2)
    s.sizeBox:SetPoint("TOPLEFT", 262, -46)
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
    s.create:SetPoint("TOPLEFT", 310, -46)
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
    s.zone:SetPoint("TOPLEFT", 416, -46)
    s.zone:SetScript("OnShow", function() s.zone:SetText(zones[zoneIndex()].label) end)
    s.zone:SetText(zones[zoneIndex()].label)
    s.prog = W.Check(s, "Progression (boss kills pay progression DKP)")
    s.prog:SetPoint("TOPLEFT", 0, -70)
    W.Text(s, "Date like 12/9. Time like 8pm or 20:00. Click the zone button to change it.", "GameFontDisableSmall"):SetPoint("TOPLEFT", 300, -74)
    s.attend = W.Button(s, "Take attendance now", 160, 22, function()
        local e, n = R.TakeAttendance("manual")
        if e then ns.UI.Say(("Attendance taken: %d guild members."):format(n)) else ns.UI.Say(n or "That didn't work.") end
    end)
    s.attend:SetPoint("TOPLEFT", 0, -114)
    s.cancel = W.Button(s, "Cancel selected raid", 160, 22)
    s.cancel:SetScript("OnClick", ns.UI.Confirm(s.cancel, function()
        if not selected then return end
        if ns.UI.Try("Raid cancelled.", R.Cancel, selected) then selected = nil end
    end))
    s.cancel:SetPoint("TOPLEFT", 166, -114)
    s.whisper = W.Button(s, "Whisper sign-ups", 140, 22, function()
        local r = Red.State() and Red.State().raids[selected]
        if not r then return end
        local n, why = R.WhisperSignups(r)
        ns.UI.Say(n and ("Whispered %d raiders."):format(n) or why)
    end)
    s.whisper:SetPoint("TOPLEFT", 332, -114)
    W.Text(s, "Boss kills take attendance on their own while you lead.", "GameFontDisableSmall"):SetPoint("TOPLEFT", 0, -140)
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
    p.place()
    local open = found ~= nil and found.at >= ns.Now() - 6 * 3600
    for _, b in ipairs(p.signButtons) do b:SetEnabled(open) end
    if not found then
        p.title:SetText("No raids scheduled yet.")
        p.info:SetText(RBAC.ICan("schedule") and "Schedule one below." or "A Team Captain or Officer schedules raids.")
        p.when:SetText("")
        p.counts:SetText("")
        p.mine:SetText("")
        p.answerHead:SetShown(false)
        p.rosterHead:SetShown(false)
        for _, fs in ipairs(p.peopleCols) do fs:SetShown(false) end
        p.sched.toolsHead:SetText("Selected raid: none")
        p.peopleHead:SetShown(false)
        p.people:SetItems({})
        return
    end
    local c, rows = R.Summary(st, found)
    p.answerHead:SetShown(true)
    p.rosterHead:SetShown(true)
    for _, fs in ipairs(p.peopleCols) do fs:SetShown(#rows > 0) end
    p.sched.toolsHead:SetText("Selected raid: " .. U.Safe(found.title, 40))
    p.title:SetText(U.Safe(found.title, 40))
    p.info:SetText(U.Safe(found.raid, 30) .. " (" .. found.size .. ")  -  " .. (found.prog and "|cffff8040Progression|r" or "Farm")
        .. (found.n and ("  -  " .. U.Safe(found.n, 60)) or ""))
    p.when:SetText(R.When(found))
    p.counts:SetText(("%d/%d selected   Tanks %d  Healers %d  DPS %d   Waiting %d  Maybe %d  Can't %d"):format(
        c.picked, found.size, c.sel.tank, c.sel.healer, c.sel.dps, c.waiting, c.maybe, c.no))
    p.peopleHead:SetShown(#rows > 0)
    p.peopleHead:SetText(RBAC.ICan("schedule") and "Click a name to give them a spot or take it back."
        or "A Team Captain or above selects who gets a spot.")
    local mine = found.signups[ns.MyGUID()]
    if not open then
        p.mine:SetText("This raid is over.")
    elseif not mine then
        p.mine:SetText("You haven't answered yet. Pick one:")
    elseif R.IsPicked(found, ns.MyGUID()) then
        p.mine:SetText("|cff40ff40You're selected" .. (mine.role and (" as " .. R.ROLE_LABEL[mine.role]) or "") .. ".|r Click another to change it.")
    elseif mine.st == "yes" then
        p.mine:SetText("Signed up" .. (mine.role and (" as " .. R.ROLE_LABEL[mine.role]) or "") .. ", not selected yet. Click another to change it.")
    else
        p.mine:SetText("Your answer: " .. R.STATUS_LABEL[mine.st] .. ". Click another to change it.")
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

-- Room the tab needs: the raid's details, a few sign-ups, and the leader
-- tools, open or folded (Team Captain and above).
ns.UI.Need("raids", function(p)
    return 160 + 58 + (RBAC.ICan("schedule") and (p.fold:Height() + 8) or 0)
end)

-- A chat line when you are given a raid spot or it is taken back.
local seenPick, pickPrimed, pickQueued = {}, false, false
function R.AnnouncePicks()
    local st = Red.State()
    if not st then return end
    local me, now = ns.MyGUID(), ns.Now()
    for id, r in pairs(st.raids) do
        local mine = (not r.cancelled and r.at >= now - 6 * 3600 and R.IsPicked(r, me)) or false
        if pickPrimed and mine ~= (seenPick[id] or false) and r.at >= now - 6 * 3600 and not r.cancelled then
            local s = r.signups[me]
            if mine then
                alert(("You're selected for %s, %s%s."):format(U.Safe(r.title, 40), R.When(r),
                    s and s.role and (", as " .. R.ROLE_LABEL[s.role]) or ""))
            elseif s and s.st ~= "no" then
                ns.Print(("You're no longer selected for %s. You're still signed up."):format(U.Safe(r.title, 40)))
            end
        end
        seenPick[id] = mine
    end
    pickPrimed = true
end
ns.Listen("LOG_CHANGED", function()
    if pickQueued or not (C_Timer and C_Timer.After) then return end
    pickQueued = true
    C_Timer.After(1, function()
        pickQueued = false
        R.AnnouncePicks()
    end)
end)

-- One click by a Team Captain or above: whisper everyone who said yes or maybe
-- and is online. Only ever sent from that click, never on a timer.
function R.WhisperSignups(r)
    if not RBAC.ICan("schedule") then return nil, "Only Team Captains and above can do this." end
    local mins = math.floor((r.at - ns.Now()) / 60 + 0.5)
    local msg = mins > 0
        and ("Blood Pact: %s starts in %d minutes. Get ready, and please be there 15 minutes early."):format(r.title, mins)
        or ("Blood Pact: %s is starting. Please head to the raid now."):format(r.title)
    local names = {}
    local chosenOnly = R.PickedCount(r) > 0      -- once the raid is selected, only the selected
    for guid, s in pairs(r.signups) do
        local m = ns.roster.byGUID[guid]
        if s.st ~= "no" and (not chosenOnly or R.IsPicked(r, guid)) and guid ~= ns.MyGUID() and m and m.online and #names < 40 then
            names[#names + 1] = ns.U.ShortName(m.name)
        end
    end
    if #names == 0 then return nil, chosenOnly and "Nobody who is selected is online." or "Nobody who signed up is online." end
    if ns.mock then return #names end   -- test mode never whispers anyone
    -- The first goes now, so a refusal by the game is known before anything is promised.
    local ok, why = ns.Chat(msg, "WHISPER", names[1])
    if not ok then return nil, why == "locked" and (ns.CHAT_LOCKED .. " Whisper them from outside.") or "The game didn't send the whispers." end
    -- The rest are spaced out so the chat server doesn't drop them.
    for i = 2, #names do
        C_Timer.After((i - 1) * 0.3, function() ns.Chat(msg, "WHISPER", names[i]) end)
    end
    return #names
end
