-- Deeprun Tithe

-- The prefix, settings, transaction IDs and messages come from DeeprunShared.lua
local addon_name, shared = ...

-- Saved per character (see DeeprunTithe.toc):
--   guild_debt     full vendor value of junk looted. What you owe is guild_debt * tithe_rate.
--   tithe_queue    deposits not yet confirmed by a ledger, oldest first
--   tithe_archive  deposits a ledger has confirmed, kept for exporting later
-- A queued row: { transactionID = "time|base64", time = ..., gold = ..., item_id = ..., count = ... }

local last_rdy_time = 0        -- GetTime() when a ledger last said RDY
local waiting_for_ack = nil    -- the transactionID sent and not yet ACKed
local sent_time = 0            -- GetTime() when that row was sent

-- What's on the cursor, remembered when it's picked up,
-- because by the time DeleteCursorItem's hook runs the item is gone
local cursor_item_id = nil
local cursor_item_count = 0

-- A bag item dropped on a guild bank slot, waiting for the slot to show it landed
local pending_bank_deposit = nil

local DeeprunDeposit = nil     -- the Pay Tithe button on the guild bank
local mail_sign = nil
local rules_card = nil         -- the rule under the tithe bar, until it's accepted
local rules_popup = nil


------------------------------------------------------------
-- Debt
------------------------------------------------------------

-- Looting junk adds its vendor value to guild_debt
local function on_loot_message(loot_text)
    if UnitLevel("player") < shared.tithes_start_at_level then
        return
    end

    if issecretvalue(loot_text) then
        return
    end

    local is_my_loot = string.find(loot_text, "^You receive loot")
    if not is_my_loot then
        return
    end

    local item_link = string.match(loot_text, "|c.-|h|r")
    local item_quality = select(3, C_Item.GetItemInfo(item_link))
    if item_quality ~= Enum.ItemQuality.Poor then
        return
    end

    local quantity = tonumber(string.match(loot_text, "|rx(%d+)")) or 1
    local vendor_price = select(11, C_Item.GetItemInfo(item_link))

    guild_debt = guild_debt + vendor_price * quantity
end


local function remember_cursor_item()
    cursor_item_id = nil
    cursor_item_count = 0

    local item_location = C_Cursor.GetCursorItem()
    if item_location == nil then
        return
    end

    if not item_location:IsValid() then
        return
    end

    cursor_item_id = C_Item.GetItemID(item_location)
    cursor_item_count = C_Item.GetStackCount(item_location)
end


-- Deleting junk takes its vendor value back off guild_debt
local function on_item_deleted()
    if cursor_item_id == nil then
        return
    end

    local item_quality = select(3, C_Item.GetItemInfo(cursor_item_id))
    if item_quality ~= Enum.ItemQuality.Poor then
        return
    end

    local vendor_price = select(11, C_Item.GetItemInfo(cursor_item_id))
    guild_debt = guild_debt - vendor_price * cursor_item_count

    if guild_debt < 0 then
        guild_debt = 0
    end

    cursor_item_id = nil
end


------------------------------------------------------------
-- Transaction IDs and the queue
------------------------------------------------------------

-- Makes the row for one deposit and puts it in the queue
local function record_deposit(gold, item_id, item_count)
    local deposit_time = GetServerTime()

    table.insert(tithe_queue, {
        -- Full "First Last" name, the same as the sender the ledger sees
        transactionID = shared.makeTransactionID(GetUnitName("player", true), deposit_time, gold, item_id, item_count),
        time = deposit_time,
        gold = gold,
        item_id = item_id,
        count = item_count,
    })
end


local function record_item_deposit(item_id, item_count)
    record_deposit(0, item_id, item_count)
end


------------------------------------------------------------
-- Talking to the ledgers
------------------------------------------------------------

local function send(message)
    C_ChatInfo.SendAddonMessage(shared.prefix, message, "GUILD")
end


local function RDY_listen(message)
    if message == shared.rdyMessage() then
        last_rdy_time = GetTime()
    end
end


local function archive(row)
    table.insert(tithe_archive, row)
    table.remove(tithe_queue, 1)
end


-- Sends the oldest queued row. One row is in flight at a time.
local function drain_queue()
    -- No ledger has said RDY in the last 6 minutes
    if GetTime() - last_rdy_time > 360 then
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


local function row_acked(message)
    if waiting_for_ack == nil then
        return
    end

    if message ~= shared.ackMessage(waiting_for_ack) then
        return
    end

    archive(tithe_queue[1])
    waiting_for_ack = nil

    -- Send the next one right away instead of waiting for the next tick
    drain_queue()
end


------------------------------------------------------------
-- Depositing
------------------------------------------------------------

local function update_bank_button()
    if DeeprunDeposit == nil then
        return
    end

    local amount_owed = math.floor(guild_debt * shared.tithe_rate)

    if amount_owed <= 0 then
        DeeprunDeposit:SetText("All paid up")
        return
    end

    DeeprunDeposit:SetText("Pay Tithe: " .. GetMoneyString(amount_owed))
end


-- Covering what's owed wipes the debt. Less than that just lowers it.
local function pay_off_debt(copper)
    local amount_owed = math.floor(guild_debt * shared.tithe_rate)

    if copper >= amount_owed then
        guild_debt = 0
    else
        guild_debt = guild_debt - copper / shared.tithe_rate
    end
end


-- Only gold paid through our buttons counts. Blizzard's own Deposit is left alone,
-- so treasurers can move guild gold in and out without it counting as anyone's tithe.
-- Assumes the deposit went through. The ledger's bank check catches any that didn't.
local function pay_tithe(copper)
    if GetMoney() < copper then
        print("Deeprun Tithe: you don't have that much gold.")
        return
    end

    DepositGuildBankMoney(copper)
    pay_off_debt(copper)
    record_deposit(copper, 0, 0)
    update_bank_button()
end


-- Pay Tithe: exactly what's owed. Asks first if it's more than a tenth of your gold.
local function pay_what_is_owed(confirmed)
    local amount_owed = math.floor(guild_debt * shared.tithe_rate)

    if amount_owed <= 0 then
        return
    end

    if confirmed == nil then
        if amount_owed > GetMoney() * 0.1 then
            StaticPopup_Show("DEEPRUN_DEPOSIT_POPUP", GetMoneyString(amount_owed))
            return
        end
    end

    pay_tithe(amount_owed)
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
local custom_tithe_frame = nil
local gold_box = nil
local silver_box = nil
local copper_box = nil


local function pay_typed_amount()
    local gold = tonumber(gold_box:GetText()) or 0
    local silver = tonumber(silver_box:GetText()) or 0
    local copper = tonumber(copper_box:GetText()) or 0

    custom_tithe_frame:Hide()

    local amount = gold * 10000 + silver * 100 + copper
    if amount > 0 then
        pay_tithe(amount)
    end
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

    local tithe_button = CreateFrame("Button", nil, custom_tithe_frame, "UIPanelButtonTemplate")
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
    custom_tithe_frame:Show()
    gold_box:SetFocus()
end


local function on_item_deposited(item_id, item_count)
    pay_off_debt(shared.itemCreditValue(item_id, item_count))
    record_item_deposit(item_id, item_count)
    update_bank_button()
end


-- How many of this item are in a guild bank slot
local function bank_slot_count(tab, slot, item_id)
    local item_link = GetGuildBankItemLink(tab, slot)
    if item_link == nil then
        return 0
    end

    if C_Item.GetItemInfoInstant(item_link) ~= item_id then
        return 0
    end

    local texture, item_count = GetGuildBankItemInfo(tab, slot)
    return item_count
end


-- Dragging a bag item onto a guild bank slot.
-- cursor_item_id is only set for bag items, so moving things around inside the bank doesn't count.
-- A split stack's size isn't known from the cursor, so the slot gets counted before and after.
hooksecurefunc("PickupGuildBankItem", function(tab, slot)
    if cursor_item_id == nil then
        return
    end

    pending_bank_deposit = {
        tab = tab,
        slot = slot,
        item_id = cursor_item_id,
        count_before = bank_slot_count(tab, slot, cursor_item_id),
    }
end)


local function check_bank_deposit()
    if pending_bank_deposit == nil then
        return
    end

    local count_after = bank_slot_count(pending_bank_deposit.tab, pending_bank_deposit.slot, pending_bank_deposit.item_id)
    local item_count = count_after - pending_bank_deposit.count_before

    -- Hasn't landed yet
    if item_count <= 0 then
        return
    end

    on_item_deposited(pending_bank_deposit.item_id, item_count)
    pending_bank_deposit = nil
end


-- Right-clicking a bag item while the guild bank is open puts it in the bank
hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
    if GuildBankFrame == nil then
        return
    end

    if not GuildBankFrame:IsShown() then
        return
    end

    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info == nil then
        return
    end

    on_item_deposited(info.itemID, info.stackCount)
end)


hooksecurefunc("DeleteCursorItem", on_item_deleted)


------------------------------------------------------------
-- Buttons
------------------------------------------------------------

-- A flat dark button on the tithe bar, lighter when you hover it
local function make_bar_button(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetNormalFontObject("GameFontHighlightSmall")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.05, 0.05, 0.06, 0.97)

    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.08)

    return button
end


-- The popup the card's checkbox opens: the rule in more detail, and Accept.
-- Accepting hides the card for good on this account (tithe_rules_accepted).
local function create_rules_popup()
    rules_popup = CreateFrame("Frame", "DeeprunRulesPopup", UIParent, "BackdropTemplate")
    rules_popup:SetWidth(340)
    rules_popup:SetPoint("TOP", UIParent, "TOP", 0, -135)
    rules_popup:SetFrameStrata("DIALOG")
    rules_popup:EnableMouse(true)
    rules_popup:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    table.insert(UISpecialFrames, "DeeprunRulesPopup")

    local title = rules_popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", rules_popup, "TOP", 0, -22)
    title:SetText("|TInterface\\MoneyFrame\\UI-GoldIcon:0|t Paying your tithe")

    local details = rules_popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    details:SetPoint("TOP", title, "BOTTOM", 0, -12)
    details:SetWidth(290)
    details:SetJustifyH("LEFT")
    details:SetSpacing(3)
    details:SetText(
        "Only gold paid with the |cffffd100Pay Tithe|r and |cffffd100Pay Custom Tithe|r buttons counts as tithe.\n\n"
        .. "Gold you put in with the bank's own Deposit button isn't recorded, and won't lower what you owe. "
        .. "Gold taken out with Withdraw isn't tracked either.\n\n"
        .. "Trade goods you drop into the bank still count.\n\n"
        .. "|cffffd100Is that okay?|r")

    local accept_button = CreateFrame("Button", nil, rules_popup, "UIPanelButtonTemplate")
    accept_button:SetSize(110, 22)
    accept_button:SetPoint("BOTTOMRIGHT", rules_popup, "BOTTOM", -4, 18)
    accept_button:SetText("Accept")
    accept_button:SetScript("OnClick", function()
        tithe_rules_accepted = true
        rules_popup:Hide()
        rules_card:Hide()
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
        rules_card.got_it:SetChecked(false)
    end)

    rules_popup:SetHeight(22 + title:GetStringHeight() + 12 + details:GetStringHeight() + 58)
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
    rules_card = CreateFrame("Frame", nil, GuildBankFrame, "BackdropTemplate")
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
    rule:SetText("Only gold paid with the |cffffd100buttons above|r counts as tithe. Trade goods you drop in the bank count too.")

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


-- The guild bank window only exists once Blizzard_GuildBankUI has loaded.
-- Same look as the mail sign, in the gap to the right of the bank's tabs:
-- Pay Tithe on the left two thirds, Pay Custom Tithe on the right third.
local function create_bank_button()
    local tithe_bar = CreateFrame("Frame", nil, GuildBankFrame)
    tithe_bar:SetPoint("BOTTOMLEFT", GuildBankFrameTab4, "BOTTOMRIGHT", 4, 4)
    tithe_bar:SetPoint("TOPRIGHT", GuildBankFrame, "BOTTOMRIGHT", -2, -2)

    local custom_button = make_bar_button(tithe_bar)
    custom_button:SetPoint("TOPRIGHT")
    custom_button:SetPoint("BOTTOMRIGHT")
    custom_button:SetText("Pay Custom Tithe")
    custom_button:SetScript("OnClick", show_custom_tithe_frame)

    -- A 4 pixel gap between them so they don't touch
    DeeprunDeposit = make_bar_button(tithe_bar)
    DeeprunDeposit:SetPoint("TOPLEFT")
    DeeprunDeposit:SetPoint("BOTTOMRIGHT", custom_button, "BOTTOMLEFT", -4, 0)
    DeeprunDeposit:SetScript("OnClick", function()
        pay_what_is_owed()
    end)

    -- The bar's width isn't known until the bank lays itself out
    tithe_bar:SetScript("OnSizeChanged", function(self, width)
        custom_button:SetWidth((width - 4) / 3)
    end)

    tithe_bar:SetScript("OnShow", update_bank_button)
    update_bank_button()

    create_rules_card(tithe_bar)
end


-- Where the old pay bar was, beside the mailbox tabs. Just a sign now, tithes go in the guild bank.
local function create_mail_sign()
    mail_sign = CreateFrame("Frame", nil, MailFrame)
    mail_sign:SetPoint("BOTTOMLEFT", MailFrameTab2, "BOTTOMRIGHT", 4, 4)
    mail_sign:SetPoint("TOPRIGHT", MailFrame, "BOTTOMRIGHT", -2, -2)

    local background = mail_sign:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.05, 0.05, 0.06, 0.97)

    local text = mail_sign:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetAllPoints()
    text:SetText("Pay tithes at the guild bank")
end


------------------------------------------------------------
-- Events
------------------------------------------------------------

local tithe_frame = CreateFrame("Frame")
tithe_frame:RegisterEvent("PLAYER_LOGIN")
tithe_frame:RegisterEvent("ADDON_LOADED")
tithe_frame:RegisterEvent("CHAT_MSG_LOOT")
tithe_frame:RegisterEvent("CHAT_MSG_ADDON")
tithe_frame:RegisterEvent("CURSOR_CHANGED")
tithe_frame:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
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

        C_ChatInfo.RegisterAddonMessagePrefix(shared.prefix)
        C_Timer.NewTicker(30, drain_queue)

        create_mail_sign()

        -- Another addon may have loaded the guild bank window already
        if C_AddOns.IsAddOnLoaded("Blizzard_GuildBankUI") then
            create_bank_button()
        end

    elseif event == "ADDON_LOADED" then
        local loaded_addon_name = ...
        if loaded_addon_name == "Blizzard_GuildBankUI" and DeeprunDeposit == nil then
            create_bank_button()
        end

    elseif event == "CHAT_MSG_LOOT" then
        on_loot_message(...)

    elseif event == "CHAT_MSG_ADDON" then
        local message_prefix, message = ...
        if message_prefix == shared.prefix then
            RDY_listen(message)
            row_acked(message)
        end

    elseif event == "CURSOR_CHANGED" then
        remember_cursor_item()

    elseif event == "GUILDBANKBAGSLOTS_CHANGED" then
        check_bank_deposit()

    -- A drop that never landed shouldn't pick up someone else's deposit later
    -- The bank closing. GUILDBANKFRAME_CLOSED never fires on Forever.
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and ... == Enum.PlayerInteractionType.GuildBanker then
        pending_bank_deposit = nil
    end
end)