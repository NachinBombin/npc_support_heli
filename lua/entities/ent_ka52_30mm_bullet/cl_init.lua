include("shared.lua")

-- ============================================================
-- NET  -- muzzle flash + dlight on bullet spawn
-- ============================================================
net.Receive("ka52_bullet_tracer", function()
    local mpos = net.ReadVector()   -- muzzle world position
    local dir  = net.ReadVector()   -- forward direction
    net.ReadBool()                  -- tracer flag (unused)
    net.ReadUInt(16)                -- entity index (unused here)

    -- Vanilla muzzle flash effect
    local med = EffectData()
    med:SetOrigin(mpos)
    med:SetAngles(dir:Angle())
    med:SetScale(2.5)
    med:SetMagnitude(2.5)
    util.Effect("MuzzleEffect", med)

    -- Brief bright muzzle dynamic light
    -- Use a rolling index (1-512) to avoid clobbering the bullet travel dlights
    if not _ka52_muzzle_dlight_idx then _ka52_muzzle_dlight_idx = 512 end
    _ka52_muzzle_dlight_idx = (_ka52_muzzle_dlight_idx % 512) + 1

    local dl = DynamicLight(_ka52_muzzle_dlight_idx)
    if dl then
        dl.Pos        = mpos
        dl.r          = 255
        dl.g          = 200
        dl.b          = 80
        dl.Brightness = 10
        dl.Size       = 220
        dl.Decay      = 8000
        dl.DieTime    = CurTime() + 0.03
    end
end)

net.Receive("ka52_bullet_pos", function()
    net.ReadUInt(16) net.ReadVector() net.ReadVector()
end)

net.Receive("ka52_bullet_remove", function()
    net.ReadUInt(16)
end)

-- ============================================================
-- RENDER
-- ============================================================
function ENT:Draw()
    self:DrawModel()
end

-- Traveling dynamic light follows the entity every frame
function ENT:DrawTranslucent()
    local dl = DynamicLight(self:EntIndex() + 8192)
    if dl then
        dl.Pos        = self:GetPos()
        dl.r          = 255
        dl.g          = 160
        dl.b          = 40
        dl.Brightness = 6
        dl.Size       = 150
        dl.Decay      = 1400
        dl.DieTime    = CurTime() + 0.05
    end
end
