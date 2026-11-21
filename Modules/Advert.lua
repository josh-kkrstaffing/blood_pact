-- Blood Pact: advertising your crafting in Trade chat.
-- On your own recipe list you tick up to four recipes, and one click posts a
-- "looking for work" line to the Trade channel with your skill, the city
-- you are in, and those recipes as links. One post per click, and no more
-- than one a minute: the addon never repeats it by itself.
local _, ns = ...
local A = {}
ns.Advert = A

local U = ns.U

A.MAX_LINKS = 4
A.WAIT = 60                 -- seconds between posts
A.CHAT_MAX = 255
A.EXTRA_MAX = 60
A.DEFAULT_EXTRA = "Tips appreciated."

---------------------------------------------------------------------------
-- Pure logic
---------------------------------------------------------------------------
-- "[Enchanting] 225/300 LFW in Undercity. Tips appreciated."
function A.Text(prof, level, max, zone, extra)
    local skill = max and (level .. "/" .. max) or tostring(level)
    local text = ("[%s] %s LFW%s."):format(prof, skill, zone and zone ~= "" and (" in " .. zone) or "")
    extra = tostring(extra or ""):gsub("%s+", " "):match("^%s*(.-)%s*$"):sub(1, A.EXTRA_MAX)
    if extra ~= "" then text = text .. " " .. extra end
    return text
end

-- Fit the text and the links into at most two chat lines. A link counts at
-- its full hidden length, so four rarely fit on one line.
-- -> { line1, line2? }, and how many links made it in
function A.Pack(text, links, max)
    max = max or A.CHAT_MAX
    local lines, used = { text:sub(1, max) }, 0
    for _, link in ipairs(links) do
        local cur = lines[#lines]
        if #cur + 1 + #link <= max then
            lines[#lines] = cur .. " " .. link
            used = used + 1
        elseif #lines < 2 and #link <= max then
            lines[2] = link
            used = used + 1
        else
            break
        end
    end
    return lines, used
end

-- The Trade channel's number from the game's channel list (id, name, disabled, ...).
function A.TradeChannel(...)
    for i = 1, select("#", ...), 3 do
        local id, name, disabled = select(i, ...)
        if type(name) == "string" and name:find("^Trade") and not disabled then return id end
    end
    return nil
end

-- Tick or untick a recipe. -> the new list, or nil and why
function A.Toggle(list, id, max)
    local out, had = {}, false
    for _, x in ipairs(list or {}) do
        if x == id then had = true else out[#out + 1] = x end
    end
    if had then return out end
    if #out >= (max or A.MAX_LINKS) then return nil, ("You can link %d recipes at most. Untick one first."):format(max or A.MAX_LINKS) end
    out[#out + 1] = id
    return out
end

---------------------------------------------------------------------------
-- Game side
---------------------------------------------------------------------------
local lastPost = -1000

function A.Links(prof)
    local c = ns.Char()
    c.adLinks = c.adLinks or {}
    return c.adLinks[prof] or {}
end

function A.IsLinked(prof, id)
    for _, x in ipairs(A.Links(prof)) do if x == id then return true end end
    return false
end

function A.ToggleLink(prof, id)
    local list, why = A.Toggle(A.Links(prof), id)
    if not list then return nil, why end
    ns.Char().adLinks[prof] = list
    return true
end

function A.Extra()
    local e = ns.Char().adExtra
    return type(e) == "string" and e or A.DEFAULT_EXTRA
end

-- The lines a post would send right now.
function A.Build(prof, skill)
    local known = ns.Reducer.State()
    known = known and known.recipes[ns.MyGUID()] and known.recipes[ns.MyGUID()][prof] or {}
    local links = {}
    for _, id in ipairs(A.Links(prof)) do
        if known[id] then links[#links + 1] = ns.Orders.RecipeLink(id) end
    end
    local zone = GetZoneText and GetZoneText() or ""
    return A.Pack(A.Text(prof, skill.level, skill.max, zone, A.Extra()), links)
end

-- Post it, from the player's click. -> a line for the player, or nil and why
function A.Post(prof, skill)
    if ns.mock then return nil, "Test mode is on, so nothing is posted." end
    local left = A.WAIT - (GetTime() - lastPost)
    if left > 0 then return nil, ("One post a minute. Try again in %d seconds."):format(math.ceil(left)) end
    local channel = type(GetChannelList) == "function" and A.TradeChannel(GetChannelList()) or nil
    if not channel then return nil, "You're not in the Trade channel. It is only there in a city." end
    local lines = A.Build(prof, skill)
    local ok, why = ns.Chat(lines[1], "CHANNEL", channel)
    if not ok then
        -- The game refused it from an addon: put the words in the chat box for the player to send.
        local open = ChatFrame_OpenChat or (ChatFrameUtil and ChatFrameUtil.OpenChat)
        local text = A.Text(prof, skill.level, skill.max, GetZoneText and GetZoneText() or "", A.Extra())
        if open and pcall(open, "/" .. channel .. " " .. text) then
            return nil, (why == "locked" and ns.CHAT_LOCKED or "The game didn't post it.") .. " The line is in your chat box: press Enter. Shift-click recipes to add links."
        end
        return nil, why == "locked" and ns.CHAT_LOCKED or "The game didn't post it."
    end
    if lines[2] then ns.Chat(lines[2], "CHANNEL", channel) end
    lastPost = GetTime()
    return "Posted in Trade chat."
end
