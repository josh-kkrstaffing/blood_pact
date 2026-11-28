-- Blind Tiger: guild chips. A raider donates gold to the guild bank and gets
-- play chips, one for one: a gold chip per gold, a silver chip per silver, a
-- copper chip per copper. Chips are for the guild's games and bragging
-- rights. They are one-way: chips never turn back into gold, and nobody
-- wins or loses gold against another player.
--
-- The addon cannot move gold. The donor presses the button at the guild bank,
-- which is their own deposit. Their chips start as pending. They become real
-- when an Officer's addon sees the matching deposit in the bank's money log,
-- which happens on its own whenever an Officer opens the guild bank. A donor
-- can't confirm their own chips.
--
-- The ADMIN can also assign chips to a guild member outright (Settings). Those
-- are written to the guild's log under the ADMIN's name like everything else.
local _, ns = ...
local C = {}
ns.Chips = C

local U, RBAC, Red = ns.U, ns.RBAC, ns.Reducer

C.MAX = 1e10            -- copper; the size check for one donation
C.SLACK = 2 * 3600      -- the money log only says "an hour ago", and clocks differ
C.WAIT = 12             -- seconds to wait for a deposit to show in the money log
C.HOWTO = {
    "1. Go to the guild bank and open it.",
    "2. Type how much to donate and press \"Donate for chips\". That is your own deposit into the guild bank: the gold goes to the guild.",
    "3. You get chips one for one: 1 gold is 1 gold chip, 1 silver is 1 silver chip, 1 copper is 1 copper chip.",
    "4. Your chips show as pending until an Officer's addon sees your deposit in the bank's money log. That happens by itself the next time an Officer opens the guild bank.",
    "Chips are one-way. They can't be turned back into gold, traded for gold, or cashed out. They are for the guild's games and the leaderboard.",
    "Only donations made with this button earn chips. Gold put in the bank the usual way is a plain donation.",
}

---------------------------------------------------------------------------
-- Pure rules
---------------------------------------------------------------------------
-- Three boxes (gold, silver, copper) -> copper, or nil and why.
function C.Amount(gold, silver, copper)
    local function whole(text, max, what)
        text = tostring(text or ""):gsub("%s", "")
        if text == "" then return 0 end
        local n = tonumber(text)
        if not n or n ~= math.floor(n) or n < 0 or n > max then return nil, "Type a whole number of " .. what .. "." end
        return n
    end
    local g, why = whole(gold, 999999, "gold")
    if not g then return nil, why end
    local s, why2 = whole(silver, 99, "silver, 0 to 99")
    if not s then return nil, why2 end
    local c, why3 = whole(copper, 99, "copper, 0 to 99")
    if not c then return nil, why3 end
    local total = g * 10000 + s * 100 + c
    if total < 1 then return nil, "Type how much to donate." end
    return total
end

-- 123456 -> "12g 34s 56c". Chips read like money, in full.
function C.Text(copper)
    copper = math.max(0, math.floor(tonumber(copper) or 0))
    local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

-- A money-log age ("2 days, 3 hours ago") in seconds. The entry happened
-- between that and an hour more.
function C.Age(years, months, days, hours)
    return ((((years or 0) * 365 + (months or 0) * 30 + (days or 0)) * 24) + (hours or 0)) * 3600
end

-- Could this deposit be that claim? Same person, same amount, and the claim
-- was made about when the money log says the deposit was.
function C.Fits(buy, dep, now)
    if buy.name ~= dep.name or buy.amt ~= dep.amount then return false end
    local age = now - buy.t
    return age >= dep.age - C.SLACK and age <= dep.age + 3600 + C.SLACK
end

-- Which pending claims does the money log back up?
-- buys = { { id, name, amt, t, ok } }, deposits = { { name, amount, age } }.
-- Each deposit backs one claim. Claims already confirmed take theirs first,
-- so one deposit can never confirm two claims. -> { id, ... }
function C.Verify(buys, deposits, now)
    local order = {}
    for _, b in ipairs(buys) do order[#order + 1] = b end
    table.sort(order, function(a, b)
        if (a.ok and 1 or 0) ~= (b.ok and 1 or 0) then return a.ok and true or false end
        if a.t ~= b.t then return a.t < b.t end
        return tostring(a.id) < tostring(b.id)
    end)
    local used, out = {}, {}
    for _, b in ipairs(order) do
        for i, d in ipairs(deposits) do
            if not used[i] and C.Fits(b, d, now) then
                used[i] = true
                if not b.ok then out[#out + 1] = b.id end
                break
            end
        end
    end
    return out
end

-- Everyone's chips. -> [guid] = { ok = confirmed, pending = waiting on an Officer }
function C.Balances(st)
    local out = {}
    for _, b in pairs(st and st.chipBuys or {}) do
        local row = out[b.who] or { ok = 0, pending = 0 }
        out[b.who] = row
        if b.ok then row.ok = row.ok + b.amt else row.pending = row.pending + b.amt end
    end
    for guid, amt in pairs(st and st.chipGrants or {}) do
        local row = out[guid] or { ok = 0, pending = 0 }
        out[guid] = row
        row.ok = row.ok + amt
    end
    -- What the games floor has given or taken. Chips can't go below nothing.
    for guid, net in pairs(st and st.chipNets or {}) do
        local row = out[guid] or { ok = 0, pending = 0 }
        out[guid] = row
        row.ok = math.max(0, row.ok + net)
    end
    return out
end

-- The leaderboard: most chips first.
function C.Board(st, nameOf)
    local rows = {}
    for guid, b in pairs(C.Balances(st)) do
        rows[#rows + 1] = { guid = guid, name = nameOf(guid) or "?", ok = b.ok, pending = b.pending }
    end
    table.sort(rows, function(a, b)
        if a.ok ~= b.ok then return a.ok > b.ok end
        if a.pending ~= b.pending then return a.pending > b.pending end
        return a.name < b.name
    end)
    return rows
end

---------------------------------------------------------------------------
-- Game side
---------------------------------------------------------------------------
local bankOpen = false
local waiting           -- { amount, token } while a donation is on its way into the money log
local lastNote
local token = 0

local function refresh() if C.Refresh then C.Refresh() end end

function C.AtBank() return bankOpen end

-- Claims as the rules want them, with the donor's character name.
local function claims(st)
    local out = {}
    for _, b in pairs(st and st.chipBuys or {}) do
        out[#out + 1] = { id = b.id, who = b.who, name = ns.NameForGUID(b.who), amt = b.amt, t = b.t, ok = b.ok }
    end
    return out
end

local function moneyLog()
    local out = {}
    if not (GetNumGuildBankMoneyTransactions and GetGuildBankMoneyTransaction) then return out end
    local ok, n = pcall(GetNumGuildBankMoneyTransactions)
    for i = 1, (ok and type(n) == "number" and n or 0) do
        local ok2, kind, name, amount, y, m, d, h = pcall(GetGuildBankMoneyTransaction, i)
        if ok2 and kind == "deposit" and type(name) == "string" and type(amount) == "number" then
            out[#out + 1] = { name = U.ShortName(name), amount = amount, age = C.Age(y, m, d, h) }
        end
    end
    return out
end

local function askForLog()
    if QueryGuildBankLog then pcall(QueryGuildBankLog, (MAX_GUILDBANK_TABS or 6) + 1) end
end

-- The money log arrived. Finish my own donation, and if I'm an Officer,
-- confirm everyone else's claims that the log backs up.
local function onLog()
    if not bankOpen then return end
    local st, now, deposits = Red.State(), ns.Now(), moneyLog()
    local all = claims(st)
    if waiting then
        -- Is there a deposit of mine that no earlier claim of mine has used?
        local mine = { id = "new", who = ns.MyGUID(), name = UnitName("player"), amt = waiting.amount, t = now, ok = false }
        local probe = { mine }
        for _, b in ipairs(all) do
            if b.who == mine.who then probe[#probe + 1] = { id = b.id, name = b.name, amt = b.amt, t = b.t, ok = true } end
        end
        for _, id in ipairs(C.Verify(probe, deposits, now)) do
            if id == "new" then
                local amount = waiting.amount
                waiting = nil
                token = token + 1
                local e, why = ns.Log.New("CHIP_BUY", { amt = amount })
                lastNote = e and ("Thank you. " .. C.Text(amount) .. " in chips are pending until an Officer's addon sees the deposit.")
                    or ("Your gold is in the guild bank, but the chips weren't recorded: " .. tostring(why))
                all = claims(Red.State())
            end
        end
    end
    if RBAC.ICan("award") then
        local me = ns.MyGUID()
        local byId = {}
        for _, b in ipairs(all) do byId[b.id] = b end
        for _, id in ipairs(C.Verify(all, deposits, now)) do
            if byId[id] and byId[id].who ~= me then ns.Log.New("CHIP_OK", { buy = id }) end
        end
    end
    refresh()
end

-- Donate to the guild bank for chips. The deposit is the player's own click.
function C.Donate(gold, silver, copper)
    local amount, why = C.Amount(gold, silver, copper)
    if not amount then return nil, why end
    if amount > C.MAX then return nil, "That is more than one donation can be." end
    if not bankOpen then return nil, "Open the guild bank first. The gold goes in there." end
    if not DepositGuildBankMoney then return nil, "This guild bank can't take deposits from addons. Use the bank's Deposit button." end
    if waiting then return nil, "Still recording your last donation." end
    if (GetMoney and GetMoney() or 0) < amount then return nil, "You don't have " .. C.Text(amount) .. "." end
    if not pcall(DepositGuildBankMoney, amount) then return nil, "The guild bank didn't take that." end
    token = token + 1
    local mine = token
    waiting, lastNote = { amount = amount }, nil
    if C_Timer and C_Timer.After then
        C_Timer.After(1, function() if waiting and token == mine then askForLog() end end)
        C_Timer.After(C.WAIT, function()
            if waiting and token == mine then
                waiting = nil
                lastNote = "The deposit didn't show in the bank's money log, so no chips were claimed. If the gold left your bags, tell an Officer."
                refresh()
            end
        end)
    end
    return true
end

-- Read the bank's money log now. Only works with the guild bank open.
function C.ReadLog()
    if not bankOpen then return nil, "Open the guild bank first. The money log is read there." end
    askForLog()
    return true
end

-- The ADMIN assigns chips to a guild member by name.
function C.Grant(name, gold, silver, copper)
    if not RBAC.ICan("devtools") then return nil, "Only the ADMIN can assign chips." end
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil, "Type the guild member's name." end
    local guid = ns.GUIDForName(name)
    if not (guid and ns.roster.byGUID[guid]) then return nil, "No guild member is named " .. U.Safe(name, 30) .. "." end
    local amount, why = C.Amount(gold, silver, copper)
    if not amount then return nil, (why == "Type how much to donate.") and "Type how many chips to give." or why end
    local e, err = ns.Log.New("CHIP_GRANT", { to = guid, amt = amount })
    if not e then return nil, err end
    return true, guid, amount
end

local function opened()
    bankOpen = true
    askForLog()
    refresh()
end
local function closed()
    bankOpen = false
    refresh()
end
ns.On("GUILDBANKFRAME_OPENED", opened)
ns.On("GUILDBANKFRAME_CLOSED", closed)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind)
    local t = Enum and Enum.PlayerInteractionType
    if t and kind == t.GuildBanker then opened() end
end)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(kind)
    local t = Enum and Enum.PlayerInteractionType
    if t and kind == t.GuildBanker then closed() end
end)
ns.On("GUILDBANK_UPDATE_MONEY", function() if bankOpen then askForLog() end end)
ns.On("GUILDBANKLOG_UPDATE", onLog)

---------------------------------------------------------------------------
-- The chips page. It lives in the Casino window, beside the games.
---------------------------------------------------------------------------
local W = ns.W
local helping = false
local WIDTH = 536

-- Build the page inside the Casino window. -> the page's frame
function C.BuildPanel(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(WIDTH, 330)
    f.help = W.Button(f, "How does this work?", 140, 20, function()
        helping = not helping
        C.Refresh()
    end)
    f.help:SetPoint("TOPRIGHT", 0, 0)
    f.read = W.Button(f, "Read the bank log", 130, 20, function()
        local ok, why = C.ReadLog()
        lastNote = ok and "Reading the guild bank's money log..." or why
        C.Refresh()
    end)
    f.read:SetPoint("TOPRIGHT", -146, 0)

    f.mine = W.Text(f, "", "GameFontNormalLarge")
    f.mine:SetPoint("TOPLEFT", 0, -2)
    f.mine:SetWidth(250)
    f.mine:SetJustifyH("LEFT")
    f.mine:SetWordWrap(false)
    f.minePending = W.Text(f, "", "GameFontHighlightSmall")
    f.minePending:SetPoint("TOPLEFT", 0, -26)
    f.minePending:SetWidth(WIDTH)
    f.minePending:SetJustifyH("LEFT")
    f.minePending:SetWordWrap(false)

    f.donateHead = W.Text(f, "Donate to the guild bank", "GameFontNormalSmall")
    f.donateHead:SetPoint("TOPLEFT", 0, -50)
    f.boxes, f.labels = {}, {}
    for i, unit in ipairs({ "gold", "silver", "copper" }) do
        local box = W.Edit(f, 54, i == 1 and 6 or 2)
        box:SetPoint("TOPLEFT", (i - 1) * 92, -68)
        local label = W.Text(f, unit, "GameFontHighlightSmall")
        label:SetPoint("LEFT", box, "RIGHT", 4, 0)
        f.boxes[i], f.labels[i] = box, label
    end
    f.donate = W.Button(f, "Donate for chips", 124, 22, function()
        local ok, why = C.Donate(f.boxes[1]:GetText(), f.boxes[2]:GetText(), f.boxes[3]:GetText())
        if ok then for _, b in ipairs(f.boxes) do b:SetText("") end else lastNote = why end
        C.Refresh()
    end, "accent")
    f.donate:SetPoint("TOPLEFT", 284, -68)
    f.status = W.Text(f, "", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", 0, -98)
    f.status:SetWidth(WIDTH)
    f.status:SetJustifyH("LEFT")
    f.status:SetWordWrap(true)

    f.boardHead = W.Text(f, "Leaderboard", "GameFontNormalSmall")
    f.boardHead:SetPoint("TOPLEFT", 0, -136)
    f.cols = {}
    for i, h in ipairs({ { "Raider", 4, 200 }, { "Chips", 220, 140 }, { "Pending", 380, 140 } }) do
        local fs = W.Text(f, h[1], "GameFontDisableSmall")
        fs:SetPoint("TOPLEFT", h[2], -154)
        fs:SetWidth(h[3])
        fs:SetJustifyH("LEFT")
        f.cols[i] = fs
    end
    f.board = W.List(f, WIDTH, 126, 18, function(row, r)
        f.board.Col(row, 1, 4, 200):SetText(U.Safe(r.name, 30))
        f.board.Col(row, 2, 220, 140):SetText(C.Text(r.ok))
        local p = f.board.Col(row, 3, 380, 140)
        p:SetText(r.pending > 0 and C.Text(r.pending) or "-")
        p:SetTextColor(W.C.muted[1], W.C.muted[2], W.C.muted[3])
    end)
    f.board.scroll:SetPoint("TOPLEFT", 0, -170)
    f.board.scroll:SetSize(WIDTH, 126)
    f.foot = W.Text(f, "Chips are one-way: they can't be turned back into gold. Donations go to the guild.", "GameFontDisableSmall")
    f.foot:SetPoint("TOPLEFT", 0, -304)
    f.foot:SetWidth(WIDTH)
    f.foot:SetJustifyH("LEFT")
    f.foot:SetWordWrap(false)
    f.helpText = W.Text(f, table.concat(C.HOWTO, "\n\n"), "GameFontHighlightSmall")
    f.helpText:SetPoint("TOPLEFT", 0, -30)
    f.helpText:SetWidth(WIDTH)
    f.helpText:SetJustifyH("LEFT")
    f.helpText:SetJustifyV("TOP")
    f.helpText:SetWordWrap(true)
    C.frame = f
    return f
end

function C.Refresh()
    local f = C.frame
    if not (f and f:IsVisible()) then return end
    f.help:SetText(helping and "Back" or "How does this work?")
    local parts = { f.mine, f.minePending, f.donateHead, f.donate, f.status, f.boardHead, f.foot, f.read }
    for _, w in ipairs(f.boxes) do parts[#parts + 1] = w end
    for _, w in ipairs(f.labels) do parts[#parts + 1] = w end
    for _, w in ipairs(f.cols) do parts[#parts + 1] = w end
    for _, w in ipairs(parts) do w:SetShown(not helping) end
    f.board.scroll:SetShown(not helping)
    f.helpText:SetShown(helping)
    if helping then return end
    local st = Red.State()
    local mine = C.Balances(st)[ns.MyGUID()] or { ok = 0, pending = 0 }
    f.mine:SetText("Your chips: |cffffd100" .. C.Text(mine.ok) .. "|r")
    f.minePending:SetText(mine.pending > 0 and (C.Text(mine.pending) .. " more pending, waiting for an Officer to open the guild bank.") or "")
    f.donate:SetEnabled(bankOpen and not waiting)
    f.read:SetEnabled(bankOpen)
    local open = 0
    for _, b in pairs(st and st.chipBuys or {}) do if not b.ok then open = open + 1 end end
    if lastNote then
        f.status:SetText("|cffffd100" .. lastNote .. "|r")
    elseif waiting then
        f.status:SetText("Recording your donation...")
    elseif not bankOpen then
        f.status:SetText("Open the guild bank to donate. 1 gold is 1 gold chip, 1 silver is 1 silver chip, 1 copper is 1 copper chip."
            .. (RBAC.ICan("award") and open > 0 and ("\n|cffffd100" .. open .. " donation" .. (open == 1 and " is" or "s are") .. " waiting: open the guild bank, then the Casino, to confirm.|r") or ""))
    else
        f.status:SetText("Type an amount and press Donate for chips. The gold goes into the guild bank.")
    end
    f.board:SetItems(C.Board(st, ns.NameForGUID))
end

-- The page was just opened: start clean, and read the money log if the bank is open.
function C.Opened()
    helping, lastNote = false, nil
    if bankOpen then askForLog() end
end

-- Open the Casino on the chips page.
function C.Toggle() ns.Casino.Toggle("Chips") end

ns.Listen("LOG_CHANGED", function() C.Refresh() end)
