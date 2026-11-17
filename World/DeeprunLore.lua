-- Deeprun Tithe: company lore, unlocked by paying tithes
-- Every tithe is written to an account-wide history. After a payment, if the account
-- meets the next rank's requirements, a roll decides whether it ascends. A new rank
-- shows its lore as a memo a few seconds later. Ranks only ever go up, one at a time.
--
-- Saved for the account (see DeeprunTithe.toc):
--   tithe_history = {
--       payments = { { time, copper }, ... },   oldest first
--       total = copper,                         every payment added up
--       lore_rank = 0,                          the highest lore shown so far
--   }
-- Each payment is two numbers, so even thousands of them are a few kilobytes,
-- and the checks below only run once per payment.

local addon_name, shared = ...

-- Settings
local lore_delay_seconds = 10   -- after the payment, before the memo shows
-- Once the next rank is earned, each payment has a 1 in <rank> chance to ascend:
-- 1 in 2 for rank 2, up to 1 in 5 for rank 5.


local lore = {
    [[As a member and contributor of <Deeprun Freight Co>, you have made your first tithe payment! As you continue to pay your tithe and contribute, you will learn more of our company, culture, and about our founder Jonathan Deeprun.]],
    [[You have ascended to level 2 in your guild tithe payments, much as Jonathan Deeprun will soon ascend into a higher plane. For now, this knowledge is beyond your clearance, but with more tithe payments, you will be entrusted with the deepest secrets of <Deeprun Freight Co>]],
    [[You have ascended to level 3 in your guild tithe payments. Jonathan Deeprun was once a mortal just like you. It’s common knowledge that the business world is cutthroat, and only the toughest and most ruthless can make it in this ever-changing world. Jonathan, in his thirst for power, was the most ruthless of all.]],
    [[You have ascended to level 4 in your guild tithe payments. You should take this moment to reflect on all you have achieved, and what you have sacrificed to make those achievements. Sacrifice. Jonathan Deeprun knows of sacrifice. All too well. You need only look at what he has achieved to begin to ponder the scale of his sacrifice. There is a reason he is feared by kings and men alike. There is reason YOU should fear.]],
    [[You have ascended to level 5 in your guild tithe payments. In level 4, is was said that you should fear. But know that Jonathan Deeprun also looks after those who contribute to his empire. As he punishes those who would stand against him, he is also magnanimous to his followers. Bathing in his presence alone is said to be more refreshing than a full night’s rest.]],
}


-- What each rank needs before it can be rolled for. Rank 1 is the first payment, no roll.
--   days      days since the first tithe
--   gold      total paid, in gold
--   streak    days in a row with at least one tithe
--   within    the streak has to fall inside this many days back from now (nil means any time)
--   payments  number of tithes paid
local requirements = {
    [2] = { days = 7,  gold = 1,   streak = 3 },
    [3] = { days = 21, gold = 15,  streak = 4, payments = 10 },
    [4] = { days = 42, gold = 100, streak = 5 },
    [5] = { days = 90, gold = 200, streak = 3, within = 30 },
}

local seconds_per_day = 86400
local copper_per_gold = 10000


-- The calendar day a time falls on, by the player's clock, as one number.
-- Noon is used so daylight saving can't push it into the next or previous day.
local function day_number(time_stamp)
    local day = date("*t", time_stamp)
    return math.floor(time({ year = day.year, month = day.month, day = day.day, hour = 12 }) / seconds_per_day)
end


-- The most days in a row with a tithe, counting only payments made at or after since
local function longest_streak(since)
    local longest = 0
    local current = 0
    local last_day = nil

    for _, payment in ipairs(tithe_history.payments) do
        if payment[1] >= since then
            local day = day_number(payment[1])

            if day ~= last_day then
                if last_day ~= nil and day == last_day + 1 then
                    current = current + 1
                else
                    current = 1
                end

                last_day = day
                longest = math.max(longest, current)
            end
        end
    end

    return longest
end


local function meets_requirements(rank)
    local needs = requirements[rank]
    if needs == nil then
        return false
    end

    local now = GetServerTime()
    local first_payment = tithe_history.payments[1][1]

    if now - first_payment < needs.days * seconds_per_day then
        return false
    end

    if tithe_history.total < needs.gold * copper_per_gold then
        return false
    end

    if needs.payments and #tithe_history.payments < needs.payments then
        return false
    end

    local since = needs.within and (now - needs.within * seconds_per_day) or 0
    return longest_streak(since) >= needs.streak
end


local function show_lore(rank)
    C_Timer.After(lore_delay_seconds, function()
        shared.showMemo(lore[rank])
        shared.printTitheLine(lore[rank])
    end)
end


-- Called by pay_tithe after every payment
function shared.recordTitheHistory(copper)
    if tithe_history == nil then
        tithe_history = { payments = {}, total = 0, lore_rank = 0 }
    end

    table.insert(tithe_history.payments, { GetServerTime(), copper })
    tithe_history.total = tithe_history.total + copper

    local next_rank = tithe_history.lore_rank + 1
    if lore[next_rank] == nil then
        return
    end

    -- The first payment always unlocks rank 1. After that, earn it, then win the roll.
    if next_rank == 1 or (meets_requirements(next_rank) and math.random(next_rank) == 1) then
        tithe_history.lore_rank = next_rank
        show_lore(next_rank)
    end
end
