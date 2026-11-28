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

local U, Red, Chips, K = ns.U, ns.Reducer, ns.Chips, ns.Cards

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

-- Chips I can stake right now: confirmed chips, plus or minus what I've played,
-- less what is sitting on a table in a hand that isn't over.
local inPlay = 0
function G.Available()
    local mine = Chips.Balances(Red.State())[ns.MyGUID()]
    return math.max(0, (mine and mine.ok or 0) + (G.Unwritten()) - inPlay)
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

---------------------------------------------------------------------------
-- Blackjack against the house
---------------------------------------------------------------------------
local function draw() return { r = G.rng(13) + 1, s = G.rng(4) } end      -- each card dealt fresh
local bj                  -- the hand in progress, or the last one finished

function G.Blackjack() return bj end

local function bjFinish()
    while K.DealerHits(bj.dealer) and bj.live do bj.dealer[#bj.dealer + 1] = draw() end
    local staked, back = 0, 0
    for _, h in ipairs(bj.hands) do
        staked = staked + h.bet
        h.back = K.BJBack(h, bj.dealer)
        back = back + h.back
    end
    bj.phase, bj.staked, bj.back = "done", staked, back
    inPlay = 0
    settle("Blackjack", staked, back)
end

-- Move to the next hand that still needs playing, or finish.
local function bjNext()
    while bj.at <= #bj.hands and bj.hands[bj.at].done do bj.at = bj.at + 1 end
    if bj.at > #bj.hands then
        -- The dealer only draws if some hand is still standing.
        bj.live = false
        for _, h in ipairs(bj.hands) do if (K.Total(h.cards)) <= 21 then bj.live = true end end
        bjFinish()
    end
end

function G.BJDeal(stake)
    if bj and bj.phase == "play" then return nil, "Finish this hand first." end
    local ok, why = canStake(stake or 0)
    if not ok then return nil, why end
    bj = { stake = stake, at = 1, phase = "play", hands = { { cards = { draw() }, bet = stake } }, dealer = { draw() } }
    bj.hands[1].cards[2] = draw()
    bj.dealer[2] = draw()
    inPlay = stake
    -- A blackjack on either side ends the hand at once.
    if K.IsNatural(bj.dealer) or K.IsNatural(bj.hands[1].cards) then
        bj.hands[1].done, bj.live = true, false
        bjFinish()
    end
    return bj
end

local function bjHand()
    if not (bj and bj.phase == "play") then return nil, "Deal a hand first." end
    return bj.hands[bj.at]
end

function G.BJHit()
    local h, why = bjHand()
    if not h then return nil, why end
    h.cards[#h.cards + 1] = draw()
    if (K.Total(h.cards)) >= 21 then h.done = true; bjNext() end
    return bj
end

function G.BJStand()
    local h, why = bjHand()
    if not h then return nil, why end
    h.done = true
    bjNext()
    return bj
end

function G.BJCanDouble()
    local h = bjHand()
    return h ~= nil and #h.cards == 2 and not h.aces and G.Available() >= h.bet
end

function G.BJDouble()
    local h, why = bjHand()
    if not h then return nil, why end
    if #h.cards ~= 2 or h.aces then return nil, "You can only double on your first two cards." end
    if G.Available() < h.bet then return nil, "You don't have the chips to double." end
    inPlay = inPlay + h.bet
    h.bet, h.doubled = h.bet * 2, true
    h.cards[#h.cards + 1] = draw()
    h.done = true
    bjNext()
    return bj
end

function G.BJCanSplit()
    local h = bjHand()
    return h ~= nil and #bj.hands == 1 and K.CanSplit(h.cards) and G.Available() >= h.bet
end

function G.BJSplit()
    local h, why = bjHand()
    if not h then return nil, why end
    if #bj.hands ~= 1 or not K.CanSplit(h.cards) then return nil, "You can split a pair once." end
    if G.Available() < h.bet then return nil, "You don't have the chips to split." end
    inPlay = inPlay + h.bet
    local aces = h.cards[1].r == 14
    local second = { cards = { h.cards[2], draw() }, bet = h.bet, split = true, aces = aces, done = aces }
    h.cards[2] = draw()
    h.split, h.aces, h.done = true, aces, aces         -- split aces get one card each
    bj.hands[2] = second
    for _, x in ipairs(bj.hands) do if (K.Total(x.cards)) == 21 then x.done = true end end
    bjNext()
    return bj
end

---------------------------------------------------------------------------
-- Hold'em against the house
---------------------------------------------------------------------------
local he

function G.Holdem() return he end

local function shuffled()
    local deck = {}
    for s = 1, 4 do for r = 2, 14 do deck[#deck + 1] = { r = r, s = s } end end
    for i = #deck, 2, -1 do
        local j = G.rng(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
    return deck
end

-- Ante up: two cards each and the flop. You need the chips to call as well.
function G.HEDeal(ante)
    if he and he.phase == "flop" then return nil, "Call or fold this hand first." end
    local ok, why = canStake((ante or 0) * 3)
    if not ok then return nil, (ante or 0) >= 1 and "You need three times the ante: the ante, and twice that to call." or why end
    local d = shuffled()
    he = { ante = ante, phase = "flop", player = { d[1], d[2] }, dealer = { d[3], d[4] }, board = { d[5], d[6], d[7] }, rest = { d[8], d[9] } }
    inPlay = ante
    return he
end

function G.HEFold()
    if not (he and he.phase == "flop") then return nil, "Deal a hand first." end
    he.phase, he.how, he.staked, he.back = "done", "fold", he.ante, 0
    inPlay = 0
    settle("Hold'em", he.ante, 0)
    return he
end

function G.HECall()
    if not (he and he.phase == "flop") then return nil, "Deal a hand first." end
    he.board[4], he.board[5] = he.rest[1], he.rest[2]
    local back, how, pc, ph, dc, dh = K.HoldemBack(he.player, he.dealer, he.board, he.ante)
    he.phase, he.how, he.staked, he.back = "done", how, he.ante * 3, back
    he.mine, he.theirs = K.HandName(pc, ph), K.HandName(dc, dh)
    inPlay = 0
    settle("Hold'em", he.staked, back)
    return he
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
    for i, name in ipairs({ "Roulette", "Slots", "Blackjack", "Hold'em" }) do
        local b = W.Button(f, name, 100, 22, function()
            game, note = name, nil
            G.Refresh()
        end)
        b:SetPoint("TOPLEFT", 12 + (i - 1) * 106, -40)
        f.tabs[name] = b
    end
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

    -- Blackjack and Hold'em share one layout: the dealer, you, a result line, buttons, the rules.
    local function table_(rules)
        local t = CreateFrame("Frame", nil, f)
        t:SetPoint("TOPLEFT", 12, -100)
        t:SetSize(536, 250)
        t.lines = {}
        for i = 1, 4 do
            local fs = W.Text(t, "", i == 4 and "GameFontNormalLarge" or "GameFontHighlightLarge")
            fs:SetPoint("TOPLEFT", 0, -(i - 1) * 28)
            fs:SetWidth(536)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            t.lines[i] = fs
        end
        t.rules = W.Text(t, rules, "GameFontDisableSmall")
        t.rules:SetPoint("TOPLEFT", 0, -156)
        t.rules:SetWidth(536)
        t.rules:SetJustifyH("LEFT")
        t.rules:SetWordWrap(true)
        t.buttons = {}
        return t
    end
    local function action(t, i, label, fn, style)
        local b = W.Button(t, label, 96, 26, function()
            local ok, why = fn()
            note = (not ok) and why or nil
            G.Refresh()
        end, style)
        b:SetPoint("TOPLEFT", (i - 1) * 102, -118)
        t.buttons[label] = b
        return b
    end
    local b = table_("Blackjack pays 6 to 5. The dealer hits a soft 17. Double on any two cards, and after a split. Split a pair once; split aces get one card each. House edge 2.14% against perfect play.")
    f.blackjack = b
    action(b, 1, "Deal", function() local st = stake(); if not st then return nil, note end; return G.BJDeal(st) end, "accent")
    action(b, 2, "Hit", G.BJHit)
    action(b, 3, "Stand", G.BJStand)
    action(b, 4, "Double", G.BJDouble)
    action(b, 5, "Split", G.BJSplit)
    local h = table_("Your stake is the ante. See your cards and the flop, then call for twice the ante or fold. The dealer needs a pair of fours to qualify. Ante pays: royal flush 100, straight flush 20, four of a kind 10, full house 3, flush 2, anything else 1. The call pays even money. House edge 2.16%.")
    f.holdem = h
    action(h, 1, "Deal", function() local st = stake(); if not st then return nil, note end; return G.HEDeal(st) end, "accent")
    action(h, 2, "Call", G.HECall)
    action(h, 3, "Fold", G.HEFold)

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
    f.blackjack:SetShown(game == "Blackjack")
    f.holdem:SetShown(game == "Hold'em")
    local function cards(list, hide)
        local out = {}
        for i, c in ipairs(list) do
            local red = c.s == 2 or c.s == 3
            out[i] = (hide and i > 1) and "??" or ((red and "|cffff5050" or "|cffffffff") .. K.Name(c) .. "|r")
        end
        return table.concat(out, "  ")
    end
    local function outcome(staked, back)
        local won = back - staked
        return won > 0 and ("|cff40ff40You won " .. Chips.Text(won) .. "|r") or won == 0 and "A push: your chips come back"
            or ("|cffff6040The house takes " .. Chips.Text(-won) .. "|r")
    end
    if game == "Blackjack" then
        local t, hand = f.blackjack, G.Blackjack()
        local playing = hand ~= nil and hand.phase == "play"
        if hand then
            t.lines[1]:SetText("Dealer: " .. cards(hand.dealer, playing) .. (playing and "" or ("   (" .. (K.Total(hand.dealer)) .. ")")))
            for i = 1, 2 do
                local x = hand.hands[i]
                t.lines[i + 1]:SetText(x and ((playing and hand.at == i and "> " or "") .. (#hand.hands > 1 and ("Hand " .. i .. ": ") or "You: ")
                    .. cards(x.cards) .. "   (" .. (K.Total(x.cards)) .. ")   " .. Chips.Text(x.bet)) or "")
            end
            t.lines[4]:SetText(playing and "Your move" or outcome(hand.staked, hand.back))
        else
            t.lines[1]:SetText("Dealer:")
            t.lines[2]:SetText("You:")
            t.lines[3]:SetText("")
            t.lines[4]:SetText("Set a stake and deal.")
        end
        t.buttons.Deal:SetEnabled(not playing)
        t.buttons.Hit:SetEnabled(playing)
        t.buttons.Stand:SetEnabled(playing)
        t.buttons.Double:SetEnabled(playing and G.BJCanDouble())
        t.buttons.Split:SetEnabled(playing and G.BJCanSplit())
    elseif game == "Hold'em" then
        local t, hand = f.holdem, G.Holdem()
        local playing = hand ~= nil and hand.phase == "flop"
        if hand then
            t.lines[1]:SetText("Dealer: " .. (playing and "??  ??" or cards(hand.dealer)) .. (hand.theirs and ("   " .. hand.theirs) or ""))
            t.lines[2]:SetText("Board: " .. cards(hand.board))
            t.lines[3]:SetText("You: " .. cards(hand.player) .. (hand.mine and ("   " .. hand.mine) or "") .. "   ante " .. Chips.Text(hand.ante))
            t.lines[4]:SetText(playing and ("Call for " .. Chips.Text(hand.ante * 2) .. " or fold")
                or hand.how == "fold" and ("|cffff6040You folded. The house takes " .. Chips.Text(hand.ante) .. "|r")
                or ((hand.how == "nofit" and "The dealer doesn't qualify. " or "") .. outcome(hand.staked, hand.back)))
        else
            t.lines[1]:SetText("Dealer:")
            t.lines[2]:SetText("Board:")
            t.lines[3]:SetText("You:")
            t.lines[4]:SetText("Set your ante as the stake and deal.")
        end
        t.buttons.Deal:SetEnabled(not playing)
        t.buttons.Call:SetEnabled(playing)
        t.buttons.Fold:SetEnabled(playing)
    elseif game == "Roulette" then
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
