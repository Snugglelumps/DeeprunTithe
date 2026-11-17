-- Deeprun Tithe: the tithe reminder
-- Meant to catch someone who has actually forgotten, and never to nag.
-- After the character has been logged in for an hour, a cryptic memo shows if:
--   it's been a day or more since our last contact (see last_contact)
--   they owe at least their level in silver: 25 silver at level 25
--   they're out of combat (if they're fighting, it waits until they stop)
-- It checks once per session. So the most anyone sees is one reminder a day, and only
-- after an hour of play.
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
local hours_between_contact = 24


local tithe_reminders = {
    [[We noticed.]],
    [[Someone was asking about you at the bank.]],
    [[The collectors have your scent.]],
    [[Your coin purse feels heavier than it should.]],
    [[Your 'participation' has been noted.]],
    [[The vault is missing something...]],
    [[The collectors have your location.]],
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

    return seconds_since_contact >= hours_between_contact * 3600 and owed >= level_in_silver
end


local reminder_frame = CreateFrame("Frame")

local function check_reminder()
    if InCombatLockdown() or UnitAffectingCombat("player") then
        reminder_frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    tithe_reminder.checked = true

    if not reminder_due() then
        return
    end

    tithe_reminder.last_reminder = GetServerTime()

    local reminder = tithe_reminders[math.random(#tithe_reminders)]
    shared.showMemo(reminder)
    shared.printTitheLine(reminder)
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
