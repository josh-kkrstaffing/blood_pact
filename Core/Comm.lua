-- Blood Pact: addon-channel transport. Splits payloads into 255-byte messages,
-- paces sends under the server's per-prefix throttle (burst of 10, refills
-- 1 per second), holds sends during WoW Forever's in-instance comms lockdown,
-- and reassembles incoming messages.
local _, ns = ...
local C = {}
ns.Comm = C

C.PREFIX = "BloodPact"
local CHUNK = 220            -- payload bytes per message, leaving room for the header
local MAX_PARTS = 64         -- largest payload we accept: 64 * 220 bytes
local REASSEMBLY_TIMEOUT = 60

-- Result codes from Enum.SendAddonMessageResult (numbers per warcraft.wiki.gg).
local RESULT_OK, RESULT_THROTTLE, RESULT_LOCKDOWN = 0, 3, 11
local DROP = { [1] = true, [2] = true, [4] = true, [5] = true, [6] = true, [7] = true,
               [9] = true, [10] = true, [12] = true }

local buckets = {
    GUILD   = { tokens = 10, max = 10, rate = 1 },
    WHISPER = { tokens = 10, max = 10, rate = 2 },
}
local queue = {}                 -- FIFO of { dist, target, msg }
local holdUntil = 0              -- lockdown or throttle backoff
local msgCounter = 0
C.stats = { sent = 0, received = 0, lockdowns = 0, throttled = 0, dropped = 0 }

local function nextId()
    msgCounter = (msgCounter + 1) % 46656
    local chars = "0123456789abcdefghijklmnopqrstuvwxyz"
    local n, s = msgCounter, ""
    for _ = 1, 3 do
        local r = n % 36
        s = chars:sub(r + 1, r + 1) .. s
        n = math.floor(n / 36)
    end
    return s
end

function C.QueueLength() return #queue end
function C.IsHeld() return GetTime() < holdUntil end

-- Queue a payload string for sending. dist: "GUILD" or "WHISPER".
function C.Send(dist, target, payload)
    if ns.mock then return end             -- mock data never leaves this client
    local parts = math.ceil(#payload / CHUNK)
    if parts > MAX_PARTS then
        ns.Print("Message too large to send (" .. #payload .. " bytes).")
        return
    end
    local id = nextId()
    for p = 1, parts do
        local chunk = payload:sub((p - 1) * CHUNK + 1, p * CHUNK)
        queue[#queue + 1] = { dist = dist, target = target, msg = id .. ":" .. p .. ":" .. parts .. ":" .. chunk }
    end
end

local lastPump = nil
local function pump()
    local now = GetTime()
    local dt = lastPump and (now - lastPump) or 0
    lastPump = now
    for _, b in pairs(buckets) do
        b.tokens = math.min(b.max, b.tokens + dt * b.rate)
    end
    if now < holdUntil then return end

    local i = 1
    while i <= #queue do
        local item = queue[i]
        local b = buckets[item.dist]
        if b.tokens < 1 then
            i = i + 1
        else
            -- Some builds throw instead of returning a code during lockdown.
            local called, result = pcall(C_ChatInfo.SendAddonMessage, C.PREFIX, item.msg, item.dist, item.target)
            if not called then result = RESULT_LOCKDOWN end
            if result == true or result == nil then result = RESULT_OK end
            if result == false then result = 9 end
            if result == RESULT_OK then
                b.tokens = b.tokens - 1
                table.remove(queue, i)
                C.stats.sent = C.stats.sent + 1
            elseif result == RESULT_LOCKDOWN then
                C.stats.lockdowns = C.stats.lockdowns + 1
                holdUntil = now + 5
                return
            elseif result == RESULT_THROTTLE then
                C.stats.throttled = C.stats.throttled + 1
                b.tokens = 0
                holdUntil = now + 2
                return
            else
                if DROP[result] then C.stats.dropped = C.stats.dropped + 1 end
                table.remove(queue, i)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local partial = {}   -- key sender:id -> { parts = {}, got = n, total = n, at = time }

local function onAddonMessage(prefix, text, channel, sender)
    if prefix ~= C.PREFIX or type(text) ~= "string" then return end
    if channel ~= "GUILD" and channel ~= "WHISPER" then return end
    local me = UnitName("player")
    if sender == me or ns.U.ShortName(sender) == me then return end

    local id, p, total, chunk = text:match("^(%w+):(%d+):(%d+):(.*)$")
    p, total = tonumber(p), tonumber(total)
    if not id or not p or not total or total < 1 or total > MAX_PARTS or p > total then return end

    local key = sender .. ":" .. id
    local now = GetTime()
    local entry = partial[key]
    if not entry then
        entry = { parts = {}, got = 0, total = total, at = now }
        partial[key] = entry
    end
    if not entry.parts[p] then
        entry.parts[p] = chunk
        entry.got = entry.got + 1
    end
    if entry.got == entry.total then
        partial[key] = nil
        C.stats.received = C.stats.received + 1
        local payload = table.concat(entry.parts, "", 1, entry.total)
        if ns.Sync then ns.Sync.OnPayload(payload, channel, sender) end
    end
end

local function sweep()
    local now = GetTime()
    for key, entry in pairs(partial) do
        if now - entry.at > REASSEMBLY_TIMEOUT then partial[key] = nil end
    end
end

ns.On("PLAYER_LOGIN", function()
    C_ChatInfo.RegisterAddonMessagePrefix(C.PREFIX)
    C_Timer.NewTicker(0.25, pump)
    C_Timer.NewTicker(30, sweep)
end)
ns.On("CHAT_MSG_ADDON", onAddonMessage)
