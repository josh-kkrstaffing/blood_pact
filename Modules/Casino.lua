-- Blind Tiger: the games floor. Guildmates play their chips against the house,
-- and the house is the guild. Every game is tilted a little toward the house,
-- by rules written down here and checked by the tests, never by a rigged deal.
--
-- Chips are play chips (see Chips.lua): they come from donations to the guild
-- bank and never turn back into gold. A game's result is worked out on the
-- player's own computer, the same trust the addon gives to readiness scores.
-- Plays are added up and written to the guild's log a session at a time, not
-- one entry per spin, so the log stays small.
local _, ns = ...
local G = {}
ns.Casino = G

local U, Red, Chips = ns.U, ns.Reducer, ns.Chips

G.MAX_MULT = 100          -- the most any game returns on one stake (the slots jackpot)
G.COMMIT_EVERY = 25       -- plays before a session is written to the log
G.BIG_WIN = 10            -- a win of this many times the stake is called out on the floor
G.rng = math.random       -- the tests swap this for a scripted one

---------------------------------------------------------------------------
-- Stakes
---------------------------------------------------------------------------
-- "1g 50s", "20s", "75c" -> copper. A unit is required, so 5 can't be read wrong.
function G.Stake(text)
    text = tostring(text or ""):lower():gsub("%s", "")
    if text == "" then return nil, "Type a stake, like 5s or 1g." end
    local total, rest = 0, text
    for n, unit in text:gmatch("(%d+)([gsc])") do
        total = total + tonumber(n) * (unit == "g" and 10000 or unit == "s" and 100 or 1)
        rest = rest:gsub("^" .. n .. unit, "", 1)
    end
    if rest ~= "" or total < 1 then return nil, "Type a stake with a unit, like 5s or 1g." end
    if total > 1e9 then return nil, "That stake is too big." end
    return total
end

---------------------------------------------------------------------------
-- Roulette: the American wheel, 38 pockets with 0 and 00. Standard payouts.
-- Every bet below gives the house 2 pockets in 38: a 5.26% edge.
---------------------------------------------------------------------------
G.RED = {}
for _, n in ipairs({ 1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36 }) do G.RED[n] = true end
G.POCKETS = { "0", "00" }
for n = 1, 36 do G.POCKETS[#G.POCKETS + 1] = tostring(n) end

-- kind -> { label(pick), pays (winnings per 1 staked), wins(number, pick) }; number is nil for 0 and 00.
G.BETS = {
    num = { pays = 35 },
    red = { pays = 1, label = "Red", wins = function(n) return G.RED[n] == true end },
    black = { pays = 1, label = "Black", wins = function(n) return not G.RED[n] end },
    odd = { pays = 1, label = "Odd", wins = function(n) return n % 2 == 1 end },
    even = { pays = 1, label = "Even", wins = function(n) return n % 2 == 0 end },
    low = { pays = 1, label = "1-18", wins = function(n) return n <= 18 end },
    high = { pays = 1, label = "19-36", wins = function(n) return n >= 19 end },
    dozen = { pays = 2, wins = function(n, pick) return math.ceil(n / 12) == pick end },
    column = { pays = 2, wins = function(n, pick) return (n - 1) % 3 + 1 == pick end },
}

function G.BetLabel(bet)
    if bet.kind == "num" then return "Number " .. bet.pick end
    if bet.kind == "dozen" then return ({ "1st 12", "2nd 12", "3rd 12" })[bet.pick] end
    if bet.kind == "column" then return "Column " .. bet.pick end
    return G.BETS[bet.kind].label
end

-- A number bet's pick, checked: "0", "00", "1".."36".
function G.Pocket(text)
    text = tostring(text or ""):gsub("%s", "")
    for _, p in ipairs(G.POCKETS) do if p == text then return p end end
    return nil
end

function G.BetWins(bet, pocket)
    if bet.kind == "num" then return bet.pick == pocket end
    local n = pocket ~= "0" and pocket ~= "00" and tonumber(pocket) or nil
    if not n then return false end                 -- 0 and 00 beat every outside bet
    return G.BETS[bet.kind].wins(n, bet.pick)
end

-- -> chips staked, chips returned (stakes of winning bets plus their winnings)
function G.RouletteResult(bets, pocket)
    local staked, back = 0, 0
    for _, b in ipairs(bets) do
        staked = staked + b.stake
        if G.BetWins(b, pocket) then back = back + b.stake * (G.BETS[b.kind].pays + 1) end
    end
    return staked, back
end

function G.PocketColor(pocket)
    if pocket == "0" or pocket == "00" then return "green" end
    return G.RED[tonumber(pocket)] and "red" or "black"
end

---------------------------------------------------------------------------
-- Slots: three reels, each stopping on one of 20 places. Returns are in
-- stakes: 9 means a 1s stake comes back as 9s. The table below returns
-- 7413/8000 of what goes in, a 7.34% edge for the house.
---------------------------------------------------------------------------
G.REEL = { { "Tiger", 1 }, { "Seven", 2 }, { "Bar", 3 }, { "Bell", 4 }, { "Cherry", 4 }, { "Lemon", 6 } }
G.SLOT_PAYS = { Tiger = 100, Seven = 36, Bar = 27, Bell = 16, Cherry = 16, Lemon = 9 }
G.TWO_CHERRIES = 3
G.REEL_SIZE = 0
for _, s in ipairs(G.REEL) do G.REEL_SIZE = G.REEL_SIZE + s[2] end

-- Where a reel stops: n = 1..20 -> the symbol there.
function G.ReelStop(n)
    for _, s in ipairs(G.REEL) do
        if n <= s[2] then return s[1] end
        n = n - s[2]
    end
    return G.REEL[#G.REEL][1]
end

function G.SlotPay(a, b, c)
    if a == b and b == c then return G.SLOT_PAYS[a] end
    local cherries = (a == "Cherry" and 1 or 0) + (b == "Cherry" and 1 or 0) + (c == "Cherry" and 1 or 0)
    return cherries == 2 and G.TWO_CHERRIES or 0
end

-- What the machine gives back per chip, worked out over every stop: -> returned, out of
function G.SlotReturn()
    local back = 0
    for a = 1, G.REEL_SIZE do
        for b = 1, G.REEL_SIZE do
            for c = 1, G.REEL_SIZE do back = back + G.SlotPay(G.ReelStop(a), G.ReelStop(b), G.ReelStop(c)) end
        end
    end
    return back, G.REEL_SIZE ^ 3
end

---------------------------------------------------------------------------
-- The ledger
---------------------------------------------------------------------------
-- Net from game sessions written to the log. -> [guid] = net, and the house's take.
function G.Nets(st)
    local out, house = {}, 0
    for guid, n in pairs(st and st.chipNets or {}) do
        out[guid] = n
        house = house - n
    end
    return out, house
end

local function tally() local c = ns.Char(); c.casino = c.casino or {}; return c.casino end

-- Plays since the last write to the log: -> net, staked, plays
function G.Unwritten()
    local net, bet, n = 0, 0, 0
    for _, s in pairs(tally()) do net, bet, n = net + s.net, bet + s.bet, n + s.n end
    return net, bet, n
end

-- Chips I can stake right now: confirmed chips, plus or minus what I've played.
function G.Available()
    local mine = Chips.Balances(Red.State())[ns.MyGUID()]
    return math.max(0, (mine and mine.ok or 0) + (G.Unwritten()))
end

-- Write my finished plays to the guild's log, one entry per game.
function G.Commit()
    local t = tally()
    for game, s in pairs(t) do
        if s.n > 0 then
            local e = ns.Log.New("CHIP_SESSION", { game = game, n = s.n, bet = s.bet, net = s.net })
            if e then t[game] = nil end
        else
            t[game] = nil
        end
    end
end

local feed = {}           -- recent big wins on the floor, newest first
function G.Feed() return feed end
local function addFeed(line)
    table.insert(feed, 1, line)
    while #feed > 6 do feed[#feed] = nil end
end

-- One play is over: staked chips went in, back came out.
local function settle(game, staked, back)
    local t = tally()
    local s = t[game] or { n = 0, bet = 0, net = 0 }
    t[game] = s
    s.n, s.bet, s.net = s.n + 1, s.bet + staked, s.net + back - staked
    if back >= staked * G.BIG_WIN then
        addFeed(("You won %s on %s."):format(Chips.Text(back - staked), game))
        if not ns.mock then ns.Sync.SendLive({ t = "CW", g = game, w = back - staked }) end
    end
    local _, _, n = G.Unwritten()
    if n >= G.COMMIT_EVERY then G.Commit() end
end

local function canStake(amount)
    if amount < 1 then return nil, "Place a bet first." end
    local have = G.Available()
    if have < 1 then return nil, "You have no chips. Donate at the guild bank to get some." end
    if amount > have then return nil, "You only have " .. Chips.Text(have) .. " in chips." end
    return true
end

-- Spin the wheel on a set of bets. -> { pocket, staked, back }, or nil and why.
function G.Spin(bets)
    local staked = 0
    for _, b in ipairs(bets or {}) do staked = staked + b.stake end
    local ok, why = canStake(staked)
    if not ok then return nil, why end
    local pocket = G.POCKETS[G.rng(#G.POCKETS)]
    local _, back = G.RouletteResult(bets, pocket)
    settle("Roulette", staked, back)
    return { pocket = pocket, staked = staked, back = back }
end

-- Pull the slot machine. -> { reels = { a, b, c }, staked, back }, or nil and why.
function G.Pull(stake)
    local ok, why = canStake(stake or 0)
    if not ok then return nil, why end
    local a, b, c = G.ReelStop(G.rng(G.REEL_SIZE)), G.ReelStop(G.rng(G.REEL_SIZE)), G.ReelStop(G.rng(G.REEL_SIZE))
    local back = stake * G.SlotPay(a, b, c)
    settle("Slots", stake, back)
    return { reels = { a, b, c }, staked = stake, back = back }
end

-- A guildmate's big win, for the floor's feed.
ns.Sync.Handle("CW", function(msg, _, sguid)
    if sguid == ns.MyGUID() or type(msg.g) ~= "string" or type(msg.w) ~= "number" then return end
    addFeed(("%s won %s on %s."):format(U.Safe(ns.NameForGUID(sguid) or "A guildmate", 30), Chips.Text(msg.w), U.Safe(msg.g, 20)))
    if G.Refresh then G.Refresh() end
end)
ns.On("PLAYER_LOGOUT", function() G.Commit() end)

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local W = ns.W
local game = "Roulette"
local bets, lastSpin, lastPull, note = {}, nil, nil, nil
local COLOR = { red = "|cffff4040", black = "|cffd0d0d0", green = "|cff40d060" }
local REEL_COLOR = { Tiger = "|cffffa020", Seven = "|cffff4040", Bar = "|cffe0e0e0", Bell = "|cffffd100", Cherry = "|cffff6080", Lemon = "|cfffff060" }

local function build()
    local f = CreateFrame("Frame", "BlindTigerFloor", UIParent)
    f:SetSize(560, 430)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    f:EnableMouse(true)
    W.Glass(f, true)
    W.Text(f, "The Blind Tiger floor", "GameFontNormal"):SetPoint("TOPLEFT", 10, -9)
    W.Button(f, "X", 22, 20, function() f:Hide() end):SetPoint("TOPRIGHT", -6, -6)
    f.chips = W.Text(f, "", "GameFontHighlightSmall")
    f.chips:SetPoint("TOPRIGHT", -36, -11)
    f.chips:SetWidth(330)
    f.chips:SetJustifyH("RIGHT")
    f.chips:SetWordWrap(false)
    W.Line(f, -32)

    f.tabs = {}
    for i, name in ipairs({ "Roulette", "Slots" }) do
        local b = W.Button(f, name, 100, 22, function()
            game, note = name, nil
            G.Refresh()
        end)
        b:SetPoint("TOPLEFT", 12 + (i - 1) * 106, -40)
        f.tabs[name] = b
    end
    f.soon = W.Text(f, "Blackjack and poker are next.", "GameFontDisableSmall")
    f.soon:SetPoint("TOPLEFT", 230, -45)
    W.Text(f, "Stake", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 12, -76)
    f.stake = W.Edit(f, 80, 12)
    f.stake:SetPoint("TOPLEFT", 52, -72)
    f.stake:SetText("1s")
    f.stakeHint = W.Text(f, "like 5s, 1g or 1g 50s", "GameFontDisableSmall")
    f.stakeHint:SetPoint("TOPLEFT", 140, -76)

    local function stake()
        local s, why = G.Stake(f.stake:GetText())
        if not s then note = why end
        return s
    end

    -- Roulette
    local r = CreateFrame("Frame", nil, f)
    r:SetPoint("TOPLEFT", 12, -100)
    r:SetSize(536, 250)
    f.roulette = r
    r.result = W.Text(r, "", "GameFontNormalHuge")
    r.result:SetPoint("TOPLEFT", 0, 0)
    r.result:SetWidth(536)
    r.result:SetJustifyH("LEFT")
    r.result:SetWordWrap(false)
    local function add(kind, pick)
        local s = stake()
        if s then
            bets[#bets + 1] = { kind = kind, pick = pick, stake = s }
            note = nil
        end
        G.Refresh()
    end
    local outside = { { "red" }, { "black" }, { "odd" }, { "even" }, { "low" }, { "high" },
        { "dozen", 1 }, { "dozen", 2 }, { "dozen", 3 }, { "column", 1 }, { "column", 2 }, { "column", 3 } }
    for i, o in ipairs(outside) do
        local b = W.Button(r, G.BetLabel({ kind = o[1], pick = o[2] }), 84, 22, function() add(o[1], o[2]) end)
        b:SetPoint("TOPLEFT", ((i - 1) % 6) * 89, -34 - math.floor((i - 1) / 6) * 26)
    end
    W.Text(r, "Number (0, 00, 1-36)", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 0, -94)
    r.num = W.Edit(r, 40, 2)
    r.num:SetPoint("TOPLEFT", 126, -90)
    W.Button(r, "Bet the number", 110, 22, function()
        local p = G.Pocket(r.num:GetText())
        if p then add("num", p) else note = "Type 0, 00 or a number from 1 to 36."; G.Refresh() end
    end):SetPoint("TOPLEFT", 176, -90)
    r.bets = W.Text(r, "", "GameFontHighlightSmall")
    r.bets:SetPoint("TOPLEFT", 0, -122)
    r.bets:SetWidth(536)
    r.bets:SetJustifyH("LEFT")
    r.bets:SetJustifyV("TOP")
    r.bets:SetWordWrap(true)
    r.spin = W.Button(r, "Spin", 120, 26, function()
        local res, why = G.Spin(bets)
        if res then lastSpin, note = res, nil else note = why end
        G.Refresh()
    end, "accent")
    r.spin:SetPoint("TOPLEFT", 0, -190)
    W.Button(r, "Clear bets", 100, 26, function() bets, note = {}, nil; G.Refresh() end):SetPoint("TOPLEFT", 128, -190)
    r.rules = W.Text(r, "American wheel: 0 and 00. A number pays 35 to 1, a dozen or column 2 to 1, the rest even money. House edge 5.26%.", "GameFontDisableSmall")
    r.rules:SetPoint("TOPLEFT", 0, -226)
    r.rules:SetWidth(536)
    r.rules:SetJustifyH("LEFT")

    -- Slots
    local s = CreateFrame("Frame", nil, f)
    s:SetPoint("TOPLEFT", 12, -100)
    s:SetSize(536, 250)
    f.slots = s
    s.reels = {}
    for i = 1, 3 do
        local box = CreateFrame("Frame", nil, s)
        box:SetSize(150, 70)
        box:SetPoint("TOPLEFT", (i - 1) * 160, 0)
        W.Glass(box, true)
        local fs = W.Text(box, "?", "GameFontNormalHuge")
        fs:SetPoint("CENTER", 0, 0)
        s.reels[i] = fs
    end
    s.result = W.Text(s, "", "GameFontNormalLarge")
    s.result:SetPoint("TOPLEFT", 0, -82)
    s.result:SetWidth(536)
    s.result:SetJustifyH("LEFT")
    s.result:SetWordWrap(false)
    s.pull = W.Button(s, "Pull", 120, 26, function()
        local st = stake()
        if st then
            local res, why = G.Pull(st)
            if res then lastPull, note = res, nil else note = why end
        end
        G.Refresh()
    end, "accent")
    s.pull:SetPoint("TOPLEFT", 0, -112)
    local lines = {}
    for _, sym in ipairs(G.REEL) do lines[#lines + 1] = ("%s x3 pays %d"):format(sym[1], G.SLOT_PAYS[sym[1]]) end
    lines[#lines + 1] = "Two Cherries pay " .. G.TWO_CHERRIES
    s.table = W.Text(s, table.concat(lines, "    ") .. "\nPays are in stakes: 9 means a 1s stake comes back as 9s. House edge 7.34%.", "GameFontDisableSmall")
    s.table:SetPoint("TOPLEFT", 0, -150)
    s.table:SetWidth(536)
    s.table:SetJustifyH("LEFT")
    s.table:SetWordWrap(true)

    f.status = W.Text(f, "", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", 12, -352)
    f.status:SetWidth(536)
    f.status:SetJustifyH("LEFT")
    f.status:SetWordWrap(false)
    f.feed = W.Text(f, "", "GameFontDisableSmall")
    f.feed:SetPoint("TOPLEFT", 12, -372)
    f.feed:SetWidth(536)
    f.feed:SetJustifyH("LEFT")
    f.feed:SetJustifyV("TOP")
    f.feed:SetWordWrap(true)
    f:SetScript("OnHide", function() G.Commit() end)
    f:Hide()
    G.frame = f
    return f
end

function G.Refresh()
    local f = G.frame
    if not (f and f:IsShown()) then return end
    local _, house = G.Nets(Red.State())
    f.chips:SetText(("Your chips: |cffffd100%s|r    The house is %s %s"):format(Chips.Text(G.Available()),
        house >= 0 and "up" or "down", Chips.Text(math.abs(house))))
    for name, b in pairs(f.tabs) do b:SetEnabled(name ~= game) end
    f.roulette:SetShown(game == "Roulette")
    f.slots:SetShown(game == "Slots")
    if game == "Roulette" then
        local r = f.roulette
        if lastSpin then
            local won = lastSpin.back - lastSpin.staked
            r.result:SetText(("%s%s|r   %s"):format(COLOR[G.PocketColor(lastSpin.pocket)], lastSpin.pocket,
                won > 0 and ("|cff40ff40You won " .. Chips.Text(won) .. "|r") or won == 0 and "You broke even"
                or ("|cffff6040The house takes " .. Chips.Text(-won) .. "|r")))
        else
            r.result:SetText("Place your bets")
        end
        local parts, total = {}, 0
        for _, b in ipairs(bets) do
            parts[#parts + 1] = G.BetLabel(b) .. " " .. Chips.Text(b.stake)
            total = total + b.stake
        end
        r.bets:SetText(#parts > 0 and ("On the table (" .. Chips.Text(total) .. "): " .. table.concat(parts, ", "))
            or "Nothing on the table. Set a stake, then click what to bet on. Click again to add more.")
        r.spin:SetEnabled(#bets > 0)
    else
        local s = f.slots
        for i = 1, 3 do
            local sym = lastPull and lastPull.reels[i]
            s.reels[i]:SetText(sym and ((REEL_COLOR[sym] or "") .. sym .. "|r") or "?")
        end
        if lastPull then
            local won = lastPull.back - lastPull.staked
            s.result:SetText(won > 0 and ("|cff40ff40You won " .. Chips.Text(won) .. "|r") or ("|cffff6040The house takes " .. Chips.Text(-won) .. "|r"))
        else
            s.result:SetText("Set a stake and pull.")
        end
    end
    f.status:SetText(note and ("|cffffd100" .. note .. "|r") or "Chips are play chips: they never turn back into gold. The house is the guild.")
    local lines = G.Feed()
    f.feed:SetText(#lines > 0 and ("On the floor: " .. table.concat(lines, "  ")) or "Big wins by guildmates show here.")
end

function G.Toggle()
    local f = G.frame or build()
    if f:IsShown() then f:Hide() return end
    note = nil
    f:Show()
    G.Refresh()
end

ns.Listen("LOG_CHANGED", function() G.Refresh() end)
