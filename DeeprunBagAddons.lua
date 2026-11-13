-- Deeprun Tithe: bag addons
-- These replace Blizzard's bags and guild bank with their own windows, so the tithe goes on theirs too.
-- Blizzard's windows keep theirs (DeeprunTithe.lua): some of these only replace one, or let you
-- switch back, and whichever window opens is the one you see.
-- Each addon is only set up if it's loaded. The .toc's OptionalDeps loads them before us.

local addon_name, shared = ...


-- Baganator: its backpack has a spot in the bottom left for other addons.
-- Its guild bank window is named after the skin in use, and made at login.
local function support_baganator()
    Baganator.API.RegisterRegion("Deeprun Tithe", "deeprun_tithe", "backpack", "bottom_left", shared.makeDebtLine(UIParent))

    local guild_window = _G["Baganator_SingleViewGuildViewFrame" .. Baganator.API.Skins.GetCurrentSkin()]
    shared.hangTitheBarUnder(guild_window)
end


-- Bagnon: its windows aren't made until they first open, and have no fixed names.
-- Every window opens through Bagnon.Frames:Show(id), so we catch each the first time.
local function support_bagnon()
    local windows_done = {}

    hooksecurefunc(Bagnon.Frames, "Show", function(frames, id)
        if windows_done[id] then
            return
        end

        if id == "inventory" then
            shared.hangDebtLineUnder(frames:Get(id))
        end

        if id == "guild" then
            shared.hangTitheBarUnder(frames:Get(id))
        end

        windows_done[id] = true
    end)
end


-- AdiBags: the backpack is made the first time it opens, and says so with a message.
-- It has a spot in the bottom left for other addons. Its gold is on the right.
-- It doesn't replace the guild bank.
local function support_adibags()
    LibStub("ABEvent-1.0").RegisterMessage("DeeprunTithe", "AdiBags_BagFrameCreated", function(message, bag)
        if bag.bagName ~= "Backpack" then
            return
        end

        local window = bag:GetFrame()
        window:AddBottomWidget(shared.makeDebtLine(window), "LEFT", 50, 16, 0, 0)
    end)
end


-- ArkInventory: fixed names. Frame1 is the bags, Frame4 is the guild bank ("vault").
local function support_arkinventory()
    shared.hangDebtLineUnder(ARKINV_Frame1)
    shared.hangTitheBarUnder(ARKINV_Frame4)
end


-- BetterBags: two designs, classic and Next, with different windows.
-- Only the one you use gets made, when BetterBags loads. Only Next replaces the guild bank.
local function support_betterbags()
    if BetterBagsBagBackpack ~= nil then
        shared.hangDebtLineUnder(BetterBagsBagBackpack)
    end

    if BetterBagsNextBackpack ~= nil then
        shared.hangDebtLineUnder(BetterBagsNextBackpack)
    end

    if BetterBagsNextGuildBank ~= nil then
        shared.hangTitheBarUnder(BetterBagsNextGuildBank)
    end
end


local bag_addons_frame = CreateFrame("Frame")
bag_addons_frame:RegisterEvent("PLAYER_LOGIN")

-- After DeeprunTithe.lua's login, which comes first in the .toc and sets up guild_debt
bag_addons_frame:SetScript("OnEvent", function()
    if C_AddOns.IsAddOnLoaded("Baganator") then
        support_baganator()
    end

    if C_AddOns.IsAddOnLoaded("Bagnon") then
        support_bagnon()
    end

    if C_AddOns.IsAddOnLoaded("AdiBags") then
        support_adibags()
    end

    if C_AddOns.IsAddOnLoaded("ArkInventory") then
        support_arkinventory()
    end

    if C_AddOns.IsAddOnLoaded("BetterBags") then
        support_betterbags()
    end
end)
