-- Deeprun Tithe

-- The prefix, settings, transaction IDs and messages come from DeeprunShared.lua
local addon_name, shared = ...

-- Saved per character (see DeeprunTithe.toc):
--   guild_debt     full vendor value of junk sold. What you owe is guild_debt * tithe_rate.
--   tithe_queue    deposits not yet confirmed by a ledger, oldest first
--   tithe_archive  deposits a ledger has confirmed, kept for exporting later
--   custom_tithe_this_week  { week_start = ..., paid = copper } custom tithes paid toward the weekly limit
--   tithe_guild    the guild this character last heard an officer's RDY in (see shared.inConfiguredGuild)
-- Saved for the account:
--   tithe_settings  the newest settings a ledger's RDY has brought: { time = ..., text = "r=0.05;t=0;l=20;c=1;" }
-- A queued row: { transactionID = "time|base64", time = ..., gold = ..., item_id = ..., count = ... }

local last_rdy_time = 0        -- GetTime() when a ledger last said RDY
local waiting_for_ack = nil    -- the transactionID sent and not yet ACKed
local sent_time = 0            -- GetTime() when that row was sent

-- How many of each grey were in your bags when the vendor opened: { [item_id] = count }
local gray_counts_at_vendor_open = {}

-- One of each per window: Blizzard's, and any bag addon's that replaces it (DeeprunBagAddons.lua)
local pay_tithe_buttons = {}   -- the Pay Tithe button on each guild bank window
local custom_tithe_buttons = {} -- the Pay Custom Tithe button beside each one
local rules_cards = {}         -- the rule under each tithe bar, until it's accepted
local bag_debt_texts = {}      -- the "Tithe:" line in each bag window
local debt_boxes = {}          -- the boxes some of those lines sit in, which grow to fit the text

local blizzard_tithe_bar = nil
local rules_popup = nil


------------------------------------------------------------
-- Debt
------------------------------------------------------------

-- The tithe is on income from selling junk you looted. WoW has no "you sold this" event,
-- so we count each grey in your bags when a vendor opens and again when it closes.
-- Whatever's gone was sold, and counts only if it's on the looted list (DeeprunLoot.lua).
-- Selling and buying back at the same visit cancels out. A grey bought back from an earlier
-- visit changes nothing: it came off the list when it was sold, so selling it again won't count twice.
-- Tradeoff: deleting a grey while a vendor is open counts as selling it.
local function add_gray_sales_to_debt()
    local gray_counts_now = shared.grayCountsInBags()

    for item_id, count_at_open in pairs(gray_counts_at_vendor_open) do
        local sold_count = count_at_open - (gray_counts_now[item_id] or 0)

        if sold_count > 0 then
            guild_debt = guild_debt + shared.takeLootedGrays(item_id, sold_count)
        end
    end
end


------------------------------------------------------------
-- Transaction IDs and the queue
------------------------------------------------------------

-- Makes the row for one payment and puts it in the queue.
-- item_id and count are always 0. They're still in the row format.
local function record_deposit(gold)
    local deposit_time = GetServerTime()

    table.insert(tithe_queue, {
        -- Full "First Last" name, the same as the sender the ledger sees
        transactionID = shared.makeTransactionID(GetUnitName("player", true), deposit_time, gold, 0, 0),
        time = deposit_time,
        gold = gold,
        item_id = 0,
        count = 0,
    })
end


------------------------------------------------------------
-- Talking to the ledgers
------------------------------------------------------------

local function send(message)
    C_ChatInfo.SendAddonMessage(shared.prefix, message, "GUILD")
end


local function archive(row)
    table.insert(tithe_archive, row)
    table.remove(tithe_queue, 1)
end


-- Sends the oldest queued row. One row is in flight at a time.
local function drain_queue()
    -- No ledger has said RDY in the last 5 minutes. The answering one says it every 4.
    if GetTime() - last_rdy_time > 300 then
        return
    end

    if #tithe_queue == 0 then
        return
    end

    -- Still waiting on the last row, and it hasn't been long enough to send it again
    if waiting_for_ack ~= nil and GetTime() - sent_time < 25 then
        return
    end

    local row = tithe_queue[1]
    send(shared.rowMessage(row))
    waiting_for_ack = row.transactionID
    sent_time = GetTime()
end


-- For the telemetry. -1 if no ledger has said RDY since login or reload.
function shared.secondsSinceReady()
    if last_rdy_time == 0 then
        return -1
    end

    return math.floor(GetTime() - last_rdy_time)
end


local function row_acked(message)
    if waiting_for_ack == nil then
        return
    end

    if message ~= shared.ackMessage(waiting_for_ack) then
        return
    end

    archive(tithe_queue[1])
    waiting_for_ack = nil

    -- All our rows are in. Ask for the board so everyone online sees them.
    if #tithe_queue == 0 then
        send(shared.ldrMessage())
    end

    -- Send the next one right away instead of waiting for the next tick
    drain_queue()
end


------------------------------------------------------------
-- Depositing
------------------------------------------------------------

-- What you owe in copper
local function amount_owed()
    return math.floor(guild_debt * shared.tithe_rate)
end

shared.amountOwed = amount_owed


-- When this character last paid a tithe, or 0 if never.
-- The queue holds the newest rows until a ledger confirms them, then they move to the archive.
function shared.lastTitheTime()
    local newest = tithe_queue[#tithe_queue] or tithe_archive[#tithe_archive]
    return newest and newest.time or 0
end


-- Memos, notices, communiques and the bank's buttons are only for a guild that runs the Ledger: one where this
-- character has heard a RDY from an officer. tithe_guild is that guild's name, saved
-- per character, so it still counts on days no officer is online. Leave that guild and
-- it doesn't count until a RDY comes in the new one.
-- Just after login the guild name can be missing for a moment, which reads as not configured.
function shared.inConfiguredGuild()
    local guild_name = GetGuildInfo("player")
    return guild_name ~= nil and guild_name == tithe_guild
end


-- Puts what you owe on the Pay Tithe buttons and in the bags.
-- The bags always show it. Outside a guild that runs the Ledger, the bank's buttons
-- say so and are off: a tithe there would go to a bank nobody's keeping a ledger of.
local function show_amount_owed()
    local button_text = "All paid up"
    local bag_text = "|cffffd100Tithe:|r All paid up"

    if amount_owed() > 0 then
        button_text = "Pay Tithe: " .. GetMoneyString(amount_owed())
        bag_text = "|cffffd100Tithe:|r " .. GetMoneyString(amount_owed())
    end

    local configured = shared.inConfiguredGuild()
    if not configured then
        button_text = "This guild doesn't collect tithes"
    end

    for _, pay_tithe_button in ipairs(pay_tithe_buttons) do
        pay_tithe_button:SetText(button_text)
        pay_tithe_button:SetEnabled(configured)
    end

    for _, custom_tithe_button in ipairs(custom_tithe_buttons) do
        custom_tithe_button:SetEnabled(configured)
    end

    for _, bag_debt_text in ipairs(bag_debt_texts) do
        bag_debt_text:SetText(bag_text)
    end

    for _, debt_box in ipairs(debt_boxes) do
        debt_box:SetWidth(debt_box.text:GetStringWidth() + 20)
    end
end


-- Once, just after login, so we get the settings and send our rows without waiting for the next RDY
local function ask_if_ledger_ready()
    send(shared.readyQuestionMessage())
end


-- RDY from the answering ledger. Its settings replace ours if they're newer.
local function ledger_ready(message)
    local message_type, ledger_id, settings_time, settings_text = strsplit("|", message)
    settings_time = tonumber(settings_time)

    last_rdy_time = GetTime()

    -- An old ledger, or a RDY typed by hand, has no settings
    if settings_time == nil then
        return
    end

    if settings_time > tithe_settings.time then
        tithe_settings = { time = settings_time, text = settings_text }
        shared.useSettings(settings_text)
        show_amount_owed()
    end
end


------------------------------------------------------------
-- Officers setting what you owe
------------------------------------------------------------

-- SET from an officer's ledger: what you owe becomes their number, and we answer DNE.
-- One try: the officer sends it once, while you're online, and sees our DNE or nothing.
-- A SET more than a minute old is never done. It's from before whatever you've sold or
-- paid since, so doing it would undo that. (Old ledgers resend theirs every 5 minutes,
-- forever. Those are still answered, so they stop.)
local set_max_age_seconds = 60

local function officer_set_owed(message, sender)
    local message_type, player, command_time, owed = strsplit("|", message)

    if player ~= GetUnitName("player", true) then
        return
    end

    -- Anyone can send an addon message, so the sender has to be in the top three ranks
    -- (shared.ledger_names in DeeprunShared.lua). Someone not on the list yet is turned down.
    -- Their ledger sends again in 5 minutes.
    if not shared.sentByLedgerRank(sender) then
        return
    end

    command_time = tonumber(command_time)
    owed = tonumber(owed)

    if GetServerTime() - command_time <= set_max_age_seconds then
        -- guild_debt is the vendor value before the rate. The extra half copper stops
        -- rounding turning 12345 owed into 12344.
        guild_debt = (owed + 0.5) / shared.tithe_rate
        show_amount_owed()

        -- Tithe stays out of chat. This shows top centre, where Blizzard's own messages go.
        UIErrorsFrame:AddMessage(Ambiguate(sender, "none") .. " set your tithe to " .. GetMoneyString(owed) .. ".",
            1, 0.82, 0)
    end

    send(shared.dneMessage(player, command_time))
end


-- Covering what's owed wipes the debt. Less than that just lowers it.
local function pay_off_debt(copper)
    if copper >= amount_owed() then
        guild_debt = 0
    else
        guild_debt = guild_debt - copper / shared.tithe_rate
    end
end


-- Only gold paid through our buttons counts. Blizzard's own Deposit is left alone,
-- so treasurers can move guild gold in and out without it counting as anyone's tithe.
-- Assumes the deposit went through. The ledger's bank check catches any that didn't.
-- True if it paid.
local function pay_tithe(copper)
    if GetMoney() < copper then
        -- Red, top centre, like Blizzard's own "not enough money"
        UIErrorsFrame:AddMessage("You don't have that much gold.", 1, 0.1, 0.1)
        return false
    end

    DepositGuildBankMoney(copper)
    pay_off_debt(copper)
    record_deposit(copper)
    shared.recordTitheHistory(copper)
    show_amount_owed()
    shared.celebrateTithe(copper)
    return true
end


-- Pay Tithe: exactly what's owed. Asks first if it's more than a tenth of your gold.
local function pay_what_is_owed(confirmed)
    if amount_owed() <= 0 then
        return
    end

    if confirmed == nil then
        if amount_owed() > GetMoney() * 0.1 then
            StaticPopup_Show("DEEPRUN_DEPOSIT_POPUP", GetMoneyString(amount_owed()))
            return
        end
    end

    pay_tithe(amount_owed())
end


StaticPopupDialogs["DEEPRUN_DEPOSIT_POPUP"] = {
    text = "Deposit %s into the guild bank?",
    button1 = "Deposit",
    button2 = "Cancel",
    OnAccept = function()
        pay_what_is_owed(true)
    end,
    timeout = 0,
    hideOnEscape = true,
}


------------------------------------------------------------
-- Pay another amount
------------------------------------------------------------

-- Forever's popups don't show a money box, so this is our own, made to look like one.
-- Typing the amount in is the confirmation.
-- Custom tithes are limited each week, resetting Monday with the leaderboard. Pay Tithe isn't.
-- The limit is a setting, in gold, from the ledger's RDY.
local custom_tithe_frame = nil
local gold_box = nil
local silver_box = nil
local copper_box = nil
local tithe_button = nil
local over_limit_alert = nil


-- In copper
local function custom_tithe_weekly_limit()
    return math.floor(shared.custom_tithe_limit * 10000)
end


-- custom_tithe_this_week is from an earlier week until the first custom tithe of this one
local function custom_tithe_paid_this_week()
    if custom_tithe_this_week.week_start ~= shared.thisWeekStart() then
        return 0
    end

    return custom_tithe_this_week.paid
end

shared.customTithePaidThisWeek = custom_tithe_paid_this_week


local function add_custom_tithe(copper)
    custom_tithe_this_week = {
        week_start = shared.thisWeekStart(),
        paid = custom_tithe_paid_this_week() + copper,
    }
end


local function is_over_weekly_limit(copper)
    return custom_tithe_paid_this_week() + copper > custom_tithe_weekly_limit()
end


local function typed_amount()
    local gold = tonumber(gold_box:GetText()) or 0
    local silver = tonumber(silver_box:GetText()) or 0
    local copper = tonumber(copper_box:GetText()) or 0

    return gold * 10000 + silver * 100 + copper
end


-- Every keystroke: over the limit shows the alert and turns the Tithe button off
local function check_typed_amount()
    local is_over = is_over_weekly_limit(typed_amount())
    over_limit_alert:SetShown(is_over)
    tithe_button:SetEnabled(not is_over)
end


local function pay_typed_amount()
    local amount = typed_amount()

    -- Enter still gets here with the button off
    if is_over_weekly_limit(amount) then
        return
    end

    custom_tithe_frame:Hide()

    if amount > 0 and pay_tithe(amount) then
        add_custom_tithe(amount)
    end
end


-- Hovering the alert says what's left this week
local function show_limit_tooltip(alert)
    local left_this_week = custom_tithe_weekly_limit() - custom_tithe_paid_this_week()

    GameTooltip:SetOwner(alert, "ANCHOR_RIGHT")
    GameTooltip:SetText("Over this week's limit")

    if left_this_week > 0 then
        GameTooltip:AddLine("Custom tithes are up to " .. GetMoneyString(custom_tithe_weekly_limit())
            .. " a week. You have " .. GetMoneyString(left_this_week) .. " left.", 1, 1, 1, true)
    else
        GameTooltip:AddLine("Custom tithes are up to " .. GetMoneyString(custom_tithe_weekly_limit())
            .. " a week, and you've paid it this week. It resets Monday.", 1, 1, 1, true)
    end

    GameTooltip:Show()
end


-- A number box with its coin after it
local function make_coin_box(left, width, max_letters, coin_texture)
    local box = CreateFrame("EditBox", nil, custom_tithe_frame, "InputBoxTemplate")
    box:SetSize(width, 20)
    box:SetPoint("TOPLEFT", custom_tithe_frame, "TOPLEFT", left, -44)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(max_letters)
    box:SetScript("OnEnterPressed", pay_typed_amount)
    box:SetScript("OnTextChanged", check_typed_amount)
    box:SetScript("OnEscapePressed", function()
        custom_tithe_frame:Hide()
    end)

    local coin = custom_tithe_frame:CreateTexture(nil, "ARTWORK")
    coin:SetSize(14, 14)
    coin:SetPoint("LEFT", box, "RIGHT", 2, 0)
    coin:SetTexture(coin_texture)

    return box
end


local function create_custom_tithe_frame()
    custom_tithe_frame = CreateFrame("Frame", "DeeprunCustomTitheFrame", UIParent, "BackdropTemplate")
    custom_tithe_frame:SetSize(300, 116)
    custom_tithe_frame:SetPoint("TOP", UIParent, "TOP", 0, -135)
    custom_tithe_frame:SetFrameStrata("DIALOG")
    custom_tithe_frame:EnableMouse(true)
    custom_tithe_frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    table.insert(UISpecialFrames, "DeeprunCustomTitheFrame")

    local question = custom_tithe_frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    question:SetPoint("TOP", custom_tithe_frame, "TOP", 0, -20)
    question:SetText("How much would you like to tithe?")

    gold_box = make_coin_box(52, 64, 6, "Interface\\MoneyFrame\\UI-GoldIcon")
    silver_box = make_coin_box(144, 32, 2, "Interface\\MoneyFrame\\UI-SilverIcon")
    copper_box = make_coin_box(204, 32, 2, "Interface\\MoneyFrame\\UI-CopperIcon")

    -- The red alert, after the copper coin
    over_limit_alert = CreateFrame("Frame", nil, custom_tithe_frame)
    over_limit_alert:SetSize(18, 18)
    over_limit_alert:SetPoint("LEFT", copper_box, "RIGHT", 22, 0)
    over_limit_alert:SetScript("OnEnter", show_limit_tooltip)
    over_limit_alert:SetScript("OnLeave", GameTooltip_Hide)
    over_limit_alert:Hide()

    local alert_icon = over_limit_alert:CreateTexture(nil, "ARTWORK")
    alert_icon:SetAllPoints()
    alert_icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
    alert_icon:SetVertexColor(1, 0.27, 0.27)

    tithe_button = CreateFrame("Button", nil, custom_tithe_frame, "UIPanelButtonTemplate")
    tithe_button:SetSize(110, 22)
    tithe_button:SetPoint("BOTTOMRIGHT", custom_tithe_frame, "BOTTOM", -4, 18)
    tithe_button:SetText("Tithe")
    tithe_button:SetScript("OnClick", pay_typed_amount)

    local cancel_button = CreateFrame("Button", nil, custom_tithe_frame, "UIPanelButtonTemplate")
    cancel_button:SetSize(110, 22)
    cancel_button:SetPoint("BOTTOMLEFT", custom_tithe_frame, "BOTTOM", 4, 18)
    cancel_button:SetText("Cancel")
    cancel_button:SetScript("OnClick", function()
        custom_tithe_frame:Hide()
    end)

    custom_tithe_frame:Hide()
end


-- Opens empty, with the cursor in the gold box
local function show_custom_tithe_frame()
    if custom_tithe_frame == nil then
        create_custom_tithe_frame()
    end

    gold_box:SetText("")
    silver_box:SetText("")
    copper_box:SetText("")
    check_typed_amount()
    custom_tithe_frame:Show()
    gold_box:SetFocus()
end


------------------------------------------------------------
-- Buttons
------------------------------------------------------------

-- Blizzard's red button, as on the bank's own Deposit and Withdraw.
-- Small text, so "Pay Custom Tithe" fits in a third of the bar.
local function make_bar_button(parent)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetNormalFontObject("GameFontNormalSmall")
    button:SetHighlightFontObject("GameFontHighlightSmall")
    return button
end


-- The popup the card's checkbox opens: the rule in more detail, and Accept.
-- Accepting hides the card for good on this account (tithe_rules_accepted).
-- Blizzard's portrait window, like the Ledger's. The text sits under the coin, centred
-- like the buttons. Beside the coin it was off to the right of them.
local function create_rules_popup()
    rules_popup = CreateFrame("Frame", "DeeprunRulesPopup", UIParent, "PortraitFrameTemplate")
    rules_popup:SetWidth(360)
    rules_popup:SetPoint("TOP", UIParent, "TOP", 0, -135)
    rules_popup:SetFrameStrata("DIALOG")
    rules_popup:SetTitle("Paying your tithe")
    rules_popup:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Coin_17")
    rules_popup:EnableMouse(true)
    table.insert(UISpecialFrames, "DeeprunRulesPopup")

    local details = rules_popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- In the gap beside the coin, the same coral as the card's warning
    local final_notice = rules_popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    final_notice:SetPoint("TOP", rules_popup, "TOP", 0, -40)
    final_notice:SetText("Final Notice")
    final_notice:SetTextColor(1, 0.5, 0.31)

    details:SetPoint("TOP", rules_popup, "TOP", 0, -70)
    details:SetWidth(310)
    details:SetJustifyH("LEFT")
    details:SetSpacing(3)
    details:SetText(
        "Only gold paid with the |cffffd100Pay Tithe|r and |cffffd100Pay Custom Tithe|r buttons counts as tithe.\n\n"
        .. "Gold you put in with the bank's own Deposit button isn't recorded, and won't lower what you owe. "
        .. "Gold taken out with Withdraw isn't tracked either.\n\n"
        .. "Trade goods you put in the bank aren't counted either.\n\n"
        .. "|cffffd100Is that okay?|r")

    local accept_button = CreateFrame("Button", nil, rules_popup, "UIPanelButtonTemplate")
    accept_button:SetSize(110, 22)
    accept_button:SetPoint("BOTTOMRIGHT", rules_popup, "BOTTOM", -4, 18)
    accept_button:SetText("Accept")
    accept_button:SetScript("OnClick", function()
        tithe_rules_accepted = true
        rules_popup:Hide()

        for _, rules_card in ipairs(rules_cards) do
            rules_card:Hide()
        end
    end)

    local cancel_button = CreateFrame("Button", nil, rules_popup, "UIPanelButtonTemplate")
    cancel_button:SetSize(110, 22)
    cancel_button:SetPoint("BOTTOMLEFT", rules_popup, "BOTTOM", 4, 18)
    cancel_button:SetText("Cancel")
    cancel_button:SetScript("OnClick", function()
        rules_popup:Hide()
    end)

    -- However it closes without Accept, the checkbox goes back to empty
    rules_popup:SetScript("OnHide", function()
        for _, rules_card in ipairs(rules_cards) do
            rules_card.got_it:SetChecked(false)
        end
    end)

    rules_popup:SetHeight(70 + details:GetStringHeight() + 58)
    rules_popup:Hide()
end


local function show_rules_popup()
    if rules_popup == nil then
        create_rules_popup()
    end

    rules_popup:Show()
end


-- The card under the tithe bar with the rule. Same width as the two buttons.
-- Same dark as the bar, with a thin gold border. A "Got it" checkbox in the corner opens the popup above.
local function create_rules_card(tithe_bar)
    local rules_card = CreateFrame("Frame", nil, tithe_bar, "BackdropTemplate")
    table.insert(rules_cards, rules_card)
    rules_card:SetPoint("TOPLEFT", tithe_bar, "BOTTOMLEFT", 0, -4)
    rules_card:SetPoint("TOPRIGHT", tithe_bar, "BOTTOMRIGHT", 0, -4)
    rules_card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    rules_card:SetBackdropColor(0.05, 0.05, 0.06, 0.97)
    rules_card:SetBackdropBorderColor(1, 0.82, 0, 0.6)

    local rule = rules_card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rule:SetPoint("TOPLEFT", rules_card, "TOPLEFT", 14, -12)
    rule:SetJustifyH("LEFT")
    rule:SetSpacing(3)
    rule:SetText("Only gold paid with the |cffffd100buttons above|r counts as tithe.")

    -- The alert triangle, tinted red
    local warning = rules_card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    warning:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -8)
    warning:SetJustifyH("LEFT")
    warning:SetSpacing(3)
    warning:SetText("|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:0:0:0:0:64:64:0:64:0:64:255:70:70|t "
        .. "|cffff7f50The bank's own Deposit button does not count.|r")

    -- "Got it" and its checkbox sit at the end of the warning's row
    local got_it_label = rules_card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    got_it_label:SetPoint("LEFT", warning, "RIGHT", 4, 0)
    got_it_label:SetText("Got it")

    rules_card.got_it = CreateFrame("CheckButton", nil, rules_card, "UICheckButtonTemplate")
    rules_card.got_it:SetSize(20, 20)
    rules_card.got_it:SetPoint("LEFT", got_it_label, "RIGHT", 2, 0)
    rules_card.got_it:SetScript("OnClick", show_rules_popup)

    -- The text wraps to the card's width, and the card grows to fit it.
    -- The warning leaves 60 on its right for "Got it" and the checkbox.
    local function fit_text()
        local text_width = rules_card:GetWidth() - 28
        rule:SetWidth(text_width)
        warning:SetWidth(text_width - 60)
        rules_card:SetHeight(12 + rule:GetStringHeight() + 8 + warning:GetStringHeight() + 12)
    end

    rules_card:SetScript("OnSizeChanged", fit_text)
    rules_card:SetScript("OnShow", fit_text)

    if tithe_rules_accepted then
        rules_card:Hide()
    end
end


-- The tithe bar for a guild bank window, with the rules card under it.
-- Pay Tithe on the left two thirds, Pay Custom Tithe on the right third.
-- The caller places it.
local function create_tithe_bar(bank_window)
    local tithe_bar = CreateFrame("Frame", nil, bank_window)

    local custom_button = make_bar_button(tithe_bar)
    custom_button:SetPoint("TOPRIGHT")
    custom_button:SetPoint("BOTTOMRIGHT")
    custom_button:SetText("Pay Custom Tithe")
    custom_button:SetScript("OnClick", show_custom_tithe_frame)
    table.insert(custom_tithe_buttons, custom_button)

    -- A 4 pixel gap between them so they don't touch
    local pay_tithe_button = make_bar_button(tithe_bar)
    pay_tithe_button:SetPoint("TOPLEFT")
    pay_tithe_button:SetPoint("BOTTOMRIGHT", custom_button, "BOTTOMLEFT", -4, 0)
    pay_tithe_button:SetScript("OnClick", function()
        pay_what_is_owed()
    end)
    table.insert(pay_tithe_buttons, pay_tithe_button)

    -- The bar's width isn't known until the window lays itself out
    tithe_bar:SetScript("OnSizeChanged", function(self, width)
        custom_button:SetWidth((width - 4) / 3)
    end)

    tithe_bar:SetScript("OnShow", show_amount_owed)
    show_amount_owed()

    create_rules_card(tithe_bar)
    return tithe_bar
end


-- Blizzard's guild bank: in the gap to the right of the bank's tabs.
-- The window only exists once Blizzard_GuildBankUI has loaded.
local function create_blizzard_tithe_bar()
    blizzard_tithe_bar = create_tithe_bar(GuildBankFrame)
    blizzard_tithe_bar:SetPoint("BOTTOMLEFT", GuildBankFrameTab4, "BOTTOMRIGHT", 4, 4)
    blizzard_tithe_bar:SetPoint("TOPRIGHT", GuildBankFrame, "BOTTOMRIGHT", -2, -2)
end


-- A bag addon's guild bank window: the bar hangs under it, as wide as it is
function shared.hangTitheBarUnder(bank_window)
    local tithe_bar = create_tithe_bar(bank_window)
    tithe_bar:SetPoint("TOPLEFT", bank_window, "BOTTOMLEFT", 0, -2)
    tithe_bar:SetPoint("TOPRIGHT", bank_window, "BOTTOMRIGHT", 0, -2)
    tithe_bar:SetHeight(24)
end


-- The bag line: "Tithe:" and what you owe. One line, placed one of two ways:
--   integrated  inside a window's own footer. The caller places it.
--   attached    in a gold box hanging under the window (hangDebtLineUnder).
-- 140 wide, because bag addons lay their footers out by it.
function shared.makeDebtLine(parent)
    local debt_line = CreateFrame("Frame", nil, parent)
    debt_line:SetSize(140, 16)

    debt_line.text = debt_line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    debt_line.text:SetPoint("LEFT")
    table.insert(bag_debt_texts, debt_line.text)

    -- Shows whenever the bags open
    debt_line:SetScript("OnShow", show_amount_owed)
    return debt_line
end


-- A copy of one piece of Blizzard's gold box border, same art
local function copy_border_piece(piece, box)
    local copy = box:CreateTexture(nil, "BACKGROUND")
    copy:SetAtlas(piece:GetAtlas())
    return copy
end


-- Attached: the line in a box hanging under the window, in the middle.
-- The box is a copy of the border round the gold in Blizzard's backpack:
-- three pieces, the ends keep their size and the middle stretches between them.
-- It grows to fit what you owe (show_amount_owed).
function shared.hangDebtLineUnder(window)
    local gold_border = ContainerFrame1.MoneyFrame.Border

    local debt_box = shared.makeDebtLine(window)
    debt_box:SetPoint("TOP", window, "BOTTOM", 0, -2)
    debt_box:SetHeight(gold_border.Left:GetHeight())
    debt_box.text:ClearAllPoints()
    debt_box.text:SetPoint("CENTER")
    table.insert(debt_boxes, debt_box)

    local left = copy_border_piece(gold_border.Left, debt_box)
    left:SetSize(gold_border.Left:GetSize())
    left:SetPoint("LEFT")

    local right = copy_border_piece(gold_border.Right, debt_box)
    right:SetSize(gold_border.Right:GetSize())
    right:SetPoint("RIGHT")

    local middle = copy_border_piece(gold_border.Middle, debt_box)
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
end


-- Blizzard's bags. Combined: integrated, in the bottom left of the gold bar,
-- level with your gold on the right, drawn above the bar's border.
-- Separate: attached under the backpack.
local function create_blizzard_bag_lines()
    local gold_bar = ContainerFrameCombinedBags.MoneyFrame
    local debt_line = shared.makeDebtLine(gold_bar)
    debt_line:SetPoint("LEFT", gold_bar, "LEFT", 8, 0)
    debt_line:SetFrameLevel(gold_bar.Border:GetFrameLevel() + 1)

    shared.hangDebtLineUnder(ContainerFrame1)
end


------------------------------------------------------------
-- Events
------------------------------------------------------------

-- Every deeprun message comes here, and goes to the one thing that handles its type
local function listen(message, sender)
    local message_type = strsplit("|", message)

    if message_type == "RDY" and shared.sentByLedgerRank(sender) then
        -- An officer's RDY: this guild runs the Ledger. Turns the bank's buttons on if it's new.
        if tithe_guild ~= GetGuildInfo("player") then
            tithe_guild = GetGuildInfo("player")
            show_amount_owed()
        end
        ledger_ready(message)
        shared.askForBoardIfNoneYet()
        shared.sendAccountID()
    end

    if message_type == "ACK" then
        row_acked(message)
    end

    if message_type == "SET" then
        officer_set_owed(message, sender)
    end

    if message_type == "RNK" and shared.sentByLedgerRank(sender) then
        shared.saveRanks(message)
    end

    if message_type == "WIN" and shared.sentByLedgerRank(sender) then
        shared.saveWinners(message)
    end

    if message_type == "EYE" and shared.sentByGuildMaster(sender) and shared.inConfiguredGuild() then
        shared.answerEye(sender)
    end
end


local tithe_frame = CreateFrame("Frame")
tithe_frame:RegisterEvent("PLAYER_LOGIN")
tithe_frame:RegisterEvent("ADDON_LOADED")
tithe_frame:RegisterEvent("CHAT_MSG_ADDON")
tithe_frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
tithe_frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")

tithe_frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        if guild_debt == nil then
            guild_debt = 0
        end

        if tithe_queue == nil then
            tithe_queue = {}
        end

        if tithe_archive == nil then
            tithe_archive = {}
        end

        if custom_tithe_this_week == nil then
            custom_tithe_this_week = { week_start = 0, paid = 0 }
        end

        -- Until a ledger's RDY brings newer ones
        if tithe_settings == nil then
            tithe_settings = { time = 0, text = shared.settingsText() }
        end

        shared.useSettings(tithe_settings.text)

        C_ChatInfo.RegisterAddonMessagePrefix(shared.prefix)
        C_Timer.NewTicker(30, drain_queue)
        C_Timer.After(5, ask_if_ledger_ready)

        create_blizzard_bag_lines()

        -- Another addon may have loaded the guild bank window already
        if C_AddOns.IsAddOnLoaded("Blizzard_GuildBankUI") then
            create_blizzard_tithe_bar()
        end

    elseif event == "ADDON_LOADED" then
        local loaded_addon_name = ...
        if loaded_addon_name == "Blizzard_GuildBankUI" and blizzard_tithe_bar == nil then
            create_blizzard_tithe_bar()
        end

    elseif event == "CHAT_MSG_ADDON" then
        local message_prefix, message, channel, sender = ...
        if message_prefix == shared.prefix then
            listen(message, sender)
        end

    -- The vendor opens and closes through the interaction manager
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and ... == Enum.PlayerInteractionType.Merchant then
        gray_counts_at_vendor_open = shared.grayCountsInBags()

    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and ... == Enum.PlayerInteractionType.Merchant then
        add_gray_sales_to_debt()
        show_amount_owed()
    end
end)