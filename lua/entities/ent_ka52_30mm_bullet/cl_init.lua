include("shared.lua")

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

    -- Muzzle dlight: big and obvious for debug
    if not _ka52_muzzle_dlight_idx then _ka52_muzzle_dlight_idx = 512 end
    _ka52_muzzle_dlight_idx = (_ka52_muzzle_dlight_idx % 512) + 1

    local dl = DynamicLight(_ka52_muzzle_dlight_idx)
    if dl then
        dl.Pos        = mpos
        dl.r          = 255
        dl.g          = 220
        dl.b          = 80
        dl.Brightness = 20      -- DEBUG: very bright
        dl.Size       = 800     -- DEBUG: huge radius
        dl.Decay      = 6000
        dl.DieTime    = CurTime() + 0.15
    end
end)

net.Receive("ka52_bullet_pos",    function() net.ReadUInt(16) net.ReadVector() net.ReadVector() end)
net.Receive("ka52_bullet_remove", function() net.ReadUInt(16) end)

-- ============================================================
-- TRAIL SETUP on entity creation
-- ============================================================
function ENT:Initialize()
    -- util.SpriteTrail: texname, attachID, color, additive, startW, endW, lifetime, minLen, filter
    util.SpriteTrail(
        self,                               -- entity to follow
        0,                                  -- attachment 0 = entity origin
        Color(255, 180, 60, 255),           -- bright orange
        true,                               -- additive blend
        40,                                 -- startWidth  (DEBUG: huge)
        0,                                  -- endWidth
        0.35,                               -- lifetime in seconds (DEBUG: long)
        1,                                  -- minLen (minimum segment length)
        "trails/laser.vmt"                  -- bright sprite so it can't be missed
    )
end

-- ============================================================
-- RENDER
-- ============================================================
function ENT:Draw()
    self:DrawModel()
end

-- DrawTranslucent is now actually called because RenderGroup = RENDERGROUP_BOTH
function ENT:DrawTranslucent()
    local pos = self:GetPos()

    -- Traveling dlight: exaggerated for debug
    local dl = DynamicLight(self:EntIndex() + 8192)
    if dl then
        dl.Pos        = pos
        dl.r          = 255
        dl.g          = 140
        dl.b          = 20
        dl.Brightness = 18      -- DEBUG: very bright
        dl.Size       = 700     -- DEBUG: large radius so you can't miss it
        dl.Decay      = 800
        dl.DieTime    = CurTime() + 0.08
    end
end
