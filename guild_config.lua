-- Deeprun guild config
-- Reads the guild's settings from a [[base64]] string in Guild Info, so nothing is hard-coded.
-- Deeprun Tithe and Deeprun Ledger each have a copy of this file, and they must stay identical.
-- Make the string with /drl hash in Deeprun Ledger.
-- Decoded, it looks like: r=0.05;l=9;t=First Treasurer,Second Treasurer;s=<secret bytes>
-- The first treasurer is who tithes get mailed to.

local addon_name, shared = ...

-- Saved per character, so an alt in another guild can't pick up this guild's config
local saved_config_name = addon_name .. "Config"

-- Used until a code says otherwise, and for codes made before l= existed
local default_start_level = 9

shared.tithe_rate = nil
shared.tithes_start_after_level = default_start_level
shared.treasurers = {}
shared.secret = nil


-- Returns the rate, the treasurer list, the secret and the start level, or nil if it isn't a real config
function shared.decodeConfig(encoded_config)
    local decoded_config = C_EncodingUtil.DecodeBase64(encoded_config)
    if decoded_config == nil then
        return nil
    end

    -- The secret is raw bytes, so it stays last and takes everything after s=
    local tithe_rate = tonumber(string.match(decoded_config, "^r=([^;]*)"))
    local treasurer_list = string.match(decoded_config, ";t=([^;]+)")
    local secret = string.match(decoded_config, ";s=(.+)$")
    local tithes_start_after_level = tonumber(string.match(decoded_config, ";l=(%d+)"))

    if tithe_rate == nil then
        return nil
    end

    if treasurer_list == nil then
        return nil
    end

    if secret == nil then
        return nil
    end

    if tithes_start_after_level == nil then
        tithes_start_after_level = default_start_level
    end

    return tithe_rate, treasurer_list, secret, tithes_start_after_level
end


-- Returns false and changes nothing if the string isn't a real config
local function useConfig(encoded_config)
    local tithe_rate, treasurer_list, secret, tithes_start_after_level = shared.decodeConfig(encoded_config)

    if tithe_rate == nil then
        return false
    end

    local treasurers = {}
    for treasurer in string.gmatch(treasurer_list, "[^,]+") do
        table.insert(treasurers, treasurer)
    end

    shared.tithe_rate = tithe_rate
    shared.tithes_start_after_level = tithes_start_after_level
    shared.treasurers = treasurers
    shared.secret = secret

    return true
end


-- Guild Info can come back empty early on. Only a valid string replaces what we have.
local function readGuildInfo()
    if not IsInGuild() then
        return
    end

    local info_text = C_GuildInfo.GetInfoText()

    if info_text == nil then
        return
    end

    if issecretvalue(info_text) then
        return
    end

    local encoded_config = string.match(info_text, "%[%[(.-)%]%]")
    if encoded_config == nil then
        return
    end

    if useConfig(encoded_config) then
        _G[saved_config_name] = encoded_config
    end
end


local config_events = CreateFrame("Frame")
config_events:RegisterEvent("PLAYER_LOGIN")
config_events:RegisterEvent("GUILD_ROSTER_UPDATE")
config_events:RegisterEvent("MAIL_SHOW")

config_events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- The saved copy works straight away. Fresh data arrives as GUILD_ROSTER_UPDATE.
        if _G[saved_config_name] ~= nil then
            useConfig(_G[saved_config_name])
        end
        C_GuildInfo.GuildRoster()

    elseif event == "GUILD_ROSTER_UPDATE" then
        readGuildInfo()

    elseif event == "MAIL_SHOW" then
        C_GuildInfo.GuildRoster()
    end
end)
