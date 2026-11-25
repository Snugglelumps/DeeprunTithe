-- Deeprun Tithe: the leaderboard tab on the guild window
-- A side tab under Blizzard's that shows this week's leaderboard in the guild window's page area,
-- the way Roster and Guild Info show theirs. The tab and page come from DeeprunShared.lua.
--
-- We ask the ledgers for a fresh board (LDR) on the first RDY of the session, so we only ask
-- once a ledger is listening. DeeprunTithe.lua also asks once a ledger has all our rows.
-- The answering ledger sends it to the whole guild in RNK messages, a few players each.
-- It's saved, so the last board still shows when no officer is online.
--
-- Your tithe level is the coin before the title. Clicking it opens
-- everything you've learned so far (DeeprunArchive.lua).
--
-- Last week's winners scroll along the bottom in a stock ticker (DeeprunWinners.lua).
--
-- Saved for the account (see DeeprunTithe.toc):
--   tithe_leaderboard  { week_start = ..., players = { [name] = { week_gold = copper, payments = ...,
--                        all_time_gold = copper, points = ..., weeks_won = ... } } }

local addon_name, shared = ...

local leaderboard_page = nil
local week_label = nil
local level_button = nil
local title = nil
local empty_label = nil
local scroll_child = nil
local rows = {}

local board_received = false   -- The first RNK of the session sets it


local function send(message)
    C_ChatInfo.SendAddonMessage(shared.prefix, message, "GUILD")
end


-- RDY means a ledger is listening. Until a board has come, ask for one.
-- The RDY that answers our login RDY? comes a moment after login, so the board does too.
function shared.askForBoardIfNoneYet()
    if board_received then
        return
    end

    send(shared.ldrMessage())
end


------------------------------------------------------------
-- The page
------------------------------------------------------------

-- The columns, the same on the heading row and every player row.
-- Money and numbers line up on their right edge, so x is where the column ends.
local function add_columns(row, font)
    row.place = row:CreateFontString(nil, "OVERLAY", font)
    row.place:SetPoint("LEFT", row, "LEFT", 8, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", font)
    row.name:SetPoint("LEFT", row, "LEFT", 34, 0)

    row.week_gold = row:CreateFontString(nil, "OVERLAY", font)
    row.week_gold:SetPoint("RIGHT", row, "LEFT", 280, 0)

    row.payments = row:CreateFontString(nil, "OVERLAY", font)
    row.payments:SetPoint("RIGHT", row, "LEFT", 340, 0)

    row.all_time_gold = row:CreateFontString(nil, "OVERLAY", font)
    row.all_time_gold:SetPoint("RIGHT", row, "LEFT", 445, 0)

    row.points = row:CreateFontString(nil, "OVERLAY", font)
    row.points:SetPoint("RIGHT", row, "LEFT", 500, 0)

    row.weeks_won = row:CreateFontString(nil, "OVERLAY", font)
    row.weeks_won:SetPoint("RIGHT", row, "LEFT", 550, 0)
end


-- A player's row. Glows on hover like the Auction House's, every other one shaded.
local function get_row(row_number)
    local row = rows[row_number]

    if row == nil then
        row = CreateFrame("Button", nil, scroll_child)
        row:SetSize(560, 18)
        row:SetPoint("TOPLEFT", scroll_child, "TOPLEFT", 0, -18 * (row_number - 1))

        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetAtlas("auctionhouse-ui-row-highlight")
        hover:SetBlendMode("ADD")

        row.shade = row:CreateTexture(nil, "BACKGROUND")
        row.shade:SetAllPoints()
        row.shade:SetColorTexture(1, 1, 1, 0.04)
        row.shade:SetShown(row_number % 2 == 0)

        add_columns(row, "GameFontHighlightSmall")
        rows[row_number] = row
    end

    row:Show()
    return row
end


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


-- The saved board, most gold this week first
local function show_leaderboard()
    for _, row in ipairs(rows) do
        row:Hide()
    end

    local players = {}
    for name, player in pairs(tithe_leaderboard.players) do
        table.insert(players, {
            name = name,
            week_gold = player.week_gold,
            payments = player.payments,
            all_time_gold = player.all_time_gold,
            points = player.points,
            weeks_won = player.weeks_won,
        })
    end

    table.sort(players, function(first, second)
        return first.week_gold > second.week_gold
    end)

    if tithe_leaderboard.week_start == 0 then
        week_label:SetText("")
        empty_label:SetText("No officer has sent the leaderboard yet")
    elseif #players == 0 then
        week_label:SetText("Week of " .. date("%B %d", tithe_leaderboard.week_start))
        empty_label:SetText("Nobody has paid a tithe yet this week")
    else
        week_label:SetText("Week of " .. date("%B %d", tithe_leaderboard.week_start))
        empty_label:SetText("")
    end

    for row_number, player in ipairs(players) do
        local row = get_row(row_number)
        row.place:SetText(place_of(players, player.week_gold))
        row.name:SetText(Ambiguate(player.name, "guild"))
        row.week_gold:SetText(GetMoneyString(player.week_gold))
        row.payments:SetText(player.payments)
        row.all_time_gold:SetText(GetMoneyString(player.all_time_gold))
        row.points:SetText(player.points)
        row.weeks_won:SetText(player.weeks_won)
    end

    scroll_child:SetHeight(18 * #players + 4)
end


-- Nothing until the first tithe, so there's nothing to open yet
local function show_tithe_level()
    local level = shared.titheLevel()
    level_button.number:SetText(level)
    level_button:SetShown(level > 0)

    -- The title makes room for the coin
    title:SetPoint("TOPLEFT", leaderboard_page, "TOPLEFT", level > 0 and 46 or 14, -12)
end


-- A circle of the given size in the middle of the button
local function add_circle(button, layer, size)
    local circle = button:CreateTexture(nil, layer)
    circle:SetSize(size, size)
    circle:SetPoint("CENTER")

    local mask = button:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    mask:SetAllPoints(circle)
    circle:AddMaskTexture(mask)
    return circle
end


-- A round coin with a gold rim and your level in the middle. The coin is darkened so the
-- number stands out, and brightens on hover.
local function create_level_button()
    level_button = CreateFrame("Button", nil, leaderboard_page)
    level_button:SetSize(29, 29)
    level_button:SetPoint("TOPLEFT", leaderboard_page, "TOPLEFT", 10, -5)

    local rim = add_circle(level_button, "BACKGROUND", 29)
    rim:SetColorTexture(1, 0.82, 0)

    local coin = add_circle(level_button, "ARTWORK", 26)
    coin:SetTexture("Interface\\Icons\\INV_Misc_Coin_17")
    coin:SetVertexColor(0.45, 0.45, 0.45)

    local hover = add_circle(level_button, "HIGHLIGHT", 29)
    hover:SetColorTexture(1, 1, 1, 0.2)

    level_button.number = level_button:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    level_button.number:SetPoint("CENTER")

    level_button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Tithe Level " .. shared.titheLevel())
        GameTooltip:AddLine("Click to recall what you've learned", 1, 1, 1)
        GameTooltip:Show()
    end)
    level_button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    level_button:SetScript("OnClick", shared.showArchive)
end


local function show_page()
    show_leaderboard()
    show_tithe_level()
    shared.startWinnersTicker()
end


-- Title and week across the top, the players in a scrolling list under their headings,
-- last week's winners ticking along the bottom. Opening it draws what's saved.
local function create_leaderboard_page()
    leaderboard_page = shared.makeGuildPage()
    leaderboard_page:SetScript("OnShow", show_page)

    title = leaderboard_page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetText("Tithe Leaderboard")

    week_label = leaderboard_page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    week_label:SetPoint("TOPRIGHT", leaderboard_page, "TOPRIGHT", -14, -16)

    create_level_button()

    -- Stops above the ticker, which is shared.winners_ticker_height tall
    local scroll = CreateFrame("ScrollFrame", nil, leaderboard_page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", leaderboard_page, "TOPLEFT", 8, -59)
    scroll:SetPoint("BOTTOMRIGHT", leaderboard_page, "BOTTOMRIGHT", -28, shared.winners_ticker_height + 6)

    scroll_child = CreateFrame("Frame", nil, scroll)
    scroll_child:SetSize(560, 100)
    scroll:SetScrollChild(scroll_child)

    local headings = CreateFrame("Frame", nil, leaderboard_page)
    headings:SetSize(560, 16)
    headings:SetPoint("BOTTOMLEFT", scroll, "TOPLEFT", 0, 4)
    add_columns(headings, "GameFontNormalSmall")
    headings.place:SetText("#")
    headings.name:SetText("Name")
    headings.week_gold:SetText("This week")
    headings.payments:SetText("Payments")
    headings.all_time_gold:SetText("All time")
    headings.points:SetText("Points")
    headings.weeks_won:SetText("Wins")

    empty_label = scroll_child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty_label:SetPoint("TOPLEFT", scroll_child, "TOPLEFT", 8, -2)

    shared.createWinnersTicker(leaderboard_page)
end


-- RNK from the answering ledger: a few players. A new week clears the old board first.
function shared.saveRanks(message)
    local message_type, week_start, entries = strsplit("|", message)
    week_start = tonumber(week_start)
    board_received = true

    if week_start ~= tithe_leaderboard.week_start then
        tithe_leaderboard = { week_start = week_start, players = {} }
    end

    for entry in string.gmatch(entries, "[^;]+") do
        local name, week_gold, payments, all_time_gold, points, weeks_won = strsplit(",", entry)

        tithe_leaderboard.players[name] = {
            week_gold = tonumber(week_gold),
            payments = tonumber(payments),
            all_time_gold = tonumber(all_time_gold),
            points = tonumber(points),
            weeks_won = tonumber(weeks_won),
        }
    end

    if leaderboard_page ~= nil and leaderboard_page:IsShown() then
        show_leaderboard()
    end
end


-- Slot 1, right under Blizzard's tabs. The Ledger's goes under it.
local function create_leaderboard_tab_and_page()
    create_leaderboard_page()
    shared.makeGuildTab(1, "Interface\\Icons\\INV_Misc_Coin_17", "Tithe Leaderboard", leaderboard_page)
end


-- The guild window only exists once Blizzard_Communities has loaded
local leaderboard_frame = CreateFrame("Frame")
leaderboard_frame:RegisterEvent("PLAYER_LOGIN")
leaderboard_frame:RegisterEvent("ADDON_LOADED")

leaderboard_frame:SetScript("OnEvent", function(self, event, loaded_addon_name)
    if event == "PLAYER_LOGIN" then
        if tithe_leaderboard == nil then
            tithe_leaderboard = { week_start = 0, players = {} }
        end

        if tithe_last_week == nil then
            tithe_last_week = { week_start = 0, players = {} }
        end

        -- It may have loaded already, before we were listening
        if C_AddOns.IsAddOnLoaded("Blizzard_Communities") and leaderboard_page == nil then
            create_leaderboard_tab_and_page()
        end

    elseif event == "ADDON_LOADED" and loaded_addon_name == "Blizzard_Communities" and leaderboard_page == nil then
        create_leaderboard_tab_and_page()
    end
end)
