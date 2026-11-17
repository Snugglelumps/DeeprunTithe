-- Deeprun Shared
-- Everything Deeprun Tithe and Deeprun Ledger have to agree on.
-- Both addons have a copy of this file, and they must stay identical.

local addon_name, shared = ...

shared.prefix = "deeprun"
-- Used until a ledger's RDY says otherwise
shared.tithe_rate = 0.05
shared.tithes_start_at_level = 20
shared.custom_tithe_limit = 1   -- gold a week


------------------------------------------------------------
-- Transaction IDs and messages
------------------------------------------------------------

-- time|base64(name|gold|item_id|count)
-- Items aren't tithes anymore, so item_id and count are always 0. They stay so the format doesn't change.
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


-- The answering ledger says RDY every 4 minutes, so tithes know someone's listening.
-- It carries that ledger's ID for the session, and the guild's settings with the time they were made.
-- RDY|<ledger id>|<settings time>|r=0.05;t=0;l=20;c=1;
function shared.rdyMessage(ledger_id, settings_time)
    return "RDY|" .. ledger_id .. "|" .. settings_time .. "|" .. shared.settingsText()
end


-- A tithe that just logged in asking if a ledger is there. The answering one replies with RDY.
function shared.readyQuestionMessage()
    return "RDY?"
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
-- DNE|<player>|<time>
function shared.dneMessage(player, command_time)
    return "DNE|" .. player .. "|" .. command_time
end


-- A tithe asking for this week's leaderboard
function shared.ldrMessage()
    return "LDR"
end


-- Part of the leaderboard, up to 3 players. The week is when it started.
-- RNK|<week start>|<player>,<week gold>,<payments>,<all-time gold>,<points>,<weeks won>;...
function shared.rnkMessage(week_start, players)
    local entries = {}

    for player_number, player in ipairs(players) do
        table.insert(entries, player.name .. "," .. player.week_gold .. "," .. player.payments
            .. "," .. player.all_time_gold .. "," .. player.points .. "," .. player.weeks_won)
    end

    return "RNK|" .. week_start .. "|" .. table.concat(entries, ";")
end


-- Last week's top 3, sent at the front of every leaderboard. The week is when it started.
-- WIN|<week start>|<player>,<week gold>;...
function shared.winMessage(week_start, players)
    local entries = {}

    for player_number, player in ipairs(players) do
        table.insert(entries, player.name .. "," .. player.week_gold)
    end

    return "WIN|" .. week_start .. "|" .. table.concat(entries, ";")
end


-- A tithe's account ID, answering RDY, so ledgers can tie alts together.
-- ACC|<id>, like ACC|a3f9-c01e42. The server stamps which character sent it.
function shared.accMessage(account_id)
    return "ACC|" .. account_id
end


------------------------------------------------------------
-- Weeks
------------------------------------------------------------

-- When this week started, Monday 00:00 on the realm's clock.
-- The leaderboard and the weekly custom tithe limit both reset then.
-- Rounded to the minute, so asking twice gives the same answer even as the seconds tick.
-- Tradeoff: the week the clocks change, the boundary is an hour off.
function shared.thisWeekStart()
    local realm_now = C_DateAndTime.GetCurrentCalendarTime()

    -- weekday is 1 for Sunday, so Monday is 2
    local days_since_monday = (realm_now.weekday + 5) % 7
    local minutes_since_midnight = realm_now.hour * 60 + realm_now.minute
    local this_minute = math.floor(GetServerTime() / 60) * 60

    return this_minute - days_since_monday * 24 * 60 * 60 - minutes_since_midnight * 60
end


------------------------------------------------------------
-- Settings
------------------------------------------------------------

-- The settings travel in RDY as key=value; pairs, like r=0.05;t=0;l=20;c=1;
-- r is the tithe rate, l is the level tithes start at, c is the weekly custom tithe limit in gold.
-- t was the trade good rate. It's always 0 now, so tithes before 1.6.0 stop giving credit for items.
function shared.settingsText()
    return "r=" .. shared.tithe_rate .. ";t=0;l=" .. shared.tithes_start_at_level
        .. ";c=" .. shared.custom_tithe_limit .. ";"
end


-- Keys can be in any order. A key that's missing or isn't a number keeps what we had.
function shared.useSettings(settings_text)
    for key, value in string.gmatch(settings_text, "(%a+)=([^;]*);") do
        if key == "r" and tonumber(value) ~= nil then
            shared.tithe_rate = tonumber(value)
        end

        if key == "l" and tonumber(value) ~= nil then
            shared.tithes_start_at_level = tonumber(value)
        end

        if key == "c" and tonumber(value) ~= nil then
            shared.custom_tithe_limit = tonumber(value)
        end
    end
end


------------------------------------------------------------
-- Our tabs on the guild window
------------------------------------------------------------

-- Tithe and Ledger each add a side tab under Blizzard's, with a page over the guild window's
-- page area, the way Blizzard's tabs show Roster or Guild Info.
-- Either addon can load first, so what they share is in one global table:
--   tabs    every Deeprun tab. tab.page is its page.
--   hidden  the names of Blizzard's frames we hid to show our page, put back when it closes
DeeprunGuildTabs = DeeprunGuildTabs or { tabs = {}, hidden = {} }

local blizzard_tab_keys = { "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab", "GuildPreferredPlaySettingsTab" }


local function isOnBlizzardsPage(frame_name)
    for _, page_frame_name in ipairs(CommunitiesFrame.displayMode) do
        if page_frame_name == frame_name then
            return true
        end
    end

    return false
end


-- Hides the frames of whatever page Blizzard has up, except the guild and community list.
-- Switching between our own pages, they're already hidden.
local function hideBlizzardsPage()
    if #DeeprunGuildTabs.hidden > 0 then
        return
    end

    for _, frame_name in ipairs(CommunitiesFrame.displayMode) do
        local frame = CommunitiesFrame[frame_name]

        if frame_name ~= "CommunitiesList" and frame:IsShown() then
            frame:Hide()
            table.insert(DeeprunGuildTabs.hidden, frame_name)
        end
    end
end


-- Closes our pages and puts back what we hid.
-- If Blizzard has switched to another page since, it's already shown that page's frames,
-- so only the ones on the page it has up come back.
function shared.closeGuildPages()
    for _, tab in ipairs(DeeprunGuildTabs.tabs) do
        tab:SetChecked(false)
        tab.page:Hide()
    end

    for _, frame_name in ipairs(DeeprunGuildTabs.hidden) do
        if isOnBlizzardsPage(frame_name) then
            CommunitiesFrame[frame_name]:Show()
        end
    end

    DeeprunGuildTabs.hidden = {}
end


-- Our tab's page replaces whatever's up, Blizzard's or our other one
function shared.pickGuildTab(picked_tab)
    hideBlizzardsPage()

    for _, tab_key in ipairs(blizzard_tab_keys) do
        CommunitiesFrame[tab_key]:SetChecked(false)
    end

    for _, tab in ipairs(DeeprunGuildTabs.tabs) do
        tab:SetChecked(tab == picked_tab)
        tab.page:SetShown(tab == picked_tab)
    end
end


-- A page over the guild window's page area, right of the guild and community list.
-- 24 right of the list, past its scroll bar, where Blizzard's own pages start.
-- Solid underneath, so nothing shows through, and it takes the clicks.
-- Under the side tabs, which sit at level 510.
function shared.makeGuildPage()
    local page = CreateFrame("Frame", nil, CommunitiesFrame, "InsetFrameTemplate")
    page:SetPoint("TOPLEFT", CommunitiesFrame.CommunitiesList, "TOPRIGHT", 24, 0)
    page:SetPoint("BOTTOMRIGHT", CommunitiesFrame, "BOTTOMRIGHT", -6, 26)
    page:SetFrameLevel(500)
    page:EnableMouse(true)
    page:Hide()

    local solid = page:CreateTexture(nil, "BACKGROUND", nil, 1)
    solid:SetPoint("TOPLEFT", 3, -3)
    solid:SetPoint("BOTTOMRIGHT", -3, 3)
    solid:SetColorTexture(0.05, 0.05, 0.05, 1)

    local art = page:CreateTexture(nil, "BACKGROUND", nil, 2)
    art:SetPoint("TOPLEFT", 3, -3)
    art:SetPoint("BOTTOMRIGHT", -3, 3)
    art:SetAtlas("auctionhouse-background-index")

    return page
end


-- A side tab made from Blizzard's own template. Slot 1 is right under Blizzard's last tab,
-- slot 2 under that. It's attached to Blizzard's last tab, so it shows and hides with the guild tabs.
function shared.makeGuildTab(slot, icon, tooltip, page)
    local last_guild_tab = CommunitiesFrame.GuildPreferredPlaySettingsTab

    local tab = CreateFrame("CheckButton", nil, last_guild_tab, "CommunitiesFrameTabTemplate")
    tab:SetPoint("TOPLEFT", last_guild_tab, "BOTTOMLEFT", 0, -20 - 52 * (slot - 1))
    tab.Icon:SetTexture(icon)
    tab.tooltip = tooltip
    tab.page = page
    table.insert(DeeprunGuildTabs.tabs, tab)

    -- Our own click. The template's would ask the guild window for a page it doesn't have.
    tab:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        shared.pickGuildTab(self)
    end)

    -- Closing the guild window, or picking a community instead of the guild
    tab:SetScript("OnHide", shared.closeGuildPages)

    -- Picking any of Blizzard's tabs goes through SetDisplayMode, even the one already picked.
    -- With both addons this runs twice, and the second time there's nothing left to close.
    hooksecurefunc(CommunitiesFrame, "SetDisplayMode", shared.closeGuildPages)

    return tab
end
