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
-- The art. Every picture is the addon's own, drawn by tools/art.py: a sheet
-- of cards, the wheel and its ball, the reel symbols, the felt and a chip.
---------------------------------------------------------------------------
G.ART = "Interface\\AddOns\\BlindTiger\\Media\\"
G.ANIMATE = true          -- the tests turn this off to read results at once

-- The card sheet is 1024 x 512: one row per suit, deuce to ace, 72 x 102 each.
-- The card back sits after the ace of spades. -> left, right, top, bottom
function G.CardCoords(card)
    local col, row = 13, 0
    if card then col, row = card.r - 2, card.s - 1 end
    return col * 72 / 1024, (col + 1) * 72 / 1024, row * 102 / 512, (row + 1) * 102 / 512
end

-- The reel sheet is 512 x 256: the symbols in G.REEL order, four to a row, 128 square.
function G.SymbolCoords(name)
    for i, s in ipairs(G.REEL) do
        if s[1] == name then
            local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
            return col / 4, (col + 1) / 4, row / 2, (row + 1) / 2
        end
    end
end

-- The American wheel, clockwise from the single zero, as the picture is drawn.
G.WHEEL = { "0", "28", "9", "26", "30", "11", "7", "20", "32", "17", "5", "22", "34", "15", "3", "24", "36", "13", "1",
    "00", "27", "10", "25", "29", "12", "8", "19", "31", "18", "6", "21", "33", "16", "4", "23", "35", "14", "2" }

-- Where a pocket sits on the wheel: radians clockwise from the top.
function G.WheelAngle(pocket)
    for i, name in ipairs(G.WHEEL) do
        if name == pocket then return (i - 1) * 2 * math.pi / #G.WHEEL end
    end
end

-- Chips with a chip picture for each kind: gold, silver, copper.
local CHIP_TINT = { "255:209:0", "200:200:210", "205:127:60" }
function G.ChipIcons(copper)
    local parts = {}
    local units = { math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100 }
    for i, n in ipairs(units) do
        if n > 0 or (i == 3 and #parts == 0) then
            parts[#parts + 1] = ("%d|T%schip:13:13:0:0:64:64:0:64:0:64:%s|t"):format(n, G.ART, CHIP_TINT[i])
        end
    end
    return table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local W = ns.W
local game = "Roulette"
local bets, lastSpin, lastPull, note = {}, nil, nil, nil
local COLOR = { red = "|cffff4040", black = "|cffd0d0d0", green = "|cff40d060" }

local CARD_W, CARD_H, SPOT_W = 44, 62, 250
local WHEEL_SIZE, WHEEL_TIME, WHEEL_TURNS, BALL_TURNS = 212, 3.2, 3, 5
local REEL_STOP = { 0.7, 1.1, 1.5 }       -- seconds until each reel stops
local FADE = 0.18                         -- seconds for a dealt card to appear

-- What is moving right now. The result is already settled when this starts:
-- the pictures only show it. { kind = "wheel", pocket } or { kind = "reels", reels }
local anim
local fading = {}

local function felt(panel, height)
    local t = panel:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(G.ART .. "felt")
    t:SetPoint("TOPLEFT", 0, 0)
    t:SetSize(536, height)
    return t
end

local function fadeIn(c, wait)
    c.a, c.wait = 0, wait
    c:SetAlpha(0)
    if not c.inFade then
        c.inFade = true
        fading[#fading + 1] = c
    end
end

-- A place on the table for a row of cards under a label.
local function spot(t, x, y)
    local sp = { cards = {}, x = x, y = y }
    sp.label = W.Text(t, "", "GameFontHighlightSmall")
    sp.label:SetPoint("TOPLEFT", x, y)
    sp.label:SetWidth(SPOT_W)
    sp.label:SetJustifyH("LEFT")
    sp.label:SetWordWrap(false)
    for i = 1, 11 do
        local c = t:CreateTexture(nil, "ARTWORK", nil, i - 5)
        c:SetTexture(G.ART .. "cards")
        c:SetSize(CARD_W, CARD_H)
        c:Hide()
        sp.cards[i] = c
    end
    return sp
end

-- Lay cards on a spot. An entry of "back" is a card face down. Long hands overlap to fit.
-- A new hand clears the spot first, so every card of it is dealt in.
local function lay(sp, list, hand)
    if sp.hand ~= hand then
        sp.hand = hand
        for _, c in ipairs(sp.cards) do c.key = nil end
    end
    local n = #list
    local gap = n > 1 and math.min(CARD_W + 4, (SPOT_W - CARD_W) / (n - 1)) or 0
    local fresh = 0
    for i, c in ipairs(sp.cards) do
        local card = list[i]
        if card then
            local down = card == "back"
            local key = down and "back" or K.Name(card)
            c:SetTexCoord(G.CardCoords((not down) and card or nil))
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", sp.x + (i - 1) * gap, sp.y - 14)
            if c.key ~= key then
                if G.ANIMATE and c.key == nil then
                    fadeIn(c, fresh * 0.12)
                    fresh = fresh + 1
                else
                    c.a = 1
                    c:SetAlpha(1)
                end
                c.key = key
            end
            c:Show()
        else
            c.key = nil
            c:Hide()
        end
    end
end

local function setSymbol(tex, name)
    if name then
        tex:SetTexCoord(G.SymbolCoords(name))
        tex:Show()
    else
        tex:Hide()
    end
    tex.sym = name
end

-- Put the wheel and ball where they are p of the way (0..1) through a spin
-- that ends on this pocket. The wheel always comes to rest the way it is drawn,
-- so the ball's last place is the pocket's own place on the picture.
local function placeWheel(r, pocket, p)
    local left = (1 - p) ^ 3
    r.wheel:SetRotation(left * WHEEL_TURNS * 2 * math.pi)
    local angle = G.WheelAngle(pocket) - left * BALL_TURNS * 2 * math.pi
    local drop = math.max(0, math.min(1, (p - 0.5) / 0.5))
    drop = drop * drop * (3 - 2 * drop)
    local radius = (0.88 - 0.34 * drop) * WHEEL_SIZE / 2
    r.ball:ClearAllPoints()
    r.ball:SetPoint("CENTER", r.wheel, "CENTER", radius * math.sin(angle), radius * math.cos(angle))
    r.ball:Show()
end

local function stopMoving()
    if not anim then return end
    local f = G.frame
    if anim.kind == "wheel" then
        placeWheel(f.roulette, anim.pocket, 1)
    else
        for i = 1, 3 do setSymbol(f.slots.reels[i], anim.reels[i]) end
    end
    anim = nil
end

function G.Moving() return anim ~= nil end

-- Move the pictures on by dt seconds. The window calls this every frame.
function G.Tick(dt)
    local f = G.frame
    if not f then return end
    for i = #fading, 1, -1 do
        local c = fading[i]
        c.wait = c.wait - dt
        if c.wait <= 0 then
            c.a = math.min(1, c.a + dt / FADE)
            c:SetAlpha(c.a)
            if c.a >= 1 then
                c.inFade = nil
                table.remove(fading, i)
            end
        end
    end
    if not anim then return end
    anim.t = anim.t + dt
    if anim.kind == "wheel" then
        if anim.t >= WHEEL_TIME then
            stopMoving()
            G.Refresh()
        else
            placeWheel(f.roulette, anim.pocket, anim.t / WHEEL_TIME)
        end
    else
        anim.flick = anim.flick + dt
        local roll = anim.flick >= 0.06
        if roll then anim.flick = 0 end
        for i = 1, 3 do
            if anim.t >= REEL_STOP[i] then
                setSymbol(f.slots.reels[i], anim.reels[i])
            elseif roll then
                setSymbol(f.slots.reels[i], G.REEL[math.random(#G.REEL)][1])      -- only the blur; the result is set
            end
        end
        if anim.t >= REEL_STOP[3] then
            stopMoving()
            G.Refresh()
        end
    end
end

local function build()
    local f = CreateFrame("Frame", "BlindTigerFloor", UIParent)
    f:SetSize(560, 480)
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
    W.Title(f, "The Blind Tiger Casino")
    W.Button(f, "X", 22, 20, function() f:Hide() end):SetPoint("TOPRIGHT", -6, -6)
    f.chips = W.Text(f, "", "GameFontHighlightSmall")
    f.chips:SetPoint("TOPRIGHT", -36, -11)
    f.chips:SetWidth(330)
    f.chips:SetJustifyH("RIGHT")
    f.chips:SetWordWrap(false)
    W.Line(f, -32)

    f.tabs = {}
    for i, name in ipairs({ "Roulette", "Slots", "Blackjack", "Hold'em", "Chips" }) do
        local b = W.Button(f, name, 100, 22, function()
            stopMoving()
            game, note = name, nil
            if name == "Chips" then Chips.Opened() end
            G.Refresh()
        end)
        b:SetPoint("TOPLEFT", 12 + (i - 1) * 106, -40)
        f.tabs[name] = b
    end
    f.stakeLabel = W.Text(f, "Stake", "GameFontHighlightSmall")
    f.stakeLabel:SetPoint("TOPLEFT", 12, -76)
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

    -- Roulette: the bets on the left, the wheel on the right.
    local r = CreateFrame("Frame", nil, f)
    r:SetPoint("TOPLEFT", 12, -100)
    r:SetSize(536, 290)
    f.roulette = r
    felt(r, 220)
    r.wheel = r:CreateTexture(nil, "ARTWORK")
    r.wheel:SetTexture(G.ART .. "wheel")
    r.wheel:SetSize(WHEEL_SIZE, WHEEL_SIZE)
    r.wheel:SetPoint("TOPLEFT", 320, -4)
    r.ball = r:CreateTexture(nil, "OVERLAY")
    r.ball:SetTexture(G.ART .. "ball")
    r.ball:SetSize(13, 13)
    r.ball:Hide()
    r.result = W.Text(r, "", "GameFontNormalLarge")
    r.result:SetPoint("TOPLEFT", 8, -8)
    r.result:SetWidth(308)
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
    r.betButtons = {}
    for i, o in ipairs(outside) do
        local b = W.Button(r, G.BetLabel({ kind = o[1], pick = o[2] }), 74, 22, function() add(o[1], o[2]) end)
        b:SetPoint("TOPLEFT", 8 + ((i - 1) % 4) * 78, -34 - math.floor((i - 1) / 4) * 26)
        r.betButtons[#r.betButtons + 1] = b
    end
    W.Text(r, "Number (0, 00, 1-36)", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 8, -120)
    r.num = W.Edit(r, 36, 2)
    r.num:SetPoint("TOPLEFT", 134, -116)
    r.betButtons[#r.betButtons + 1] = W.Button(r, "Bet the number", 110, 22, function()
        local p = G.Pocket(r.num:GetText())
        if p then add("num", p) else note = "Type 0, 00 or a number from 1 to 36."; G.Refresh() end
    end)
    r.betButtons[#r.betButtons]:SetPoint("TOPLEFT", 180, -116)
    r.bets = W.Text(r, "", "GameFontHighlightSmall")
    r.bets:SetPoint("TOPLEFT", 8, -146)
    r.bets:SetWidth(306)
    r.bets:SetHeight(36)
    r.bets:SetJustifyH("LEFT")
    r.bets:SetJustifyV("TOP")
    r.bets:SetWordWrap(true)
    r.spin = W.Button(r, "Spin", 120, 26, function()
        local res, why = G.Spin(bets)
        if res then
            lastSpin, note = res, nil
            if G.ANIMATE then anim = { kind = "wheel", t = 0, pocket = res.pocket } end
        else
            note = why
        end
        G.Refresh()
    end, "accent")
    r.spin:SetPoint("TOPLEFT", 8, -188)
    r.clear = W.Button(r, "Clear bets", 100, 26, function() bets, note = {}, nil; G.Refresh() end)
    r.clear:SetPoint("TOPLEFT", 136, -188)
    r.rules = W.Text(r, "American wheel: 0 and 00. A number pays 35 to 1, a dozen or column 2 to 1, the rest even money. House edge 5.26%.", "GameFontDisableSmall")
    r.rules:SetPoint("TOPLEFT", 0, -228)
    r.rules:SetWidth(536)
    r.rules:SetJustifyH("LEFT")

    -- Slots: three reels on the felt, the pay table in pictures below.
    local s = CreateFrame("Frame", nil, f)
    s:SetPoint("TOPLEFT", 12, -100)
    s:SetSize(536, 290)
    f.slots = s
    felt(s, 152)
    s.reels = {}
    for i = 1, 3 do
        local box = CreateFrame("Frame", nil, s)
        box:SetSize(104, 104)
        box:SetPoint("TOPLEFT", 92 + (i - 1) * 124, -10)
        W.Glass(box, true)
        local tex = box:CreateTexture(nil, "ARTWORK")
        tex:SetTexture(G.ART .. "reels")
        tex:SetSize(88, 88)
        tex:SetPoint("CENTER", 0, 0)
        tex:Hide()
        s.reels[i] = tex
    end
    s.result = W.Text(s, "", "GameFontNormalLarge")
    s.result:SetPoint("TOPLEFT", 8, -124)
    s.result:SetWidth(520)
    s.result:SetJustifyH("CENTER")
    s.result:SetWordWrap(false)
    s.pull = W.Button(s, "Pull", 120, 26, function()
        local st = stake()
        if st then
            local res, why = G.Pull(st)
            if res then
                lastPull, note = res, nil
                if G.ANIMATE then anim = { kind = "reels", t = 0, flick = 1, reels = res.reels } end
            else
                note = why
            end
        end
        G.Refresh()
    end, "accent")
    s.pull:SetPoint("TOPLEFT", 208, -160)
    for i, sym in ipairs(G.REEL) do
        local icon = s:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(G.ART .. "reels")
        icon:SetTexCoord(G.SymbolCoords(sym[1]))
        icon:SetSize(24, 24)
        icon:SetPoint("TOPLEFT", 4 + (i - 1) * 89, -198)
        W.Text(s, "x3 = " .. G.SLOT_PAYS[sym[1]], "GameFontHighlightSmall"):SetPoint("TOPLEFT", 32 + (i - 1) * 89, -204)
    end
    s.table = W.Text(s, ("Three of a kind pays what is shown, in stakes: 9 means a 1s stake comes back as 9s. Two Cherries pay %d. House edge 7.34%%."):format(G.TWO_CHERRIES), "GameFontDisableSmall")
    s.table:SetPoint("TOPLEFT", 0, -232)
    s.table:SetWidth(536)
    s.table:SetJustifyH("LEFT")
    s.table:SetWordWrap(true)

    -- Blackjack and Hold'em share one table: three spots for cards on the felt,
    -- a result line, the buttons, the rules.
    local function table_(rules, places)
        local t = CreateFrame("Frame", nil, f)
        t:SetPoint("TOPLEFT", 12, -100)
        t:SetSize(536, 290)
        felt(t, 166)
        t.spots = {}
        for i, at in ipairs(places) do t.spots[i] = spot(t, at[1], at[2]) end
        t.result = W.Text(t, "", "GameFontNormalLarge")
        t.result:SetPoint("TOPLEFT", 0, -172)
        t.result:SetWidth(536)
        t.result:SetJustifyH("LEFT")
        t.result:SetWordWrap(false)
        t.rules = W.Text(t, rules, "GameFontDisableSmall")
        t.rules:SetPoint("TOPLEFT", 0, -232)
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
        b:SetPoint("TOPLEFT", (i - 1) * 102, -198)
        t.buttons[label] = b
        return b
    end
    local TOP, LOW = -6, -86
    -- Blackjack: the dealer on top, your hand below, a split hand beside it.
    local b = table_("Blackjack pays 6 to 5. The dealer hits a soft 17. Double on any two cards, and after a split. Split a pair once; split aces get one card each. House edge 2.14% against perfect play.",
        { { 12, TOP }, { 12, LOW }, { 276, LOW } })
    f.blackjack = b
    action(b, 1, "Deal", function() local st = stake(); if not st then return nil, note end; return G.BJDeal(st) end, "accent")
    action(b, 2, "Hit", G.BJHit)
    action(b, 3, "Stand", G.BJStand)
    action(b, 4, "Double", G.BJDouble)
    action(b, 5, "Split", G.BJSplit)
    -- Hold'em: the dealer and the board on top, your cards below.
    local h = table_("Your stake is the ante. See your cards and the flop, then call for twice the ante or fold. The dealer needs a pair of fours to qualify. Ante pays: royal flush 100, straight flush 20, four of a kind 10, full house 3, flush 2, anything else 1. The call pays even money. House edge 2.16%.",
        { { 12, TOP }, { 276, TOP }, { 12, LOW } })
    f.holdem = h
    action(h, 1, "Deal", function() local st = stake(); if not st then return nil, note end; return G.HEDeal(st) end, "accent")
    action(h, 2, "Call", G.HECall)
    action(h, 3, "Fold", G.HEFold)

    -- Chips: your count, donating at the guild bank, and the leaderboard.
    f.chipsPage = Chips.BuildPanel(f)
    f.chipsPage:SetPoint("TOPLEFT", 12, -72)

    f.status = W.Text(f, "", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", 12, -398)
    f.status:SetWidth(536)
    f.status:SetJustifyH("LEFT")
    f.status:SetWordWrap(false)
    f.feed = W.Text(f, "", "GameFontDisableSmall")
    f.feed:SetPoint("TOPLEFT", 12, -418)
    f.feed:SetWidth(536)
    f.feed:SetJustifyH("LEFT")
    f.feed:SetJustifyV("TOP")
    f.feed:SetWordWrap(true)
    f:SetScript("OnUpdate", function(_, dt) G.Tick(dt) end)
    f:SetScript("OnHide", function() stopMoving(); G.Commit() end)
    f:Hide()
    G.frame = f
    return f
end

function G.Refresh()
    local f = G.frame
    if not (f and f:IsShown()) then return end
    -- While the wheel or the reels are moving, nothing on screen gives the result away.
    if not anim then
        local _, house = G.Nets(Red.State())
        f.chips:SetText(("Your chips: |cffffd100%s|r    The house is %s %s"):format(G.ChipIcons(G.Available()),
            house >= 0 and "up" or "down", Chips.Text(math.abs(house))))
        local lines = G.Feed()
        f.feed:SetText(#lines > 0 and ("On the floor: " .. table.concat(lines, "  ")) or "Big wins by guildmates show here.")
    end
    for name, b in pairs(f.tabs) do b:SetEnabled(name ~= game) end
    f.roulette:SetShown(game == "Roulette")
    f.slots:SetShown(game == "Slots")
    f.blackjack:SetShown(game == "Blackjack")
    f.holdem:SetShown(game == "Hold'em")
    local chipsTab = game == "Chips"
    f.chipsPage:SetShown(chipsTab)
    f.stakeLabel:SetShown(not chipsTab)
    f.stake:SetShown(not chipsTab)
    f.stakeHint:SetShown(not chipsTab)
    f.status:SetShown(not chipsTab)
    if chipsTab then
        Chips.Refresh()
        return
    end
    local function outcome(staked, back)
        local won = back - staked
        return won > 0 and ("|cff40ff40You won " .. Chips.Text(won) .. "|r") or won == 0 and "A push: your chips come back"
            or ("|cffff6040The house takes " .. Chips.Text(-won) .. "|r")
    end
    if game == "Blackjack" then
        local t, hand = f.blackjack, G.Blackjack()
        local playing = hand ~= nil and hand.phase == "play"
        local dealer, first, second = t.spots[1], t.spots[2], t.spots[3]
        if hand then
            dealer.label:SetText(playing and "Dealer" or ("Dealer  (" .. (K.Total(hand.dealer)) .. ")"))
            lay(dealer, playing and { hand.dealer[1], "back" } or hand.dealer, hand)
            for i, sp in ipairs({ first, second }) do
                local x = hand.hands[i]
                sp.label:SetText(x and ((playing and hand.at == i and "|cffffd100>|r " or "") .. (#hand.hands > 1 and ("Hand " .. i) or "You")
                    .. "  (" .. (K.Total(x.cards)) .. ")   " .. Chips.Text(x.bet)) or "")
                lay(sp, x and x.cards or {}, hand)
            end
            t.result:SetText(playing and "Your move" or outcome(hand.staked, hand.back))
        else
            dealer.label:SetText("Dealer")
            first.label:SetText("You")
            second.label:SetText("")
            for _, sp in ipairs(t.spots) do lay(sp, {}) end
            t.result:SetText("Set a stake and deal.")
        end
        t.buttons.Deal:SetEnabled(not playing)
        t.buttons.Hit:SetEnabled(playing)
        t.buttons.Stand:SetEnabled(playing)
        t.buttons.Double:SetEnabled(playing and G.BJCanDouble())
        t.buttons.Split:SetEnabled(playing and G.BJCanSplit())
    elseif game == "Hold'em" then
        local t, hand = f.holdem, G.Holdem()
        local playing = hand ~= nil and hand.phase == "flop"
        local dealer, board, you = t.spots[1], t.spots[2], t.spots[3]
        if hand then
            dealer.label:SetText("Dealer" .. (hand.theirs and (": " .. hand.theirs) or ""))
            lay(dealer, playing and { "back", "back" } or hand.dealer, hand)
            board.label:SetText("Board")
            lay(board, hand.board, hand)
            you.label:SetText("You" .. (hand.mine and (": " .. hand.mine) or "") .. "   ante " .. Chips.Text(hand.ante))
            lay(you, hand.player, hand)
            t.result:SetText(playing and ("Call for " .. Chips.Text(hand.ante * 2) .. " or fold")
                or hand.how == "fold" and ("|cffff6040You folded. The house takes " .. Chips.Text(hand.ante) .. "|r")
                or ((hand.how == "nofit" and "The dealer doesn't qualify. " or "") .. outcome(hand.staked, hand.back)))
        else
            dealer.label:SetText("Dealer")
            board.label:SetText("Board")
            you.label:SetText("You")
            for _, sp in ipairs(t.spots) do lay(sp, {}) end
            t.result:SetText("Set your ante as the stake and deal.")
        end
        t.buttons.Deal:SetEnabled(not playing)
        t.buttons.Call:SetEnabled(playing)
        t.buttons.Fold:SetEnabled(playing)
    elseif game == "Roulette" then
        local r = f.roulette
        local spinning = anim ~= nil
        if spinning then
            r.result:SetText("No more bets...")
        elseif lastSpin then
            local won = lastSpin.back - lastSpin.staked
            r.result:SetText(("%s%s|r   %s"):format(COLOR[G.PocketColor(lastSpin.pocket)], lastSpin.pocket,
                won > 0 and ("|cff40ff40You won " .. Chips.Text(won) .. "|r") or won == 0 and "You broke even"
                or ("|cffff6040The house takes " .. Chips.Text(-won) .. "|r")))
            placeWheel(r, lastSpin.pocket, 1)
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
        r.spin:SetEnabled(#bets > 0 and not spinning)
        r.clear:SetEnabled(not spinning)
        for _, b in ipairs(r.betButtons) do b:SetEnabled(not spinning) end
    else
        local s = f.slots
        local rolling = anim ~= nil
        if rolling then
            s.result:SetText("Rolling...")
        else
            for i = 1, 3 do setSymbol(s.reels[i], lastPull and lastPull.reels[i]) end
            if lastPull then
                local won = lastPull.back - lastPull.staked
                s.result:SetText(won > 0 and ("|cff40ff40You won " .. Chips.Text(won) .. "|r") or ("|cffff6040The house takes " .. Chips.Text(-won) .. "|r"))
            else
                s.result:SetText("Set a stake and pull.")
            end
        end
        s.pull:SetEnabled(not rolling)
    end
    f.status:SetText(note and ("|cffffd100" .. note .. "|r") or "Chips are play chips: they never turn back into gold. The house is the guild.")
end

-- Open or close the Casino. With a page name ("Chips", "Slots"...) it opens on that page.
function G.Toggle(page)
    local f = G.frame or build()
    if f:IsShown() and (page == nil or page == game) then f:Hide() return end
    if page and f.tabs[page] then game = page end
    note = nil
    f:Show()
    Chips.Opened()        -- at the guild bank, opening the Casino reads the money log
    G.Refresh()
end

ns.Listen("LOG_CHANGED", function() G.Refresh() end)
