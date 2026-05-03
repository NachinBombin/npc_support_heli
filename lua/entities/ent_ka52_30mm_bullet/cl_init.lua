include("shared.lua")

-- Precache sprites
local MAT_GLOW  = Material("sprites/light_glow02_add")
local MAT_TRAIL = Material("trails/laser")

-- ============================================================
-- NET  -- muzzle flash + dlight on bullet spawn
-- ============================================================
net.Receive("ka52_bullet_tracer", function()
    local mpos = net.ReadVector()
    local dir  = net.ReadVector()
    net.ReadBool()
    net.ReadUInt(16)

    local med = EffectData()
    med:SetOrigin(mpos)
    med:SetAngles(dir:Angle())
    med:SetScale(6)
    med:SetMagnitude(6)
    util.Effect("MuzzleEffect", med)

    -- Muzzle dlight
    if not _ka52_muzzle_dlight_idx then _ka52_muzzle_dlight_idx = 512 end
    _ka52_muzzle_dlight_idx = (_ka52_muzzle_dlight_idx % 512) + 1
    local dl = DynamicLight(_ka52_muzzle_dlight_idx)
    if dl then
        dl.Pos        = mpos
        dl.r          = 255
        dl.g          = 220
        dl.b          = 80
        dl.Brightness = 20
        dl.Size       = 800
        dl.Decay      = 6000
        dl.DieTime    = CurTime() + 0.15
    end
end)

net.Receive("ka52_bullet_pos",    function() net.ReadUInt(16) net.ReadVector() net.ReadVector() end)
net.Receive("ka52_bullet_remove", function() net.ReadUInt(16) end)

-- ============================================================
-- CLIENT TRAIL on Initialize
-- ============================================================
function ENT:Initialize()
    -- Client-side trail: bright orange-white, laser sprite, wide and long for debug
    util.SpriteTrail(
        self,
        0,
        Color(255, 200, 80, 255),
        true,       -- additive
        28,         -- startWidth  (DEBUG: wide)
        0,          -- endWidth
        0.4,        -- lifetime
        1,
        "trails/laser"
    )
end

-- ============================================================
-- RENDER
-- ============================================================
function ENT:Draw()
    -- Don't draw the dark bullet model — the glow sprite IS the visual
    -- self:DrawModel()  -- kept off: black model kills the glowing look
end

--[[
    DrawTranslucent is called every frame because shared.lua sets
    RenderGroup = RENDERGROUP_BOTH.

    This draws TWO layered sprites at the bullet position:
      1. A large soft outer halo (light_glow02_add) — the "LED" corona
      2. A small bright core (light_glow02_add at full white) — the hot centre

    These sprites face the camera (billboarded) and are additive, so they
    SELF-ILLUMINATE — they glow in the dark and bloom on bright surfaces,
    looking like a hot projectile rather than a flashlight.

    DynamicLight on top lights up nearby world geometry as a bonus.
--]]
function ENT:DrawTranslucent()
    local pos = self:GetPos()

    render.SetMaterial(MAT_GLOW)

    -- Outer halo: large, dim orange — the corona
    render.DrawSprite(pos, 120, 120, Color(255, 140, 20, 180))

    -- Inner core: small, near-white hot centre
    render.DrawSprite(pos, 30, 30, Color(255, 240, 180, 255))

    -- DynamicLight to illuminate nearby world geometry
    local dl = DynamicLight(self:EntIndex() + 8192)
    if dl then
        dl.Pos        = pos
        dl.r          = 255
        dl.g          = 160
        dl.b          = 40
        dl.Brightness = 18
        dl.Size       = 700
        dl.Decay      = 800
        dl.DieTime    = CurTime() + 0.08
    end
end
