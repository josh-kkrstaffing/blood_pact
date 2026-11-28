-- Blind Tiger: the card rules for the games floor. No game state here, only
-- what the cards mean: blackjack totals and payouts, and poker hand ranks
-- for Hold'em against the house.
local _, ns = ...
local K = {}
ns.Cards = K

K.RANKS = { [11] = "J", [12] = "Q", [13] = "K", [14] = "A" }
K.SUITS = { "s", "h", "d", "c" }

-- A card is { r = 2..14 (14 = ace), s = 1..4 }.
function K.Name(card)
    return (K.RANKS[card.r] or tostring(card.r)) .. K.SUITS[card.s]
end

---------------------------------------------------------------------------
-- Blackjack. Blackjack pays 6 to 5, the dealer hits a soft 17, you can
-- double on any two cards and after a split, and split a pair once. Each
-- card is dealt fresh, so every rank is always equally likely. Played
-- perfectly this gives the house 2.14%.
---------------------------------------------------------------------------
K.BJ_PAYS = { 6, 5 }      -- blackjack pays 6 for every 5 staked

function K.Total(cards)
    local total, aces = 0, 0
    for _, c in ipairs(cards) do
        if c.r == 14 then total, aces = total + 11, aces + 1
        elseif c.r >= 10 then total = total + 10
        else total = total + c.r end
    end
    while total > 21 and aces > 0 do total, aces = total - 10, aces - 1 end
    return total, aces > 0          -- total, and whether an ace still counts as 11 (a "soft" hand)
end

function K.IsNatural(cards)
    return #cards == 2 and (K.Total(cards)) == 21
end

-- Does the dealer take another card? Stands on hard 17 and up, hits a soft 17.
function K.DealerHits(cards)
    local total, soft = K.Total(cards)
    return total < 17 or (total == 17 and soft)
end

function K.CanSplit(cards)
    if #cards ~= 2 then return false end
    local a, b = cards[1].r, cards[2].r
    return a == b or (a >= 10 and a <= 13 and b >= 10 and b <= 13)
end

-- What one finished hand gets back, in chips. hand = { cards, bet, split }.
-- A 21 made after a split is not a blackjack.
function K.BJBack(hand, dealer)
    local total = K.Total(hand.cards)
    local dTotal = K.Total(dealer)
    local natural = K.IsNatural(hand.cards) and not hand.split
    local dNatural = K.IsNatural(dealer)
    if total > 21 then return 0 end
    if natural then
        if dNatural then return hand.bet end
        return hand.bet + math.floor(hand.bet * K.BJ_PAYS[1] / K.BJ_PAYS[2])
    end
    if dNatural then return 0 end
    if dTotal > 21 or total > dTotal then return hand.bet * 2 end
    if total == dTotal then return hand.bet end
    return 0
end

---------------------------------------------------------------------------
-- Poker hands. Best five of up to seven cards -> a number; bigger wins.
---------------------------------------------------------------------------
K.HANDS = { [0] = "high card", "a pair", "two pair", "three of a kind", "a straight", "a flush", "a full house",
    "four of a kind", "a straight flush" }

local function straightHigh(has)       -- has[rank] = true; the top card of the best straight, or nil
    for high = 14, 5, -1 do
        local ok = true
        for r = high, high - 4, -1 do
            if not has[r == 1 and 14 or r] then ok = false; break end
        end
        if ok then return high end
    end
    return nil
end

local function score(cat, a, b, c, d, e)
    return ((((cat * 15 + (a or 0)) * 15 + (b or 0)) * 15 + (c or 0)) * 15 + (d or 0)) * 15 + (e or 0)
end

function K.Rank(cards)
    local count, bySuit, has = {}, { {}, {}, {}, {} }, {}
    for _, c in ipairs(cards) do
        count[c.r] = (count[c.r] or 0) + 1
        has[c.r] = true
        bySuit[c.s][c.r] = true
    end
    -- Straight flush and flush
    local flush
    for s = 1, 4 do
        local n = 0
        for _ in pairs(bySuit[s]) do n = n + 1 end
        if n >= 5 then flush = bySuit[s] end
    end
    if flush then
        local high = straightHigh(flush)
        if high then return score(8, high), 8, high end
    end
    local quads, trips, pairsOf, singles = {}, {}, {}, {}
    for r = 14, 2, -1 do
        local n = count[r]
        if n == 4 then quads[#quads + 1] = r
        elseif n == 3 then trips[#trips + 1] = r
        elseif n == 2 then pairsOf[#pairsOf + 1] = r
        elseif n == 1 then singles[#singles + 1] = r end
    end
    local function kickers(skip, n)
        local out = {}
        for r = 14, 2, -1 do
            if count[r] and not skip[r] then
                out[#out + 1] = r
                if #out == n then break end
            end
        end
        return out
    end
    if quads[1] then
        local k = kickers({ [quads[1]] = true }, 1)
        return score(7, quads[1], k[1]), 7, quads[1]
    end
    if trips[1] and (trips[2] or pairsOf[1]) then
        local second = math.max(trips[2] or 0, pairsOf[1] or 0)
        return score(6, trips[1], second), 6, trips[1]
    end
    if flush then
        local top = {}
        for r = 14, 2, -1 do
            if flush[r] then top[#top + 1] = r end
            if #top == 5 then break end
        end
        return score(5, top[1], top[2], top[3], top[4], top[5]), 5, top[1]
    end
    local sHigh = straightHigh(has)
    if sHigh then return score(4, sHigh), 4, sHigh end
    if trips[1] then
        local k = kickers({ [trips[1]] = true }, 2)
        return score(3, trips[1], k[1], k[2]), 3, trips[1]
    end
    if pairsOf[2] then
        local k = kickers({ [pairsOf[1]] = true, [pairsOf[2]] = true }, 1)
        return score(2, pairsOf[1], pairsOf[2], k[1]), 2, pairsOf[1]
    end
    if pairsOf[1] then
        local k = kickers({ [pairsOf[1]] = true }, 3)
        return score(1, pairsOf[1], k[1], k[2], k[3]), 1, pairsOf[1]
    end
    return score(0, singles[1], singles[2], singles[3], singles[4], singles[5]), 0, singles[1]
end

function K.HandName(cat, high)
    if cat == 8 and high == 14 then return "a royal flush" end
    return K.HANDS[cat]
end

---------------------------------------------------------------------------
-- Hold'em against the house (the casino game). You ante, see your two cards
-- and the flop, then fold or call for twice the ante. The dealer needs a
-- pair of fours or better to qualify. The ante pays by the table below; the
-- call pays even money. Published house edge for these rules: 2.16%.
---------------------------------------------------------------------------
K.ANTE_PAYS = { [8] = 20, [7] = 10, [6] = 3, [5] = 2 }      -- everything else pays 1 to 1
K.ROYAL_PAYS = 100

function K.AntePays(cat, high)
    if cat == 8 and high == 14 then return K.ROYAL_PAYS end
    return K.ANTE_PAYS[cat] or 1
end

function K.DealerQualifies(cat, high)
    return cat >= 2 or (cat == 1 and high >= 4)
end

-- A called hand at showdown: -> chips back (of ante + 2 x ante staked), and what happened.
function K.HoldemBack(player, dealer, board, ante)
    local p, d = {}, {}
    for _, c in ipairs(player) do p[#p + 1] = c end
    for _, c in ipairs(dealer) do d[#d + 1] = c end
    for _, c in ipairs(board) do p[#p + 1] = c; d[#d + 1] = c end
    local ps, pc, ph = K.Rank(p)
    local ds, dc, dh = K.Rank(d)
    local call = ante * 2
    if not K.DealerQualifies(dc, dh) then
        return ante + ante * K.AntePays(pc, ph) + call, "nofit", pc, ph, dc, dh
    end
    if ps > ds then return ante + ante * K.AntePays(pc, ph) + call * 2, "win", pc, ph, dc, dh end
    if ps == ds then return ante + call, "tie", pc, ph, dc, dh end
    return 0, "lose", pc, ph, dc, dh
end
