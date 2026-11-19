-- Deeprun Tithe: the notice, the memo banner with the lights off
-- The memo is the front office. Notices ("The collectors have your scent.") are the back room:
-- the same band, so it's still the company, but nearly black with dull crimson lines, no gold,
-- and the words in Morpheus, the gothic book font, in a bone colour. No unroll and no glint.
-- The band rises out of nothing, the words write themselves a letter at a time, and the edges
-- of the screen darken while it's up. Then it all sinks back to black.
-- Takes no clicks, like the memo.
--
-- shared.showNotice(text, when_gone)   when_gone is optional: called once it has sunk away

local addon_name, shared = ...

-- Settings
local crimson = { 0.55, 0.08, 0.08 }
local bone = { 0.86, 0.82, 0.72 }
local letters_per_second = 14
local typing_waits_seconds = 0.8      -- after the band starts rising
local fade_letters = 4                -- how many letters are part-way in at once
local rise_seconds = 1.2
local sink_seconds = 2.5
local shadow_color = { 0.10, 0, 0 }   -- nearly black, a touch of red
local shadow_alpha = 0.85             -- at the very edge of the screen
local shadow_depth = 0.30             -- how far in the edges reach, as a share of the screen


-- Rises in, holds, sinks out, then hides
local function rise_hold_sink(frame, hold_seconds, when_gone)
    local show = frame:CreateAnimationGroup()
    show:SetToFinalAlpha(true)

    local rise = show:CreateAnimation("Alpha")
    rise:SetFromAlpha(0)
    rise:SetToAlpha(1)
    rise:SetDuration(rise_seconds)
    rise:SetSmoothing("IN")
    rise:SetOrder(1)

    local sink = show:CreateAnimation("Alpha")
    sink:SetFromAlpha(1)
    sink:SetToAlpha(0)
    sink:SetDuration(sink_seconds)
    sink:SetStartDelay(hold_seconds)
    sink:SetSmoothing("OUT")
    sink:SetOrder(2)

    show:SetScript("OnFinished", function()
        frame:Hide()
        if when_gone then
            when_gone()
        end
    end)

    show:Play()
end


-- Darkness at one edge of the screen, thinning to nothing towards the middle
local function add_shadow_edge(shadow, side)
    local r, g, b = shadow_color[1], shadow_color[2], shadow_color[3]
    local dark = CreateColor(r, g, b, shadow_alpha)
    local clear = CreateColor(r, g, b, 0)

    local edge = shadow:CreateTexture(nil, "BACKGROUND")
    edge:SetTexture("Interface\\Buttons\\WHITE8X8")
    edge:SetPoint(side)

    if side == "TOP" or side == "BOTTOM" then
        edge:SetPoint("LEFT")
        edge:SetPoint("RIGHT")
        edge:SetHeight(UIParent:GetHeight() * shadow_depth)
        -- Vertical gradients go bottom colour, then top colour
        if side == "TOP" then
            edge:SetGradient("VERTICAL", clear, dark)
        else
            edge:SetGradient("VERTICAL", dark, clear)
        end
    else
        edge:SetPoint("TOP")
        edge:SetPoint("BOTTOM")
        edge:SetWidth(UIParent:GetWidth() * shadow_depth)
        if side == "LEFT" then
            edge:SetGradient("HORIZONTAL", dark, clear)
        else
            edge:SetGradient("HORIZONTAL", clear, dark)
        end
    end
end


-- The screen's edges darken, under the rest of the UI, like the room just got smaller
local function show_shadow(hold_seconds)
    local shadow = CreateFrame("Frame", nil, UIParent)
    shadow:SetAllPoints(UIParent)
    shadow:SetFrameStrata("BACKGROUND")
    shadow:SetAlpha(0)

    add_shadow_edge(shadow, "TOP")
    add_shadow_edge(shadow, "BOTTOM")
    add_shadow_edge(shadow, "LEFT")
    add_shadow_edge(shadow, "RIGHT")

    rise_hold_sink(shadow, hold_seconds)
end


-- The letters come in one after another, each fading up over the next few.
-- SetAlphaGradient shows them in place, so centred text doesn't shift as it writes.
local function write_out(banner, message, text)
    local letters_written = -typing_waits_seconds * letters_per_second
    message:SetAlphaGradient(0, fade_letters)

    banner:SetScript("OnUpdate", function(self, elapsed)
        letters_written = letters_written + elapsed * letters_per_second
        message:SetAlphaGradient(math.max(0, math.floor(letters_written)), fade_letters)

        if letters_written > #text + fade_letters then
            self:SetScript("OnUpdate", nil)
        end
    end)
end


function shared.showNotice(text, when_gone)
    -- It writes itself out, then stays long enough to read again
    local writing_seconds = typing_waits_seconds + (#text + fade_letters) / letters_per_second
    local hold_seconds = writing_seconds + 2.5 + #text / 20

    local banner = CreateFrame("Frame", nil, UIParent)
    banner:SetWidth(900)
    banner:SetPoint("CENTER", UIParent, "CENTER", 0, 230)
    banner:SetFrameStrata("DIALOG")
    banner:SetAlpha(0)

    local header = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOP", banner, "TOP", 0, -14)
    header:SetText("DEEPRUN FREIGHT CO.  ·  NOTICE")
    header:SetTextColor(crimson[1] + 0.15, crimson[2] + 0.07, crimson[3] + 0.07)

    local message = banner:CreateFontString(nil, "OVERLAY")
    message:SetFont("Fonts\\MORPHEUS.TTF", 24, "")
    message:SetTextColor(bone[1], bone[2], bone[3])
    message:SetPoint("TOP", header, "BOTTOM", 0, -10)
    message:SetWidth(640)
    message:SetText(text)

    banner:SetHeight(14 + header:GetStringHeight() + 10 + message:GetStringHeight() + 18)
    shared.addFadingStrip(banner, "", banner:GetHeight(), 0, 0, 0, 0.9)
    shared.addFadingStrip(banner, "TOP", 1.5, crimson[1], crimson[2], crimson[3], 0.9)
    shared.addFadingStrip(banner, "BOTTOM", 1.5, crimson[1], crimson[2], crimson[3], 0.9)

    show_shadow(hold_seconds)
    rise_hold_sink(banner, hold_seconds, when_gone)
    write_out(banner, message, text)
end
