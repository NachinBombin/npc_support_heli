include("shared.lua")

-- Drain net messages to stay protocol-compatible
net.Receive("ka52_bullet_tracer", function()
    net.ReadVector() net.ReadVector() net.ReadBool() net.ReadUInt(16)
end)
net.Receive("ka52_bullet_pos", function()
    net.ReadUInt(16) net.ReadVector() net.ReadVector()
end)
net.Receive("ka52_bullet_remove", function()
    net.ReadUInt(16)
end)

function ENT:Draw()
    self:DrawModel()

    local dl = DynamicLight(self:EntIndex())
    if dl then
        dl.Pos        = self:GetPos()
        dl.r          = 255
        dl.g          = 140
        dl.b          = 40
        dl.Brightness = 4
        dl.Size       = 120
        dl.Decay      = 1200
        dl.DieTime    = CurTime() + 0.05
    end
end
