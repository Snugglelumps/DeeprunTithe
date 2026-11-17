-- Deeprun Tithe: login messages
-- One random message each login. Once in a while, the commercial instead.

local addon_name, shared = ...

-- Settings
local commercial_enabled = false     -- off for now
local commercial_odds = 420          -- 1 in this many logins get the commercial
local commercial_line_seconds = 0.5


local login_messages = {
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
-- Building the login message
------------------------------------------------------------

-- Every message this player could get today: the usual ones, plus any that
-- only apply to them. One is picked at random from the lot.
local function build_content_list()
    local content = {}

    for _, message in ipairs(login_messages) do
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


local function print_tithe_line(text)
    print("|TInterface\\MoneyFrame\\UI-GoldIcon:0|t |cffffd100DeeprunTithe|r: " .. text)
end


-- One line every half second, like it's airing
local function print_commercial()
    local line_number = 0

    C_Timer.NewTicker(commercial_line_seconds, function()
        line_number = line_number + 1
        print_tithe_line(commercial[line_number])
    end, #commercial)
end


------------------------------------------------------------
-- The memo banner
------------------------------------------------------------

-- A strip of colour along the banner that fades out at both ends.
-- Two halves: the left one fades in towards the middle, the right one fades out from it.
local function add_fading_strip(banner, point, height, r, g, b, alpha)
    local half_width = banner:GetWidth() / 2

    local left_half = banner:CreateTexture(nil, "BACKGROUND")
    left_half:SetTexture("Interface\\Buttons\\WHITE8X8")
    left_half:SetSize(half_width, height)
    left_half:SetPoint(point .. "LEFT")
    left_half:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, alpha))

    local right_half = banner:CreateTexture(nil, "BACKGROUND")
    right_half:SetTexture("Interface\\Buttons\\WHITE8X8")
    right_half:SetSize(half_width, height)
    right_half:SetPoint(point .. "RIGHT")
    right_half:SetGradient("HORIZONTAL", CreateColor(r, g, b, alpha), CreateColor(r, g, b, 0))
end


-- A gold glint that runs once along one of the gold lines
local function add_glint(banner, point, from_x, to_x)
    local glint = banner:CreateTexture(nil, "OVERLAY")
    glint:SetTexture("Interface\\Cooldown\\star4")
    glint:SetBlendMode("ADD")
    glint:SetVertexColor(1, 0.82, 0)
    glint:SetSize(40, 20)
    glint:SetPoint("CENTER", banner, point, from_x, 0)
    glint:SetAlpha(0)

    local run = glint:CreateAnimationGroup()

    local appear = run:CreateAnimation("Alpha")
    appear:SetFromAlpha(0)
    appear:SetToAlpha(1)
    appear:SetDuration(0.2)
    appear:SetStartDelay(0.4)

    local travel = run:CreateAnimation("Translation")
    travel:SetOffset(to_x - from_x, 0)
    travel:SetDuration(1.4)
    travel:SetStartDelay(0.4)
    travel:SetSmoothing("IN_OUT")

    local vanish = run:CreateAnimation("Alpha")
    vanish:SetFromAlpha(1)
    vanish:SetToAlpha(0)
    vanish:SetDuration(0.3)
    vanish:SetStartDelay(1.5)

    run:Play()
end


-- The message across the top of the screen, like a company memo.
-- A dark band with soft ends, a thin gold line above and below, the header in gold
-- and the message under it. It unrolls from the middle, a glint runs along each line,
-- the words fade in, it stays long enough to read, then fades away.
-- It takes no clicks and can't be moved, so it never gets in the way.
-- The band grows to fit the text. seconds_to_read is optional: leave it out and
-- the memo stays up longer the longer the text is.
local function show_memo(text, seconds_to_read)
    local banner = CreateFrame("Frame", nil, UIParent)
    banner:SetWidth(900)
    banner:SetPoint("CENTER", UIParent, "CENTER", 0, 230)
    banner:SetFrameStrata("DIALOG")

    -- The words are on their own frame, so they can fade in after the band unrolls
    local words = CreateFrame("Frame", nil, banner)
    words:SetAllPoints()
    words:SetAlpha(0)

    local header = words:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOP", banner, "TOP", 0, -14)
    header:SetText("|TInterface\\MoneyFrame\\UI-GoldIcon:0|t   DEEPRUN FREIGHT CO.  ·  MEMO   |TInterface\\MoneyFrame\\UI-GoldIcon:0|t")

    local message = words:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    message:SetPoint("TOP", header, "BOTTOM", 0, -10)
    message:SetWidth(640)
    message:SetSpacing(4)
    message:SetText(text)

    -- The band fits the message, then the strips are drawn to that size
    banner:SetHeight(14 + header:GetStringHeight() + 10 + message:GetStringHeight() + 18)
    add_fading_strip(banner, "", banner:GetHeight(), 0, 0, 0, 0.75)
    add_fading_strip(banner, "TOP", 1.5, 1, 0.82, 0, 0.9)
    add_fading_strip(banner, "BOTTOM", 1.5, 1, 0.82, 0, 0.9)

    -- One glint runs left to right along the top, the other right to left along the bottom
    add_glint(banner, "TOP", -300, 300)
    add_glint(banner, "BOTTOM", 300, -300)

    -- Longer messages stay up longer: 4 seconds, plus a second for every 20 letters
    seconds_to_read = seconds_to_read or (4 + #text / 20)

    local show = banner:CreateAnimationGroup()
    show:SetToFinalAlpha(true)

    local unroll = show:CreateAnimation("Scale")
    unroll:SetScaleFrom(0.05, 1)
    unroll:SetScaleTo(1, 1)
    unroll:SetDuration(0.45)
    unroll:SetSmoothing("OUT")
    unroll:SetOrder(1)

    local fade_in = show:CreateAnimation("Alpha")
    fade_in:SetFromAlpha(0)
    fade_in:SetToAlpha(1)
    fade_in:SetDuration(0.45)
    fade_in:SetOrder(1)

    local fade_out = show:CreateAnimation("Alpha")
    fade_out:SetFromAlpha(1)
    fade_out:SetToAlpha(0)
    fade_out:SetDuration(2)
    fade_out:SetStartDelay(seconds_to_read)
    fade_out:SetOrder(2)

    show:SetScript("OnFinished", function()
        banner:Hide()
    end)

    local words_appear = words:CreateAnimationGroup()
    words_appear:SetToFinalAlpha(true)

    local words_fade_in = words_appear:CreateAnimation("Alpha")
    words_fade_in:SetFromAlpha(0)
    words_fade_in:SetToAlpha(1)
    words_fade_in:SetDuration(0.5)
    words_fade_in:SetStartDelay(0.35)

    show:Play()
    words_appear:Play()
end

shared.showMemo = show_memo
shared.printTitheLine = print_tithe_line


-- After the loading screen, on login and /reload but not when zoning.
-- A moment's wait so it doesn't land while the screen is still settling.
local login_messages_frame = CreateFrame("Frame")
login_messages_frame:RegisterEvent("PLAYER_ENTERING_WORLD")

login_messages_frame:SetScript("OnEvent", function(self, event, is_initial_login, is_reloading_ui)
    if not is_initial_login and not is_reloading_ui then
        return
    end

    C_Timer.After(2, function()
        if commercial_enabled and math.random(commercial_odds) == commercial_odds then
            show_memo("Please enjoy this message from our sponsors.")
            print_commercial()
        else
            local content = build_content_list()
            local login_message = content[math.random(#content)]
            show_memo(login_message)
            print_tithe_line(login_message)
        end
    end)
end)
