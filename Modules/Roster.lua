-- Blood Pact: guild roster manager. Join dates, rank history, alts and a log
-- of guild changes, all on the synced log so every officer sees the same thing.
-- Team Captains and above record changes from two sources:
--   1. the game's guild system messages, live ("X has promoted Y to Z")
--   2. comparing the roster with what they saw last time (catches changes
--      made while they were offline; the actor isn't known then)
-- The first time it runs it only remembers the roster; history starts there.
local _, ns = ...
local R = {}
ns.Roster = R

local Log, Red, RBAC = ns.Log, ns.Reducer, ns.RBAC
local date = date or os.date   -- WoW global; os.date in tests

-- Turn a game message format ("%s has joined the guild.") into a Lua pattern.
R.Pattern = ns.U.FormatPattern

local PATTERNS = {
    { "join", ERR_GUILD_JOIN_S or "%s has joined the guild." },
    { "leave", ERR_GUILD_LEAVE_S or "%s has left the guild." },
    { "kick", ERR_GUILD_REMOVE_SS or "%s has been kicked out of the guild by %s." },
    { "promote", ERR_GUILD_PROMOTE_SSS or "%s has promoted %s to %s." },
    { "demote", ERR_GUILD_DEMOTE_SSS or "%s has demoted %s to %s." },
}
for _, p in ipairs(PATTERNS) do p[3] = R.Pattern(p[2]) end

-- A guild system message -> { ev, name, by } or nil.
function R.ParseSystem(msg)
    for _, p in ipairs(PATTERNS) do
        local a, b = msg:match(p[3])
        if a then
            if p[1] == "join" or p[1] == "leave" then return { ev = p[1], name = a } end
            if p[1] == "kick" then return { ev = "kick", name = a, by = b } end
            return { ev = p[1], name = b, by = a }   -- "<by> has promoted <name> to <rank>"
        end
    end
end

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- What changed between two roster snapshots ({ [guid] = {name, ri, rank} }).
-- Changes the synced log already shows are left out. nil = the new roster
-- looks incomplete (the game sometimes sends a partial roster at login).
function R.Diff(old, new, st)
    local nOld, nNew = count(old), count(new)
    if nNew == 0 then return nil end
    local members = st and st.members or {}
    local out, missing = {}, 0
    for guid, m in pairs(new) do
        local o, known = old[guid], members[guid]
        if not o then
            if not (known and known.inGuild) then
                out[#out + 1] = { ev = "join", who = guid, name = m.name, ri = m.ri, rank = m.rank }
            end
        elseif o.ri ~= m.ri and m.ri and o.ri then
            if not (known and known.ri == m.ri) then
                out[#out + 1] = { ev = m.ri < o.ri and "promote" or "demote", who = guid, name = m.name, ri = m.ri, rank = m.rank }
            end
        end
    end
    for guid, o in pairs(old) do
        if not new[guid] then
            missing = missing + 1
            local known = members[guid]
            if not (known and known.inGuild == false) then
                out[#out + 1] = { ev = "leave", who = guid, name = o.name, ri = o.ri, rank = o.rank }
            end
        end
    end
    if missing > 3 and nNew < nOld * 0.9 then return nil end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function R.Idem(c, now)
    return ("%s:%s:%s:%s"):format(c.ev, c.who, tostring(c.ri or ""), date("!%Y-%m-%d", now))
end

---------------------------------------------------------------------------
-- Game side
---------------------------------------------------------------------------
local pending = {}   -- [name] = { ev, by, at } from live system messages

local function short(name) return name and name:match("^[^-]+") or name end

local function current()
    local snap = {}
    for guid, m in pairs(ns.roster.byGUID) do
        snap[guid] = { name = m.name, ri = m.rankIndex, rank = m.rank }
    end
    return snap
end

function R.Scan()
    if ns.mock or not ns.roster.loaded or not ns.roster.complete or not RBAC.ICan("roster") then return end
    local g = ns.G()
    if not g then return end
    local now = current()
    if not g.snap then g.snap = now; return end   -- first run: remember, log nothing
    local changes = R.Diff(g.snap, now, Red.State())
    if not changes then return end
    local t = ns.Now()
    for _, c in ipairs(changes) do
        local live = pending[c.name] or pending[short(c.name)]
        local d = { ev = c.ev, who = c.who, name = c.name:sub(1, 48), ri = c.ri,
            rank = c.rank and c.rank:sub(1, 32) or nil, idem = R.Idem(c, t) }
        if live and t - live.at < 600 then
            if live.ev == "kick" and c.ev == "leave" then d.ev = "kick"; d.idem = R.Idem(d, t) end
            if live.by then d.by = live.by:sub(1, 48) end
            d.live = true
        end
        Log.New("ROSTER", d)
    end
    g.snap = now
end

local scheduled
local function scanSoon()
    if scheduled then return end
    scheduled = true
    -- Several officers see the same change. A random wait lets the first one's
    -- record reach the others before they write their own.
    C_Timer.After(3 + math.random() * 12, function() scheduled = false; R.Scan() end)
end
ns.Listen("ROSTER_CHANGED", scanSoon)

ns.On("CHAT_MSG_SYSTEM", function(msg)
    local p = type(msg) == "string" and R.ParseSystem(msg)
    if not p then return end
    pending[p.name] = { ev = p.ev, by = p.by, at = ns.Now() }
    pending[short(p.name)] = pending[p.name]
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
end)

function R.LinkAlt(altName, mainGUID)
    if not RBAC.ICan("altlink") then return nil, "Only Officers and above can link alts." end
    local alt = ns.GUIDForName(tostring(altName or ""):match("^%s*(.-)%s*$"))
    if not alt then return nil, "No guild member named " .. tostring(altName) .. "." end
    if not mainGUID then return nil, "Select the main first." end
    if alt == mainGUID then return nil, "A character can't be its own alt." end
    local st = Red.State()
    if st and st.alts[mainGUID] then return nil, "That character is an alt. Pick the main." end
    return Log.New("ALT_LINK", { alt = alt, main = mainGUID })
end

function R.Unlink(altGUID)
    if not RBAC.ICan("altlink") then return nil, "Only Officers and above can unlink alts." end
    return Log.New("ALT_UNLINK", { alt = altGUID })
end

-- One line of the guild log.
function R.Describe(e)
    local d = e.d
    local name = function(guid) return ns.NameForGUID(guid) or (Red.State() and Red.State().members[guid] or {}).name or "?" end
    if e.k == "ALT_LINK" then return ("%s linked as an alt of %s"):format(name(d.alt), name(d.main)) end
    if e.k == "ALT_UNLINK" then return ("%s unlinked from its main"):format(name(d.alt)) end
    local by = d.by and (" by " .. d.by) or ""
    if d.ev == "join" then return d.name .. " joined the guild" end
    if d.ev == "leave" then return d.name .. " left the guild" end
    if d.ev == "kick" then return d.name .. " was removed" .. by end
    return ("%s %s to %s%s"):format(d.name, d.ev == "promote" and "promoted" or "demoted", d.rank or "?", by)
end

---------------------------------------------------------------------------
-- Roster tab (everyone; alt links for Officers and above)
---------------------------------------------------------------------------
local W, U = ns.W, ns.U
local view, selected, filter = "members", nil, ""
local sortKey, sortDesc, onlineOnly = "rank", false, false
local classFilter              -- a class token such as "MAGE", or nil for every class
local pane = "details"         -- right side of the Members view: "details", "loot" or "classes"

R.MAX_TELLS = 40               -- most members one click may whisper
R.PIE_SPOKES = 120             -- the pie is drawn as this many thin wedges

-- "WARLOCK" -> "Warlock", for when the game gives no display name.
function R.ClassLabel(token, label)
    if type(label) == "string" and label ~= "" then return label end
    if type(token) ~= "string" or token == "" then return "Unknown" end
    return token:sub(1, 1):upper() .. token:sub(2):lower()
end

-- How many members of each class. Biggest first. onlyOnline counts just who is on.
--   -> { { class =, label =, n =, pct = }, ... }, total
function R.ClassCounts(roster, onlyOnline)
    local by, total = {}, 0
    for _, m in pairs(roster) do
        if m.online or not onlyOnline then
            local token = m.class or "UNKNOWN"
            local c = by[token]
            if not c then
                c = { class = token, label = R.ClassLabel(m.class, m.classLabel), n = 0 }
                by[token] = c
            end
            c.n = c.n + 1
            total = total + 1
        end
    end
    local out = {}
    for _, c in pairs(by) do
        c.pct = total > 0 and math.floor(c.n * 100 / total + 0.5) or 0
        out[#out + 1] = c
    end
    table.sort(out, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.label < b.label
    end)
    return out, total
end

-- Which class each wedge of the pie belongs to, clockwise from the top, in
-- the order of counts. Every class gets at least one wedge, so a class with
-- a single member still shows.
function R.Slices(counts, total, spokes)
    local out, share, sum = {}, {}, 0
    if total <= 0 or #counts == 0 then return out end
    for i, c in ipairs(counts) do
        share[i] = math.max(1, math.floor(c.n * spokes / total + 0.5))
        sum = sum + share[i]
    end
    -- Rounding can leave a wedge or two over or under: the biggest class absorbs it.
    local big = 1
    for i = 2, #counts do if share[i] > share[big] then big = i end end
    share[big] = math.max(1, share[big] + (spokes - sum))
    for i, c in ipairs(counts) do
        for _ = 1, share[i] do
            if #out < spokes then out[#out + 1] = c.class end
        end
    end
    return out
end

-- Who a class message goes to: online members in these rows, never me.
function R.Audience(rows, online, me, max)
    local names = {}
    for _, r in ipairs(rows) do
        if r.guid ~= me and online[r.guid] and #names < (max or R.MAX_TELLS) then names[#names + 1] = r.name end
    end
    return names
end

local function day(t) return t and date("%b %d, %Y", t) or "-" end

local function lastOn(m)
    if m.online then return "online" end
    if not m.offlineDays then return "-" end
    if m.offlineDays == 0 then return "today" end
    return m.offlineDays .. "d ago"
end

-- Sort member rows by a column. Ties go by name. Members with nothing in
-- that column (no join date, never seen) stay at the bottom either way.
function R.Sort(rows, key, desc)
    local function value(r)
        if key == "name" then return r.name:lower() end
        if key == "level" then return r.level end
        if key == "class" then return (r.classLabel or ""):lower() end
        if key == "joined" then return r.joined end
        if key == "last" then return r.lastKey end
        return r.ri
    end
    table.sort(rows, function(a, b)
        local x, y = value(a), value(b)
        if x ~= y then
            if x == nil then return false end
            if y == nil then return true end
            if desc then return x > y end
            return x < y
        end
        local an, bn = a.name:lower(), b.name:lower()
        if an ~= bn then return an < bn end
        return a.guid < b.guid
    end)
    return rows
end

function R.Rows(st)
    local rows = {}
    for guid, m in pairs(ns.roster.byGUID) do
        local known = st and st.members[guid]
        local main = st and st.alts[guid]
        local nm = m.name or "?"
        if (filter == "" or nm:lower():find(filter, 1, true)) and (m.online or not onlineOnly)
            and (classFilter == nil or (m.class or "UNKNOWN") == classFilter) then
            local level = "unknown"
            if st then level = ns.Officer.Level(ns.Officer.ActiveDays(st, ns.roster.byGUID, guid, ns.Now()), st.settings) end
            rows[#rows + 1] = { guid = guid, name = nm, rank = m.rank or "", ri = m.rankIndex or 9, level = m.level or 0,
                class = m.class or "UNKNOWN", classLabel = R.ClassLabel(m.class, m.classLabel),
                joined = known and known.joined, main = main, activity = level,
                lastKey = m.online and -1 or m.offlineDays,       -- smaller = seen more recently
                pvp = st and st.pvp[guid],
                last = "|cff" .. ns.Officer.LEVEL_COLOR[level] .. lastOn(m) .. "|r" }
        end
    end
    return R.Sort(rows, sortKey, sortDesc)
end

-- Room the tab needs, and the window width: the Roster is the widest tab.
-- The right-hand pane decides the height: the class chart, or a member's
-- details with the alt tools under them (Officers), open or folded.
function R.Need(p)
    local h = 200
    if view == "members" then
        if pane == "classes" then
            h = RBAC.ICan("schedule") and 300 or 215
        elseif pane == "loot" then
            h = 170
        else
            h = 48 + 196 + (RBAC.ICan("altlink") and (8 + p.altFold:Height()) or 0)
        end
    end
    return h, 800
end

function R.SetClassFilter(token) classFilter = token end
function R.ClassFilter() return classFilter end

-- Team Captain and above: one whisper to each online member of the chosen
-- class, from this click. Guild members only.
function R.MessageClass(text)
    if not RBAC.ICan("schedule") then return nil, "Only Team Captains and above can message a class." end
    if not classFilter then return nil, "Pick a class first." end
    text = tostring(text or ""):match("^%s*(.-)%s*$")
    if text == "" then return nil, "Type the message first." end
    if #text > 255 then return nil, "That message is too long for one whisper (255 letters)." end
    local online = {}
    for guid, m in pairs(ns.roster.byGUID) do online[guid] = m.online and true or nil end
    local names = R.Audience(R.Rows(Red.State()), online, ns.MyGUID(), R.MAX_TELLS)
    if #names == 0 then return nil, "Nobody of that class is online." end
    if ns.mock then return #names end      -- test mode never whispers anyone
    local ok, why = ns.Chat(text, "WHISPER", U.ShortName(names[1]))
    if not ok then return nil, why == "locked" and ns.CHAT_LOCKED or "The game didn't send the whispers." end
    for i = 2, #names do
        C_Timer.After((i - 1) * 0.3, function() ns.Chat(text, "WHISPER", U.ShortName(names[i])) end)
    end
    return #names
end

local function classColor(token)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c then return c.r, c.g, c.b end
    return 0.6, 0.6, 0.6
end

ns.UI.AddTab("roster", "Roster", "view", function(p)
    p.membersBtn = W.Button(p, "Members", 90, 22, function() view = "members"; ns.UI.Refresh() end)
    p.membersBtn:SetPoint("TOPLEFT", 0, 0)
    p.logBtn = W.Button(p, "Guild log", 90, 22, function() view = "log"; ns.UI.Refresh() end)
    p.logBtn:SetPoint("TOPLEFT", 94, 0)
    p.tasksBtn = W.Button(p, "Officer tasks", 110, 22, function() view = "tasks"; ns.UI.Refresh() end)
    p.tasksBtn:SetPoint("TOPLEFT", 188, 0)
    p.searchLabel = W.Text(p, "Search", "GameFontHighlightSmall")
    p.searchLabel:SetPoint("TOPLEFT", 310, -5)
    p.search = W.Edit(p, 120, 30)
    p.search:SetPoint("TOPLEFT", 354, -1)
    p.search:SetScript("OnTextChanged", function(self)
        filter = (self:GetText() or ""):lower()
        if view == "members" then ns.UI.Refresh() end
    end)
    p.count = W.Text(p, "", "GameFontDisableSmall")
    p.online = W.Check(p, "Online only", function(on) onlineOnly = on; ns.UI.Refresh() end)
    p.online:SetPoint("TOPLEFT", 486, -4)
    p.count:SetPoint("TOPLEFT", 590, -5)
    p.count:SetWidth(200)
    p.count:SetWordWrap(false)

    -- Members view
    -- Press a column to sort by it; press it again to flip the order.
    p.head = {}
    for _, h in ipairs({ { "Name", "name", 0, 144 }, { "Rank", "rank", 146, 92 }, { "Class", "class", 240, 70 },
        { "Lvl", "level", 312, 38 }, { "Joined", "joined", 352, 74 }, { "Last on", "last", 428, 62 } }) do
        local b = W.SortButton(p, h[1], h[4], function()
            if sortKey == h[2] then sortDesc = not sortDesc else sortKey, sortDesc = h[2], false end
            ns.UI.Refresh()
        end)
        b:SetPoint("TOPLEFT", h[3], -24)
        b.key = h[2]
        p.head[#p.head + 1] = b
    end
    p.list = W.List(p, 490, 310, 16, function(row, r)
        -- PvP rank badge to the left of the name; hover the row for the rank's name.
        if not row.badge then
            row.badge = row:CreateTexture(nil, "ARTWORK")
            row.badge:SetSize(14, 14)
            row.badge:SetPoint("LEFT", 4, 0)
            row:SetScript("OnEnter", function(self)
                if self.item then ns.PvP.Tooltip(self, self.item.name, self.item.pvp) end
            end)
            row:SetScript("OnLeave", GameTooltip_Hide)
        end
        local icon = r.pvp and ns.PvP.Icon(r.pvp.r)
        row.badge:SetShown(icon ~= nil)
        if icon then row.badge:SetTexture(icon) end
        p.list.Col(row, 1, 22, 122):SetText(U.Safe(r.name, 40) .. (r.main and " |cff808080(alt)|r" or ""))
        p.list.Col(row, 2, 151, 86):SetText(U.Safe(r.rank, 32))
        local class = p.list.Col(row, 6, 245, 64)
        class:SetText(U.Safe(r.classLabel, 16))
        class:SetTextColor(classColor(r.class))
        p.list.Col(row, 3, 317, 32):SetText(r.level)
        p.list.Col(row, 4, 357, 70):SetText(day(r.joined))
        p.list.Col(row, 5, 433, 54):SetText(r.last)
    end, function(r) selected = r.guid; ns.UI.Refresh() end)
    p.list:Stretch(0, -44, nil, 0)
    p.list.key = "guid"

    -- Detail of the selected member
    p.classBtn = W.Button(p, "Classes", 70, 18, function() pane = "classes"; ns.UI.Refresh() end)
    p.classBtn:SetPoint("TOPLEFT", 520, -24)
    p.detailBtn = W.Button(p, "Details", 70, 18, function() pane = "details"; ns.UI.Refresh() end)
    p.detailBtn:SetPoint("TOPLEFT", 594, -24)
    p.lootBtn = W.Button(p, "Loot", 80, 18, function() pane = "loot"; ns.UI.Refresh() end)
    p.lootBtn:SetPoint("TOPLEFT", 668, -24)

    -- Classes: a pie of the guild by class, a legend to filter with, and a
    -- message to the online members of the chosen class.
    local cp = CreateFrame("Frame", nil, p)
    cp:SetPoint("TOPLEFT", 520, -48)
    cp:SetSize(240, 300)
    p.classPane = cp
    cp.pie = CreateFrame("Frame", nil, cp)
    cp.pie:SetSize(110, 110)
    cp.pie:SetPoint("TOPLEFT", 0, 0)
    cp.spokes = {}
    if cp.pie.CreateLine then
        local radius = 54
        for i = 1, R.PIE_SPOKES do
            local angle = (i - 0.5) / R.PIE_SPOKES * 2 * math.pi       -- clockwise from the top
            local line = cp.pie:CreateLine(nil, "ARTWORK")
            line:SetThickness(3.6)
            line:SetStartPoint("CENTER", cp.pie, 0, 0)
            line:SetEndPoint("CENTER", cp.pie, radius * math.sin(angle), radius * math.cos(angle))
            cp.spokes[i] = line
        end
    end
    cp.rows = {}
    for i = 1, 10 do
        local b = CreateFrame("Button", nil, cp)
        b:SetSize(122, 13)
        b:SetPoint("TOPLEFT", 118, -(i - 1) * 13)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        b.sel = b:CreateTexture(nil, "BACKGROUND")
        b.sel:SetAllPoints()
        b.sel:SetColorTexture(W.C.accent[1], W.C.accent[2], W.C.accent[3], 0.3)
        b.swatch = b:CreateTexture(nil, "ARTWORK")
        b.swatch:SetSize(8, 8)
        b.swatch:SetPoint("LEFT", 2, 0)
        b.bar = b:CreateTexture(nil, "BORDER")                           -- used when the pie can't be drawn
        b.bar:SetPoint("LEFT", 0, 0)
        b.bar:SetHeight(11)
        b.name = W.Text(b, "", "GameFontHighlightSmall")
        b.name:SetPoint("LEFT", 14, 0)
        b.num = W.Text(b, "", "GameFontDisableSmall")
        b.num:SetPoint("RIGHT", -2, 0)
        b.num:SetJustifyH("RIGHT")
        b:SetScript("OnClick", function(self)
            if not self.class then return end
            classFilter = (classFilter ~= self.class) and self.class or nil      -- click again to clear
            ns.UI.Refresh()
        end)
        cp.rows[i] = b
    end
    cp.hint = W.Text(cp, "", "GameFontDisableSmall")
    cp.hint:SetPoint("TOPLEFT", 0, -136)
    cp.hint:SetWidth(240)
    cp.msgBox = W.Edit(cp, 240, 200)
    cp.msgBox:SetPoint("TOPLEFT", 0, -168)
    cp.send = W.Button(cp, "Whisper them", 240, 22, function()
        local n, why = R.MessageClass(cp.msgBox:GetText())
        if n then
            ns.UI.Say(("Whispered %d online %s."):format(n, n == 1 and "member" or "members"))
            cp.msgBox:SetText("")
        else
            ns.UI.Say(why or "That didn't work.")
        end
    end, "accent")
    cp.send:SetPoint("TOPLEFT", 0, -194)
    cp.msgHint = W.Text(cp, "One click whispers each online member of the chosen class. Team Captains and above.", "GameFontDisableSmall")
    cp.msgHint:SetPoint("TOPLEFT", 0, -222)
    cp.msgHint:SetWidth(240)

    p.detail = W.Text(p, "", "GameFontHighlightSmall")
    p.detail:SetPoint("TOPLEFT", 520, -48)
    p.detail:SetWidth(240)
    p.detail:SetJustifyV("TOP")
    p.detail:SetHeight(196)
    -- The selected member's loot: icon, item, date, DKP. Hover for the item's stats.
    p.loot = W.List(p, 224, 280, 20, function(row, e) ns.Loot.Render(p.loot, row, e, false) end,
        function(e) ns.Loot.Click(e) end)
    p.loot:Stretch(520, -48, 0, 0)
    p.loot.key = "id"
    -- Linking alts is an occasional officer job: it folds away under the details.
    p.altFold = W.Accordion(p, "Link or unlink an alt", 240, 78, "rosterAlts")
    p.altFold:SetPoint("TOPLEFT", 520, -250)
    local ab = p.altFold.body
    p.altBox = W.Edit(ab, 120, 48)
    p.altBox:SetPoint("TOPLEFT", 0, 0)
    p.link = W.Button(ab, "Link as alt", 100, 22, function()
        if ns.UI.Try("Alt linked.", R.LinkAlt, p.altBox:GetText(), selected) then p.altBox:SetText("") end
    end, "accent")
    p.link:SetPoint("TOPLEFT", 126, 0)
    p.altHint = W.Text(ab, "Type an alt's name, then link it to the selected main.", "GameFontDisableSmall")
    p.altHint:SetPoint("TOPLEFT", 0, -28)
    p.altHint:SetWidth(240)
    p.unlink = W.Button(ab, "Unlink selected alt", 150, 22, function()
        if selected then ns.UI.Try("Alt unlinked.", R.Unlink, selected) end
    end)
    p.unlink:SetPoint("TOPLEFT", 0, -54)

    -- Log view
    p.log = W.List(p, 710, 330, 16, function(row, e)
        p.log.Col(row, 1, 4, 130):SetText(date("%b %d %I:%M %p", e.t))
        p.log.Col(row, 2, 136, 560):SetText(U.Safe(R.Describe(e), 120))
    end)
    p.log:Stretch(0, -28, 0, 0)

    -- Officer tasks view (Team Captain and above)
    p.tasks = W.List(p, 710, 250, 18, function(row, task)
        p.tasks.Col(row, 1, 4, 560):SetText(U.Safe(task.text, 140))
        p.tasks.Col(row, 2, 570, 136):SetText(task.claimedBy and ("|cffffd100" .. U.Safe(ns.NameForGUID(task.claimedBy) or "an officer", 30) .. "|r") or "")
    end, function(task) p.taskSel = task.id; ns.UI.Refresh() end)
    p.tasks:Stretch(0, -28, 0, 70)
    p.tasks.key = "id"
    p.tw = CreateFrame("Frame", nil, p)
    p.tw:SetPoint("BOTTOMLEFT", 0, 0)
    p.tw:SetSize(710, 60)
    p.claim = W.Button(p.tw, "Claim", 80, 22, function()
        if p.taskSel then ns.UI.Try("Claimed. Other officers see it's yours.", ns.Officer.Mark, p.taskSel, "claim") end
    end, "accent")
    p.claim:SetPoint("TOPLEFT", 0, 0)
    p.done = W.Button(p.tw, "Done / dismiss", 120, 22, function()
        if p.taskSel then
            if ns.UI.Try("Marked done for every officer.", ns.Officer.Mark, p.taskSel, "done") then p.taskSel = nil end
        end
    end)
    p.done:SetPoint("TOPLEFT", 84, 0)
    W.Text(p.tw, "Command:", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 216, -5)
    p.cmd = W.Edit(p.tw, 220, 80)
    p.cmd:SetPoint("TOPLEFT", 280, -1)
    p.cmd:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    p.cmdHint = W.Text(p.tw, "Ctrl+C, then paste in chat. The game only lets officers do this by hand.", "GameFontDisableSmall")
    p.cmdHint:SetPoint("TOPLEFT", 0, -30)
end, function(p)
    local st = Red.State()
    local canTasks = RBAC.ICan("roster")
    if view == "tasks" and not canTasks then view = "members" end
    local members, tasks = view == "members", view == "tasks"
    p.membersBtn:SetEnabled(not members)
    p.logBtn:SetEnabled(view ~= "log")
    p.tasksBtn:SetShown(canTasks)
    p.tasksBtn:SetEnabled(not tasks)
    p.tasks.scroll:SetShown(tasks)
    p.tw:SetShown(tasks)
    p.searchLabel:SetShown(members)
    for _, b in ipairs(p.head) do
        b:SetShown(members)
        b:SetSort(b.key == sortKey and (sortDesc and "down" or "up") or nil)
    end
    p.online:SetShown(members)
    p.online.label:SetShown(members)
    p.list.scroll:SetShown(members)
    p.detail:SetShown(members)
    p.detailBtn:SetShown(false)
    p.lootBtn:SetShown(false)
    p.classBtn:SetShown(members)
    p.classBtn:SetEnabled(pane ~= "classes")
    p.classPane:SetShown(false)
    p.loot.scroll:SetShown(false)
    p.search:SetShown(members)
    p.log.scroll:SetShown(view == "log")
    local officer = RBAC.ICan("altlink")
    p.altFold:SetShown(members and officer)

    if tasks then
        local list = ns.Officer.Current()
        local sel
        for _, task in ipairs(list) do if task.id == p.taskSel then sel = task end end
        p.taskSel = sel and sel.id or nil
        p.tasks.selected = sel
        p.tasks:SetItems(list)
        p.count:SetText(#list == 0 and "Nothing to do." or (#list .. " tasks"))
        p.claim:SetEnabled(sel ~= nil)
        p.done:SetEnabled(sel ~= nil)
        p.cmd:SetText(sel and sel.cmd or "")
        return
    end
    if not members then
        local list = {}
        for i = #(st and st.rosterLog or {}), 1, -1 do list[#list + 1] = st.rosterLog[i] end
        p.log:SetItems(list)
        p.count:SetText(#list .. " changes recorded")
        return
    end

    -- A class that has left the guild can't stay as the filter.
    local counts, total = R.ClassCounts(ns.roster.byGUID, onlineOnly)
    local filterLabel
    for _, c in ipairs(counts) do if c.class == classFilter then filterLabel = c.label end end
    if classFilter and not filterLabel then
        filterLabel = R.ClassLabel(classFilter)
        local any = false
        for _, m in pairs(ns.roster.byGUID) do if (m.class or "UNKNOWN") == classFilter then any = true end end
        if not any then classFilter, filterLabel = nil, nil end
    end
    local rows = R.Rows(st)
    p.list:SetItems(rows)
    p.count:SetText(#rows .. (#rows == 1 and " member" or " members") .. (filterLabel and ("  |cffffd100" .. U.Safe(filterLabel, 16) .. " only|r") or ""))
    local sel
    for _, r in ipairs(rows) do if r.guid == selected then sel = r end end
    p.list.selected = sel
    p.unlink:SetEnabled(sel ~= nil and sel.main ~= nil)
    p.link:SetEnabled(sel ~= nil and sel.main == nil)
    p.detailBtn:SetShown(sel ~= nil)
    p.lootBtn:SetShown(sel ~= nil)
    p.detailBtn:SetEnabled(pane ~= "details")
    p.lootBtn:SetEnabled(pane ~= "loot")
    if pane == "classes" then
        -- The guild by class: pie, legend, and a message to one class.
        local cp = p.classPane
        p.altFold:SetShown(false)
        p.detail:SetShown(false)
        cp:SetShown(true)
        local slices = R.Slices(counts, total, R.PIE_SPOKES)
        for i, line in ipairs(cp.spokes) do
            line:SetShown(slices[i] ~= nil)
            if slices[i] then
                local r, g, b = classColor(slices[i])
                line:SetColorTexture(r, g, b, (classFilter == nil or classFilter == slices[i]) and 1 or 0.25)
            end
        end
        local noPie = #cp.spokes == 0
        for i, b in ipairs(cp.rows) do
            local c = counts[i]
            b.class = c and c.class or nil
            b:SetShown(c ~= nil)
            if c then
                local r, g, bl = classColor(c.class)
                b.swatch:SetColorTexture(r, g, bl, 1)
                b.swatch:SetShown(not noPie)
                b.bar:SetShown(noPie)
                if noPie then
                    b.bar:SetColorTexture(r, g, bl, 0.35)
                    b.bar:SetWidth(math.max(2, 122 * c.n / math.max(1, counts[1].n)))
                end
                b.name:SetText(U.Safe(c.label, 16))
                b.name:SetTextColor(r, g, bl)
                b.num:SetText(c.n .. "  " .. c.pct .. "%")
                b.sel:SetShown(classFilter == c.class)
            end
        end
        cp.hint:SetText((onlineOnly and (total .. " online. ") or (total .. " members. "))
            .. (classFilter and "Click the class again to show everyone." or "Click a class to list only its members."))
        local can = RBAC.ICan("schedule")
        local online = {}
        for guid, m in pairs(ns.roster.byGUID) do online[guid] = m.online and true or nil end
        local reach = classFilter and #R.Audience(rows, online, ns.MyGUID(), R.MAX_TELLS) or 0
        cp.msgBox:SetShown(can)
        cp.send:SetShown(can)
        cp.msgHint:SetShown(can)
        cp.send:SetEnabled(can and classFilter ~= nil and reach > 0)
        cp.send:SetText(classFilter and ("Whisper %d online %s"):format(reach, U.Safe(filterLabel or "", 16)) or "Pick a class to message")
        return
    end
    if not sel then
        p.detail:SetText("Select a member to see their alts, join date and rank history.")
        return
    end
    -- Details or Loot for the selected member.
    local loot = ns.Loot.For(st, ns.Loot.Entries(st), sel.guid)
    p.lootBtn:SetText("Loot (" .. #loot .. ")")
    if pane == "loot" then
        p.altFold:SetShown(false)
        p.loot.scroll:SetShown(#loot > 0)
        p.loot:SetItems(loot)
        p.detail:SetShown(#loot == 0)
        p.detail:SetText(U.Safe(sel.name, 48) .. " has no loot recorded yet.\n\nLoot shows here when an officer charges DKP for an item in Raid & Loot. Linked alts count together.")
        return
    end
    local known = st and st.members[sel.guid]
    local lines = { U.Safe(sel.name, 48), sel.rank .. ", level " .. sel.level, "Joined: " .. (sel.joined and day(sel.joined) or "before Blood Pact started tracking") }
    if sel.main then
        lines[#lines + 1] = "Alt of: " .. U.Safe(ns.NameForGUID(sel.main) or "?", 48)
    else
        local alts = {}
        for alt, main in pairs(st and st.alts or {}) do
            if main == sel.guid then alts[#alts + 1] = U.Safe(ns.NameForGUID(alt) or "?", 48) end
        end
        table.sort(alts)
        lines[#lines + 1] = "Alts: " .. (#alts > 0 and table.concat(alts, ", ") or "none")
    end
    local gear = st and st.gear[sel.guid]
    lines[#lines + 1] = gear and ("Pre-raid BiS: %d%% owned, %d%% worn (%s)"):format(gear.pre, gear.worn, U.Safe(gear.spec, 24))
        or "Pre-raid BiS: no score yet"
    local rank = sel.pvp and ns.PvP.Valid(sel.pvp.r)
    lines[#lines + 1] = rank and ("PvP rank %d: %s"):format(rank, ns.PvP.Title(rank, ns.PvP.MyFaction()) or "?")
        or (sel.pvp and "PvP rank: none yet" or "PvP rank: not shared yet")
    local pr = st and st.profs[sel.guid]
    if pr then
        local L = ns.Professions.Label
        lines[#lines + 1] = U.Safe(L(pr.p1, pr.l1), 32) .. (pr.p2 and (", " .. U.Safe(L(pr.p2, pr.l2), 32)) or "")
        lines[#lines + 1] = ("First Aid %s, Cooking %s, Fishing %s"):format(tostring(pr.fa or "-"), tostring(pr.ck or "-"), tostring(pr.fi or "-"))
    else
        lines[#lines + 1] = "Professions: not shared yet"
    end
    lines[#lines + 1] = " "
    lines[#lines + 1] = "Rank history:"
    local hist = known and known.history or {}
    if #hist == 0 then lines[#lines + 1] = "  nothing recorded yet" end
    for i = #hist, math.max(1, #hist - 4), -1 do
        lines[#lines + 1] = "  " .. date("%b %d, %Y", hist[i].t) .. "  " .. U.Safe(R.Describe(hist[i]), 80)
    end
    p.detail:SetText(table.concat(lines, "\n"))
end)

ns.UI.Need("roster", R.Need)
