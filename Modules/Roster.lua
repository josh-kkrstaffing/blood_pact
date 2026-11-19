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

local function day(t) return t and date("%b %d, %Y", t) or "-" end

local function lastOn(m)
    if m.online then return "online" end
    if not m.offlineDays then return "-" end
    if m.offlineDays == 0 then return "today" end
    return m.offlineDays .. "d ago"
end

function R.Rows(st)
    local rows = {}
    for guid, m in pairs(ns.roster.byGUID) do
        local known = st and st.members[guid]
        local main = st and st.alts[guid]
        local nm = m.name or "?"
        if filter == "" or nm:lower():find(filter, 1, true) then
            local level = "unknown"
            if st then level = ns.Officer.Level(ns.Officer.ActiveDays(st, ns.roster.byGUID, guid, ns.Now()), st.settings) end
            rows[#rows + 1] = { guid = guid, name = nm, rank = m.rank or "", ri = m.rankIndex or 9, level = m.level or 0,
                joined = known and known.joined, main = main, activity = level,
                last = "|cff" .. ns.Officer.LEVEL_COLOR[level] .. lastOn(m) .. "|r" }
        end
    end
    table.sort(rows, function(a, b)
        if a.ri ~= b.ri then return a.ri < b.ri end
        return a.name < b.name
    end)
    return rows
end

ns.UI.AddTab("roster", "Roster", "view", function(p)
    p.membersBtn = W.Button(p, "Members", 90, 22, function() view = "members"; ns.UI.Refresh() end)
    p.membersBtn:SetPoint("TOPLEFT", 0, 0)
    p.profBtn = W.Button(p, "Professions", 100, 22, function() view = "profs"; ns.UI.Refresh() end)
    p.profBtn:SetPoint("TOPLEFT", 94, 0)
    p.logBtn = W.Button(p, "Guild log", 90, 22, function() view = "log"; ns.UI.Refresh() end)
    p.logBtn:SetPoint("TOPLEFT", 198, 0)
    p.tasksBtn = W.Button(p, "Officer tasks", 110, 22, function() view = "tasks"; ns.UI.Refresh() end)
    p.tasksBtn:SetPoint("TOPLEFT", 292, 0)
    p.searchLabel = W.Text(p, "Search", "GameFontHighlightSmall")
    p.searchLabel:SetPoint("TOPLEFT", 414, -5)
    p.search = W.Edit(p, 110, 30)
    p.search:SetPoint("TOPLEFT", 458, -1)
    p.search:SetScript("OnTextChanged", function(self)
        filter = (self:GetText() or ""):lower()
        if view == "members" or view == "profs" then ns.UI.Refresh() end
    end)

    -- Professions view: click a column to sort by it.
    p.profSort = "name"
    p.profHead = {}
    for _, h in ipairs({ { "Name", "name", 4, 150 }, { "Profession 1", "p1", 158, 140 }, { "Profession 2", "p2", 302, 140 },
        { "First Aid", "fa", 446, 72 }, { "Cooking", "ck", 522, 72 }, { "Fishing", "fi", 598, 72 } }) do
        local b = W.Button(p, h[1], h[4], 18, function() p.profSort = h[2]; ns.UI.Refresh() end)
        b:SetPoint("TOPLEFT", h[3], -24)
        b.key = h[2]
        p.profHead[#p.profHead + 1] = b
    end
    p.profs = W.List(p, 690, 300, 16, function(row, r)
        local rec = r.rec
        local main = Red.State() and Red.State().alts[r.guid]
        p.profs.Col(row, 1, 4, 150):SetText(U.Safe(r.name, 40) .. (main and " |cff808080(alt)|r" or ""))
        p.profs.Col(row, 2, 158, 140):SetText(rec and U.Safe(ns.Professions.Label(rec.p1, rec.l1), 32) or "|cff808080not shared yet|r")
        p.profs.Col(row, 3, 302, 140):SetText(rec and U.Safe(ns.Professions.Label(rec.p2, rec.l2), 32) or "")
        p.profs.Col(row, 4, 446, 72):SetText(rec and tostring(rec.fa or "-") or "")
        p.profs.Col(row, 5, 522, 72):SetText(rec and tostring(rec.ck or "-") or "")
        p.profs.Col(row, 6, 598, 72):SetText(rec and tostring(rec.fi or "-") or "")
    end)
    p.profs:Stretch(0, -46, 0, 0)
    p.count = W.Text(p, "", "GameFontDisableSmall")
    p.count:SetPoint("TOPLEFT", 578, -5)

    -- Members view
    p.head = {}
    for _, h in ipairs({ { "Name", 4 }, { "Rank", 150 }, { "Lvl", 250 }, { "Joined", 282 }, { "Last on", 370 } }) do
        local fs = W.Text(p, h[1], "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", h[2], -28)
        p.head[#p.head + 1] = fs
    end
    p.list = W.List(p, 440, 310, 16, function(row, r)
        p.list.Col(row, 1, 4, 144):SetText(U.Safe(r.name, 40) .. (r.main and " |cff808080(alt)|r" or ""))
        p.list.Col(row, 2, 150, 98):SetText(U.Safe(r.rank, 32))
        p.list.Col(row, 3, 250, 30):SetText(r.level)
        p.list.Col(row, 4, 282, 86):SetText(day(r.joined))
        p.list.Col(row, 5, 370, 66):SetText(r.last)
    end, function(r) selected = r.guid; ns.UI.Refresh() end)
    p.list:Stretch(0, -44, nil, 0)
    p.list.key = "guid"

    -- Detail of the selected member
    p.detail = W.Text(p, "", "GameFontHighlightSmall")
    p.detail:SetPoint("TOPLEFT", 470, -28)
    p.detail:SetWidth(240)
    p.detail:SetJustifyV("TOP")
    p.detail:SetHeight(200)
    p.altBox = W.Edit(p, 120, 48)
    p.altBox:SetPoint("TOPLEFT", 470, -250)
    p.link = W.Button(p, "Link as alt", 100, 22, function()
        if ns.UI.Try("Alt linked.", R.LinkAlt, p.altBox:GetText(), selected) then p.altBox:SetText("") end
    end, "accent")
    p.link:SetPoint("TOPLEFT", 596, -248)
    p.altHint = W.Text(p, "Type an alt's name, then link it to the selected main.", "GameFontDisableSmall")
    p.altHint:SetPoint("TOPLEFT", 470, -274)
    p.altHint:SetWidth(240)
    p.unlink = W.Button(p, "Unlink selected alt", 150, 22, function()
        if selected then ns.UI.Try("Alt unlinked.", R.Unlink, selected) end
    end)
    p.unlink:SetPoint("TOPLEFT", 470, -300)

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
    local members, tasks, profs = view == "members", view == "tasks", view == "profs"
    p.membersBtn:SetEnabled(not members)
    p.profBtn:SetEnabled(not profs)
    p.profs.scroll:SetShown(profs)
    for _, b in ipairs(p.profHead) do
        b:SetShown(profs)
        b:SetEnabled(b.key ~= p.profSort)
    end
    p.logBtn:SetEnabled(view ~= "log")
    p.tasksBtn:SetShown(canTasks)
    p.tasksBtn:SetEnabled(not tasks)
    p.tasks.scroll:SetShown(tasks)
    p.tw:SetShown(tasks)
    p.searchLabel:SetShown(members or profs)
    for _, fs in ipairs(p.head) do fs:SetShown(members) end
    p.list.scroll:SetShown(members)
    p.detail:SetShown(members)
    p.search:SetShown(members or profs)
    p.log.scroll:SetShown(view == "log")
    local officer = RBAC.ICan("altlink")
    for _, w in ipairs({ p.altBox, p.link, p.altHint, p.unlink }) do w:SetShown(members and officer) end

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
    if profs then
        local rows = ns.Professions.Rows(ns.roster.byGUID, st and st.profs or {}, filter, p.profSort)
        local shared = 0
        for _, r in ipairs(rows) do if r.rec then shared = shared + 1 end end
        p.profs:SetItems(rows)
        p.count:SetText(shared .. " of " .. #rows .. " shared")
        return
    end
    if not members then
        local list = {}
        for i = #(st and st.rosterLog or {}), 1, -1 do list[#list + 1] = st.rosterLog[i] end
        p.log:SetItems(list)
        p.count:SetText(#list .. " changes recorded")
        return
    end

    local rows = R.Rows(st)
    p.list:SetItems(rows)
    p.count:SetText(#rows .. " members")
    local sel
    for _, r in ipairs(rows) do if r.guid == selected then sel = r end end
    p.list.selected = sel
    p.unlink:SetEnabled(sel ~= nil and sel.main ~= nil)
    p.link:SetEnabled(sel ~= nil and sel.main == nil)
    if not sel then
        p.detail:SetText("Select a member to see their alts, join date and rank history.")
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
    for i = #hist, math.max(1, #hist - 5), -1 do
        lines[#lines + 1] = "  " .. date("%b %d, %Y", hist[i].t) .. "  " .. U.Safe(R.Describe(hist[i]), 80)
    end
    p.detail:SetText(table.concat(lines, "\n"))
end)
