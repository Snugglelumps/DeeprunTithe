-- Deeprun Tithe: the banner across the top of the screen, like a company memo
-- The front office's messages use it. The header says which kind it is:
--   MEMO        memorandums, at login (World/DeeprunMemorandums.lua)
--   COMMUNIQUE  communiques, earned by paying (World/DeeprunCommuniques.lua)
-- Notices are the back room, so they have their own darker look (Chrome/DeeprunNotice.lua).
--
-- shared.showBanner(kind, text, seconds_to_read)
--   seconds_to_read is optional: leave it out and longer text stays up longer.

local addon_name, shared = ...


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

-- The notice's band is built from the same strips
shared.addFadingStrip = add_fading_strip


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


-- A dark band with soft ends, a thin gold line above and below, the header in gold
-- and the message under it. It unrolls from the middle, a glint runs along each line,
-- the words fade in, it stays long enough to read, then fades away.
-- It takes no clicks and can't be moved, so it never gets in the way.
-- The band grows to fit the text.
function shared.showBanner(kind, text, seconds_to_read)
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
    header:SetText("|TInterface\\MoneyFrame\\UI-GoldIcon:0|t   DEEPRUN FREIGHT CO.  ·  " .. kind
        .. "   |TInterface\\MoneyFrame\\UI-GoldIcon:0|t")

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


-- A line in chat with the gold coin and our name
function shared.printTitheLine(text)
    print("|TInterface\\MoneyFrame\\UI-GoldIcon:0|t |cffffd100DeeprunTithe|r: " .. text)
end
