-- Deeprun Tithe: fog over the screen
-- A pale haze over everything, thicker at the edges as if it's closing in, slowly breathing.
-- It rolls in, stays for the given time, then lifts. It sits under the rest of the UI,
-- so it fogs the world and not the action bars, and a memo shows on top of it.
-- Takes no clicks. Built from gradients, the same as the memo banner's strips.
--
-- shared.showFog(seconds)       rolls in, stays this many seconds at full thickness, lifts
-- shared.rollInFog(thickness)   rolls in and stays until liftFog. 1 is full, lower is lighter.
-- shared.liftFog()

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

    -- Rolling in and lifting are separate, so the fog can stay up as long as something needs it
    fog.roll_in = fog:CreateAnimationGroup()
    fog.roll_in:SetToFinalAlpha(true)
    fog.roll_in_alpha = fog.roll_in:CreateAnimation("Alpha")
    fog.roll_in_alpha:SetFromAlpha(0)
    fog.roll_in_alpha:SetDuration(roll_in_seconds)
    fog.roll_in_alpha:SetSmoothing("IN")

    fog.lift = fog:CreateAnimationGroup()
    fog.lift:SetToFinalAlpha(true)
    fog.lift_alpha = fog.lift:CreateAnimation("Alpha")
    fog.lift_alpha:SetToAlpha(0)
    fog.lift_alpha:SetDuration(lift_seconds)
    fog.lift_alpha:SetSmoothing("OUT")

    fog.lift:SetScript("OnFinished", function()
        fog:Hide()
    end)
end


-- Lifting while it's still rolling in jumps to full thickness first, then lifts.
-- Only happens if it's lifted in the first couple of seconds, so it's left as it is.
function shared.rollInFog(thickness)
    if fog == nil then
        create_fog()
    end

    fog.lift:Stop()
    fog.roll_in_alpha:SetToAlpha(thickness)
    fog.lift_alpha:SetFromAlpha(thickness)
    fog:Show()
    fog.roll_in:Play()
end


function shared.liftFog()
    fog.roll_in:Stop()
    fog.lift:Play()
end


function shared.showFog(seconds)
    shared.rollInFog(1)
    C_Timer.After(roll_in_seconds + seconds, shared.liftFog)
end
