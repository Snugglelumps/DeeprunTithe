-- Deeprun Tithe: telemetry, for the Guild Master's Ring
-- EYE from the Guild Master asks every tithe how it's doing. We whisper back SEE, so nobody
-- else hears it. It only reads: nothing about this character or account can be changed by it.
-- DeeprunTithe.lua checks who's asking before it calls answerEye.
--
-- The keys in SEE. Money is in copper. have/need pairs are toward the next level, and a need
-- of 0 means that level doesn't ask for it.
--   v     this addon's version
--   id    account ID
--   lv    tithe level
--   d     days since the first tithe, have/need
--   g     total paid, have/need
--   s     longest streak that counts toward the next level, have/need
--   cs    the streak still going
--   p     payments, have/need
--   f     failed rolls at this level
--   o     owed now, this character
--   u     unsold looted greys' full value
--   c     custom tithes paid this week, this character
--   q     payments waiting for a ledger, this character
--   r     seconds since the last RDY, -1 for none since login
--   t     when the settings in use were made, 0 for never received

local addon_name, shared = ...

-- Settings
-- Everyone online hears EYE at once. Spread out so the answers don't all land together.
local answer_within_seconds = 10


-- The level progress. Nothing here until the first tithe.
local function progress_text()
    if tithe_history == nil then
        return "lv=0;"
    end

    local progress = shared.titheProgress(shared.titheLevel() + 1)

    return "lv=" .. shared.titheLevel()
        .. ";d=" .. progress.days .. "/" .. progress.days_needed
        .. ";g=" .. progress.gold .. "/" .. progress.gold_needed
        .. ";s=" .. progress.streak .. "/" .. progress.streak_needed
        .. ";cs=" .. progress.current_streak
        .. ";p=" .. progress.payments .. "/" .. progress.payments_needed
        .. ";f=" .. (tithe_history.failed_rolls or 0) .. ";"
end


local function telemetry_text()
    return "v=" .. C_AddOns.GetAddOnMetadata(addon_name, "Version")
        .. ";id=" .. deeprun_client_id
        .. ";" .. progress_text()
        .. "o=" .. shared.amountOwed()
        .. ";u=" .. shared.unsoldGrayValue()
        .. ";c=" .. shared.customTithePaidThisWeek()
        .. ";q=" .. #tithe_queue
        .. ";r=" .. shared.secondsSinceReady()
        .. ";t=" .. tithe_settings.time .. ";"
end


function shared.answerEye(guild_master)
    C_Timer.After(math.random() * answer_within_seconds, function()
        C_ChatInfo.SendAddonMessage(shared.prefix, shared.seeMessage(telemetry_text()), "WHISPER", guild_master)
    end)
end
