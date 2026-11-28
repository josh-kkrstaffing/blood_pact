-- Blind Tiger: addon-channel transport. Splits payloads into 255-byte messages,
-- paces sends under the server's per-prefix throttle (burst of 10, refills
-- 1 per second), holds sends during WoW Forever's in-instance comms lockdown,
-- and reassembles incoming messages.
local _, ns = ...
local C = {}
ns.Comm = C

C.PREFIX = "BlindTiger"
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
-- Whisper targets. WoW Forever has no realms, and some name forms aren't
-- found by the server; when a whisper bounces we retry with the short name,
-- and stop whispering someone who has gone offline.
local alias = {}                 -- [name as heard] = name that works
local unreachable = {}           -- [name as heard] = GetTime() until which we skip them
local lastWhisper = {}           -- [name sent to] = { orig = name as heard, at = GetTime() }
local recent = {}                -- [name as heard] = whispers of the last seconds, to resend after a bounce
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
        if item.dist == "WHISPER" and (unreachable[item.target] or 0) > now then
            table.remove(queue, i)
            C.stats.dropped = C.stats.dropped + 1
        elseif b.tokens < 1 then
            i = i + 1
        else
            local target = item.target
            if item.dist == "WHISPER" then
                target = alias[target] or target
                lastWhisper[target] = { orig = item.target, at = now }
            end
            -- Some builds throw instead of returning a code during lockdown.
            local called, result = pcall(C_ChatInfo.SendAddonMessage, C.PREFIX, item.msg, item.dist, target)
            if not called then
                C.lastError = tostring(result):sub(1, 120)      -- shown by /tiger status, to tell a real error from the lockdown
                result = RESULT_LOCKDOWN
            end
            if result == true or result == nil then result = RESULT_OK end
            if result == false then result = 9 end
            if result == RESULT_OK then
                b.tokens = b.tokens - 1
                table.remove(queue, i)
                C.stats.sent = C.stats.sent + 1
                if item.dist == "WHISPER" and not alias[item.target] then
                    local r = recent[item.target]
                    if not r then
                        r = {}
                        recent[item.target] = r
                    end
                    if #r < 40 then r[#r + 1] = { msg = item.msg, at = now } end
                end
            elseif result == RESULT_LOCKDOWN then
                C.lastHold = C.lastError and "error" or "code 11"
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
    for name, w in pairs(lastWhisper) do
        if now - w.at > 30 then lastWhisper[name] = nil end
    end
    for name, r in pairs(recent) do
        if #r == 0 or now - r[#r].at > 15 then recent[name] = nil end
    end
end

-- "No player named 'X' is currently playing." after one of our whispers.
local NOT_FOUND = ns.U.FormatPattern(ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing.")

-- Returns true when the message was caused by a Blind Tiger whisper.
function C.OnSystemMessage(msg)
    if type(msg) ~= "string" then return false end
    local name = msg:match(NOT_FOUND)
    local w = name and lastWhisper[name]
    if not w or GetTime() - w.at > 10 then return false end
    local short = ns.U.ShortName(w.orig)
    if name ~= (alias[w.orig] or w.orig) then return true end   -- a late bounce from the old form
    if not alias[w.orig] and short ~= w.orig then
        alias[w.orig] = short                    -- try the short name next
        -- Send again what just bounced, under the name that works.
        for _, sent in ipairs(recent[w.orig] or {}) do
            if GetTime() - sent.at <= 10 then
                queue[#queue + 1] = { dist = "WHISPER", target = w.orig, msg = sent.msg }
            end
        end
        recent[w.orig] = nil
    else
        unreachable[w.orig] = GetTime() + 60     -- offline: stop for a minute
    end
    return true
end

ns.On("CHAT_MSG_SYSTEM", function(msg) C.OnSystemMessage(msg) end)

ns.On("PLAYER_LOGIN", function()
    -- Keep those bounce messages out of the chat window.
    local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if addFilter then
        pcall(addFilter, "CHAT_MSG_SYSTEM", function(_, _, msg)
            local name = type(msg) == "string" and msg:match(NOT_FOUND)
            local w = name and lastWhisper[name]
            return (w and GetTime() - w.at <= 10) and true or false
        end)
    end
    C_ChatInfo.RegisterAddonMessagePrefix(C.PREFIX)
    C_Timer.NewTicker(0.25, pump)
    C_Timer.NewTicker(30, sweep)
end)
ns.On("CHAT_MSG_ADDON", onAddonMessage)
