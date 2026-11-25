-- Deeprun Tithe: notices, the reminder when you haven't paid
-- Meant to catch someone who has actually forgotten, and never to nag.
-- After the character has been logged in for an hour, a cryptic notice shows if:
--   they're in a guild that runs the Ledger (shared.inConfiguredGuild)
--   it's been a day or more since our last contact (see last_contact)
--   they owe at least their level in silver: 25 silver at level 25
--   they're out of combat (if they're fighting, it waits until they stop)
--   no memo, communique or archive is on screen (if one is, it looks again in 30 seconds)
-- It checks once per session. So the most anyone sees is one reminder every two days,
-- and only after an hour of play.
--
-- Outside a guild that runs the Ledger (an alt, or no guild), the notice is one of the
-- outsider notices instead: Deeprun calling them in. Every 3 days, the same hour in,
-- owing or not. They share last_reminder with the reminders, so one doesn't follow
-- right on the other's heels.
--
-- Saved per character (see DeeprunTithe.toc):
--   tithe_reminder = {
--       session_start = time,     when this session's login happened
--       checked = true/false,     this session's check has run
--       last_reminder = time,     when the last reminder showed, 0 if never
--   }
-- A /reload restarts every timer, so the login time is saved to keep the hour counting
-- from the real login, and checked stops a reload from running the check twice.

local addon_name, shared = ...

-- Settings
local minutes_logged_in = 60
local hours_between_contact = 48
local hours_between_outsider_notices = 72
local busy_retry_seconds = 30


local notices = {
    [[Someone was asking about you at the bank.]],
    [[The collectors have your scent.]],
    [[Your coin purse feels heavier than it should.]],
    [[Your tithe 'participation' has been noted.]],
    [[The vault is missing something...]],
    [[Jonathan is displeased]],
}


-- For someone outside Deeprun. Plainer than the ones above: they don't know us yet.
local outsider_notices = {
    [[You walk alone, and your coin serves no one. Deeprun Freight Co. could change that.]],
    [[Jonathan Deeprun keeps a ledger of the faithful. Your name is not in it. Yet.]],
    [[Somewhere, a guild bank waits for your offering. Seek out Deeprun Freight Co.]],
    [[The members of Deeprun Freight Co. never wander without purpose. Ask one how to join.]],
    [[You carry the Tithe, but you tithe to no one. That is a waste Jonathan cannot abide.]],
    [[Deeprun Freight Co. has noticed you. There is a place for you among us, if you want it.]],
}


-- The last time we and the player were in touch: they paid, or we reminded them.
-- Whichever was more recent. 0 if neither has happened.
local function last_contact()
    return math.max(shared.lastTitheTime(), tithe_reminder.last_reminder)
end


local function reminder_due()
    local owed = shared.amountOwed()
    local level_in_silver = UnitLevel("player") * 100
    local seconds_since_contact = GetServerTime() - last_contact()

    return shared.inConfiguredGuild() and seconds_since_contact >= hours_between_contact * 3600 and owed >= level_in_silver
end


-- "1 day" or "3 days"
local function count_of(number, word)
    if number == 1 then
        return "1 " .. word
    end
    return number .. " " .. word .. "s"
end


-- "3 days, 4 hours and 12 minutes since your last tithe." Exact on purpose: someone is counting.
local function time_since_tithe_notice(last_tithe)
    local minutes = math.floor((GetServerTime() - last_tithe) / 60)
    local days = math.floor(minutes / 1440)
    local hours = math.floor(minutes % 1440 / 60)

    return count_of(days, "day") .. ", " .. count_of(hours, "hour") .. " and "
        .. count_of(minutes % 60, "minute") .. " since your last tithe.. we're counting."
end


-- The usual notices, plus the time since this character last tithed, if they ever have
local function pick_notice()
    local choices = {}

    for _, notice in ipairs(notices) do
        table.insert(choices, notice)
    end

    local last_tithe = shared.lastTitheTime()
    if last_tithe > 0 then
        table.insert(choices, time_since_tithe_notice(last_tithe))
    end

    return choices[math.random(#choices)]
end


-- Outside a guild that runs the Ledger, every 3 days
local function outsider_notice_due()
    local seconds_since_last = GetServerTime() - tithe_reminder.last_reminder
    return not shared.inConfiguredGuild() and seconds_since_last >= hours_between_outsider_notices * 3600
end


local function show_notice(text)
    tithe_reminder.last_reminder = GetServerTime()
    shared.notice_showing = true
    shared.showNotice(text, function()
        shared.notice_showing = false
    end)
end


local reminder_frame = CreateFrame("Frame")

local function check_reminder()
    if InCombatLockdown() or UnitAffectingCombat("player") then
        reminder_frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    if shared.memo_showing or shared.communique_showing or shared.archive_showing then
        C_Timer.After(busy_retry_seconds, check_reminder)
        return
    end

    tithe_reminder.checked = true

    if reminder_due() then
        show_notice(pick_notice())
    elseif outsider_notice_due() then
        show_notice(outsider_notices[math.random(#outsider_notices)])
    end
end


reminder_frame:RegisterEvent("PLAYER_ENTERING_WORLD")

reminder_frame:SetScript("OnEvent", function(self, event, is_initial_login, is_reloading_ui)
    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        check_reminder()
        return
    end

    -- Zoning doesn't restart anything
    if not is_initial_login and not is_reloading_ui then
        return
    end

    if tithe_reminder == nil then
        tithe_reminder = { session_start = 0, checked = false, last_reminder = 0 }
    end

    if is_initial_login then
        tithe_reminder.session_start = GetServerTime()
        tithe_reminder.checked = false
    end

    if tithe_reminder.checked then
        return
    end

    local seconds_left = tithe_reminder.session_start + minutes_logged_in * 60 - GetServerTime()
    C_Timer.After(math.max(seconds_left, 1), check_reminder)
end)
