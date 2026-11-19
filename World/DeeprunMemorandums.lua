-- Deeprun Tithe: memorandums, the company memo at login
-- One random memorandum each login, in the banner (Chrome/DeeprunBanner.lua).
-- Once in a while, the commercial instead.
-- The other two kinds: notices when you haven't paid (DeeprunNotices.lua), and
-- communiques earned by paying (DeeprunCommuniques.lua).
-- Only one of the three is on screen at a time. Each raises its flag while it shows:
--   shared.memo_showing, shared.notice_showing, shared.communique_showing
-- If another is up, a memo just doesn't show. It's only flavour, there's another next login.

local addon_name, shared = ...

-- Settings
local commercial_enabled = false     -- off for now
local commercial_odds = 420          -- 1 in this many logins get the commercial
local commercial_line_seconds = 0.5


local memorandums = {
    [[Announcement: Voluntary Tithes are now mandatory, congratulations.]],
    [[Insubordination will be met with swift fines.]],
    [[Remember, tithes are collected at the Guild Bank! Pay today... or we will find you.]],
    [[All tithe payments are due by EOD. Delinquency will reflect on your quarterly reviews.]],
    [[Jonathan Deeprun thanks you for your contribution.]],
    [[You know what they say, "A tithe a day keeps well-armed debt collectors away."]],
    [[Management has found some discrepancies in your payments, expect a visit... soon...]],
    [[High repair costs is not an excuse for missing tithes... it's a skill issue.]],
    [[Announcement: Management has removed the processing fee when paying your tithe! Pay Today!]],
    [[Tithes can be collected in any major city.]],
    [[Employees may now pay additional tithe each day!]],
    [[Ummm, mind paying a bit extra this week? Jonathan lost some gold on a horse race and coffers are a bit low.]],
    [[Suggestions about the tithe can be left in the suggestion box. The suggestion box is the guild bank... while you're there...]],
    [[Tithes are tax deductible.* *They are not.]],
    [[Congratulations! You've been selected for this week's random audit.]],
    [[Dying does not pause your tithe. The spirit healer has been briefed.]],
    [[Unpaid tithes accrue interest. We won't say how much. We're not sure either.]],
    [[Today's motivational quote: "A copper tithed is a copper earned." -Management]],
    [[The Guild Bank is open 24/7. Your excuses are not.]],
    [[There is no "I" in team. There is one in tithe. It stands for Invoice.]],
    [[Studies show members who pay their tithe live longer. The studies were conducted by us.]],
    [[Your tithe helps fund important guild projects, such as Mr. Deeprun's new gryphon.]],
    [[Paying your tithe takes three seconds. Fleeing from collectors takes considerably longer.]],
    [[Employee of the Month is chosen based on tithe payments and nothing else.]],
    [[Guild Treasurers have an excellent memory and no sense of humor.]],
    [[Please welcome our new Debt Collecting team! Pae, Hoove, and Ruun are all Taurens... have plainsrunning... and will catch you.]],
    [[Did you see Mr. Deeprun's new Gryphon?]],
    [[Fraternizing with "Deeprun Trading" will result in immediate disciplinary action.]],
    [[Statement from Legal: Jonathan Deeprun has never had an affair. He has had several “extended negotiations.”]],
    [[Per Legal: Jonathan Deeprun was not at the Booty Bay inn last Tuesday. Anyone who says otherwise is in breach of their NDA.]],
    [[Deeprun Freight Co. does not comment on ongoing litigation involving Jonathan Deeprun and a certain barmaid.]],
    [[Legal notice: Jonathan’s “business trips” to Booty Bay are business expenses, and are not to be discussed in guild chat.]],
    [[Did you see GPU prices?? Unrelated, tithes are doubled until further notice. -Management]],
    -- [[Remember to check out Muscle Mathers' new single on SoundCloud]],
    -- [[Hey everyone, Muscle Mathers' latest album is not doing so great, we're taking a collection in the guild bank. - Rebecca from HR]],
    [[I'm going to say this one last time CLEAN OUT THE REHEAT-O-MATIC 3000 AFTER USE. The break room is a shared space. - Rebecca from HR]],
    [[Legal notice: We have just decided you can't sue.. ever..]],
    [[Welcome back. You were offline for 14 hours. I counted. - Rebecca from HR]],
    [[Reminder that I also read the Discord. All of it. - Rebecca from HR]],
    [[HR is here for you. HR is always here. HR is behind you. - Rebecca from HR]],
    [[Someone has been microwaving fish in the Reheat-O-Matic 3000. I know who you are. - Rebecca from HR]],
    [[Mr. Deeprun's gryphon has been repossessed. Unrelated, please pay your tithe.]],
    -- [[Muscle Mathers' world tour has been canceled due to low ticket sales. Tithes are now being accepted as condolences. - Rebecca from HR]],
    [[Your login has been recorded for quality and training purposes.]],
    [[This message is a gentle reminder. The next one will not be.]],
    [[Jonathan Deeprun has been named Employer of the Year by a committee of Jonathan Deeprun.]],
    [[Hiding gold on your alts is not a loophole. I have a list. - Rebecca from HR]],
    [[Deeprun Freight Co. would like to apologize for last week's incident on the tram. There was no incident on the tram. -Legal]],
    [[Due to recent events Mr. Mathers will not be our entertainment for the Holiday party this year. - Rebecca from HR]],
    [[Legal Notice: All tickets to the recent CANCELED Muscle Mathers show can be discarded...]],
    [[Deeprun Tram is now offering premium tickets which offer priority boarding!.. IF you don't miss the jump.]],
    [[All branding deals and projects with Muscle Mathers have been hereby CANCELED. - Legal]],
    [[]]
}


-- Only in the running when the player has a spell rank they could learn right now.
-- %s is the spell, like "Frostbolt (Rank 4)".
local spell_ranks = {
    [[Training records show you have not learned %s. Untrained employees are a liability. - Rebecca from HR]],
    [[Your skills review is overdue. %s is waiting at your trainer. - Rebecca from HR]],
    [[Reminder: %s is covered under your training plan. However you have not met your deductible..]],
}


local commercial = {
    [[Do you suffer from heavy bags? Too much junk? A nagging feeling you owe somebody something?]],
    [[Ask your Guild Master about Tithe.]],
    [[Tithe is a once-per-bank-visit treatment for chronic junk accumulation.]],
    [[In clinical trials, members using Tithe reported lighter bags and up to 100% fewer visits from collectors.]],
    [[Do not use Tithe if you are allergic to gold, guild banks, or accountability.]],
    [[Tell your officer if you are a goblin, or have ever been a goblin.]],
    [[Side effects may include dry pockets, sudden generosity, a warm feeling near the guild bank, and mild poverty.]],
    [[Some members experienced unexplained loyalty to Deeprun Freight Co. This is permanent.]],
    [[Rare side effects include promotions.]],
    [[Stop using Tithe and contact an officer immediately if you experience hoarding, vendoring without tithing, or the words "I'll pay next time."]],
    [[Do not operate heavy machinery, gnomish or otherwise, while carrying an unpaid tithe.]],
    [[Tithe is not right for everyone. Tithe is, however, mandatory.]],
    [[Ask your Guild Master if Tithe is right for you. It is.]],
    [[Deeprun Freight Co. We know where you hearth.]],
}


------------------------------------------------------------
-- Class trainer records
------------------------------------------------------------

-- trainer_table (saved, account wide) maps a character to the spell ranks their
-- class trainer offered that they hadn't learned on their last visit:
--   trainer_table["Name"] = { { name = "Frostbolt", rank = "Rank 4", level = 20 }, ... }
-- Rebuilt on every visit and every purchase. Later, anything with level <= the
-- player's level is something they could learn right now.

local trainer_open = false
local scan_pending = false


local function scan_trainer()
    scan_pending = false

    if not trainer_open or IsTradeskillTrainer() then
        return
    end

    -- Hidden entries aren't listed, so make sure the ones we need are showing.
    -- Only touched when off, so once they're on this doesn't fire TRAINER_UPDATE again.
    if not GetTrainerServiceTypeFilter("available") then
        SetTrainerServiceTypeFilter("available", 1)
    end
    if not GetTrainerServiceTypeFilter("unavailable") then
        SetTrainerServiceTypeFilter("unavailable", 1)
    end

    local unlearned = {}

    for i = 1, GetNumTrainerServices() do
        local name, rank, service_type, is_expanded = GetTrainerServiceInfo(i)

        if service_type == "header" and not is_expanded then
            -- A collapsed section hides its spells. Open them all and scan again.
            ExpandTrainerSkillLine(0)
            return
        end

        if service_type == "available" or service_type == "unavailable" then
            table.insert(unlearned, {
                name = name,
                rank = rank,
                level = GetTrainerServiceLevelReq(i) or 0,
            })
        end
    end

    trainer_table = trainer_table or {}
    trainer_table[GetUnitName("player", true)] = unlearned
end


-- TRAINER_UPDATE can come in bursts, so scan once on the next frame
local function queue_scan()
    if not scan_pending then
        scan_pending = true
        C_Timer.After(0, scan_trainer)
    end
end


local trainer_frame = CreateFrame("Frame")
trainer_frame:RegisterEvent("TRAINER_SHOW")
trainer_frame:RegisterEvent("TRAINER_UPDATE")
trainer_frame:RegisterEvent("TRAINER_CLOSED")

trainer_frame:SetScript("OnEvent", function(self, event)
    if event == "TRAINER_SHOW" then
        trainer_open = true
        queue_scan()
    elseif event == "TRAINER_UPDATE" then
        queue_scan()
    elseif event == "TRAINER_CLOSED" then
        trainer_open = false
    end
end)


-- Spell ranks this character could learn right now but hasn't
local function learnable_spell_ranks()
    local learnable = {}
    local unlearned = trainer_table and trainer_table[GetUnitName("player", true)]

    if unlearned then
        local player_level = UnitLevel("player")

        for _, spell in ipairs(unlearned) do
            if spell.level <= player_level then
                table.insert(learnable, spell)
            end
        end
    end

    return learnable
end


------------------------------------------------------------
-- Picking the memorandum
------------------------------------------------------------

-- Every message this player could get today: the usual ones, plus any that
-- only apply to them. One is picked at random from the lot.
local function build_content_list()
    local content = {}

    for _, message in ipairs(memorandums) do
        table.insert(content, message)
    end

    local learnable = learnable_spell_ranks()
    if #learnable > 0 then
        local spell = learnable[math.random(#learnable)]
        local spell_text = spell.rank ~= "" and (spell.name .. " (" .. spell.rank .. ")") or spell.name

        for _, message in ipairs(spell_ranks) do
            table.insert(content, string.format(message, spell_text))
        end
    end

    return content
end


-- One line every half second in chat, like it's airing
local function print_commercial()
    local line_number = 0

    C_Timer.NewTicker(commercial_line_seconds, function()
        line_number = line_number + 1
        shared.printTitheLine(commercial[line_number])
    end, #commercial)
end


-- After the loading screen, on login and /reload but not when zoning.
-- A moment's wait so it doesn't land while the screen is still settling.
-- Banner only. Nothing goes in chat at login, except the commercial, which is chat by nature.
local function memo_gone()
    shared.memo_showing = false
end

local memorandum_frame = CreateFrame("Frame")
memorandum_frame:RegisterEvent("PLAYER_ENTERING_WORLD")

memorandum_frame:SetScript("OnEvent", function(self, event, is_initial_login, is_reloading_ui)
    if not is_initial_login and not is_reloading_ui then
        return
    end

    C_Timer.After(2, function()
        if shared.notice_showing or shared.communique_showing then
            return
        end

        shared.memo_showing = true

        if commercial_enabled and math.random(commercial_odds) == commercial_odds then
            shared.showBanner("MEMO", "Please enjoy this message from our sponsors.", nil, memo_gone)
            print_commercial()
        else
            local content = build_content_list()
            shared.showBanner("MEMO", content[math.random(#content)], nil, memo_gone)
        end
    end)
end)
