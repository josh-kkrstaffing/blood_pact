-- Blood Pact: time zones for raid scheduling. Pure Lua, no game API.
-- Raids are stored as one moment (server unix time). The scheduler types a
-- wall-clock time in a chosen zone; everyone else sees it in their own PC time.
-- US zones follow US daylight saving: 2nd Sunday of March to 1st Sunday of
-- November, switching at 2:00 local time.
local _, ns = ...
local T = {}
ns.Time = T

local floor = math.floor
local dateFn = date or os.date   -- WoW global; os.date in tests

-- Days since 1970-01-01 for a calendar date (proleptic Gregorian).
function T.DaysFromCivil(y, m, d)
    y = (m <= 2) and (y - 1) or y
    local era = floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

-- Wall-clock fields read as UTC -> unix seconds.
function T.Civil(y, m, d, h, mi)
    return T.DaysFromCivil(y, m, d) * 86400 + (h or 0) * 3600 + (mi or 0) * 60
end

-- 0 = Sunday.
function T.Weekday(y, m, d) return (T.DaysFromCivil(y, m, d) + 4) % 7 end

-- Day of month of the nth Sunday.
local function nthSunday(y, m, n)
    local first = T.Weekday(y, m, 1)
    return 1 + (7 - first) % 7 + (n - 1) * 7
end

T.ZONES = {
    { key = "ET", label = "Eastern", std = -5, dst = true },
    { key = "CT", label = "Central", std = -6, dst = true },
    { key = "MT", label = "Mountain", std = -7, dst = true },
    { key = "AZ", label = "Arizona", std = -7, dst = false },
    { key = "PT", label = "Pacific", std = -8, dst = true },
}
T.BY_KEY = {}
for _, z in ipairs(T.ZONES) do T.BY_KEY[z.key] = z end

-- UTC offset in hours for a zone at a unix moment.
function T.Offset(key, unix)
    local z = T.BY_KEY[key]
    if not z then return nil end
    if not z.dst then return z.std end
    local y = tonumber(dateFn("!%Y", unix))
    local startUtc = T.Civil(y, 3, nthSunday(y, 3, 2), 2, 0) - z.std * 3600
    local endUtc = T.Civil(y, 11, nthSunday(y, 11, 1), 2, 0) - (z.std + 1) * 3600
    if unix >= startUtc and unix < endUtc then return z.std + 1 end
    return z.std
end

-- Wall-clock time in a zone -> unix seconds.
function T.FromZone(key, y, m, d, h, mi)
    local z = T.BY_KEY[key]
    if not z then return nil end
    local wall = T.Civil(y, m, d, h, mi)
    local guess = wall - z.std * 3600
    return wall - T.Offset(key, guess) * 3600
end

-- Unix seconds -> wall-clock text in a zone, e.g. "8:00 PM Central".
function T.Format(key, unix, fmt)
    local off = T.Offset(key, unix)
    if not off then return nil end
    local s = dateFn("!" .. (fmt or "%I:%M %p"), unix + off * 3600)
    return (s:gsub("^0", "")) .. " " .. T.BY_KEY[key].label
end
