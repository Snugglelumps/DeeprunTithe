-- Deeprun Shared
-- Everything Deeprun Tithe and Deeprun Ledger have to agree on.
-- Both addons have a copy of this file, and they must stay identical.

local addon_name, shared = ...

shared.prefix = "deeprun"
-- Used until Guild Info says otherwise
shared.tithe_rate = 0.05
shared.trade_good_rate = 2
shared.tithes_start_at_level = 20

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


-- An officer's ledger setting what a player owes, in copper.
-- The time it was made tells a resend apart from a new one.
-- SET|<player>|<time>|<owed>
function shared.setMessage(command)
    return "SET|" .. command.player .. "|" .. command.time .. "|" .. command.owed
end


-- That player's tithe saying it's done
-- DONE|<player>|<time>
function shared.doneMessage(player, command_time)
    return "DONE|" .. player .. "|" .. command_time
end


------------------------------------------------------------
-- Items
------------------------------------------------------------

-- Items count for their vendor price times the trade good rate. Grays count for nothing.
function shared.itemCreditValue(item_id, item_count)
    local item_quality = select(3, C_Item.GetItemInfo(item_id))
    local vendor_price = select(11, C_Item.GetItemInfo(item_id))

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

-- The settings are a [[base64]] code in Guild Info. Decoded, it's key=value; pairs, like r=0.05;t=2;l=20;
-- r is the tithe rate, t is the trade good rate, l is the level tithes start at.
-- Keys can be in any order. A key that's missing or isn't a number comes back nil.
function shared.readSettings(settings_code)
    local settings = C_EncodingUtil.DecodeBase64(settings_code)
    if settings == nil then
        return nil
    end

    local tithe_rate = nil
    local trade_good_rate = nil
    local tithes_start_at_level = nil

    for key, value in string.gmatch(settings, "(%a+)=([^;]*);") do
        if key == "r" then
            tithe_rate = tonumber(value)
        end

        if key == "t" then
            trade_good_rate = tonumber(value)
        end

        if key == "l" then
            tithes_start_at_level = tonumber(value)
        end
    end

    return tithe_rate, trade_good_rate, tithes_start_at_level
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

    -- Only what Guild Info has replaces the defaults
    local tithe_rate, trade_good_rate, tithes_start_at_level = shared.readSettings(settings_code)

    if tithe_rate ~= nil then
        shared.tithe_rate = tithe_rate
    end

    if trade_good_rate ~= nil then
        shared.trade_good_rate = trade_good_rate
    end

    if tithes_start_at_level ~= nil then
        shared.tithes_start_at_level = tithes_start_at_level
    end

    known_settings_code = settings_code
end


local settings_frame = CreateFrame("Frame")
settings_frame:RegisterEvent("PLAYER_LOGIN")
settings_frame:RegisterEvent("GUILD_ROSTER_UPDATE")
-- Opening any NPC window, like the guild bank. GUILDBANKFRAME_OPENED never fires on Forever.
settings_frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")

settings_frame:SetScript("OnEvent", function(self, event, interaction_type)
    -- Guild Info arrives with the roster, so these ask for a fresh one
    if event == "PLAYER_LOGIN" then
        C_GuildInfo.GuildRoster()

    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and interaction_type == Enum.PlayerInteractionType.GuildBanker then
        C_GuildInfo.GuildRoster()

    elseif event == "GUILD_ROSTER_UPDATE" then
        readGuildInfo()
    end
end)
