include("shared.lua")

local MAT_GLOW = Material("sprites/light_glow02_add")

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
-- RENDER
-- ============================================================
function ENT:Draw()
    -- model hidden; sprite in DrawTranslucent is the visual
end

function ENT:DrawTranslucent()
    local pos = self:GetPos()

    render.SetMaterial(MAT_GLOW)
    render.DrawSprite(pos, 120, 120, Color(255, 140, 20, 180))
    render.DrawSprite(pos, 30,  30,  Color(255, 240, 180, 255))

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
