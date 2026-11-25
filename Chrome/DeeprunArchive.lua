-- Deeprun Tithe: everything you've learned so far, on one page
-- Opened by clicking your tithe level on the leaderboard (DeeprunLeaderboard.lua).
-- The screen goes dark, the fog rolls in over it, and every communique you've earned is there
-- to read again. A click or Escape closes it, and so does a fight starting.
--
-- Three layers: the dark, then the fog, then the words, so the fog never dulls the words.
-- The words are scaled to fit, so it's one page at any level and any UI scale.
--
-- shared.archive_showing is raised while it's up, so a notice or communique waits for it.

local addon_name, shared = ...

-- Settings
local text_width = 760
local share_of_screen = 0.88    -- how much of the screen the words can take up
local largest_scale = 1.3       -- so one short communique isn't huge
local fade_in_seconds = 1.5

local archive = nil
local words = nil
local lore_text = nil


local function create_archive()
    archive = CreateFrame("Frame", "DeeprunArchive", UIParent)
    archive:SetAllPoints()
    archive:SetFrameStrata("DIALOG")
    archive:EnableMouse(true)
    table.insert(UISpecialFrames, "DeeprunArchive")

    local dark = archive:CreateTexture(nil, "BACKGROUND")
    dark:SetAllPoints()
    dark:SetColorTexture(0.05, 0.05, 0.06, 0.94)

    words = CreateFrame("Frame", nil, archive)
    words:SetFrameStrata("FULLSCREEN_DIALOG")
    words:SetPoint("CENTER")

    local header = words:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOP")
    header:SetText("|TInterface\\MoneyFrame\\UI-GoldIcon:0|t   DEEPRUN FREIGHT CO.   |TInterface\\MoneyFrame\\UI-GoldIcon:0|t")

    lore_text = words:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lore_text:SetPoint("TOP", words, "TOP", 0, -40)
    lore_text:SetWidth(text_width)
    lore_text:SetSpacing(4)

    archive:SetScript("OnMouseUp", function()
        archive:Hide()
    end)

    -- However it closes, the fog lifts
    archive:SetScript("OnHide", function()
        shared.archive_showing = false
        shared.liftFog()
    end)

    archive:RegisterEvent("PLAYER_REGEN_DISABLED")
    archive:SetScript("OnEvent", function()
        archive:Hide()
    end)

    archive.fade_in = archive:CreateAnimationGroup()
    local fade_in = archive.fade_in:CreateAnimation("Alpha")
    fade_in:SetFromAlpha(0)
    fade_in:SetToAlpha(1)
    fade_in:SetDuration(fade_in_seconds)
end


-- Every communique up to this level, each under its number in gold
local function write_lore(level)
    local pieces = {}
    for rank = 1, level do
        table.insert(pieces, "|cffffd100Level " .. rank .. "|r\n" .. shared.lore[rank])
    end

    lore_text:SetText(table.concat(pieces, "\n\n"))
end


local function fit_to_screen()
    local height = 40 + lore_text:GetStringHeight()
    words:SetSize(text_width, height)
    words:SetScale(math.min(largest_scale,
        UIParent:GetHeight() * share_of_screen / height,
        UIParent:GetWidth() * share_of_screen / text_width))
end


-- Never in combat, and not over a communique: they share the fog
function shared.showArchive()
    if InCombatLockdown() or UnitAffectingCombat("player") or shared.communique_showing then
        return
    end

    if archive == nil then
        create_archive()
    end

    write_lore(shared.titheLevel())
    fit_to_screen()

    shared.archive_showing = true
    shared.rollInFog(1, "FULLSCREEN")
    archive:Show()
    archive.fade_in:Play()
end
