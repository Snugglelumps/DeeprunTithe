-- Deeprun Tithe: the greys you've looted, so only those count when you sell them
-- Selling a grey only adds to your tithe if it's on this list. Buying greys off the AH and
-- vendoring them adds nothing. Loot one grey rock, buy another, sell both: one counts.
--
-- It's for the whole account, so greys looted on your main still count when a bank alt sells them.
-- "You receive loot" covers mobs, chests, fishing, clams and pickpocketing, so that's what we watch.
-- Each entry is dropped after 30 days, so a grey you destroyed doesn't sit on the list forever.
--
-- Saved for the account (see DeeprunTithe.toc):
--   looted_grays  oldest first: { item_id = ..., count = ..., price = <vendor price each, copper>, time = ... }

local addon_name, shared = ...

-- Settings
local keep_for_seconds = 30 * 24 * 60 * 60


-- Blizzard's "You receive loot: %s." as a pattern that captures the item link.
-- From their own text, so it works in every language.
local function pattern_from(loot_text)
    local pattern = string.gsub(loot_text, "[%%%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
    pattern = string.gsub(pattern, "%%%%s", "(.+)")
    pattern = string.gsub(pattern, "%%%%d", "(%%d+)")
    return "^" .. pattern .. "$"
end

-- Several first, since the single one would also match "[Grey Rock]x3"
local several_looted_pattern = pattern_from(LOOT_ITEM_SELF_MULTIPLE)
local one_looted_pattern = pattern_from(LOOT_ITEM_SELF)


local function add_to_list(item_id, count, price)
    table.insert(looted_grays, { item_id = item_id, count = count, price = price, time = GetServerTime() })
end


-- A loot line in chat. Only our own loot matches, and only greys go on the list.
-- Below the level tithes start at, nothing goes on, the same as selling there never counted.
local function heard_loot(message)
    if UnitLevel("player") < shared.tithes_start_at_level then
        return
    end

    local item_link, count = string.match(message, several_looted_pattern)

    if item_link == nil then
        item_link = string.match(message, one_looted_pattern)
        count = 1
    end

    if item_link == nil then
        return
    end

    local _, _, quality, _, _, _, _, _, _, _, price = C_Item.GetItemInfo(item_link)

    if quality ~= Enum.ItemQuality.Poor then
        return
    end

    add_to_list(tonumber(string.match(item_link, "item:(%d+)")), tonumber(count), price)
end


-- Sold count of item_id: takes that many off the list, oldest first, and returns what they're worth.
-- Any past what's on the list weren't looted, so they're worth nothing.
function shared.takeLootedGrays(item_id, sold_count)
    local copper = 0
    local entry_number = 1

    while sold_count > 0 and entry_number <= #looted_grays do
        local entry = looted_grays[entry_number]

        if entry.item_id == item_id then
            local taken = math.min(entry.count, sold_count)
            copper = copper + taken * entry.price
            sold_count = sold_count - taken
            entry.count = entry.count - taken
        end

        if entry.count == 0 then
            table.remove(looted_grays, entry_number)
        else
            entry_number = entry_number + 1
        end
    end

    return copper
end


-- How many of each grey are in your bags: { [item_id] = count }
function shared.grayCountsInBags()
    local counts = {}

    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)

            if info ~= nil and info.quality == Enum.ItemQuality.Poor then
                counts[info.itemID] = (counts[info.itemID] or 0) + info.stackCount
            end
        end
    end

    return counts
end


-- The first time this account runs this version, the greys already in this character's bags
-- go on the list, so nobody loses tithe on junk they were carrying when they updated.
-- Tradeoff: a grey whose price the game hasn't loaded yet is skipped.
local function seed_from_bags()
    looted_grays = {}

    for item_id, count in pairs(shared.grayCountsInBags()) do
        local price = select(11, C_Item.GetItemInfo(item_id))

        if price ~= nil then
            add_to_list(item_id, count, price)
        end
    end
end


local function drop_old_entries()
    for entry_number = #looted_grays, 1, -1 do
        if GetServerTime() - looted_grays[entry_number].time > keep_for_seconds then
            table.remove(looted_grays, entry_number)
        end
    end
end


local loot_frame = CreateFrame("Frame")
loot_frame:RegisterEvent("PLAYER_LOGIN")
loot_frame:RegisterEvent("CHAT_MSG_LOOT")

loot_frame:SetScript("OnEvent", function(self, event, message)
    if event == "PLAYER_LOGIN" then
        if looted_grays == nil then
            seed_from_bags()
        end

        drop_old_entries()

    elseif event == "CHAT_MSG_LOOT" then
        heard_loot(message)
    end
end)
