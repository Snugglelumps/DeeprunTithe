-- Deeprun Tithe

-- shared.sha256 comes from sha256.lua
-- shared.tithe_rate, shared.tithes_start_after_level, shared.treasurers and shared.secret come from guild_config.lua
local addon_name, shared = ...

-- Settings
local tithe_subject = "Deeprun Tithe"
local goods_multiplier = 3
local postage_refund = 30 -- copper. Added to every tithe, so the guild covers the stamp.

local pending_credit = 0
local pending_transaction_id = nil

-- The bar in the gap beside the mailbox tabs
local tithe_bar = nil
local pay_button = nil
local seconds_since_refresh = 0
local refresh_every_seconds = 0.2


-- UnitName gives first name and surname separately. Mail shows them joined by a space.
local function fullPlayerName()
    local first_name, surname = UnitName("player")

    if surname == nil then
        return first_name
    end

    if surname == "" then
        return first_name
    end

    return first_name .. " " .. surname
end


-- Same function as DeeprunLedger
local function makeTransactionID(sent_time, player_name)
    local full_hash = shared.sha256(sent_time .. player_name .. shared.secret)
    return sent_time .. "-" .. string.sub(full_hash, 1, 10)
end


local function itemTitheValue(item_id, stack_count, item_quality)
    local item_class_id = select(12, C_Item.GetItemInfo(item_id))
    local vendor_price = select(11, C_Item.GetItemInfo(item_id))

    if vendor_price == nil then
        return 0
    end

    -- Grays make debt but don't pay it. Vendoring one gives the same gold without the postage.
    if item_quality == Enum.ItemQuality.Poor then
        return 0
    end

    if item_class_id == Enum.ItemClass.Tradegoods then
        return vendor_price * stack_count * goods_multiplier
    end

    return 0
end


local function attachedItemsTitheValue()
    local items_value = 0

    for slot = 1, ATTACHMENTS_MAX_SEND do
        if HasSendMailItem(slot) then
            local item_name, item_id, item_texture, stack_count, item_quality = GetSendMailItem(slot)
            items_value = items_value + itemTitheValue(item_id, stack_count, item_quality)
        end
    end

    return items_value
end


-- Treasurers don't pay tithes
local function playerIsTreasurer()
    for treasurer_number, treasurer in ipairs(shared.treasurers) do
        if fullPlayerName() == treasurer then
            return true
        end
    end

    return false
end


-- Debt is kept at full junk value, so it tracks fine before the rate is known
local function amountOwed()
    return math.floor(guild_debt * shared.tithe_rate)
end

-- THE boy
local function on_loot_message(loot_text)
    if playerIsTreasurer() then
        return
    end

    if UnitLevel("player") <= shared.tithes_start_after_level then
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


local function moneyText(copper)
    if copper == 0 then
        return "0"
    end
    return GetMoneyString(copper)
end


-- The gold typed into the mail so far. C.O.D. isn't payment, so it counts as none.
local function goldInMail()
    if not SendMailSendMoneyButton:GetChecked() then
        return 0
    end

    return MoneyInputFrame_GetCopper(SendMailMoney)
end


-- The gold that covers whatever the attached items don't
local function goldToPay(amount_owed, items_value)
    local gold_needed = amount_owed - items_value

    if gold_needed < 0 then
        return 0
    end

    return gold_needed
end


-- True once the button has filled in this mail
local function mailIsFilledIn()
    if pending_transaction_id == nil then
        return false
    end

    if not string.find(SendMailSubjectEditBox:GetText(), pending_transaction_id, 1, true) then
        return false
    end

    return true
end


local function update_pay_button(amount_owed, items_value)
    local gold_to_pay = goldToPay(amount_owed, items_value)
    local gold_needed = amount_owed - items_value

    pay_button:Enable()

    if mailIsFilledIn() then
        if goldInMail() == gold_to_pay then
            pay_button:SetText("Ready, click Send")
            pay_button:Disable()
            return
        end

        pay_button:SetText("Update gold: " .. moneyText(gold_to_pay))
        return
    end

    if gold_needed < 0 then
        pay_button:SetText("Covered, +" .. moneyText(-gold_needed) .. " credit")
        return
    end

    if gold_needed == 0 then
        pay_button:SetText("Covered, fill in mail")
        return
    end

    pay_button:SetText("Pay " .. moneyText(gold_to_pay))
end


-- Overpaying leaves guild_debt below zero, which is credit towards future tithes
local function tithe_credit()
    if guild_debt >= 0 then
        return 0
    end

    -- The postage refund stays hidden. It just quietly covers the next bit of debt.
    local credit = math.floor(-guild_debt * shared.tithe_rate) - postage_refund

    if credit < 0 then
        return 0
    end

    return credit
end


local function update_tithe_bar()
    -- Hidden with alpha, because really hiding it would stop these checks from running
    if not IsInGuild() then
        tithe_bar:SetAlpha(0)
        pay_button:Hide()
        return
    end

    if playerIsTreasurer() then
        tithe_bar:SetAlpha(0)
        pay_button:Hide()
        return
    end

    tithe_bar:SetAlpha(1)
    pay_button:Show()

    if shared.tithe_rate == nil then
        tithe_bar:SetValue(0)
        pay_button:SetText("Not set up")
        pay_button:Disable()
        return
    end

    local amount_owed = amountOwed()

    if amount_owed <= 0 then
        tithe_bar:SetMinMaxValues(0, 1)
        tithe_bar:SetValue(1)
        tithe_bar:SetStatusBarColor(0.25, 0.8, 0.4, 0.4)

        pay_button:Disable()

        if tithe_credit() > 0 then
            pay_button:SetText("Credit " .. moneyText(tithe_credit()))
            return
        end

        pay_button:SetText("All paid up")
        return
    end

    local items_value = attachedItemsTitheValue()
    local amount_covered = items_value + goldInMail()

    tithe_bar:SetMinMaxValues(0, amount_owed)
    tithe_bar:SetValue(amount_covered)

    update_pay_button(amount_owed, items_value)

    if amount_covered >= amount_owed then
        tithe_bar:SetStatusBarColor(0.25, 0.8, 0.4, 0.4)
    else
        tithe_bar:SetStatusBarColor(1, 0.82, 0, 0.4)
    end
end


-- Fills in the mail. Gold covers whatever the attached items don't. The player still clicks Send.
local function fill_tithe_mail()
    local amount_owed = amountOwed()

    if amount_owed <= 0 then
        return
    end

    -- The bar shows on the Inbox tab too, and the mail can only be filled in on Send
    if not SendMailFrame:IsShown() then
        MailFrameTab_OnClick(nil, 2)
    end

    pending_transaction_id = makeTransactionID(GetServerTime(), fullPlayerName())

    SendMailNameEditBox:SetText(shared.treasurers[1])
    -- The ID goes in the subject so the ledger can check it without opening the mail
    SendMailSubjectEditBox:SetText(tithe_subject .. " " .. pending_transaction_id)
    SendMailBodyEditBox:SetText("")
    SendMailSendMoneyButton:SetChecked(true)
    SendMailCODButton:SetChecked(false)

    MoneyInputFrame_SetCopper(SendMailMoney, goldToPay(amount_owed, attachedItemsTitheValue()))

    update_tithe_bar()
end


-- The detail that doesn't fit on the bar. Items worth nothing are dimmed.
local function show_tithe_tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Deeprun Tithe")

    if shared.tithe_rate == nil then
        GameTooltip:AddLine("Waiting for a code in Guild Info", 1, 1, 1)
        GameTooltip:Show()
        return
    end

    local amount_owed = amountOwed()

    if amount_owed <= 0 then
        GameTooltip:AddDoubleLine("Credit", moneyText(tithe_credit()), 1, 1, 1, 1, 1, 1)
        GameTooltip:Show()
        return
    end

    local amount_attached = attachedItemsTitheValue() + goldInMail()

    GameTooltip:AddDoubleLine("Owed", moneyText(amount_owed), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Attached", moneyText(amount_attached), 1, 1, 1, 1, 1, 1)

    for slot = 1, ATTACHMENTS_MAX_SEND do
        if HasSendMailItem(slot) then
            local item_name, item_id, item_texture, stack_count, item_quality = GetSendMailItem(slot)
            local item_value = itemTitheValue(item_id, stack_count, item_quality)
            local item_text = "  " .. item_name .. " x" .. stack_count

            if item_value == 0 then
                GameTooltip:AddDoubleLine(item_text, "0", 0.5, 0.5, 0.5, 0.5, 0.5, 0.5)
            else
                GameTooltip:AddDoubleLine(item_text, moneyText(item_value), 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
            end
        end
    end

    local amount_remaining = amount_owed - amount_attached
    if amount_remaining < 0 then
        amount_remaining = 0
    end

    GameTooltip:AddDoubleLine("Remaining", moneyText(amount_remaining), 1, 0.82, 0, 1, 0.82, 0)
    GameTooltip:Show()
end


local function hide_tithe_tooltip()
    GameTooltip:Hide()
end


-- Checked a few times a second, because typing gold doesn't fire any event.
-- It only runs while the mailbox is open.
local function on_bar_update(self, elapsed)
    seconds_since_refresh = seconds_since_refresh + elapsed

    if seconds_since_refresh < refresh_every_seconds then
        return
    end

    seconds_since_refresh = 0
    update_tithe_bar()
end


-- Sits in the gap to the right of the tabs, on both the Inbox and Send Mail tabs.
-- Anchored to the tab and the mailbox's corner, so it fills exactly that gap.
local function create_tithe_bar()
    tithe_bar = CreateFrame("StatusBar", nil, MailFrame)
    tithe_bar:SetPoint("BOTTOMLEFT", MailFrameTab2, "BOTTOMRIGHT", 4, 4)
    tithe_bar:SetPoint("TOPRIGHT", MailFrame, "BOTTOMRIGHT", -2, -2)
    tithe_bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")

    local background = tithe_bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.05, 0.05, 0.06, 0.97)

    -- The button sits on top of the bar, so the gold fills up behind its text
    pay_button = CreateFrame("Button", nil, tithe_bar)
    pay_button:SetAllPoints()
    pay_button:SetNormalFontObject("GameFontHighlightSmall")
    pay_button:SetDisabledFontObject("GameFontHighlightSmall")
    pay_button:SetText("All paid up")
    pay_button:SetScript("OnClick", fill_tithe_mail)
    pay_button:SetScript("OnEnter", show_tithe_tooltip)
    pay_button:SetScript("OnLeave", hide_tithe_tooltip)

    local hover = pay_button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.08)

    tithe_bar:SetScript("OnUpdate", on_bar_update)
end


-- Runs right after Send is clicked, while the gold and items are still attached.
-- Only counts once MAIL_SEND_SUCCESS fires.
hooksecurefunc("SendMail", function(recipient, subject, body)
    pending_credit = 0

    if pending_transaction_id == nil then
        return
    end

    if string.lower(recipient) ~= string.lower(shared.treasurers[1]) then
        return
    end

    if not string.find(subject, pending_transaction_id, 1, true) then
        return
    end

    if GetSendMailCOD() > 0 then
        return
    end

    local tithe_paid = GetSendMailMoney() + attachedItemsTitheValue() + postage_refund

    pending_credit = tithe_paid / shared.tithe_rate
end)


local tithe_frame = CreateFrame("Frame")
tithe_frame:RegisterEvent("PLAYER_LOGIN")
tithe_frame:RegisterEvent("CHAT_MSG_LOOT")
tithe_frame:RegisterEvent("MAIL_SEND_SUCCESS")
tithe_frame:RegisterEvent("MAIL_FAILED")

tithe_frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        if guild_debt == nil then
            guild_debt = 0
        end
        create_tithe_bar()

    elseif event == "CHAT_MSG_LOOT" then
        on_loot_message(...)

    elseif event == "MAIL_SEND_SUCCESS" then
        guild_debt = guild_debt - pending_credit
        pending_credit = 0
        pending_transaction_id = nil
        update_tithe_bar()

    elseif event == "MAIL_FAILED" then
        pending_credit = 0
    end
end)
