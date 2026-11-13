-- Deeprun Tithe: login messages
-- One random message each login. Once in a while, the commercial instead.

local addon_name, shared = ...

-- Settings
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
    [[Your tithe helps fund important guild projects, such as management's new gryphon.]],
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
    [[Remember to check out Muscle Mathers' new single on SoundCloud]],
    [[Hey everyone, Muscle Mathers' latest album is not doing so great, we're taking a collection in the guild bank. - Rebecca from HR]],
    [[I'm going to say this one last time CLEAN OUT THE REHEAT-O-MATIC 3000 AFTER USE. The break room is a shared space. - Rebecca from HR]],
    [[Legal notice: We have just decided you can't sue.. ever..]],
    [[Welcome back. You were offline for 14 hours. I counted. - Rebecca from HR]],
    [[Reminder that I also read the Discord. All of it. - Rebecca from HR]],
    [[HR is here for you. HR is always here. HR is behind you. - Rebecca from HR]],
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


local login_messages_frame = CreateFrame("Frame")
login_messages_frame:RegisterEvent("PLAYER_LOGIN")

login_messages_frame:SetScript("OnEvent", function()
    if math.random(commercial_odds) == commercial_odds then
        print_commercial()
    else
        print_tithe_line(login_messages[math.random(#login_messages)])
    end
end)
