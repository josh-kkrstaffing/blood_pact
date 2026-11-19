-- Blood Pact: utilities (pure Lua, no WoW API). Serializer, hash, text safety.
local _, ns = ...
local U = {}
ns.U = U

local floor, format, type, pairs, tostring, tonumber = math.floor, string.format, type, pairs, tostring, tonumber

---------------------------------------------------------------------------
-- Text shown in the UI. WoW renders "|" escape codes (colors, links, icons),
-- so every string that came from another player is escaped before display.
---------------------------------------------------------------------------
function U.Safe(text, maxLen)
    if text == nil then return "" end
    text = tostring(text)
    if maxLen and #text > maxLen then text = text:sub(1, maxLen) end
    return (text:gsub("|", "||"))
end

---------------------------------------------------------------------------
-- 32-bit djb2 hash, arithmetic only (WoW's Lua 5.1 and test Lua 5.3 agree).
---------------------------------------------------------------------------
function U.Hash(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + s:byte(i)) % 4294967296
    end
    return format("%08x", h)
end

---------------------------------------------------------------------------
-- Serializer: deterministic (sorted keys), length-prefixed strings, no NULs.
--   s<len>:<bytes>   #<number>;   t / f   { key value key value ... }
---------------------------------------------------------------------------
local function keyLess(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta < tb end
    return a < b
end

local function encode(v, out, depth)
    if depth > 12 then error("Encode: too deep") end
    local t = type(v)
    if t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then error("Encode: bad number") end
        if v == floor(v) and v > -9007199254740992 and v < 9007199254740992 then
            out[#out + 1] = format("#%d;", v)
        else
            out[#out + 1] = format("#%.17g;", v)
        end
    elseif t == "boolean" then
        out[#out + 1] = v and "t" or "f"
    elseif t == "table" then
        local keys = {}
        for k in pairs(v) do
            local tk = type(k)
            if tk == "string" or tk == "number" then keys[#keys + 1] = k end
        end
        table.sort(keys, keyLess)
        out[#out + 1] = "{"
        for i = 1, #keys do
            local k = keys[i]
            encode(k, out, depth + 1)
            encode(v[k], out, depth + 1)
        end
        out[#out + 1] = "}"
    else
        error("Encode: unsupported type " .. t)
    end
end

function U.Encode(v)
    local out = {}
    encode(v, out, 0)
    return table.concat(out)
end

local MAX_STRING = 4096

local function decode(s, i, depth)
    if depth > 12 then error("Decode: too deep") end
    local c = s:sub(i, i)
    if c == "s" then
        local colon = s:find(":", i + 1, true)
        if not colon then error("Decode: bad string") end
        local len = tonumber(s:sub(i + 1, colon - 1))
        if not len or len < 0 or len > MAX_STRING or colon + len > #s then error("Decode: bad length") end
        return s:sub(colon + 1, colon + len), colon + len + 1
    elseif c == "#" then
        local semi = s:find(";", i + 1, true)
        if not semi then error("Decode: bad number") end
        local n = tonumber(s:sub(i + 1, semi - 1))
        if not n then error("Decode: bad number") end
        return n, semi + 1
    elseif c == "t" then
        return true, i + 1
    elseif c == "f" then
        return false, i + 1
    elseif c == "{" then
        local tbl, count = {}, 0
        i = i + 1
        while s:sub(i, i) ~= "}" do
            if i > #s then error("Decode: unterminated table") end
            local k, v
            k, i = decode(s, i, depth + 1)
            v, i = decode(s, i, depth + 1)
            if type(k) ~= "string" and type(k) ~= "number" then error("Decode: bad key") end
            tbl[k] = v
            count = count + 1
            if count > 2000 then error("Decode: table too large") end
        end
        return tbl, i + 1
    end
    error("Decode: unexpected '" .. c .. "'")
end

-- Returns value or nil, errorMessage. Never throws.
function U.Decode(s)
    if type(s) ~= "string" or #s == 0 then return nil, "empty" end
    local ok, v, nextI = pcall(decode, s, 1, 0)
    if not ok then return nil, v end
    if nextI ~= #s + 1 then return nil, "trailing data" end
    return v
end

function U.Copy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = U.Copy(v) end
    return c
end

-- Turn a game message format ("%s has joined the guild.") into a Lua pattern.
function U.FormatPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("%%%d%$s", "\001"):gsub("%%s", "\001")
    p = p:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("\001", "(.+)")
    return "^" .. p .. "$"
end

-- "0.10.2" vs "0.9.0": true when a is newer than b.
function U.VersionNewer(a, b)
    local function parts(v)
        local out = {}
        for n in tostring(v or ""):gmatch("%d+") do out[#out + 1] = tonumber(n) end
        return out
    end
    local x, y = parts(a), parts(b)
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p > q end
    end
    return false
end

function U.ShortName(fullName)
    if not fullName then return "?" end
    return (fullName:match("^[^-]+")) or fullName
end
