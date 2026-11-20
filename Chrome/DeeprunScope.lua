-- Deeprun Tithe: Scope and Impact
-- A window that says, in plain words, what this addon does and what it shares.
-- Once per account: a few seconds after login, and never again after it's closed.
-- Players updating from an older version see it once too, since they've never seen it.
--
-- Saved for the account (see DeeprunTithe.toc):
--   tithe_scope_seen  true once the window has been closed

local addon_name, shared = ...

-- Settings
local show_after_seconds = 3   -- lets the login memo have its moment first
local text_width = 460
local fade_in_seconds = 0.6
local fog_thickness = 0.5       -- lighter than a communique's fog

local scope_window = nil

local scope_text =
    "Here's what this addon does, and what it shares, in plain words.\n\n"

    .. "|cffffd100Immersion: Memos|r\n"
    .. "When you log in, a short company memo may slide across the top of your screen. "
    .. "Just a little flavor to start your day.\n\n"

    .. "|cffffd100Immersion: Communiques|r\n"
    .. "As you keep paying your tithe, you'll unlock pieces of company lore. Each one arrives "
    .. "in a soft fog that covers the screen for a few moments, then lifts.\n\n"

    .. "|cffffd100Immersion: Notices|r\n"
    .. "If your tithe has gone unpaid for two days or more, a short notice may appear while the edges "
    .. "of your screen darken. It shows at most once every two days, and only after an hour of play.\n\n"

    .. "|cffffd100Immersion: Celebrations|r\n"
    .. "When you pay your tithe, coins shower across your screen and fireworks go off. "
    .. "Every payment deserves a little party.\n\n"

    .. "None of these ever show in combat, and none of them need a click. "
    .. "They're only here to make the company feel alive.\n\n"

    .. "|cffffd100Grey Tracking|r\n"
    .. "We keep a tally of the gold you earn from looting and vendoring greys. "
    .. "A small share of it becomes your tithe.\n\n"

    .. "|cffffd100What We Collect, and Why|r\n"
    .. "When you pay a tithe, your character name, the time and the amount are sent to the guild's "
    .. "ledgers on a guild-only channel that never shows in chat. That's what fills the leaderboard, "
    .. "and how treasurers match your payment to the guild bank log.\n\n"

    .. "Thank you for being part of Deeprun Freight Co."


-- Blizzard's portrait window, like the rules popup. The text sits under the coin, centred.
-- It fades in over a light fog, and the fog lifts when it closes.
local function create_scope_window()
    scope_window = CreateFrame("Frame", "DeeprunScopeWindow", UIParent, "PortraitFrameTemplate")
    scope_window:SetWidth(text_width + 50)
    scope_window:SetPoint("CENTER")
    scope_window:SetFrameStrata("DIALOG")
    scope_window:SetTitle("DeeprunTithe: Scope and Impact")
    scope_window:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Coin_17")
    scope_window:EnableMouse(true)
    table.insert(UISpecialFrames, "DeeprunScopeWindow")

    local welcome = scope_window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    welcome:SetPoint("TOP", scope_window, "TOP", 0, -40)
    welcome:SetText("Welcome to Deeprun Tithe!")

    local details = scope_window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    details:SetPoint("TOP", scope_window, "TOP", 0, -70)
    details:SetWidth(text_width)
    details:SetJustifyH("LEFT")
    details:SetSpacing(4)
    details:SetText(scope_text)

    local got_it_button = CreateFrame("Button", nil, scope_window, "UIPanelButtonTemplate")
    got_it_button:SetSize(110, 22)
    got_it_button:SetPoint("BOTTOM", scope_window, "BOTTOM", 0, 18)
    got_it_button:SetText("Sounds good")
    got_it_button:SetScript("OnClick", function()
        scope_window:Hide()
    end)

    -- However it closes, the button, the X or Escape, it's been seen, and the fog lifts
    scope_window:SetScript("OnHide", function()
        tithe_scope_seen = true
        shared.liftFog()
    end)

    scope_window.fade_in = scope_window:CreateAnimationGroup()
    local fade_in = scope_window.fade_in:CreateAnimation("Alpha")
    fade_in:SetFromAlpha(0)
    fade_in:SetToAlpha(1)
    fade_in:SetDuration(fade_in_seconds)
    fade_in:SetSmoothing("OUT")

    scope_window:SetHeight(70 + details:GetStringHeight() + 58)
end


local scope_frame = CreateFrame("Frame")
scope_frame:RegisterEvent("PLAYER_LOGIN")

scope_frame:SetScript("OnEvent", function()
    if tithe_scope_seen then
        return
    end

    C_Timer.After(show_after_seconds, function()
        create_scope_window()
        shared.rollInFog(fog_thickness)
        scope_window:Show()
        scope_window.fade_in:Play()
    end)
end)
