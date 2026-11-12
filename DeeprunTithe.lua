-- Deeprun Tithe

-- The prefix, tithe rate, transaction IDs and messages come from DeeprunShared.lua
local addon_name, shared = ...

-- Settings
local tithes_start_after_level = 10

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

local DeeprunDeposit = nil     -- the button on the guild bank
local mail_button = nil


------------------------------------------------------------
-- Debt
------------------------------------------------------------

-- Looting junk adds its vendor value to guild_debt
local function on_loot_message(loot_text)
    if UnitLevel("player") <= tithes_start_after_level then
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

    if shared.tithe_rate == nil then
        DeeprunDeposit:SetText("Not set up")
        return
    end

    local amount_owed = math.floor(guild_debt * shared.tithe_rate)

    if amount_owed <= 0 then
        DeeprunDeposit:SetText("All paid up")
        return
    end

    DeeprunDeposit:SetText("Pay Tithe: " .. GetMoneyString(amount_owed))
end


local function deposit_tithe(confirmed)
    if shared.tithe_rate == nil then
        return
    end

    local deposit = math.floor(guild_debt * shared.tithe_rate)

    if deposit <= 0 then
        return
    end

    if GetMoney() < deposit then
        print("Deeprun Tithe: you don't have enough gold to cover the tithe.")
        return
    end

    if confirmed == nil then
        if deposit > GetMoney() * 0.1 then
            StaticPopup_Show("DEEPRUN_DEPOSIT_POPUP", GetMoneyString(deposit))
            return
        end
    end

    -- The DepositGuildBankMoney hook below records it and lowers the debt
    DepositGuildBankMoney(deposit)
end


StaticPopupDialogs["DEEPRUN_DEPOSIT_POPUP"] = {
    text = "Deposit %s into the guild bank?",
    button1 = "Deposit",
    button2 = "Cancel",
    OnAccept = function()
        deposit_tithe(true)
    end,
    timeout = 0,
    hideOnEscape = true,
}


-- Covering what's owed wipes the debt. Less than that just lowers it.
local function pay_off_debt(copper)
    -- No rate yet means no way to turn copper back into debt. The queued row still has the deposit.
    if shared.tithe_rate == nil then
        return
    end

    local amount_owed = math.floor(guild_debt * shared.tithe_rate)

    if copper >= amount_owed then
        guild_debt = 0
    else
        guild_debt = guild_debt - copper / shared.tithe_rate
    end
end


-- Every gold deposit goes through here: the DeeprunDeposit button and Blizzard's own deposit box.
-- Assumes the deposit went through. The ledger's bank check catches any that didn't.
hooksecurefunc("DepositGuildBankMoney", function(copper)
    pay_off_debt(copper)
    record_deposit(copper, 0, 0)
    update_bank_button()
end)


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

-- The guild bank window only exists once Blizzard_GuildBankUI has loaded
local function create_bank_button()
    DeeprunDeposit = CreateFrame("Button", nil, GuildBankFrame, "UIPanelButtonTemplate")
    DeeprunDeposit:SetSize(300, 26)
    DeeprunDeposit:SetPoint("BOTTOM", GuildBankFrame, "TOP", 0, 4)
    DeeprunDeposit:SetScript("OnClick", function()
        deposit_tithe()
    end)
    DeeprunDeposit:SetScript("OnShow", update_bank_button)
    update_bank_button()
end


local function create_mail_button()
    mail_button = CreateFrame("Button", nil, MailFrame, "UIPanelButtonTemplate")
    mail_button:SetSize(300, 26)
    mail_button:SetPoint("BOTTOM", MailFrame, "TOP", 0, 4)
    mail_button:SetText("Deposit in the Guild Bank")
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
tithe_frame:RegisterEvent("GUILDBANKFRAME_CLOSED")

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

        create_mail_button()

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
    elseif event == "GUILDBANKFRAME_CLOSED" then
        pending_bank_deposit = nil
    end
end)