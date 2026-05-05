include("shared.lua")

local MAT_GLOW = Material("sprites/light_glow02_add")

local _bulletData = {}

-- ============================================================
-- NET
-- ============================================================
net.Receive("ka52_bullet_tracer", function()
    local mpos     = net.ReadVector()
    local dir      = net.ReadVector()
    net.ReadBool()
    local entIdx   = net.ReadUInt(16)

    dir:Normalize()
    _bulletData[entIdx] = {
        pos = mpos,
        dir = dir,
        vel = 25000,
        t0  = CurTime(),
    }
end)

net.Receive("ka52_bullet_pos",    function() net.ReadUInt(16) net.ReadVector() net.ReadVector() end)
net.Receive("ka52_bullet_remove", function()
    local idx = net.ReadUInt(16)
    _bulletData[idx] = nil
end)

-- ============================================================
-- RENDER
-- ============================================================
function ENT:Draw()
    self:DrawModel()
end

function ENT:DrawTranslucent()
    local idx  = self:EntIndex()
    local data = _bulletData[idx]

    local pos
    if data then
        local dt = CurTime() - data.t0
        pos = data.pos
            + data.dir * (data.vel * dt)
            - Vector(0, 0, 0.5 * 600 * dt * dt)
    else
        pos = self:GetPos()
    end

    render.SetMaterial(MAT_GLOW)
    render.DrawSprite(pos, 120, 120, Color(255, 140, 20, 180))
    render.DrawSprite(pos, 30,  30,  Color(255, 240, 180, 255))
end
