-- Deeprun Celebrate: the show for paying your tithe.
-- pay_tithe in DeeprunTithe.lua plays it after Pay Tithe or Pay Custom Tithe goes through.

local addon_name, shared = ...


-- Colour palettes, like the coins and the item qualities. Each colour is { red, green, blue }.
local copper = {
    { 0.72, 0.45, 0.20 },
    { 0.85, 0.55, 0.30 },
    { 0.60, 0.35, 0.15 },
    { 0.95, 0.65, 0.40 },
}

local silver = {
    { 0.75, 0.75, 0.78 },
    { 0.85, 0.85, 0.90 },
    { 0.60, 0.62, 0.65 },
    { 1.00, 1.00, 1.00 },
}

local gold = {
    { 1.00, 0.82, 0.00 },
    { 1.00, 0.90, 0.40 },
    { 0.90, 0.70, 0.10 },
    { 1.00, 0.95, 0.70 },
}

local purple = {
    { 0.64, 0.21, 0.93 },
    { 0.75, 0.40, 1.00 },
    { 0.50, 0.15, 0.80 },
    { 0.85, 0.60, 1.00 },
}

local orange = {
    { 1.00, 0.50, 0.00 },
    { 1.00, 0.65, 0.20 },
    { 0.90, 0.40, 0.05 },
    { 1.00, 0.78, 0.45 },
}


-- The game's own firework booms (sound/doodad/g_fireworkboomgeneral1 to 6), by file ID
local boom_sounds = {
    566373,
    566585,
    566862,
    565731,
    567011,
    566876,
}


-- The big coin loot sound (sound/interface/lootcoinlarge)
local ka_ching_sound = 567413


-- Bigger tithes, fancier colours. Copper under a silver, silver under a gold,
-- gold under 10 gold, purple under 100 gold, orange (legendary) for anything more.
local function palette_for(amount_paid)
    if amount_paid < 100 then
        return copper
    end

    if amount_paid < 10000 then
        return silver
    end

    if amount_paid < 100000 then
        return gold
    end

    if amount_paid < 1000000 then
        return purple
    end

    return orange
end


-- One spark: a glowing star of one colour at x, y (from the middle of the screen)
local function make_spark(stage, color, x, y, size)
    local spark = stage:CreateTexture(nil, "OVERLAY")
    spark:SetTexture("Interface\\Cooldown\\star4")
    spark:SetBlendMode("ADD")
    spark:SetVertexColor(color[1], color[2], color[3])
    spark:SetSize(size, size)
    spark:SetPoint("CENTER", UIParent, "CENTER", x, y)
    return spark
end


-- The burst: 30 sparks fly out in a ring, fast then slowing,
-- then drop a little as they shrink and fade, like a real firework.
local function burst(stage, color, x, y)
    for spark_number = 1, 30 do
        local spark = make_spark(stage, color, x, y, 24)

        -- Each spark gets a direction around the circle and a distance, so the burst is round
        local angle = math.random() * 2 * math.pi
        local distance = math.random(80, 160)

        local sparkle = spark:CreateAnimationGroup()
        sparkle:SetToFinalAlpha(true)

        local fly_out = sparkle:CreateAnimation("Translation")
        fly_out:SetOffset(math.cos(angle) * distance, math.sin(angle) * distance)
        fly_out:SetDuration(0.7)
        fly_out:SetSmoothing("OUT")
        fly_out:SetOrder(1)

        -- Then, all at once: fall, fade and shrink
        local fall = sparkle:CreateAnimation("Translation")
        fall:SetOffset(0, -50)
        fall:SetDuration(0.8)
        fall:SetSmoothing("IN")
        fall:SetOrder(2)

        local fade = sparkle:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        fade:SetDuration(0.8)
        fade:SetOrder(2)

        local shrink = sparkle:CreateAnimation("Scale")
        shrink:SetScaleFrom(1, 1)
        shrink:SetScaleTo(0.4, 0.4)
        shrink:SetDuration(0.8)
        shrink:SetOrder(2)

        sparkle:Play()
    end
end


-- One firework: a small spark shoots up from 250 below x, y, then bursts there.
-- The rise takes 0.45 seconds.
local function firework(stage, color, x, y)
    local rocket = make_spark(stage, color, x, y - 250, 16)

    local rise = rocket:CreateAnimationGroup()

    local up = rise:CreateAnimation("Translation")
    up:SetOffset(0, 250)
    up:SetDuration(0.45)
    up:SetSmoothing("OUT")

    rise:SetScript("OnFinished", function()
        rocket:Hide()
        burst(stage, color, x, y)
    end)

    rise:Play()
end


-- 25 gold coins fall from the top of the screen, spinning, a little apart
local function coin_shower(stage)
    local fall_distance = UIParent:GetHeight() + 60

    for coin_number = 1, 25 do
        local coin = stage:CreateTexture(nil, "OVERLAY")
        coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
        coin:SetSize(20, 20)
        coin:SetPoint("BOTTOM", UIParent, "TOP", math.random(-600, 600), 0)

        local tumble = coin:CreateAnimationGroup()
        tumble:SetToFinalAlpha(true)

        -- Fall, spin and drift sideways at the same time. The start delay spreads them out.
        local start_delay = math.random() * 1.2
        local fall_time = 1.6 + math.random() * 0.8

        local fall = tumble:CreateAnimation("Translation")
        fall:SetOffset(math.random(-80, 80), -fall_distance)
        fall:SetDuration(fall_time)
        fall:SetStartDelay(start_delay)
        fall:SetSmoothing("IN")

        local spin = tumble:CreateAnimation("Rotation")
        spin:SetDegrees(math.random(-720, 720))
        spin:SetDuration(fall_time)
        spin:SetStartDelay(start_delay)

        tumble:Play()
    end
end


-- "Tithe Paid" and the amount, above the middle of the screen.
-- Pops in a little big, settles, stays two seconds, then fades.
local function banner(stage, amount_paid, color)
    local banner_frame = CreateFrame("Frame", nil, stage)
    banner_frame:SetSize(400, 80)
    banner_frame:SetPoint("CENTER", UIParent, "CENTER", 0, 160)

    local title = banner_frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP")
    title:SetText("Tithe Paid")
    title:SetTextColor(color[1], color[2], color[3])

    local amount = banner_frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    amount:SetPoint("TOP", title, "BOTTOM", 0, -8)
    amount:SetText(GetMoneyString(amount_paid))

    local show = banner_frame:CreateAnimationGroup()
    show:SetToFinalAlpha(true)

    local pop = show:CreateAnimation("Scale")
    pop:SetScaleFrom(0.5, 0.5)
    pop:SetScaleTo(1, 1)
    pop:SetDuration(0.3)
    pop:SetSmoothing("OUT")
    pop:SetOrder(1)

    local fade_in = show:CreateAnimation("Alpha")
    fade_in:SetFromAlpha(0)
    fade_in:SetToAlpha(1)
    fade_in:SetDuration(0.3)
    fade_in:SetOrder(1)

    local fade_out = show:CreateAnimation("Alpha")
    fade_out:SetFromAlpha(1)
    fade_out:SetToAlpha(0)
    fade_out:SetDuration(0.6)
    fade_out:SetStartDelay(2)
    fade_out:SetOrder(2)

    show:Play()
end


-- The whole show for a tithe. Everything goes on one stage that covers the screen:
-- no clicks, can't be moved, no background. The stage hides when it's all over.
--   right away    the banner, the coin shower and a ka-ching
--   over 4 secs   12 fireworks in the palette for the amount, a boom on every fourth
--                 and a second ka-ching on the 11th
function shared.celebrateTithe(amount_paid)
    local palette = palette_for(amount_paid)

    local stage = CreateFrame("Frame", nil, UIParent)
    stage:SetAllPoints()
    stage:SetFrameStrata("FULLSCREEN_DIALOG")

    banner(stage, amount_paid, palette[1])
    coin_shower(stage)
    PlaySoundFile(ka_ching_sound, "SFX")

    for firework_number = 1, 12 do
        local launch_time = 0.35 * (firework_number - 1)

        C_Timer.After(launch_time, function()
            local color = palette[math.random(#palette)]
            firework(stage, color, math.random(-500, 500), math.random(-150, 300))
        end)

        -- The boom goes with the burst, after the rocket's 0.45 second rise
        if firework_number % 4 == 1 then
            C_Timer.After(launch_time + 0.45, function()
                PlaySoundFile(boom_sounds[math.random(#boom_sounds)], "SFX")
            end)
        end

        if firework_number == 11 then
            C_Timer.After(launch_time, function()
                PlaySoundFile(ka_ching_sound, "SFX")
            end)
        end
    end

    -- The last firework launches at 3.85, rises for 0.45 and its sparks last 1.5
    C_Timer.After(6, function()
        stage:Hide()
    end)
end

