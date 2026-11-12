-- Deeprun Shared
-- Everything Deeprun Tithe and Deeprun Ledger have to agree on.
-- Both addons have a copy of this file, and they must stay identical.

local addon_name, shared = ...

shared.prefix = "deeprun"
shared.tithe_rate = nil
shared.trade_good_rate = nil

-- The Guild Info code last read, so the same one isn't read twice
local known_settings_code = nil


------------------------------------------------------------
-- Transaction IDs and messages
------------------------------------------------------------

-- time|base64(name|gold|item_id|count)
function shared.makeTransactionID(player_name, deposit_time, gold, item_id, item_count)
    if gold == nil then
        gold = 0
    end

    if item_id == nil then
        item_id = 0
    end

    if item_count == nil then
        item_count = 0
    end

    local plain_id = player_name .. "|" .. gold .. "|" .. item_id .. "|" .. item_count
    return deposit_time .. "|" .. C_EncodingUtil.EncodeBase64(plain_id)
end


-- A ledger says RDY so tithes know someone's listening
function shared.rdyMessage()
    return "RDY"
end


-- ROW|<time>|<base64>|<gold>|<item_id>|<count>
function shared.rowMessage(row)
    return "ROW|" .. row.transactionID .. "|" .. row.gold .. "|" .. row.item_id .. "|" .. row.count
end


-- ACK|<time>|<base64>
function shared.ackMessage(transactionID)
    return "ACK|" .. transactionID
end


------------------------------------------------------------
-- Items
------------------------------------------------------------

-- Items count for their vendor price times the trade good rate. Grays count for nothing.
function shared.itemCreditValue(item_id, item_count)
    local item_quality = select(3, C_Item.GetItemInfo(item_id))
    local vendor_price = select(11, C_Item.GetItemInfo(item_id))

    if shared.trade_good_rate == nil then
        return 0
    end

    if vendor_price == nil then
        return 0
    end

    if item_quality == Enum.ItemQuality.Poor then
        return 0
    end

    return vendor_price * shared.trade_good_rate * item_count
end


------------------------------------------------------------
-- Guild Info settings
------------------------------------------------------------

-- The settings are a [[base64]] code in Guild Info. Decoded, it's key=value; pairs, like r=0.05;t=2;
-- r is the tithe rate and t is the trade good rate.
-- Returns both rates, or nil if it isn't a real code.
function shared.readSettings(settings_code)
    local settings = C_EncodingUtil.DecodeBase64(settings_code)
    if settings == nil then
        return nil
    end

    local tithe_rate = tonumber(string.match(settings, "^r=([^;]*)"))
    if tithe_rate == nil then
        return nil
    end

    local trade_good_rate = tonumber(string.match(settings, ";t=([^;]*)"))
    if trade_good_rate == nil then
        return nil
    end

    return tithe_rate, trade_good_rate
end


local function readGuildInfo()
    if not IsInGuild() then
        return
    end

    -- Reading Guild Info is blocked in combat. The next roster update after the fight reads it.
    if InCombatLockdown() then
        return
    end

    local info_text = C_GuildInfo.GetInfoText()

    if info_text == nil then
        return
    end

    if issecretvalue(info_text) then
        return
    end

    local settings_code = string.match(info_text, "%[%[(.-)%]%]")
    if settings_code == nil then
        return
    end

    if settings_code == known_settings_code then
        return
    end

    local tithe_rate, trade_good_rate = shared.readSettings(settings_code)
    if tithe_rate == nil then
        return
    end

    shared.tithe_rate = tithe_rate
    shared.trade_good_rate = trade_good_rate
    known_settings_code = settings_code
end


local settings_frame = CreateFrame("Frame")
settings_frame:RegisterEvent("PLAYER_LOGIN")
settings_frame:RegisterEvent("GUILD_ROSTER_UPDATE")
settings_frame:RegisterEvent("GUILDBANKFRAME_OPENED")

settings_frame:SetScript("OnEvent", function(self, event)
    -- Guild Info arrives with the roster, so these ask for a fresh one
    if event == "PLAYER_LOGIN" then
        C_GuildInfo.GuildRoster()

    elseif event == "GUILDBANKFRAME_OPENED" then
        C_GuildInfo.GuildRoster()

    elseif event == "GUILD_ROSTER_UPDATE" then
        readGuildInfo()
    end
end)
