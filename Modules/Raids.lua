-- Blood Pact: raid sign-ups and attendance.
-- Team Captains and above schedule raids and take attendance; everyone signs up.
-- Everything is a log event, so it syncs like DKP and no website is needed.
-- Raid nights are grouped by UTC date so officers in different time zones agree.
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

function R.RaidDay(unix) return date("!%Y-%m-%d", unix) end

-- "2026-12-09" + "20:00" (your local time) -> server unix time.
function R.ParseWhen(day, clock)
    local y, mo, d = tostring(day or ""):match("^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s*$")
    local h, mi = tostring(clock or ""):match("^%s*(%d%d?):(%d%d)%s*$")
    if not y or not h then return nil end
    y, mo, d, h, mi = tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi)
    if mo < 1 or mo > 12 or d < 1 or d > 31 or h > 23 or mi > 59 then return nil end
    local t = time({ year = y, month = mo, day = d, hour = h, min = mi, sec = 0 })
    -- Local clock -> server clock, in case the PC clock is off.
    return t and (t + (ns.Now() - time())) or nil
end

function R.Create(title, raid, day, clock, size, note)
    if not RBAC.ICan("schedule") then return nil, "Only Team Captains and above can schedule raids." end
    title = tostring(title or ""):match("^%s*(.-)%s*$")
    if title == "" then title = raid end
    if not raid or raid == "" then return nil, "Pick Barrow Deeps or Hyjal Summit, or type a raid." end
    local at = R.ParseWhen(day, clock)
    if not at then return nil, "Date as YYYY-MM-DD and time as HH:MM (24-hour, your time)." end
    if at < ns.Now() - 3600 then return nil, "That time has already passed." end
    size = tonumber(size)
    if not size or size < 5 or size > 40 or size ~= math.floor(size) then return nil, "Raid size 5 to 40." end
    return Log.New("RAID", { title = title:sub(1, 40), raid = raid:sub(1, 30), at = at, size = size,
        n = note and note ~= "" and note:sub(1, Log.MAX_NOTE) or nil })
end

function R.Cancel(id)
    if not RBAC.ICan("schedule") then return nil, "Only Team Captains and above can cancel raids." end
    return Log.New("RAID_CANCEL", { ev = id })
end

function R.SignUp(id, status, role)
    if not RBAC.ICan("signup") then return nil, "You need to be in the guild to sign up." end
    return Log.New("SIGNUP", { ev = id, st = status, role = role })
end

function R.TakeAttendance(reason)
    if not RBAC.ICan("schedule") then return nil, "Only Team Captains and above take attendance." end
    local who = ns.DKP.GroupGUIDs()
    if #who < 2 and not ns.mock then return nil, "Get the raid together first." end
    local now = ns.Now()
    local idem = (reason or "manual") .. ":" .. date("!%Y-%m-%d %H:%M", now)
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
    if not ns.mock and not UnitIsGroupLeader("player") then return end
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

local function when(at) return date("%a %b %d  %I:%M %p", at) end

ns.UI.AddTab("raids", "Raids", "view", function(p)
    local h = W.Text(p, "Raids (times in your local time)", "GameFontNormal")
    h:SetPoint("TOPLEFT", 0, 0)
    p.list = W.List(p, 300, 180, 18, function(row, r)
        local past = r.at < ns.Now() - 6 * 3600
        local c = R.Summary(Red.State(), r)
        p.list.Col(row, 1, 4, 130):SetText((past and "|cff808080" or "") .. when(r.at))
        p.list.Col(row, 2, 136, 110):SetText(U.Safe(r.title, 30))
        p.list.Col(row, 3, 248, 50):SetText(c.yes .. "/" .. r.size)
    end, function(r) selected = r.id; ns.UI.Refresh() end)
    p.list.scroll:SetPoint("TOPLEFT", 0, -18)

    -- Right side: selected raid
    p.title = W.Text(p, "", "GameFontNormal")
    p.title:SetPoint("TOPLEFT", 330, 0)
    p.title:SetWidth(320)
    p.info = W.Text(p, "", "GameFontHighlightSmall")
    p.info:SetPoint("TOPLEFT", 330, -18)
    p.info:SetWidth(320)
    p.counts = W.Text(p, "", "GameFontHighlightSmall")
    p.counts:SetPoint("TOPLEFT", 330, -48)
    p.counts:SetWidth(320)
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
            ns.UI.Try("Signed up: " .. R.STATUS_LABEL[b[2]] .. (b[2] == "yes" and (" as " .. R.ROLE_LABEL[role]) or "") .. ".",
                R.SignUp, selected, b[2], role)
        end)
        btn:SetPoint("TOPLEFT", 330 + (i - 1) * 64, -66)
        p.signButtons[i] = btn
    end
    p.people = W.List(p, 320, 110, 16, function(row, s)
        p.people.Col(row, 1, 4, 140):SetText(U.Safe(s.name or "?", 40))
        p.people.Col(row, 2, 146, 80):SetText(R.STATUS_LABEL[s.st] .. (s.role and (" " .. R.ROLE_LABEL[s.role]) or ""))
        p.people.Col(row, 3, 230, 86):SetText(s.showed and "|cff40ff40was there|r" or "")
    end)
    p.people.scroll:SetPoint("TOPLEFT", 330, -94)

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
    s.dayBox:SetText(date("%Y-%m-%d"))
    W.Text(s, "Time", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 140, -52)
    s.timeBox = W.Edit(s, 50, 5)
    s.timeBox:SetPoint("TOPLEFT", 172, -48)
    W.Text(s, "Size", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 232, -52)
    s.sizeBox = W.Edit(s, 30, 2)
    s.sizeBox:SetPoint("TOPLEFT", 262, -48)
    s.create = W.Button(s, "Create raid", 100, 22, function()
        local e = ns.UI.Try("Raid scheduled.", R.Create, s.titleBox:GetText(), s.raid,
            s.dayBox:GetText(), s.timeBox:GetText(), s.sizeBox:GetText())
        if e then selected = e.id; s.titleBox:SetText(""); ns.UI.Refresh() end
    end)
    s.create:SetPoint("TOPLEFT", 310, -48)
    W.Text(s, "Date YYYY-MM-DD, time HH:MM in 24-hour, your local time.", "GameFontDisableSmall"):SetPoint("TOPLEFT", 0, -76)
    s.attend = W.Button(s, "Take attendance now", 160, 22, function()
        local e, n = R.TakeAttendance("manual")
        if e then ns.UI.Say(("Attendance taken: %d guild members."):format(n)) else ns.UI.Say(n or "That didn't work.") end
    end)
    s.attend:SetPoint("TOPLEFT", 0, -100)
    s.cancel = W.Button(s, "Cancel selected raid", 160, 22, function()
        if not selected then return end
        if ns.UI.Try("Raid cancelled.", R.Cancel, selected) then selected = nil end
    end)
    s.cancel:SetPoint("TOPLEFT", 166, -100)
    W.Text(s, "Boss kills record attendance on their own while you lead.", "GameFontDisableSmall"):SetPoint("TOPLEFT", 334, -105)
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
    for _, b in ipairs(p.signButtons) do b:SetEnabled(found ~= nil) end
    if not found then
        p.title:SetText("No raids scheduled yet.")
        p.info:SetText(RBAC.ICan("schedule") and "Schedule one below." or "A Team Captain or Officer schedules raids.")
        p.counts:SetText("")
        p.people:SetItems({})
        return
    end
    local c, rows = R.Summary(st, found)
    p.title:SetText(U.Safe(found.title, 40))
    p.info:SetText(U.Safe(found.raid, 30) .. " (" .. found.size .. ")  -  " .. when(found.at)
        .. (found.n and ("\n" .. U.Safe(found.n, 120)) or ""))
    p.counts:SetText(("Coming %d/%d   Tanks %d  Healers %d  DPS %d   Maybe %d   Can't %d"):format(
        c.yes, found.size, c.tank, c.healer, c.dps, c.maybe, c.no))
    p.people:SetItems(rows)
end)
