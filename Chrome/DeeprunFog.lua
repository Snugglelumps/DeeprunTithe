-- Deeprun Tithe: fog over the screen
-- A pale haze over everything, thicker at the edges as if it's closing in, slowly breathing.
-- It rolls in, stays for the given time, then lifts. It sits under the rest of the UI,
-- so it fogs the world and not the action bars, and a memo shows on top of it.
-- Takes no clicks. Built from gradients, the same as the memo banner's strips.
--
-- shared.showFog(seconds)   seconds is how long it stays at full thickness

local addon_name, shared = ...

-- Settings
local fog_color = { 0.78, 0.80, 0.84 }   -- grey with a little blue
local haze_alpha = 0.22                  -- over the whole screen
local edge_alpha = 0.75                  -- at the very edge of the screen
local edge_depth = 0.38                  -- how far in the edges reach, as a share of the screen
local roll_in_seconds = 2.5
local lift_seconds = 3.5


local fog = nil


local function add_texture(parent)
    local texture = parent:CreateTexture(nil, "BACKGROUND")
    texture:SetTexture("Interface\\Buttons\\WHITE8X8")
    return texture
end


-- Fog thick at one edge, thinning to nothing towards the middle
local function add_edge(parent, side)
    local r, g, b = fog_color[1], fog_color[2], fog_color[3]
    local thick = CreateColor(r, g, b, edge_alpha)
    local clear = CreateColor(r, g, b, 0)

    local edge = add_texture(parent)
    edge:SetPoint(side)

    if side == "TOP" or side == "BOTTOM" then
        edge:SetPoint("LEFT")
        edge:SetPoint("RIGHT")
        edge:SetHeight(UIParent:GetHeight() * edge_depth)
        -- Vertical gradients go bottom colour, then top colour
        if side == "TOP" then
            edge:SetGradient("VERTICAL", clear, thick)
        else
            edge:SetGradient("VERTICAL", thick, clear)
        end
    else
        edge:SetPoint("TOP")
        edge:SetPoint("BOTTOM")
        edge:SetWidth(UIParent:GetWidth() * edge_depth)
        if side == "LEFT" then
            edge:SetGradient("HORIZONTAL", thick, clear)
        else
            edge:SetGradient("HORIZONTAL", clear, thick)
        end
    end
end


-- A layer that slowly thickens and thins, forever, while the fog is up
local function breathe(layer, low, high, seconds)
    local breathing = layer:CreateAnimationGroup()
    breathing:SetLooping("BOUNCE")

    local swell = breathing:CreateAnimation("Alpha")
    swell:SetFromAlpha(low)
    swell:SetToAlpha(high)
    swell:SetDuration(seconds)
    swell:SetSmoothing("IN_OUT")

    breathing:Play()
end


-- A layer that drifts a little one way and back, forever
local function drift(layer, x, y, seconds)
    local drifting = layer:CreateAnimationGroup()
    drifting:SetLooping("BOUNCE")

    local move = drifting:CreateAnimation("Translation")
    move:SetOffset(x, y)
    move:SetDuration(seconds)
    move:SetSmoothing("IN_OUT")

    drifting:Play()
end


local function create_fog()
    fog = CreateFrame("Frame", nil, UIParent)
    fog:SetAllPoints(UIParent)
    fog:SetFrameStrata("BACKGROUND")
    fog:SetAlpha(0)
    fog:Hide()

    local haze = add_texture(fog)
    haze:SetAllPoints()
    haze:SetColorTexture(fog_color[1], fog_color[2], fog_color[3], haze_alpha)

    -- The edges are a little bigger than the screen so drifting never shows a gap
    local edges = CreateFrame("Frame", nil, fog)
    edges:SetPoint("TOPLEFT", -40, 40)
    edges:SetPoint("BOTTOMRIGHT", 40, -40)
    add_edge(edges, "TOP")
    add_edge(edges, "BOTTOM")
    add_edge(edges, "LEFT")
    add_edge(edges, "RIGHT")

    breathe(edges, 0.75, 1, 4)
    drift(edges, 30, -12, 9)

    -- Roll in, hold, lift
    fog.show = fog:CreateAnimationGroup()
    fog.show:SetToFinalAlpha(true)

    local roll_in = fog.show:CreateAnimation("Alpha")
    roll_in:SetFromAlpha(0)
    roll_in:SetToAlpha(1)
    roll_in:SetDuration(roll_in_seconds)
    roll_in:SetSmoothing("IN")
    roll_in:SetOrder(1)

    fog.lift = fog.show:CreateAnimation("Alpha")
    fog.lift:SetFromAlpha(1)
    fog.lift:SetToAlpha(0)
    fog.lift:SetDuration(lift_seconds)
    fog.lift:SetSmoothing("OUT")
    fog.lift:SetOrder(2)

    fog.show:SetScript("OnFinished", function()
        fog:Hide()
    end)
end


function shared.showFog(seconds)
    if fog == nil then
        create_fog()
    end

    fog.show:Stop()
    fog.lift:SetStartDelay(seconds)
    fog:Show()
    fog.show:Play()
end
