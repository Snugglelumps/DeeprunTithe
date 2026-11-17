-- Deeprun Tithe: last week's winners, as a stock ticker along the bottom of the leaderboard page
-- Entries scroll right to left through a dark band: last week's top 3, with made-up stocks
-- between them. Each time the page opens, the tape starts over:
--   first  stock, stock, 1st, stock, 2nd, stock, 3rd
--   then   5 or 6 stocks, a winner, and again. Never the same winner twice in a row.
-- An entry that scrolls off the left becomes the next one on the right.
--
-- The winners come from the answering ledger in WIN, at the front of every board.
-- Stock prices aren't saved or sent. Each one is its base price, times the day's multiplier,
-- moved a few percent by its ticker and the current 2 hours. So everyone sees the same market,
-- it moves every 2 hours, and the whole market jumps each day.
--
-- Saved for the account (see DeeprunTithe.toc):
--   tithe_last_week  { week_start = <0 until a ledger sends it>, players = { { name = ..., week_gold = copper }, ... } }

local addon_name, shared = ...

-- Settings
local scroll_pixels_per_second = 40
local ticker_refresh_seconds = 2 * 60 * 60
local fewest_stocks_between_winners = 5
local most_stocks_between_winners = 6
local gap_between_entries = 32

-- How much of the page's bottom the ticker takes. The leaderboard's list stops above it.
shared.winners_ticker_height = 80

local stocks = {
    { ticker = "DRT",  name = "Deeprun Trading", base_price = 23.10 },
    { ticker = "RHT",  name = "Reheat-O-Matic",  base_price = 14.80 },
    { ticker = "MRGL", name = "Mrrgl Lynch",     base_price = 88.00 },
    { ticker = "KBLD", name = "Kobold Candle",   base_price = 0.03 },
    { ticker = "MMR",  name = "Muscle Mathers",  base_price = 1.12 },
    { ticker = "GRYF", name = "Gryphon Leasing", base_price = 61.50 },
    { ticker = "PIGW", name = "Pig & Whistle",   base_price = 9.75 },
    { ticker = "STMW", name = "Steamwheedle",    base_price = 412.00 },
    { ticker = "VNTR", name = "Venture Co.",     base_price = 33.33 },
    { ticker = "GNOM", name = "Gnomeregan Fund", base_price = 2.50 },
    { ticker = "TRAM", name = "Tram Authority",  base_price = 45.00 },
    { ticker = "FORM", name = "Dept. of Forms",  base_price = 27.00 },
}

-- First, second and third: a coin, a colour, a size and the points it earned
local place_coins = {
    "Interface\\MoneyFrame\\UI-GoldIcon",
    "Interface\\MoneyFrame\\UI-SilverIcon",
    "Interface\\MoneyFrame\\UI-CopperIcon",
}
local place_colors = {
    { 1, 0.82, 0 },
    { 0.82, 0.88, 1 },
    { 0.85, 0.55, 0.3 },
}
local place_fonts = { "GameFontNormalHuge", "GameFontNormalLarge", "GameFontNormal" }
local place_coin_sizes = { 20, 16, 13 }
local place_points = { "+3 points", "+2 points", "+1 point" }

local header_week = nil
local band = nil
local tape = {}                 -- the entries on the band now, left to right
local spare_stock_entries = {}
local spare_winner_entries = {}
local coming_up = {}            -- what the next entries are: "stock" or a winner's number
local last_winner = nil
local last_stock = nil


------------------------------------------------------------
-- The fake market
------------------------------------------------------------

-- The whole market's mood for the day, from 0.001 to 1. A whole-number hash of the date,
-- read as if its last 3 digits were decimals, and those decimals taken from 1:
-- a hash of 48213 is 48.213, so the day's multiplier is 1 - 0.213 = 0.787.
-- By UTC, so everyone's day turns over at the same moment.
local function day_multiplier()
    local today = date("!%d/%m/%Y", GetServerTime())
    local hash = 0

    for character_number = 1, #today do
        hash = (hash * 31 + string.byte(today, character_number)) % 1000003
    end

    -- Dates a day apart only differ in one digit, so the hash steps by the same amount each day.
    -- Squaring it scrambles that, or the market would just climb and wrap around.
    hash = (hash * hash) % 1000003

    return 1 - (hash % 1000) / 1000
end


-- Between -5% and +5%, the same for everyone during each 2 hours
local function stock_change(stock)
    local hash = math.floor(GetServerTime() / ticker_refresh_seconds)

    for character_number = 1, #stock.ticker do
        hash = (hash * 31 + string.byte(stock.ticker, character_number)) % 1000003
    end

    return (hash % 1001) / 10000 - 0.05
end


------------------------------------------------------------
-- Entries
------------------------------------------------------------

-- 1 plus how many paid more, so tied players get the same place
local function place_of(players, week_gold)
    local place = 1

    for _, player in ipairs(players) do
        if player.week_gold > week_gold then
            place = place + 1
        end
    end

    return place
end


-- Hovering a winner: the exact amount and the points the week gave them
local function show_winner_tooltip(entry)
    GameTooltip:SetOwner(entry, "ANCHOR_TOP")
    GameTooltip:SetText(Ambiguate(entry.player.name, "guild"))
    GameTooltip:AddLine(GetMoneyString(entry.player.week_gold), 1, 1, 1)
    GameTooltip:AddLine(place_points[entry.place], 1, 0.82, 0)
    GameTooltip:Show()
end


-- NAME  TICKER  price, then a green up or red down arrow
local function make_stock_entry()
    local entry = CreateFrame("Frame", nil, band)
    entry:SetHeight(band:GetHeight())
    entry.kind = "stock"

    entry.name = entry:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    entry.name:SetPoint("LEFT", entry, "LEFT", 0, 0)
    entry.name:SetTextColor(0.85, 0.72, 0.4)

    entry.ticker = entry:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    entry.ticker:SetPoint("LEFT", entry.name, "RIGHT", 6, 0)

    entry.price = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    entry.price:SetPoint("LEFT", entry.ticker, "RIGHT", 6, 0)

    entry.arrow = entry:CreateTexture(nil, "OVERLAY")
    entry.arrow:SetSize(14, 14)
    entry.arrow:SetPoint("LEFT", entry.price, "RIGHT", 1, 0)

    return entry
end


local function fill_stock_entry(entry, stock)
    local change = stock_change(stock)

    entry.name:SetText(string.upper(stock.name))
    entry.ticker:SetText(stock.ticker)
    entry.price:SetText(string.format("%.2f", stock.base_price * day_multiplier() * (1 + change)))

    if change >= 0 then
        entry.arrow:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
        entry.arrow:SetVertexColor(0.3, 0.9, 0.3)
    else
        entry.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
        entry.arrow:SetVertexColor(1, 0.3, 0.3)
    end

    entry.width = entry.name:GetStringWidth() + 6 + entry.ticker:GetStringWidth() + 6
        + entry.price:GetStringWidth() + 1 + 14
end


-- (coin) NAME (coin), sized and coloured by place
local function make_winner_entry()
    local entry = CreateFrame("Frame", nil, band)
    entry:SetHeight(band:GetHeight())
    entry.kind = "winner"
    entry:SetScript("OnEnter", show_winner_tooltip)
    entry:SetScript("OnLeave", GameTooltip_Hide)

    entry.left_coin = entry:CreateTexture(nil, "OVERLAY")
    entry.left_coin:SetPoint("LEFT", entry, "LEFT", 0, 0)

    entry.name = entry:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    entry.name:SetPoint("LEFT", entry.left_coin, "RIGHT", 6, 0)

    entry.right_coin = entry:CreateTexture(nil, "OVERLAY")
    entry.right_coin:SetPoint("LEFT", entry.name, "RIGHT", 6, 0)

    return entry
end


local function fill_winner_entry(entry, player, place)
    local color = place_colors[place]
    local coin_size = place_coin_sizes[place]

    entry.player = player
    entry.place = place

    entry.left_coin:SetTexture(place_coins[place])
    entry.left_coin:SetSize(coin_size, coin_size)
    entry.right_coin:SetTexture(place_coins[place])
    entry.right_coin:SetSize(coin_size, coin_size)

    entry.name:SetFontObject(place_fonts[place])
    entry.name:SetText(string.upper(Ambiguate(player.name, "guild")))
    entry.name:SetTextColor(color[1], color[2], color[3])

    entry.width = coin_size + 6 + entry.name:GetStringWidth() + 6 + coin_size
end


------------------------------------------------------------
-- What comes next
------------------------------------------------------------

-- Any stock but the one just shown
local function pick_stock()
    local stock = stocks[math.random(#stocks)]

    while stock == last_stock do
        stock = stocks[math.random(#stocks)]
    end

    last_stock = stock
    return stock
end


-- Any winner but the one just shown, unless there's only one
local function pick_winner()
    local winner_count = #tithe_last_week.players
    local winner = math.random(winner_count)

    while winner_count > 1 and winner == last_winner do
        winner = math.random(winner_count)
    end

    return winner
end


-- 5 or 6 stocks, then a winner if there are any
local function plan_more()
    for stock_number = 1, math.random(fewest_stocks_between_winners, most_stocks_between_winners) do
        table.insert(coming_up, "stock")
    end

    if #tithe_last_week.players > 0 then
        table.insert(coming_up, pick_winner())
    end
end


-- Stock, stock, 1st, stock, 2nd, stock, 3rd, leaving out winners there aren't
local function plan_opening()
    coming_up = { "stock", "stock" }

    for winner = 1, #tithe_last_week.players do
        table.insert(coming_up, winner)

        if winner < #tithe_last_week.players then
            table.insert(coming_up, "stock")
        end
    end
end


local function next_entry()
    if #coming_up == 0 then
        plan_more()
    end

    local next_up = table.remove(coming_up, 1)

    if next_up == "stock" then
        local entry = table.remove(spare_stock_entries) or make_stock_entry()
        fill_stock_entry(entry, pick_stock())
        return entry
    end

    local players = tithe_last_week.players
    local entry = table.remove(spare_winner_entries) or make_winner_entry()
    fill_winner_entry(entry, players[next_up], place_of(players, players[next_up].week_gold))
    last_winner = next_up
    return entry
end


------------------------------------------------------------
-- The tape
------------------------------------------------------------

local function put_away(entry)
    entry:Hide()

    if entry.kind == "stock" then
        table.insert(spare_stock_entries, entry)
    else
        table.insert(spare_winner_entries, entry)
    end
end


-- Adds entries on the right until the band is full
local function fill_tape()
    while true do
        local last = tape[#tape]
        local x = 12

        if last ~= nil then
            x = last.x + last.width + gap_between_entries

            if x > band:GetWidth() then
                return
            end
        end

        local entry = next_entry()
        entry.x = x
        entry:SetWidth(entry.width)
        entry:SetPoint("LEFT", band, "LEFT", x, 0)
        entry:Show()
        table.insert(tape, entry)
    end
end


-- Everything slides left. Paused while the mouse is on the band.
-- Filled first, since the band can be on screen before the page has started a tape.
local function scroll_tape(self, elapsed)
    fill_tape()

    if band:IsMouseOver() then
        return
    end

    local step = scroll_pixels_per_second * elapsed

    for _, entry in ipairs(tape) do
        entry.x = entry.x - step
        entry:SetPoint("LEFT", band, "LEFT", entry.x, 0)
    end

    if tape[1].x + tape[1].width < 0 then
        put_away(table.remove(tape, 1))
    end
end


------------------------------------------------------------
-- Building it
------------------------------------------------------------

-- 8 strips of black, darkest at the edge, so entries fade in and out.
-- Strips instead of a gradient, so it doesn't depend on which gradient call this client has.
local function add_fade(fade_frame, side)
    for strip_number = 1, 8 do
        local strip = fade_frame:CreateTexture(nil, "OVERLAY")
        strip:SetColorTexture(0, 0, 0, 1 - (strip_number - 1) / 8)
        strip:SetWidth(4)
        strip:SetPoint("TOP")
        strip:SetPoint("BOTTOM")

        local inward = 4 * (strip_number - 1)
        if side == "LEFT" then
            strip:SetPoint("LEFT", fade_frame, "LEFT", inward, 0)
        else
            strip:SetPoint("RIGHT", fade_frame, "RIGHT", -inward, 0)
        end
    end
end


-- Under a thin gold line: the header and week centred, then the band with gold lines along it
function shared.createWinnersTicker(page)
    local line = page:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.35)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 4, shared.winners_ticker_height)
    line:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -4, shared.winners_ticker_height)

    local header = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("BOTTOM", page, "BOTTOM", 0, 62)
    header:SetText("DFC EXCHANGE  ·  LAST WEEK'S CLOSE")

    header_week = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    header_week:SetPoint("BOTTOM", page, "BOTTOM", 0, 49)

    band = CreateFrame("Frame", nil, page)
    band:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 8, 8)
    band:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -8, 8)
    band:SetHeight(34)
    band:SetClipsChildren(true)
    band:SetScript("OnUpdate", scroll_tape)

    local background = band:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.55)

    local top_line = band:CreateTexture(nil, "ARTWORK")
    top_line:SetColorTexture(1, 0.82, 0, 0.5)
    top_line:SetHeight(1)
    top_line:SetPoint("TOPLEFT")
    top_line:SetPoint("TOPRIGHT")

    local bottom_line = band:CreateTexture(nil, "ARTWORK")
    bottom_line:SetColorTexture(1, 0.82, 0, 0.5)
    bottom_line:SetHeight(1)
    bottom_line:SetPoint("BOTTOMLEFT")
    bottom_line:SetPoint("BOTTOMRIGHT")

    -- Above the entries, which are frames on the band and would cover its own textures
    local fade_frame = CreateFrame("Frame", nil, band)
    fade_frame:SetAllPoints()
    fade_frame:SetFrameLevel(band:GetFrameLevel() + 10)
    add_fade(fade_frame, "LEFT")
    add_fade(fade_frame, "RIGHT")
end


-- Opening the page: the week or why there are no winners, then a fresh tape
function shared.startWinnersTicker()
    if tithe_last_week.week_start == 0 then
        header_week:SetText("No officer has sent last week's winners yet")
    elseif #tithe_last_week.players == 0 then
        header_week:SetText("Nobody paid a tithe last week")
    else
        header_week:SetText("Week of " .. date("%B %d", tithe_last_week.week_start))
    end

    while #tape > 0 do
        put_away(table.remove(tape))
    end

    last_winner = nil
    plan_opening()
    fill_tape()
end


-- WIN from the answering ledger: last week's top 3, all in one message
function shared.saveWinners(message)
    local message_type, week_start, entries = strsplit("|", message)

    tithe_last_week = { week_start = tonumber(week_start), players = {} }

    for entry in string.gmatch(entries or "", "[^;]+") do
        local name, week_gold = strsplit(",", entry)
        table.insert(tithe_last_week.players, { name = name, week_gold = tonumber(week_gold) })
    end

    -- The planned tape may name a winner that's gone, so start over with the new ones
    if band ~= nil and band:IsVisible() then
        shared.startWinnersTicker()
    end
end
