include("shared.lua")

-- Drain net messages for protocol compat
net.Receive("ka52_bullet_tracer", function()
    net.ReadVector() net.ReadVector() net.ReadBool() net.ReadUInt(16)
end)
net.Receive("ka52_bullet_pos", function()
    net.ReadUInt(16) net.ReadVector() net.ReadVector()
end)
net.Receive("ka52_bullet_remove", function()
    net.ReadUInt(16)
end)

-- Called every frame by engine to render the bullet model
function ENT:Draw()
    self:DrawModel()
end

-- DynamicLight MUST live in DrawTranslucent, not Draw().
-- Index offset avoids collision with engine reserved 0-255 range.
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
