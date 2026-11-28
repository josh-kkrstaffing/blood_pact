-- Blind Tiger: copy scheduled raids to the in-game calendar as guild sign-up
-- events, so the whole guild sees them there, and mirror your sign-up onto it.
-- Runs only from a button click. If the client refuses (the calendar API may be
-- restricted on WoW Forever), it says so once and Blind Tiger keeps working.
local _, ns = ...
local C = {}
ns.Calendar = C

local function cal() return C_Calendar end

-- The realm's calendar clock differs from UTC by this many seconds.
local function realmOffset()
    local now = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
    if not now then return nil end
    local wall = ns.Time.Civil(now.year, now.month, now.monthDay, now.hour, now.minute)
    local diff = wall - ns.Now()
    return math.floor(diff / 900 + 0.5) * 900   -- zones are whole quarter hours
end

-- Realm wall-clock fields for a raid's moment.
function C.RealmTime(at, offset)
    local t = date("!*t", at + offset)
    return t.year, t.month, t.day, t.hour, t.min
end

local function say(msg) if ns.UI then ns.UI.Say(msg) else ns.Print(msg) end end

function C.Add(r)
    if ns.mock then return false end   -- test mode never touches the real calendar
    local api = cal()
    if not api or not api.CreateGuildSignUpEvent or not api.AddEvent then
        say("Raid saved. This client has no in-game calendar for addons, so add it there by hand.")
        return false
    end
    if api.CanAddEvent and not api.CanAddEvent() then
        say("Raid saved. Your guild rank can't add calendar events, so ask an Officer to add it there.")
        return false
    end
    local offset = realmOffset()
    if not offset then return false end
    local y, m, d, h, mi = C.RealmTime(r.at, offset)
    local ok, err = pcall(function()
        api.CreateGuildSignUpEvent()
        api.EventSetTitle(r.title)
        api.EventSetDescription(("%s - %s. Sign up here or in Blind Tiger (/tiger)."):format(r.raid, r.prog and "progression" or "farm"))
        if api.EventSetType and Enum and Enum.CalendarEventType and Enum.CalendarEventType.Raid then
            api.EventSetType(Enum.CalendarEventType.Raid)
        end
        api.EventSetDate(m, d, y)
        api.EventSetTime(h, mi)
        api.AddEvent()
    end)
    if ok then
        say("Raid saved and added to the in-game calendar for the guild.")
    else
        say("Raid saved, but the game wouldn't let Blind Tiger add it to the calendar: " .. tostring(err))
    end
    return ok
end

-- Find the calendar event for a raid (same title, same realm date) and answer it.
local pending
function C.Respond(r, status)
    if ns.mock then return end
    local api = cal()
    if not api or not api.OpenEvent or not api.SetAbsMonth then return end
    local offset = realmOffset()
    if not offset then return end
    local y, m, d = C.RealmTime(r.at, offset)
    local ok = pcall(function()
        api.SetAbsMonth(m, y)
        for i = 1, api.GetNumDayEvents(0, d) do
            local ev = api.GetDayEvent(0, d, i)
            if ev and ev.title == r.title then
                pending = status
                api.OpenEvent(0, d, i)
                return
            end
        end
    end)
    if not ok then pending = nil end
end

ns.On("CALENDAR_OPEN_EVENT", function()
    if not pending then return end
    local status, api = pending, cal()
    pending = nil
    pcall(function()
        if status == "yes" and api.EventSignUp then api.EventSignUp()
        elseif status == "maybe" and api.EventTentative then api.EventTentative()
        elseif status == "no" and api.EventDecline then api.EventDecline() end
    end)
end)
