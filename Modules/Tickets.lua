-- Speakeasy: tickets. A guild member reports a problem (bad language,
-- cheating, a ninja loot, a broken rule) and Team Captains and above work it
-- through three states: New, In progress, Resolved.
--
-- Who can read a ticket matters more than anything else here, so tickets do
-- NOT go into the guild's shared log, which every member's game keeps a copy
-- of. A ticket is whispered, addon to addon, only to Team Captains and above,
-- and they keep each other's copies in step the same way. The reporter keeps
-- their own tickets and is told only the status, never the staff notes.
-- A ticket about a Team Captain or above is never sent to that person.
--
-- This is the guild's own follow-up. It doesn't replace reporting a player
-- to Blizzard, which the report form says.
local _, ns = ...
local T = {}
ns.Tickets = T

local U, W, RBAC = ns.U, ns.W, ns.RBAC
local date = date or os.date   -- WoW global; os.date in tests

T.CATS = {
    { "lang", "Language or harassment" },
    { "cheat", "Cheating, botting or exploits" },
    { "loot", "Ninja looting or a loot dispute" },
    { "rules", "Breaking guild rules" },
    { "tos", "Breaking the game's rules" },
    { "scam", "Scam or guild bank" },
    { "other", "Something else" },
}
T.OUTCOMES = {
    { "none", "No action needed" },
    { "talk", "Spoke with the player" },
    { "warn", "Warning given" },
    { "loot", "Loot corrected" },
    { "kick", "Removed from the guild" },
    { "blizz", "Reported to Blizzard" },
}
-- Short names for a narrow list; the full name shows wherever there is room.
T.CAT_SHORT = { lang = "Language", cheat = "Cheating", loot = "Loot", rules = "Guild rules", tos = "Game rules",
    scam = "Scam or bank", other = "Other" }
T.CAT_LABEL, T.OUTCOME_LABEL = {}, {}
for _, c in ipairs(T.CATS) do T.CAT_LABEL[c[1]] = c[2] end
for _, o in ipairs(T.OUTCOMES) do T.OUTCOME_LABEL[o[1]] = o[2] end
T.STATUS = { new = "New", work = "In progress", done = "Resolved" }

T.MAX_ABOUT = 48
T.MAX_TEXT = 300
T.MAX_NOTE = 200
T.MAX_NOTES = 20
T.MAX_OPEN = 5                -- unresolved tickets one member may have at a time
T.MAX_STORE = 300             -- tickets a staff member's game keeps
T.KEEP_DONE = 90 * 86400      -- resolved tickets are dropped after this long
T.MAX_SEND = 5                -- staff a new ticket is whispered to directly
T.SYNC_DONE = 14 * 86400      -- staff compare open tickets and ones resolved this recently

---------------------------------------------------------------------------
-- Pure logic
---------------------------------------------------------------------------
local function trim(s) return (tostring(s or ""):gsub("%s+", " "):match("^%s*(.-)%s*$")) end

-- Check what a member typed. -> { cat, about, text } or nil and what to fix
function T.Clean(cat, about, text)
    if not T.CAT_LABEL[cat] then return nil, "Pick what kind of problem it is." end
    about, text = trim(about), trim(text)
    if #about > T.MAX_ABOUT then return nil, "That name is too long." end
    if about == "" and cat ~= "other" then return nil, "Say who it is about." end
    if #text < 10 then return nil, "Say what happened, in a sentence or two." end
    if #text > T.MAX_TEXT then return nil, ("Keep it under %d letters."):format(T.MAX_TEXT) end
    return { cat = cat, about = about, text = text }
end

-- A ticket's id is its reporter and the second it was made.
function T.NewId(guid, now) return guid .. "/" .. tostring(math.floor(now)) end
function T.IdBy(id) return type(id) == "string" and id:match("^(.+)/%d+$") or nil end

-- A full ticket from another game: keep only what a ticket may hold.
function T.Sanitize(k)
    if type(k) ~= "table" or type(k.id) ~= "string" or #k.id > 80 then return nil end
    local by = T.IdBy(k.id)
    if not by or k.by ~= by then return nil end
    if not T.CAT_LABEL[k.cat] or not T.STATUS[k.status] then return nil end
    if type(k.text) ~= "string" or #k.text > T.MAX_TEXT or type(k.about) ~= "string" or #k.about > T.MAX_ABOUT then return nil end
    if type(k.at) ~= "number" or type(k.v) ~= "number" or type(k.ut) ~= "number" or type(k.ub) ~= "string" then return nil end
    local t = { id = k.id, by = by, byName = type(k.byName) == "string" and k.byName:sub(1, 48) or nil,
        at = k.at, cat = k.cat, about = k.about, text = k.text, status = k.status,
        aboutGuid = type(k.aboutGuid) == "string" and k.aboutGuid or nil,
        owner = type(k.owner) == "string" and k.owner or nil,
        outcome = T.OUTCOME_LABEL[k.outcome] and k.outcome or nil,
        v = math.floor(k.v), ut = k.ut, ub = k.ub, notes = {} }
    if type(k.notes) == "table" then
        for i = 1, math.min(#k.notes, T.MAX_NOTES) do
            local n = k.notes[i]
            if type(n) == "table" and type(n.by) == "string" and type(n.at) == "number"
                and type(n.text) == "string" and #n.text <= T.MAX_NOTE then
                t.notes[#t.notes + 1] = { by = n.by, at = n.at, text = n.text }
            end
        end
    end
    return t
end

-- Which copy of a ticket has the later word on its state.
function T.Newer(a, b)
    if a.v ~= b.v then return a.v > b.v end
    if a.ut ~= b.ut then return a.ut > b.ut end
    return a.ub > b.ub
end

-- Take in a ticket from another staff member. State goes to the newer copy;
-- notes from both are kept. -> changed, isNew
function T.Merge(store, k)
    local mine = store[k.id]
    if not mine then
        store[k.id] = k
        return true, true
    end
    local changed = false
    if T.Newer(k, mine) then
        mine.status, mine.owner, mine.outcome = k.status, k.owner, k.outcome
        mine.v, mine.ut, mine.ub = k.v, k.ut, k.ub
        changed = true
    end
    local have = {}
    for _, n in ipairs(mine.notes) do have[n.by .. "/" .. n.at .. "/" .. n.text] = true end
    for _, n in ipairs(k.notes) do
        local key = n.by .. "/" .. n.at .. "/" .. n.text
        if not have[key] and #mine.notes < T.MAX_NOTES then
            have[key] = true
            mine.notes[#mine.notes + 1] = n
            changed = true
        end
    end
    table.sort(mine.notes, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.by < b.by
    end)
    return changed, false
end

-- What one staff member tells another they hold: id -> "version:notes".
-- A ticket about `skip` is left out, so it is never offered to that person.
-- Tickets resolved before `since` are left out too: they are settled, and
-- leaving them out keeps the message small.
function T.Digest(store, skip, since)
    local d = {}
    for id, t in pairs(store) do
        if (not skip or t.aboutGuid ~= skip) and not (since and t.status == "done" and t.ut < since) then
            d[id] = t.v .. ":" .. #t.notes
        end
    end
    return d
end

local function stampNewer(a, b)        -- "3:2" vs "2:5": version first, then notes
    local av, an = a:match("^(%d+):(%d+)$")
    local bv, bn = b:match("^(%d+):(%d+)$")
    av, an, bv, bn = tonumber(av) or 0, tonumber(an) or 0, tonumber(bv) or 0, tonumber(bn) or 0
    if av ~= bv then return av > bv end
    return an > bn
end

-- Compare my tickets with a colleague's digest.
-- -> ids I should send them, and whether they hold something I lack
function T.Diff(store, digest, skip, since)
    local send, want = {}, false
    local mine = T.Digest(store, skip, since)
    for id, stamp in pairs(mine) do
        local theirs = digest[id]
        if type(theirs) ~= "string" or stampNewer(stamp, theirs) then send[#send + 1] = id end
    end
    for id, stamp in pairs(digest) do
        local have = mine[id] or (store[id] and (store[id].v .. ":" .. #store[id].notes))      -- an old resolved one I do hold
        if type(id) == "string" and type(stamp) == "string" and (have == nil or stampNewer(stamp, have)) then want = true end
    end
    table.sort(send)
    return send, want
end

-- Online staff a ticket may go to: never me, never the person it is about.
-- Highest rank first. roster = { [guid] = { name, full, online, rankIndex } }
function T.Recipients(roster, isStaff, me, aboutGuid)
    local out = {}
    for guid, m in pairs(roster) do
        if guid ~= me and guid ~= aboutGuid and m.online and isStaff(guid) then
            out[#out + 1] = { guid = guid, name = m.full or m.name, ri = m.rankIndex or 9 }
        end
    end
    table.sort(out, function(a, b)
        if a.ri ~= b.ri then return a.ri < b.ri end
        return a.name < b.name
    end)
    return out
end

-- Rows for the staff queue. filter: "open", "mine" (assigned to me) or "done".
function T.Rows(store, filter, me)
    local rows = {}
    for _, t in pairs(store) do
        local open = t.status ~= "done"
        if (filter == "open" and open) or (filter == "done" and not open) or (filter == "mine" and open and t.owner == me) then
            rows[#rows + 1] = t
        end
    end
    table.sort(rows, function(a, b)
        if a.at ~= b.at then return a.at > b.at end
        return a.id < b.id
    end)
    return rows
end

-- The queue's columns for a list this wide: the date, name and status keep
-- their size and the kind of problem takes whatever is left.
--   -> { about = {x, w}, cat = {x, w}, status = {x, w} }
function T.Columns(width)
    width = math.max(300, math.floor(tonumber(width) or 300))
    local about = math.min(150, math.floor(width * 0.30))
    local status = 76
    local catX = 50 + about + 6
    return { about = { 50, about }, cat = { catX, math.max(60, width - catX - status - 8) }, status = { width - status - 2, status } }
end

-- The kind of problem, in full when it fits the column and short when it doesn't.
function T.CatText(cat, width)
    local full = T.CAT_LABEL[cat] or "?"
    if #full * 6.2 <= width then return full end
    return T.CAT_SHORT[cat] or full
end

function T.Counts(store, me)
    local c = { open = 0, mine = 0, done = 0, new = 0 }
    for _, t in pairs(store) do
        if t.status == "done" then
            c.done = c.done + 1
        else
            c.open = c.open + 1
            if t.status == "new" then c.new = c.new + 1 end
            if t.owner == me then c.mine = c.mine + 1 end
        end
    end
    return c
end

-- Drop resolved tickets that are old, and the oldest resolved ones if the
-- store is over its size. -> how many went
function T.Prune(store, now)
    local gone, n, done = 0, 0, {}
    for id, t in pairs(store) do
        if t.status == "done" and now - t.ut > T.KEEP_DONE then
            store[id] = nil
            gone = gone + 1
        else
            n = n + 1
            if t.status == "done" then done[#done + 1] = t end
        end
    end
    table.sort(done, function(a, b) return a.ut < b.ut end)
    local i = 1
    while n > T.MAX_STORE and done[i] do
        store[done[i].id] = nil
        n, gone, i = n - 1, gone + 1, i + 1
    end
    return gone
end

---------------------------------------------------------------------------
-- Game side
---------------------------------------------------------------------------
local function isStaff(guid) return RBAC.Can(guid, "tickets") end
function T.IAmStaff() return isStaff(ns.MyGUID()) end

-- Staff copy of every ticket, and my own reports. Both live with the guild's
-- saved data on this account; the guild log never sees them.
local function store()
    local g = ns.G()
    if not g then return {} end
    g.tickets = g.tickets or {}
    return g.tickets
end
local function mine()
    local g = ns.G()
    if not g then return {} end
    g.myTickets = g.myTickets or {}
    return g.myTickets
end
T.Store, T.Mine = store, mine

local function nameOf(guid) return U.ShortName(ns.NameForGUID(guid) or "someone") end

local function whisper(guid, msg)
    local m = ns.roster.byGUID[guid]
    if not m or not m.online or ns.mock then return false end
    ns.Comm.Send("WHISPER", m.full or m.name, U.Encode(msg))
    return true
end

local function refresh() if ns.UI then ns.UI.RefreshSoon() end end

-- Send a ticket to every online staff member who may see it.
local function tellStaff(t, except)
    for _, r in ipairs(T.Recipients(ns.roster.byGUID, isStaff, ns.MyGUID(), t.aboutGuid)) do
        if r.guid ~= except then whisper(r.guid, { t = "TU", k = t }) end
    end
end

-- Tell the reporter where their ticket stands. Status only: never the notes.
local function tellReporter(t)
    if t.by == ns.MyGUID() then
        local own = mine()[t.id]
        if own then own.st, own.outcome = t.status, t.outcome end
        return
    end
    whisper(t.by, { t = "TS", s = { [t.id] = { st = t.status, o = t.outcome } } })
end

-- My reports that staff haven't confirmed receiving: send them (again).
local lastDeliver = -1000
function T.Deliver()
    local me = ns.MyGUID()
    for id, own in pairs(mine()) do
        if own.by == me and not own.sent then
            if T.IAmStaff() then
                -- A Team Captain or above reporting: it goes straight into the queue.
                local st = store()
                if not st[id] then
                    st[id] = { id = id, by = me, byName = nameOf(me), at = own.at, cat = own.cat, about = own.about,
                        aboutGuid = ns.GUIDForName(own.about), text = own.text, status = "new", v = 1, ut = own.at, ub = me, notes = {} }
                end
                own.sent = true
                tellStaff(st[id])
            else
                local sent = 0
                for _, r in ipairs(T.Recipients(ns.roster.byGUID, isStaff, me, ns.GUIDForName(own.about))) do
                    if sent < T.MAX_SEND and whisper(r.guid, { t = "TN", id = id, at = own.at, cat = own.cat, about = own.about, text = own.text }) then
                        sent = sent + 1
                    end
                end
            end
        end
    end
    lastDeliver = GetTime()
end

function T.OpenCount()
    local n, me = 0, ns.MyGUID()
    for _, own in pairs(mine()) do
        if own.by == me and own.st ~= "done" then n = n + 1 end
    end
    return n
end

-- A member reports a problem.
local lastSubmit = -1000
function T.Submit(cat, about, text)
    if ns.mock then return nil, "Test mode is on, so no ticket is sent." end
    if not (ns.G() and ns.roster.loaded and RBAC.RoleOf(ns.MyGUID())) then return nil, "Not connected to the guild yet. Try again in a moment." end
    local d, why = T.Clean(cat, about, text)
    if not d then return nil, why end
    if GetTime() - lastSubmit < 30 then return nil, "You just sent one. Give it half a minute." end
    if T.OpenCount() >= T.MAX_OPEN then return nil, ("You have %d tickets still open. Wait for one to be resolved."):format(T.MAX_OPEN) end
    local me, now = ns.MyGUID(), ns.Now()
    if ns.GUIDForName(d.about) == me then return nil, "A ticket can't be about yourself." end
    local id = T.NewId(me, now)
    if mine()[id] then return nil, "You just sent one. Give it a moment." end
    lastSubmit = GetTime()
    mine()[id] = { id = id, by = me, at = now, cat = d.cat, about = d.about, text = d.text, st = "new", sent = false }
    T.Deliver()
    refresh()
    return id
end

-- Staff: change a ticket, then tell the other staff and the reporter.
local function change(id, fn)
    if not T.IAmStaff() then return nil, "Only Team Captains and above manage tickets." end
    local t = store()[id]
    if not t then return nil, "That ticket is gone." end
    local before = t.status
    local ok, why = fn(t)
    if ok == false then return nil, why end
    t.v, t.ut, t.ub = t.v + 1, ns.Now(), ns.MyGUID()
    tellStaff(t)
    if t.status ~= before then tellReporter(t) end
    refresh()
    return true
end

function T.Take(id)
    return change(id, function(t)
        if t.status == "done" then return false, "It is resolved. Reopen it first." end
        t.owner, t.status = ns.MyGUID(), "work"
    end)
end

function T.Resolve(id, outcome)
    if not T.OUTCOME_LABEL[outcome] then return nil, "Pick how it was resolved." end
    return change(id, function(t)
        if t.status == "done" then return false, "It is already resolved." end
        t.status, t.outcome = "done", outcome
        t.owner = t.owner or ns.MyGUID()
    end)
end

function T.Reopen(id)
    return change(id, function(t)
        if t.status ~= "done" then return false, "It is still open." end
        t.status, t.outcome = "work", nil
    end)
end

function T.AddNote(id, text)
    text = trim(text)
    if text == "" then return nil, "Type the note first." end
    if #text > T.MAX_NOTE then return nil, ("Keep a note under %d letters."):format(T.MAX_NOTE) end
    return change(id, function(t)
        if #t.notes >= T.MAX_NOTES then return false, "This ticket has all the notes it can hold." end
        t.notes[#t.notes + 1] = { by = ns.MyGUID(), at = ns.Now(), text = text }
    end)
end

---------------------------------------------------------------------------
-- Messages between games (whispers only, never the guild channel)
---------------------------------------------------------------------------
local function alertNew(t)
    ns.Print(("New ticket from %s: %s%s. Type /spk and open Tickets."):format(U.Safe(t.byName or nameOf(t.by), 40),
        T.CAT_LABEL[t.cat], t.about ~= "" and (", about " .. U.Safe(t.about, 48)) or ""))
end

-- Made before the Guild Master's last ticket wipe?
local function wiped(at)
    local st = ns.Reducer.State()
    local r = st and st.resets and st.resets.tickets
    return r ~= nil and type(at) == "number" and at <= r.t
end

local function onMessage(msg, _, sguid, channel)
    if channel ~= "WHISPER" then return end          -- a ticket on the guild channel is never ours
    local me, now = ns.MyGUID(), ns.Now()
    if msg.t == "TN" then
        -- A member's new ticket, sent to me because I am staff.
        if not T.IAmStaff() or type(msg.id) ~= "string" or T.IdBy(msg.id) ~= sguid then return end
        local d = T.Clean(msg.cat, msg.about, msg.text)
        if not d or wiped(msg.at) then return end
        local aboutGuid = ns.GUIDForName(d.about)
        if aboutGuid == me then return end
        local st = store()
        if not st[msg.id] then
            local open = 0
            for _, t in pairs(st) do if t.by == sguid and t.status ~= "done" then open = open + 1 end end
            if open >= T.MAX_OPEN then return end
            local at = type(msg.at) == "number" and math.abs(msg.at - now) < 86400 and msg.at or now
            local t = { id = msg.id, by = sguid, byName = nameOf(sguid), at = at, cat = d.cat, about = d.about,
                aboutGuid = aboutGuid, text = d.text, status = "new", v = 1, ut = at, ub = sguid, notes = {} }
            st[msg.id] = t
            alertNew(t)
            tellStaff(t, sguid)
            refresh()
        end
        whisper(sguid, { t = "TA", id = msg.id })
    elseif msg.t == "TA" then
        local own = type(msg.id) == "string" and mine()[msg.id]
        if own and isStaff(sguid) and not own.sent then own.sent = true; refresh() end
    elseif msg.t == "TU" then
        if not T.IAmStaff() or not isStaff(sguid) then return end
        local k = T.Sanitize(msg.k)
        if not k or wiped(k.at) or k.aboutGuid == me or ns.GUIDForName(k.about) == me then return end
        local changed, isNew = T.Merge(store(), k)
        if isNew then alertNew(k) end
        if changed then refresh() end
    elseif msg.t == "TD" then
        if not T.IAmStaff() or not isStaff(sguid) or type(msg.d) ~= "table" then return end
        local since = now - T.SYNC_DONE
        local send, want = T.Diff(store(), msg.d, sguid, since)
        for i = 1, math.min(#send, 30) do whisper(sguid, { t = "TU", k = store()[send[i]] }) end
        if want and not msg.r then whisper(sguid, { t = "TD", d = T.Digest(store(), sguid, since), r = 1 }) end
    elseif msg.t == "TQ" then
        -- A reporter asking where their own tickets stand.
        if not T.IAmStaff() or type(msg.ids) ~= "table" then return end
        local s, n = {}, 0
        for i = 1, math.min(#msg.ids, 20) do
            local t = type(msg.ids[i]) == "string" and store()[msg.ids[i]]
            if t and t.by == sguid then s[t.id] = { st = t.status, o = t.outcome }; n = n + 1 end
        end
        if n > 0 then whisper(sguid, { t = "TS", s = s }) end
    elseif msg.t == "TS" then
        if not isStaff(sguid) or type(msg.s) ~= "table" then return end
        for id, v in pairs(msg.s) do
            local own = type(id) == "string" and mine()[id]
            if own and own.by == me and type(v) == "table" and T.STATUS[v.st] then
                own.sent = true
                if own.st ~= v.st then
                    own.st, own.outcome = v.st, T.OUTCOME_LABEL[v.o] and v.o or nil
                    ns.Print(("Your ticket%s is now: %s%s."):format(own.about ~= "" and (" about " .. U.Safe(own.about, 48)) or "",
                        T.STATUS[v.st], own.outcome and (" (" .. T.OUTCOME_LABEL[own.outcome] .. ")") or ""))
                    refresh()
                end
            end
        end
    end
end
for _, kind in ipairs({ "TN", "TA", "TU", "TD", "TQ", "TS" }) do ns.Sync.Handle(kind, onMessage) end

-- Staff keep each other's copies in step: now and then each tells the others
-- what it holds, and they send back what is missing.
local syncedWith = {}
function T.Sync(force)
    if not T.IAmStaff() or ns.mock then return 0 end
    local me, n = ns.MyGUID(), 0
    for _, r in ipairs(T.Recipients(ns.roster.byGUID, isStaff, me, nil)) do
        if n < 3 and (force or GetTime() - (syncedWith[r.guid] or -10000) > 600) then
            syncedWith[r.guid] = GetTime()
            whisper(r.guid, { t = "TD", d = T.Digest(store(), r.guid, ns.Now() - T.SYNC_DONE) })
            n = n + 1
        end
    end
    return n
end

-- A reporter asks one online staff member where their open tickets stand.
local lastAsk = -1000
function T.AskStatus(force)
    if ns.mock or (not force and GetTime() - lastAsk < 60) then return false end
    local me, ids = ns.MyGUID(), {}
    for id, own in pairs(mine()) do
        if own.by == me and own.sent and own.st ~= "done" and #ids < 20 then ids[#ids + 1] = id end
    end
    if #ids == 0 then return false end
    local staff = T.Recipients(ns.roster.byGUID, isStaff, me, nil)
    if not staff[1] then return false end
    lastAsk = GetTime()
    return whisper(staff[1].guid, { t = "TQ", ids = ids })
end

-- The Guild Master wiped tickets: drop every ticket made before that, staff
-- copies and my own reports alike.
function T.ApplyWipe()
    local st = ns.Reducer.State()
    local r = st and st.resets and st.resets.tickets
    if not r or not ns.G() then return 0 end
    local n = 0
    for _, list in ipairs({ store(), mine() }) do
        for id, t in pairs(list) do
            if (t.at or 0) <= r.t then list[id] = nil; n = n + 1 end
        end
    end
    if n > 0 then refresh() end
    return n
end
ns.Listen("LOG_CHANGED", function() T.ApplyWipe() end)

local started = false
local function tick()
    if not (ns.db and ns.roster.loaded and not ns.mock and RBAC.RoleOf(ns.MyGUID())) then return end
    if not started then
        started = true
        T.Prune(store(), ns.Now())
        if T.IAmStaff() then
            local c = T.Counts(store(), ns.MyGUID())
            if c.new > 0 then ns.Print(("%d new ticket%s waiting. Type /spk and open Tickets."):format(c.new, c.new == 1 and " is" or "s are")) end
        end
    end
    if GetTime() - lastDeliver > 60 then T.Deliver() end
    T.Sync(false)
    T.AskStatus(false)
end
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(45, tick) end

---------------------------------------------------------------------------
-- Tickets tab: everyone reports and sees their own; staff work the queue
---------------------------------------------------------------------------
local view, filter, selected = nil, "open", nil
local pickedCat, pickedOutcome = nil, 1

local function statusText(st, outcome)
    local color = st == "new" and "ffd100" or (st == "work" and "40c0ff" or "40ff40")
    return "|cff" .. color .. T.STATUS[st] .. "|r" .. (st == "done" and outcome and (": " .. T.OUTCOME_LABEL[outcome]) or "")
end

ns.UI.AddTab("tickets", "Tickets", "view", function(p)
    p.viewBtns = {}
    for i, v in ipairs({ { "queue", "Queue", 110 }, { "report", "Report a problem", 140 }, { "mine", "My tickets", 110 } }) do
        local b = W.Button(p, v[2], v[3], 22, function() view = v[1]; ns.UI.Refresh() end)
        b.key, b.label = v[1], v[2]
        p.viewBtns[i] = b
    end

    -- Report a problem (everyone) ------------------------------------------
    local r = CreateFrame("Frame", nil, p)
    r:SetPoint("TOPLEFT", 0, -32)
    r:SetPoint("BOTTOMRIGHT", 0, 0)
    p.report = r
    W.Text(r, "1. What kind of problem is it?", "GameFontNormal"):SetPoint("TOPLEFT", 0, 0)
    p.catBtns = {}
    for i, c in ipairs(T.CATS) do
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        local b = W.Button(r, c[2], 174, 22, function() pickedCat = c[1]; ns.UI.Refresh() end)
        b:SetPoint("TOPLEFT", col * 178, -20 - row * 26)
        b.cat = c[1]
        p.catBtns[i] = b
    end
    W.Text(r, "2. Who is it about?", "GameFontNormal"):SetPoint("TOPLEFT", 0, -82)
    p.about = W.Edit(r, 200, T.MAX_ABOUT)
    p.about:SetPoint("TOPLEFT", 0, -100)
    local aboutHint = W.Text(r, "Their character's name. Leave it empty only for \"Something else\".", "GameFontDisableSmall")
    aboutHint:SetPoint("LEFT", p.about, "RIGHT", 10, 0)
    W.Text(r, "3. What happened?", "GameFontNormal"):SetPoint("TOPLEFT", 0, -132)
    local bg = CreateFrame("Frame", nil, r)
    bg:SetPoint("TOPLEFT", 0, -150)
    bg:SetSize(700, 62)
    W.Panel(bg)
    p.text = CreateFrame("EditBox", nil, bg)
    p.text:SetMultiLine(true)
    p.text:SetFontObject(W.F.bodySm)
    p.text:SetPoint("TOPLEFT", 6, -6)
    p.text:SetPoint("BOTTOMRIGHT", -6, 6)
    p.text:SetAutoFocus(false)
    p.text:SetMaxLetters(T.MAX_TEXT)
    p.text:SetScript("OnEscapePressed", p.text.ClearFocus)
    p.submit = W.Button(r, "Send ticket", 140, 22, function()
        local id, why = T.Submit(pickedCat, p.about:GetText(), p.text:GetText())
        if not id then ns.UI.Say(why or "That didn't work.") return end
        local own = mine()[id]
        ns.UI.Say(own and own.sent and "Ticket sent to the Team Captains and above."
            or "Ticket saved. It goes out as soon as a Team Captain or above is online.")
        p.about:SetText("")
        p.text:SetText("")
        pickedCat, view = nil, "mine"
        ns.UI.Refresh()
    end, "accent")
    p.submit:SetPoint("TOPLEFT", 0, -220)
    local privacy = W.Text(r, "Only Team Captains and above can read a ticket, and one about a Team Captain or above is not shown to that person. "
        .. "For harassment, cheating or anything against the game's rules, also report the player to Blizzard (right-click their name, then Report).",
        "GameFontDisableSmall")
    privacy:SetPoint("TOPLEFT", 0, -250)
    privacy:SetWidth(700)
    privacy:SetWordWrap(true)

    -- My tickets (everyone) ------------------------------------------------
    local m = CreateFrame("Frame", nil, p)
    m:SetPoint("TOPLEFT", 0, -32)
    m:SetPoint("BOTTOMRIGHT", 0, 0)
    p.mineFrame = m
    p.mineList = W.List(m, 690, 200, 18, function(row, own)
        p.mineList.Col(row, 1, 4, 90):SetText(date("%b %d %I:%M %p", own.at))
        p.mineList.Col(row, 2, 100, 190):SetText(T.CAT_LABEL[own.cat] or "?")
        p.mineList.Col(row, 3, 296, 150):SetText(U.Safe(own.about, 48))
        p.mineList.Col(row, 4, 452, 230):SetText(own.sent and statusText(own.st, own.outcome) or "|cff808080waiting for staff to come online|r")
    end)
    p.mineList:Stretch(0, 0, 0, 22)
    p.mineList.key = "id"
    p.mineEmpty = W.Text(m, "You haven't sent any tickets.", "GameFontHighlightSmall")
    p.mineEmpty:SetPoint("TOPLEFT", 4, -6)
    local mineHint = W.Text(m, "You see where each ticket stands. Notes the staff write on it stay with them.", "GameFontDisableSmall")
    mineHint:SetPoint("BOTTOMLEFT", 0, 2)

    -- Queue (Team Captain and above) ---------------------------------------
    local q = CreateFrame("Frame", nil, p)
    q:SetPoint("TOPLEFT", 0, -32)
    q:SetPoint("BOTTOMRIGHT", 0, 0)
    p.queue = q
    p.filterBtns = {}
    for i, f in ipairs({ { "open", "Open" }, { "mine", "Assigned to me" }, { "done", "Resolved" } }) do
        local b = W.Button(q, f[2], i == 2 and 130 or 96, 20, function() filter = f[1]; ns.UI.Refresh() end)
        b:SetPoint("TOPLEFT", i == 1 and 0 or (i == 2 and 100 or 234), 0)
        b.key, b.label = f[1], f[2]
        p.filterBtns[i] = b
    end
    -- The list takes the width the window gives it; the ticket's details keep
    -- theirs on the right.
    p.list = W.List(q, 322, 200, 18, function(row, t)
        local c = T.Columns(p.list.scroll:GetWidth())
        p.list.Col(row, 1, 4, 44):SetText(date("%b %d", t.at))
        p.list.Col(row, 2, c.about[1], c.about[2]):SetText(U.Safe(t.about ~= "" and t.about or "(nobody named)", 48))
        p.list.Col(row, 3, c.cat[1], c.cat[2]):SetText(T.CatText(t.cat, c.cat[2]))
        p.list.Col(row, 4, c.status[1], c.status[2]):SetText(statusText(t.status))
    end, function(t) selected = t and t.id or nil; ns.UI.Refresh() end)
    p.list:Stretch(0, -26, 362, 0)
    p.list.key = "id"
    p.empty = W.Text(q, "", "GameFontHighlightSmall")
    p.empty:SetPoint("TOPLEFT", 4, -32)
    p.empty:SetWidth(320)

    -- The picked ticket: what was reported, then the steps to work it. It
    -- keeps to the right edge so the list can grow.
    local d = CreateFrame("Frame", nil, q)
    d:SetPoint("TOPRIGHT", 0, 0)
    d:SetPoint("BOTTOMRIGHT", 0, 0)
    d:SetWidth(350)
    p.detail = W.Text(d, "", "GameFontHighlightSmall")
    p.detail:SetPoint("TOPLEFT", 0, -26)
    p.detail:SetWidth(350)
    p.detail:SetHeight(172)
    p.detail:SetJustifyV("TOP")
    p.detail:SetWordWrap(true)
    p.take = W.Button(d, "1. Take it", 96, 22, function()
        if selected then ns.UI.Try("It's yours. The other staff see that.", T.Take, selected) end
    end, "accent")
    p.take:SetPoint("TOPLEFT", 0, -206)
    p.noteBox = W.Edit(d, 256, T.MAX_NOTE)
    p.noteBox:SetPoint("TOPLEFT", 0, -234)
    p.addNote = W.Button(d, "2. Add note", 90, 22, function()
        if selected and ns.UI.Try("Note added. Only staff see notes.", T.AddNote, selected, p.noteBox:GetText()) then p.noteBox:SetText("") end
    end)
    p.addNote:SetPoint("TOPLEFT", 260, -234)
    p.outcome = W.Button(d, "", 200, 22, function()
        pickedOutcome = pickedOutcome % #T.OUTCOMES + 1
        ns.UI.Refresh()
    end)
    p.outcome:SetPoint("TOPLEFT", 0, -262)
    p.resolve = W.Button(d, "3. Resolve", 96, 22, function()
        if selected then ns.UI.Try("Resolved. The reporter is told the status.", T.Resolve, selected, T.OUTCOMES[pickedOutcome][1]) end
    end, "accent")
    p.resolve:SetPoint("TOPLEFT", 204, -262)
    p.reopen = W.Button(d, "Reopen", 96, 22, function()
        if selected then ns.UI.Try("Reopened.", T.Reopen, selected) end
    end)
    p.reopen:SetPoint("TOPLEFT", 0, -206)
    p.queueHint = W.Text(d, "Click the outcome to change it. The reporter sees the status and outcome, never the notes.", "GameFontDisableSmall")
    p.queueHint:SetPoint("TOPLEFT", 0, -290)
    p.queueHint:SetWidth(350)
end, function(p)
    local me = ns.MyGUID()
    local staff = T.IAmStaff()
    if not view or (view == "queue" and not staff) then view = staff and "queue" or "report" end
    local st, own = store(), {}
    for _, o in pairs(mine()) do if o.by == me then own[#own + 1] = o end end
    table.sort(own, function(a, b) return a.at > b.at end)
    local c = T.Counts(st, me)

    -- The views, in the order each kind of player uses them.
    local x = 0
    for _, b in ipairs(p.viewBtns) do
        local show = b.key ~= "queue" or staff
        b:SetShown(show)
        if show then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", x, 0)
            x = x + b:GetWidth() + 4
            b:SetEnabled(view ~= b.key)
            b:SetText(b.key == "queue" and c.open > 0 and ("Queue (" .. c.open .. ")")
                or (b.key == "mine" and #own > 0 and ("My tickets (" .. #own .. ")") or b.label))
        end
    end
    p.report:SetShown(view == "report")
    p.mineFrame:SetShown(view == "mine")
    p.queue:SetShown(view == "queue" and staff)

    if view == "report" then
        for _, b in ipairs(p.catBtns) do b:SetEnabled(b.cat ~= pickedCat) end
        return
    end
    if view == "mine" then
        T.AskStatus(false)
        p.mineList:SetItems(own)
        p.mineEmpty:SetShown(#own == 0)
        return
    end

    for _, b in ipairs(p.filterBtns) do
        b:SetEnabled(filter ~= b.key)
        b:SetText(b.label .. " (" .. c[b.key] .. ")")
    end
    local rows = T.Rows(st, filter, me)
    local sel
    for _, t in ipairs(rows) do if t.id == selected then sel = t end end
    selected = sel and sel.id or nil
    p.list.selected = sel
    p.list:SetItems(rows)
    p.empty:SetShown(#rows == 0)
    p.empty:SetText(filter == "open" and "No open tickets." or (filter == "mine" and "Nothing is assigned to you." or "Nothing resolved yet."))
    local done = sel ~= nil and sel.status == "done"
    for _, w in ipairs({ p.take, p.noteBox, p.addNote, p.outcome, p.resolve, p.queueHint }) do w:SetShown(sel ~= nil and not done) end
    p.reopen:SetShown(done)
    if not sel then
        p.detail:SetText(#rows > 0 and "Pick a ticket to read it." or "")
        return
    end
    p.take:SetEnabled(sel.owner ~= me)
    p.outcome:SetText("Outcome: " .. T.OUTCOMES[pickedOutcome][2])
    local lines = {
        "|cffffd100" .. T.CAT_LABEL[sel.cat] .. "|r" .. (sel.about ~= "" and (", about " .. U.Safe(sel.about, 48)) or ""),
        ("Reported by %s, %s"):format(U.Safe(sel.byName or nameOf(sel.by), 40), date("%b %d %I:%M %p", sel.at)),
        statusText(sel.status, sel.outcome) .. (sel.owner and ("  -  " .. U.Safe(nameOf(sel.owner), 40) .. " has it") or "  -  nobody has taken it"),
        " ",
        U.Safe(sel.text, T.MAX_TEXT),
    }
    if #sel.notes > 0 then
        lines[#lines + 1] = " "
        lines[#lines + 1] = "|cffffd100Staff notes|r"
        for i = math.max(1, #sel.notes - 2), #sel.notes do          -- the latest three
            local n = sel.notes[i]
            lines[#lines + 1] = ("%s %s: %s"):format(date("%b %d", n.at), U.Safe(nameOf(n.by), 24), U.Safe(n.text, T.MAX_NOTE))
        end
    end
    p.detail:SetText(table.concat(lines, "\n"))
end)

-- Room the tab needs: the report form, or the queue's detail and its buttons.
ns.UI.Need("tickets", function() return view == "mine" and 150 or 32 + 322 end)
