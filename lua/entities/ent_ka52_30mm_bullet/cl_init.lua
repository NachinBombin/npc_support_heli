include("shared.lua")

local MAT_GLOW = Material("sprites/light_glow02_add")

-- ============================================================
-- NET -- consume packets only, no client-side position tracking
-- ============================================================
net.Receive("ka52_bullet_tracer",  function() net.ReadVector() net.ReadVector() net.ReadBool() net.ReadUInt(16) end)
net.Receive("ka52_bullet_pos",     function() net.ReadUInt(16) net.ReadVector() net.ReadVector() end)
net.Receive("ka52_bullet_remove",  function() net.ReadUInt(16) end)

-- ============================================================
-- RENDER
-- ============================================================
function ENT:Draw()
    self:DrawModel()
end

function ENT:DrawTranslucent()
    local pos = self:GetPos()
    render.SetMaterial(MAT_GLOW)
    render.DrawSprite(pos, 120, 120, Color(255, 140, 20, 180))
    render.DrawSprite(pos, 30,  30,  Color(255, 240, 180, 255))
end
